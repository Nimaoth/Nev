import app, document_editor, popup, widgets, selector_popup, ui/node

method updateWidget*(self: DocumentEditor, app: App, widget: WPanel, mainPanel: WPanel, frameIndex: int) {.base.} = discard
method updateWidget*(self: Popup, app: App, widget: WPanel, mainPanel: WPanel, frameIndex: int) {.base.} = discard
method updateWidget*(self: SelectorItem, app: App, widget: WPanel, frameIndex: int) {.base.} = discard

method createUI*(self: DocumentEditor, builder: UINodeBuilder, app: App) {.base.} = discard
method createUI*(self: Popup, builder: UINodeBuilder, app: App) {.base.} = discard
method createUI*(self: SelectorItem, builder: UINodeBuilder, app: App) {.base.} = discard

func withAlpha*(color: Color, alpha: float32): Color = color(color.r, color.g, color.b, alpha)

{.used.}
