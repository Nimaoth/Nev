import misc/[custom_logger, util]
import view

export view

include dynlib_export

{.push gcsafe, raises: [].}

type
  OverlayRenderFunc* = proc() {.closure, gcsafe, raises: [].}
  DynamicView* = ref object of View

when implModule:
  import std/[tables, json, sets]
  import misc/[custom_logger, util]
  import view, events
  import ui/node, document_editor

  method close*(view: DynamicView) =
    if view.closeImpl != nil:
      view.closeImpl(view)

  method activate*(view: DynamicView) =
    if view.activateImpl != nil:
      view.activateImpl(view)
    else:
      if view.active:
        return
      view.active = true
      view.markDirtyBase()

  method deactivate*(view: DynamicView) =
    if view.deactivateImpl != nil:
      view.deactivateImpl(view)
    else:
      if not view.active:
        return
      view.active = false
      view.markDirtyBase()

  method checkDirty*(view: DynamicView) =
    if view.checkDirtyImpl != nil:
      view.checkDirtyImpl(view)

  method markDirty*(view: DynamicView, notify: bool = true) =
    if view.markDirtyImpl != nil:
      view.markDirtyImpl(view, notify)
    else:
      view.markDirtyBase(notify)

  method getEventHandlers*(view: DynamicView, inject: Table[string, EventHandler]): seq[EventHandler] =
    if view.getEventHandlersImpl != nil:
      return view.getEventHandlersImpl(view, inject)

  method getActiveEditor*(view: DynamicView): Option[DocumentEditor] =
    if view.getActiveEditorImpl != nil:
      return view.getActiveEditorImpl(view)

  method saveLayout*(self: DynamicView, discardedViews: HashSet[Id]): JsonNode =
    if self.saveLayoutImpl != nil:
      return self.saveLayoutImpl(self, discardedViews)
    else:
      result = newJObject()
      result["id"] = self.id.toJson

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
