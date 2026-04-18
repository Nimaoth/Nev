import std/[options, strformat]
import misc/[util, custom_logger, rope_utils, jsonex]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import finder, previewer
import service, document_editor, document, text_component, text_editor_component, language_component
import nimsumtree/rope

export previewer

logCategory "data-previewer"

type
  DataPreviewer* = ref object of DynamicPreviewer
    editor*: DocumentEditor
    tempDocument: Document
    getPreviewTextImpl: proc(item: FinderItem): string {.gcsafe, raises: [].}

proc setPath*(self: DataPreviewer, path: string) =
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

proc newDataPreviewer*(services: Services, language = string.none,
    getPreviewTextImpl: proc(item: FinderItem): string {.gcsafe, raises: [].} = nil): DataPreviewer =

  new result
  result.activateImpl = proc (self: DynamicPreviewer) =
    self.DataPreviewer.dataPreviewerActivate()
  result.deactivateImpl = proc (self: DynamicPreviewer) =
    self.DataPreviewer.dataPreviewerDeactivate()
  result.previewItemImpl = proc (self: DynamicPreviewer, item: FinderItem, editor: DocumentEditor) =
    self.DataPreviewer.dataPreviewerPreviewItem(item, editor)
  result.delayPreviewImpl = proc (self: DynamicPreviewer) =
    self.DataPreviewer.dataPreviewerDelayPreview()
  result.deinitImpl = proc (self: DynamicPreviewer) =
    self.DataPreviewer.dataPreviewerDeinit()

  let document = getServiceChecked(DocumentEditorService).createDocument("text", ".txt", load = false, %%*{"createLanguageServer": false})
  if document == nil:
    return
  document.usage = "data-previewer-temp"
  document.setReadOnly(true)
  if language.isSome:
    document.getLanguageComponent().get.setLanguageId(language.get)
  result.tempDocument = document
  result.getPreviewTextImpl = getPreviewTextImpl
