import std/[options]
import finder, previewer

const currentSourcePath2 = currentSourcePath()
include module_base

type GetPreviewTextImpl* = proc(item: FinderItem): string {.gcsafe, raises: [].}

{.push modrtl, gcsafe, raises: [].}
proc newDataPreviewer*(language = string.none, getPreviewTextImpl: GetPreviewTextImpl = nil): Previewer
proc dataPreviewerSetPath(self: Previewer, path: string)
{.pop.}

proc setPath*(self: Previewer, path: string) = dataPreviewerSetPath(self, path)

when implModule:
  import std/[strformat]
  import misc/[util, custom_logger, rope_utils, jsonex]
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
  import service, document_editor, document, text_component, text_editor_component, language_component
  import nimsumtree/rope
  import ui/node

  export previewer

  logCategory "data-previewer"

  type
    DataPreviewer* = ref object of Previewer
      editor*: DocumentEditor
      tempDocument: Document
      getPreviewTextImpl: proc(item: FinderItem): string {.gcsafe, raises: [].}

  proc dataPreviewerSetPath(self: Previewer, path: string) =
    let self = self.DataPreviewer
    self.tempDocument.filename = path

  proc dataPreviewerActivate(self: DataPreviewer) =
    discard

  proc dataPreviewerDeactivate(self: DataPreviewer) =
    discard

  proc dataPreviewerPreviewItem(self: DataPreviewer, item: FinderItem, editor: DocumentEditor) =
    let edit = editor.getTextEditorComponent().getOr:
      return

    self.editor = editor
    self.editor.setDocument(self.tempDocument)

    let text = self.tempDocument.getTextComponent().get
    if self.getPreviewTextImpl.isNotNil:
      text.content = self.getPreviewTextImpl(item)
    else:
      text.content = item.data

    edit.selection = point(0, 0).toRange
    edit.setCursorScrollOffset(point(0, 0), 0)

  proc dataPreviewerDelayPreview(self: DataPreviewer) =
    discard

  proc dataPreviewerDeinit(self: DataPreviewer) =
    logScope lvlInfo, &"[deinit] Destroying data file previewer"

    self[] = default(typeof(self[]))

  proc newDataPreviewer*(language = string.none, getPreviewTextImpl: GetPreviewTextImpl = nil): Previewer =
    let res = DataPreviewer()
    res.activateImpl = proc (self: Previewer) =
      self.DataPreviewer.dataPreviewerActivate()
    res.deactivateImpl = proc (self: Previewer) =
      self.DataPreviewer.dataPreviewerDeactivate()
    res.previewItemImpl = proc (self: Previewer, item: FinderItem, editor: DocumentEditor) =
      self.DataPreviewer.dataPreviewerPreviewItem(item, editor)
    res.delayPreviewImpl = proc (self: Previewer) =
      self.DataPreviewer.dataPreviewerDelayPreview()
    res.deinitImpl = proc (self: Previewer) =
      self.DataPreviewer.dataPreviewerDeinit()

    let document = getServiceChecked(DocumentEditorService).createDocument("text", ".txt", load = false, %%*{"createLanguageServer": false})
    if document == nil:
      return
    document.usage = "data-previewer-temp"
    if language.isSome:
      document.getLanguageComponent().get.setLanguageId(language.get)
    res.tempDocument = document
    res.getPreviewTextImpl = getPreviewTextImpl
    res.renderImpl = proc(self: Previewer, builder: UINodeBuilder): seq[OverlayFunction] =
      let self = self.DataPreviewer
      if self.editor.isNotNil:
        result.add self.editor.render(builder)

    return res
