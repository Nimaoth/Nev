import std/[options]
import config_provider
import component

export component

include dynlib_export

declareSettings InlayHintSettings, "":
  ## Whether inlay hints are enabled.
  declare enable, bool, true

type InlayHintComponent* = ref object of Component
  settings*: InlayHintSettings

# DLL API
var InlayHintComponentId* {.apprtl.}: ComponentTypeId
const overlayIdInlayHint* = 14

proc inlayHintComponentUpdateInlayHints(self: InlayHintComponent, now: bool = false) {.apprtl, gcsafe, raises: [].}

proc getInlayHintComponent*(self: ComponentOwner): Option[InlayHintComponent] {.apprtl, gcsafe, raises: [].}

# Nice wrappers
proc updateInlayHints*(self: InlayHintComponent, now: bool = false) {.inline.} = inlayHintComponentUpdateInlayHints(self, now)

# Implementation
when implModule:
  import std/[tables, sequtils]
  import nimsumtree/[rope, buffer, clock]
  import misc/[util, custom_logger, rope_utils, delayed_task, id, event, custom_async, response]
  import document_editor, document
  import text/language/language_server_base
  import text/[display_map, overlay_map]
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
  import language_server_component, text_editor_component, text_component

  logCategory "inlay-hint-component"

  InlayHintComponentId = componentGenerateTypeId()

  type InlayHintComponentImpl* = ref object of InlayHintComponent
    displayMap*: DisplayMap
    inlayHints: seq[tuple[anchor: Anchor, hint: InlayHint]]
    inlayHintsTask: DelayedTask
    lastInlayHintTimestamp: Global
    lastInlayHintDisplayRange: Range[Point]
    lastInlayHintBufferRange: Range[Point]
    documentChangedHandle: Id

  proc getInlayHintComponent*(self: ComponentOwner): Option[InlayHintComponent] {.gcsafe, raises: [].} =
    return self.getComponent(InlayHintComponentId).mapIt(it.InlayHintComponent)

  proc handleDocumentChanged(self: InlayHintComponentImpl, old: Document) =
    self.inlayHints.setLen(0)

  proc listenForDocumentChanges*(self: InlayHintComponentImpl) =
    if self.documentChangedHandle != idNone():
      return
    self.documentChangedHandle = self.owner.DocumentEditor.onDocumentChanged.subscribe proc(arg: auto) {.closure, gcsafe, raises: [].} = self.handleDocumentChanged(arg.old)

  proc newInlayHintComponent*(settings: InlayHintSettings, displayMap: DisplayMap): InlayHintComponentImpl =
    return InlayHintComponentImpl(
      typeId: InlayHintComponentId,
      settings: settings,
      displayMap: displayMap,
      initializeImpl: (proc(self: Component, owner: ComponentOwner) =
        self.InlayHintComponentImpl.listenForDocumentChanges()
      ),
      deinitializeImpl: (proc(self: Component) =
        let self = self.InlayHintComponentImpl
        if self.inlayHintsTask.isNotNil:
          self.inlayHintsTask.pause()
      ),
    )

  proc updateInlayHintsAfterChange(self: InlayHintComponentImpl, buffer: BufferSnapshot) =
    if self.inlayHints.len > 0 and self.lastInlayHintTimestamp != buffer.version:
      self.lastInlayHintTimestamp = buffer.version
      for i in countdown(self.inlayHints.high, 0):
        if self.inlayHints[i].anchor.summaryOpt(Point, buffer, resolveDeleted = false).getSome(point):
          self.inlayHints[i].hint.location = point.toCursor
          self.inlayHints[i].anchor = buffer.anchorAt(self.inlayHints[i].hint.location.toPoint, Left)
        else:
          self.inlayHints.removeSwap(i)

  proc document*(self: InlayHintComponent): Document =
    let editor = self.owner.DocumentEditor
    return editor.currentDocument

  proc updateInlayHintsAsync*(self: InlayHintComponent): Future[void] {.async.} =
    let self = self.InlayHintComponentImpl
    let editor = self.owner.DocumentEditor
    let document = editor.currentDocument
    if document.isNil or not self.document.isReady:
      return

    if not self.settings.enable.get():
      return

    let lsComp = document.getLanguageServerComponent().getOr:
      return

    let te = editor.getTextEditorComponent().getOr:
      return

    let text = document.getTextComponent().getOr:
      return

    let screenLineCount = te.screenLineCount
    let visibleRangeHalf = te.visibleTextRange(screenLineCount div 2)
    let visibleRange = te.visibleTextRange(screenLineCount)
    let snapshot = text.buffer.snapshot.clone()
    let inlayHints: Response[seq[language_server_base.InlayHint]] = await lsComp.getInlayHints(document.filename, visibleRange)
    if self.document.isNil:
      return

    if inlayHints.isSuccess:
      template getBias(hint: untyped): Bias =
        if hint.paddingRight:
          Bias.Right
        else:
          Bias.Left

      self.inlayHints = inlayHints.result.mapIt (snapshot.anchorAt(it.location.toPoint, it.getBias), it)
      self.lastInlayHintTimestamp = snapshot.version
      self.updateInlayHintsAfterChange(snapshot)
      self.lastInlayHintDisplayRange = visibleRange.toRange
      self.lastInlayHintBufferRange = visibleRangeHalf.toRange

      self.displayMap.overlay.clear(overlayIdInlayHint)
      for hint in self.inlayHints:
        let point = hint.hint.location.toPoint
        let bias = hint.hint.getBias
        if hint.hint.paddingLeft:
          self.displayMap.overlay.addOverlay(point...point, " " & hint.hint.label, overlayIdInlayHint, "comment", bias)
        elif hint.hint.paddingRight:
          self.displayMap.overlay.addOverlay(point...point, hint.hint.label & " ", overlayIdInlayHint, "comment", bias)
        else:
          self.displayMap.overlay.addOverlay(point...point, hint.hint.label, overlayIdInlayHint, "comment", bias)

    self.owner.DocumentEditor.markDirty()

  proc inlayHintComponentUpdateInlayHints(self: InlayHintComponent, now: bool = false) =
    let self = self.InlayHintComponentImpl
    if now:
      asyncSpawn self.updateInlayHintsAsync()
    else:
      if self.inlayHintsTask.isNil:
        self.inlayHintsTask = startDelayed(200, repeat=false):
          asyncSpawn self.updateInlayHintsAsync()
      else:
        self.inlayHintsTask.schedule()

  proc preRender*(self: InlayHintComponent) =
    let self = self.InlayHintComponentImpl
    let editor = self.owner.DocumentEditor
    let document = editor.currentDocument
    if document.isNil or not self.document.isReady:
      return
    let te = editor.getTextEditorComponent().getOr:
      return
    let text = document.getTextComponent().getOr:
      return

    let snapshot = text.buffer.snapshot.clone()
    self.updateInlayHintsAfterChange(snapshot)
    let visibleRange = te.visibleTextRange.toRange
    let bufferRange = self.lastInlayHintBufferRange
    if visibleRange.a < bufferRange.a or visibleRange.b > bufferRange.b:
      self.inlayHintComponentUpdateInlayHints()
