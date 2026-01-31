import document_editor
import ui/node

include dynlib_export

type OverlayRenderFunc* = proc() {.closure, gcsafe, raises: [].}

# DLL API
proc documentEditorRender(self: DocumentEditor, builder: UINodeBuilder): seq[OverlayRenderFunc] {.apprtl, gcsafe, raises: [].}

# Nice wrappers
proc render*(self: DocumentEditor, builder: UINodeBuilder): seq[OverlayRenderFunc] {.inline.} = documentEditorRender(self, builder)

when implModule:
  var renderEditorImpl*: proc(self: DocumentEditor, builder: UINodeBuilder): seq[OverlayRenderFunc] {.gcsafe, raises: [].}

  proc documentEditorRender(self: DocumentEditor, builder: UINodeBuilder): seq[OverlayRenderFunc] {.gcsafe, raises: [].} =
    {.gcsafe.}:
      if renderEditorImpl != nil:
        return renderEditorImpl(self, builder)
    return @[]
