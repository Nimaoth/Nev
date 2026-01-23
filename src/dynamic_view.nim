
import std/[tables, json]
import misc/[custom_logger, util]
import view, events, layouts
import ui/node

export view

{.push gcsafe, raises: [].}

type
  OverlayRenderFunc* = proc() {.closure, gcsafe, raises: [].}
  DynamicView* = ref object of View
    render*: proc(builder: UINodeBuilder): seq[OverlayRenderFunc] {.gcsafe, raises: [].}
    closeImpl*: proc(view: DynamicView) {.gcsafe, raises: [].}
    activateImpl*: proc(view: DynamicView) {.gcsafe, raises: [].}
    deactivateImpl*: proc(view: DynamicView) {.gcsafe, raises: [].}
    checkDirtyImpl*: proc(view: DynamicView) {.gcsafe, raises: [].}
    markDirtyImpl*: proc(view: DynamicView, notify: bool = true) {.gcsafe, raises: [].}
    getEventHandlersImpl*: proc(view: DynamicView, inject: Table[string, EventHandler]): seq[EventHandler] {.gcsafe, raises: [].}
    # getActiveEditorImpl*: proc(view: DynamicView): Option[DocumentEditor] {.gcsafe, raises: [].}
    saveStateImpl*: proc(view: DynamicView): JsonNode {.gcsafe, raises: [].}
    descImpl*: proc(self: DynamicView): string {.gcsafe, raises: [].}
    kindImpl*: proc(self: DynamicView): string {.gcsafe, raises: [].}
    copyImpl*: proc(self: DynamicView): View {.gcsafe, raises: [].}
    displayImpl*: proc(self: DynamicView): string {.gcsafe, raises: [].}

method close*(view: DynamicView) =
  if view.closeImpl != nil:
    view.closeImpl(view)

method activate*(view: DynamicView) =
  if view.activateImpl != nil:
    view.activateImpl(view)

method deactivate*(view: DynamicView) =
  if view.deactivateImpl != nil:
    view.deactivateImpl(view)

method checkDirty*(view: DynamicView) =
  if view.checkDirtyImpl != nil:
    view.checkDirtyImpl(view)

method markDirty*(view: DynamicView, notify: bool = true) =
  if view.markDirtyImpl != nil:
    view.markDirtyImpl(view, notify)

method getEventHandlers*(view: DynamicView, inject: Table[string, EventHandler]): seq[EventHandler] =
  if view.getEventHandlersImpl != nil:
    return view.getEventHandlersImpl(view, inject)

# method getActiveEditor*(view: DynamicView): Option[DocumentEditor] =
#   if view.getActiveEditorImpl != nil:
#     return view.getActiveEditorImpl(view)

method saveState*(view: DynamicView): JsonNode =
  if view.saveStateImpl != nil:
    return view.saveStateImpl(view)

method desc*(self: DynamicView): string =
  if self.descImpl != nil:
    return self.descImpl(self)
method kind*(self: DynamicView): string =
  if self.kindImpl != nil:
    return self.kindImpl(self)
method copy*(self: DynamicView): View =
  if self.copyImpl != nil:
    return self.copyImpl(self)
method display*(self: DynamicView): string =
  if self.displayImpl != nil:
    return self.displayImpl(self)
