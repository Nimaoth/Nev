import editor, document_editor, popup, widgets, selector_popup

method updateWidget*(self: DocumentEditor, app: App, widget: WPanel, frameIndex: int) {.base.} = discard
method updateWidget*(self: Popup, app: App, widget: WPanel, frameIndex: int) {.base.} = discard
method updateWidget*(self: SelectorItem, app: App, widget: WPanel, frameIndex: int) {.base.} = discard

{.used.}
