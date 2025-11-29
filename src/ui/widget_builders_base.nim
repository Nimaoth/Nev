import view, document_editor, popup, ui/node, finder/previewer

{.used.}

type OverlayFunction* = proc() {.closure, gcsafe, raises: [].}

{.push gcsafe.}
{.push raises: [].}

method createUI*(view: View, builder: UINodeBuilder): seq[OverlayFunction] {.base.} =
  discard

method createUI*(self: DocumentEditor, builder: UINodeBuilder): seq[OverlayFunction] {.base.} =
  discard

method createUI*(self: Popup, builder: UINodeBuilder): seq[OverlayFunction] {.base.} =
  discard

method createUI*(self: Previewer, builder: UINodeBuilder): seq[OverlayFunction] {.base.} =
  discard

func withAlpha*(color: Color, alpha: float32): Color =
  color(color.r, color.g, color.b, alpha)
