import previewer

const currentSourcePath2 = currentSourcePath()
include module_base

{.push modrtl, gcsafe, raises: [].}
proc newOpenEditorPreviewer*(): Previewer
{.pop.}

when implModule:
  import std/[options, strformat, strutils]
  import nimsumtree/[rope]
  import misc/[util, custom_logger]
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
  import finder, document_editor, service
  import text_editor_component
  import ui/node

  logCategory "open-editor-previewer"

  type
    OpenEditorPreviewer* = ref object of Previewer
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

    let editorToPreview = getServiceChecked(DocumentEditorService).getEditor(editorId.EditorIdNew).getOr:
      return

    let tecToPreview = editorToPreview.getTextEditorComponent().getOr:
      return

    let tec = editor.getTextEditorComponent().getOr:
      return

    editor.setDocument(editorToPreview.currentDocument)
    tec.selection = tecToPreview.selection
    tec.centerCursor(point(0, 0), 0, snap = true)

  proc newOpenEditorPreviewer*(): Previewer =
    let res = OpenEditorPreviewer()
    res.previewItemImpl = proc(self: Previewer, item: FinderItem, editor: DocumentEditor) = previewItemImpl(self.OpenEditorPreviewer, item, editor)
    res.deinitImpl = proc(self: Previewer) = deinitImpl(self.OpenEditorPreviewer)
    res.renderImpl = proc(self: Previewer, builder: UINodeBuilder): seq[OverlayFunction] =
      let self = self.OpenEditorPreviewer
      if self.editor.isNotNil:
        result.add self.editor.render(builder)

    return res
