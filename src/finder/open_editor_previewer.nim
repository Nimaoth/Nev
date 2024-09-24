import std/[options, strformat, strutils]
import misc/[util, custom_logger]
import text/[text_editor, text_document]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import finder, previewer
import app_interface, config_provider

logCategory "open-editor-previewer"

type
  OpenEditorPreviewer* = ref object of Previewer
    configProvider: ConfigProvider

proc newOpenEditorPreviewer*(configProvider: ConfigProvider): OpenEditorPreviewer =
  new result

method deinit*(self: OpenEditorPreviewer) =
  logScope lvlInfo, &"[deinit] Destroying open editor previewer"

  self[] = default(typeof(self[]))

method delayPreview*(self: OpenEditorPreviewer) =
  discard

method previewItem*(self: OpenEditorPreviewer, item: FinderItem, editor: DocumentEditor) =
  logScope lvlInfo, &"previewItem {item}"

  if not (editor of TextDocumentEditor):
    return

  let editorId = item.data.parseInt.EditorId.catch:
    log lvlError, fmt"Failed to parse editor id from data '{item}'"
    return

  let editor = editor.TextDocumentEditor
  let app = editor.app

  let editorToPreview = app.getEditorForId(editorId).getOr:
    return

  if not (editorToPreview of TextDocumentEditor):
    return

  let textEditorToPreview = editorToPreview.TextDocumentEditor
  editor.setDocument(textEditorToPreview.document)
  editor.selection = textEditorToPreview.selection
  editor.centerCursor()
