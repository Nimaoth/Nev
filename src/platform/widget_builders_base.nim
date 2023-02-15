import editor, document_editor, widgets

method updateWidget*(self: DocumentEditor, app: Editor, widget: WPanel, frameIndex: int): bool {.base.} = discard
