import editor, document_editor, popup, widgets

method updateWidget*(self: DocumentEditor, app: Editor, widget: WPanel, frameIndex: int) {.base.} = discard
method updateWidget*(self: Popup, app: Editor, widget: WPanel, frameIndex: int) {.base.} = discard
