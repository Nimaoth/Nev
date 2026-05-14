import std/[options, tables, json, sets]
import misc/[event, id]
import input_handler/input_handler, document_editor
import bumpy
import ui/node

include misc/dynlib_export

{.push gcsafe.}
{.push raises: [].}

type
  View* = ref object of RootObj
    mId*: Id
    mId2: int32
    active*: bool
    mDirty: bool
    onMarkedDirty*: Event[void]
    onDetached*: Event[void]
    detached*: bool # Whether the view is detached from any parent and can be moved around freely
    absoluteBounds*: Rect # Absolute bounds when detached
    renderImpl*: proc(view: View, builder: UINodeBuilder): seq[OverlayFunction] {.gcsafe, raises: [].}
    copyImpl*: proc(self: View): View {.gcsafe, raises: [].}
    closeImpl*: proc(view: View) {.gcsafe, raises: [].}
    activateImpl*: proc(view: View) {.gcsafe, raises: [].}
    deactivateImpl*: proc(view: View) {.gcsafe, raises: [].}
    checkDirtyImpl*: proc(view: View) {.gcsafe, raises: [].}
    markDirtyImpl*: proc(view: View, notify: bool = true) {.gcsafe, raises: [].}
    getEventHandlersImpl*: proc(view: View, inject: Table[string, EventHandler]): seq[EventHandler] {.gcsafe, raises: [].}
    getActiveEditorImpl*: proc(view: View): Option[DocumentEditor] {.gcsafe, raises: [].}
    activeLeafViewImpl*: proc(view: View): View {.gcsafe, raises: [].}
    saveLayoutImpl*: proc(view: View, discardedViews: HashSet[Id]): JsonNode {.gcsafe, raises: [].}
    saveStateImpl*: proc(view: View): JsonNode {.gcsafe, raises: [].}
    dumpImpl*: proc(self: View): string {.gcsafe, raises: [].}
    descImpl*: proc(self: View): string {.gcsafe, raises: [].}
    kindImpl*: proc(self: View): string {.gcsafe, raises: [].}
    displayImpl*: proc(self: View): string {.gcsafe, raises: [].}

var viewIdCounter {.apprtlvar.}: int32 = 1

proc id*(self: View): Id =
  if self.mId == idNone():
    self.mId = newId()
  self.mId

proc id2*(self: View): int32 =
  if self.mId2 == 0:
    self.mId2 = viewIdCounter
    inc(viewIdCounter)
  self.mId2

proc initView*(self: View) =
  self.mId = newId()
  discard self.id2()

proc detach*(self: View, bounds: Rect) =
  if not self.detached:
    self.absoluteBounds = bounds
    self.detached = true
    self.onDetached.invoke()

func dirty*(self: View): bool = self.mDirty

proc resetDirty*(self: View) =
  self.mDirty = false

proc markDirtyBase*(self: View, notify: bool = true) =
  if not self.mDirty and notify:
    self.mDirty = true
    self.onMarkedDirty.invoke()
  else:
    self.mDirty = true

proc dump*(self: View): string =
  if self.dumpImpl != nil:
    return self.dumpImpl(self)
  return "View"

proc desc*(self: View): string =
  if self.descImpl != nil:
    return self.descImpl(self)
  return "View"

proc kind*(self: View): string =
  if self.kindImpl != nil:
    return self.kindImpl(self)
  return ""

proc display*(self: View): string =
  if self.displayImpl != nil:
    return self.displayImpl(self)
  return ""

proc copy*(self: View): View =
  if self.copyImpl != nil:
    return self.copyImpl(self)
  assert(false)

proc close*(view: View) =
  if view.closeImpl != nil:
    view.closeImpl(view)

proc activate*(view: View) =
  if view.activateImpl != nil:
    view.activateImpl(view)
  else:
    if view.active:
      return
    view.active = true
    view.markDirtyBase()

proc deactivate*(view: View) =
  if view.deactivateImpl != nil:
    view.deactivateImpl(view)
  else:
    if not view.active:
      return
    view.active = false
    view.markDirtyBase()

proc checkDirty*(view: View) =
  if view.checkDirtyImpl != nil:
    view.checkDirtyImpl(view)

proc markDirty*(self: View, notify: bool = true) =
  if self.markDirtyImpl != nil:
    self.markDirtyImpl(self, notify)
  else:
    self.markDirtyBase(notify)

proc createUI*(view: View, builder: UINodeBuilder): seq[OverlayFunction] =
  if view.renderImpl != nil:
    return view.renderImpl(view, builder)
  return @[]

proc getEventHandlers*(self: View, inject: Table[string, EventHandler]): seq[EventHandler] =
  if self.getEventHandlersImpl != nil:
    return self.getEventHandlersImpl(self, inject)

proc getActiveEditor*(self: View): Option[DocumentEditor] =
  if self.getActiveEditorImpl != nil:
    return self.getActiveEditorImpl(self)

proc activeLeafView*(self: View): View =
  if self.activeLeafViewImpl != nil:
    return self.activeLeafViewImpl(self)
  return self

proc saveState*(self: View): JsonNode =
  if self.saveStateImpl != nil:
    return self.saveStateImpl(self)
  return nil

proc saveLayout*(self: View, discardedViews: HashSet[Id]): JsonNode =
  if self.saveLayoutImpl != nil:
    return self.saveLayoutImpl(self, discardedViews)
  else:
    result = newJObject()
    result["id"] = self.id.toJson

proc render*(self: View, builder: UINodeBuilder): seq[OverlayFunction] =
  if self.renderImpl != nil:
    return self.renderImpl(self, builder)
  return @[]
