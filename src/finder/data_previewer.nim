import std/[options, strformat]
import misc/[util, custom_logger]
import text/[text_editor, text_document]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import finder, previewer
import service

logCategory "data-previewer"

type
  DataPreviewer* = ref object of Previewer
    editor: TextDocumentEditor
    tempDocument: TextDocument
    getPreviewTextImpl: proc(item: FinderItem): string {.gcsafe, raises: [].}

proc newDataPreviewer*(services: Services, language = string.none,
    getPreviewTextImpl: proc(item: FinderItem): string {.gcsafe, raises: [].} = nil): DataPreviewer =

  new result

  result.tempDocument = newTextDocument(services, language=language, createLanguageServer=false)
  result.tempDocument.readOnly = true
  result.getPreviewTextImpl = getPreviewTextImpl

method deinit*(self: DataPreviewer) =
  logScope lvlInfo, &"[deinit] Destroying data file previewer"
  if self.tempDocument.isNotNil:
    self.tempDocument.deinit()

  self[] = default(typeof(self[]))

method delayPreview*(self: DataPreviewer) =
  discard

method previewItem*(self: DataPreviewer, item: FinderItem, editor: DocumentEditor) =
  if not (editor of TextDocumentEditor):
    return

  self.editor = editor.TextDocumentEditor
  self.editor.setDocument(self.tempDocument)
  self.editor.selection = (0, 0).toSelection
  self.editor.scrollToTop()

  if self.getPreviewTextImpl.isNotNil:
    self.tempDocument.content = self.getPreviewTextImpl(item)
  else:
    self.tempDocument.content = item.data
