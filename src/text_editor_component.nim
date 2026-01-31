import std/[options]
import nimsumtree/[rope]
import misc/[event]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import component

export component

include dynlib_export

type TextEditorComponent* = ref object of Component
  # onEdit*: Event[Patch[Point]]

# DLL API
var TextEditorComponentId* {.apprtl.}: ComponentTypeId

proc textEditorComponentSelections(self: TextEditorComponent): lent seq[Range[Point]] {.apprtl, gcsafe, raises: [].}
proc textEditorComponentSetSelections(self: TextEditorComponent, selections: sink seq[Range[Point]]) {.apprtl, gcsafe, raises: [].}
proc textEditorComponentSetTargetSelections(self: TextEditorComponent, selections: sink seq[Range[Point]]) {.apprtl, gcsafe, raises: [].}

proc getTextEditorComponent*(self: ComponentOwner): Option[TextEditorComponent] {.apprtl, gcsafe, raises: [].}
proc textEditorComponentCenterCursor(self: TextEditorComponent, point: Point, relativePosition: float = 0.5, snap: bool = false) {.apprtl, gcsafe, raises: [].}
proc textEditorComponentScrollToCursor(self: TextEditorComponent, point: Point, scrollBehaviour: ScrollBehaviour, snap: bool = false) {.apprtl, gcsafe, raises: [].}

# Nice wrappers
proc selection*(self: TextEditorComponent): Range[Point] {.inline.} = textEditorComponentSelections(self)[0]
proc selections*(self: TextEditorComponent): lent seq[Range[Point]] {.inline.} = textEditorComponentSelections(self)
proc `selections=`*(self: TextEditorComponent, selections: sink seq[Range[Point]]) {.inline.} = textEditorComponentSetSelections(self, selections.ensureMove)
proc `selection=`*(self: TextEditorComponent, selection: Range[Point]) {.inline.} = textEditorComponentSetSelections(self, @[selection])
proc `selection=`*(self: TextEditorComponent, cursor: Point) {.inline.} = textEditorComponentSetSelections(self, @[cursor...cursor])
proc setTargetSelections*(self: TextEditorComponent, selections: sink seq[Range[Point]]) {.inline.} = textEditorComponentSetTargetSelections(self, selections.ensureMove)
proc setTargetSelection*(self: TextEditorComponent, selection: Range[Point]) {.inline.} = textEditorComponentSetTargetSelections(self, @[selection])
proc `targetSelections=`*(self: TextEditorComponent, selections: sink seq[Range[Point]]) {.inline.} = textEditorComponentSetTargetSelections(self, selections.ensureMove)
proc `targetSelection=`*(self: TextEditorComponent, selection: Range[Point]) {.inline.} = textEditorComponentSetTargetSelections(self, @[selection])
proc centerCursor*(self: TextEditorComponent, point: Point, relativePosition: float = 0.5, snap: bool = false) {.inline.} = textEditorComponentCenterCursor(self, point, relativePosition, snap)
proc scrollToCursor*(self: TextEditorComponent, point: Point, scrollBehaviour: ScrollBehaviour, snap: bool = false) {.inline.} = textEditorComponentScrollToCursor(self, point, scrollBehaviour, snap)

# Implementation
when implModule:
  import std/[sequtils, deques]
  import misc/[util, custom_logger, rope_utils]
  import nimsumtree/[clock]
  import text/[text_document, display_map]
  import scroll_box

  logCategory "text-editor-component"

  TextEditorComponentId = componentGenerateTypeId()

  type TextEditorComponentImpl* = ref object of TextEditorComponent
    document: TextDocument
    mSelections: seq[Range[Point]]
    mSelectionsOld: seq[Selection]
    mTargetSelections*: Option[seq[Range[Point]]]
    selectionHistory*: Deque[Selections]

    displayMap*: DisplayMap

    scrollBox*: ScrollBox

    onSelectionsChanged*: Event[tuple[editor: TextEditorComponent, old: seq[Selection]]]
    onDocumentChanged*: Event[tuple[editor: TextEditorComponent]]

  proc getTextEditorComponent*(self: ComponentOwner): Option[TextEditorComponent] {.gcsafe, raises: [].} =
    return self.getComponent(TextEditorComponentId).mapIt(it.TextEditorComponent)

  proc newTextEditorComponent*(document: TextDocument = nil): TextEditorComponentImpl =
    return TextEditorComponentImpl(
      typeId: TextEditorComponentId,
      document: document,
      mSelectionsOld: @[(0, 0).toSelection],
      mSelections: @[point(0, 0)...point(0, 0)]
    )

  proc setDocument*(self: TextEditorComponent, document: TextDocument) =
    let self = self.TextEditorComponentImpl
    if self.document == document:
      return
    self.document = document
    self.onDocumentChanged.invoke((self.TextEditorComponent,))

  proc selectionsOld*(self: TextEditorComponent): var seq[Selection] =
    return self.TextEditorComponentImpl.mSelectionsOld

  proc handleSelectionsChanged(self: TextEditorComponentImpl, old: openArray[Selection], addToHistory: Option[bool] = bool.none) =
    let addToHistory = addToHistory.get(self.selectionHistory.len == 0 or
        abs(self.mSelectionsOld[^1].last.line - old[^1].last.line) > 1 or
        old.len != self.mSelectionsOld.len)
    if addToHistory:
      self.selectionHistory.addLast @old
      if self.selectionHistory.len > 100:
        discard self.selectionHistory.popFirst

  proc setSelectionsOld*(self: TextEditorComponent, selections: sink seq[Selection], addToHistory: Option[bool] = bool.none) =
    if selections.len == 0:
      return
    let self = self.TextEditorComponentImpl
    var old = seq[Selection].default
    swap(old, self.mSelectionsOld)
    self.mSelectionsOld = selections.ensureMove
    self.mSelections = self.mSelectionsOld.mapIt(it.toRange)
    self.handleSelectionsChanged(old, addToHistory)
    self.onSelectionsChanged.invoke((self.TextEditorComponent, old))

  proc textEditorComponentSelections(self: TextEditorComponent): lent seq[Range[Point]] =
    return self.TextEditorComponentImpl.mSelections

  proc textEditorComponentSetSelections(self: TextEditorComponent, selections: sink seq[Range[Point]]) =
    if selections.len == 0:
      return
    let self = self.TextEditorComponentImpl
    var old = seq[Selection].default
    swap(old, self.mSelectionsOld)
    self.mSelections = selections.ensureMove
    self.mSelectionsOld = self.mSelections.mapIt(it.toSelection)
    self.handleSelectionsChanged(old)
    self.onSelectionsChanged.invoke((self.TextEditorComponent, old))

  proc textEditorComponentSetTargetSelections(self: TextEditorComponent, selections: sink seq[Range[Point]]) =
    let self = self.TextEditorComponentImpl
    if self.document == nil:
      return

    if self.document.isLoadingAsync or self.document.requiresLoad:
      self.mTargetSelections = selections.some
    else:
      self.textEditorComponentSetSelections(selections)
      # self.updateTargetColumn(Last) # todo

  proc textEditorComponentCenterCursor(self: TextEditorComponent, point: Point, relativePosition: float = 0.5, snap: bool = false) =
    let self = self.TextEditorComponentImpl
    let displayPoint = self.displayMap.toDisplayPoint(point)
    debugf"textEditorComponentCenterCursor {point}, {relativePosition}, {snap}, {self.scrollBox.size.y * relativePosition}"
    if snap and self.scrollBox.size.y != 0:
      self.scrollBox.scrollXToY(displayPoint.row.int, self.scrollBox.size.y * relativePosition)
    else:
      self.scrollBox.scrollTo(displayPoint.row.int, center = true, snap = snap)

  proc textEditorComponentScrollToCursor(self: TextEditorComponent, point: Point, scrollBehaviour: ScrollBehaviour, snap: bool = false) =
    let self = self.TextEditorComponentImpl
    let displayPoint = self.displayMap.toDisplayPoint(point)
    let (centerY, centerOffscreenY) = case scrollBehaviour
      of CenterAlways: (true, false)
      of CenterOffscreen: (false, true)
      of CenterMargin: (false, false)
      of ScrollToMargin: (false, false)
      of TopOfScreen: (false, false)

    self.scrollBox.scrollTo(displayPoint.row.int, center = centerY, centerOffscreen = centerOffscreenY, snap = snap)
