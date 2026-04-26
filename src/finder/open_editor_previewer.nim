import std/[options, strformat, strutils]
import nimsumtree/[rope]
import misc/[util, custom_logger]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import finder, previewer, service, document_editor
import text_editor_component

logCategory "open-editor-previewer"

type
  OpenEditorPreviewer* = ref object of DynamicPreviewer
    services*: Services
    editors*: DocumentEditorService
    editor*: DocumentEditor

proc deinitImpl(self: OpenEditorPreviewer) =
  # logScope lvlInfo, &"[deinit] Destroying open editor previewer"
  self[] = default(typeof(self[]))

proc previewItemImpl(self: OpenEditorPreviewer, item: FinderItem, editor: DocumentEditor) =
  # logScope lvlInfo, &"previewItem {item}"

  self.editor = editor

  let editorId = item.data.parseInt.EditorId.catch:
    log lvlError, fmt"Failed to parse editor id from data '{item}'"
    return

  let editorToPreview = self.editors.getEditor(editorId.EditorIdNew).getOr:
    return

  let tecToPreview = editorToPreview.getTextEditorComponent().getOr:
    return

  let tec = editor.getTextEditorComponent().getOr:
    return

  editor.setDocument(editorToPreview.currentDocument)
  tec.selection = tecToPreview.selection
  tec.centerCursor(point(0, 0), 0, snap = true)

proc newOpenEditorPreviewer*(services: Services): OpenEditorPreviewer =
  new result
  result.services = services
  result.editors = services.getService(DocumentEditorService).get
  result.previewItemImpl = proc(self: DynamicPreviewer, item: FinderItem, editor: DocumentEditor) = previewItemImpl(self.OpenEditorPreviewer, item, editor)
  result.deinitImpl = proc(self: DynamicPreviewer) = deinitImpl(self.OpenEditorPreviewer)
