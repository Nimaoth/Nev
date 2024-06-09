import app, view, document_editor, popup, ui/node

{.used.}

method createUI*(view: View, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] {.base.} =
  discard

method createUI*(self: DocumentEditor, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] {.base.} =
  discard

method createUI*(self: Popup, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] {.base.} =
  discard

func withAlpha*(color: Color, alpha: float32): Color =
  color(color.r, color.g, color.b, alpha)
