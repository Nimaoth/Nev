import editor, document_editor, popup, widgets, selector_popup

method updateWidget*(self: DocumentEditor, app: Editor, widget: WPanel, frameIndex: int) {.base.} = discard
method updateWidget*(self: Popup, app: Editor, widget: WPanel, frameIndex: int) {.base.} = discard
method updateWidget*(self: SelectorItem, app: Editor, widget: WPanel, frameIndex: int) {.base.} = discard