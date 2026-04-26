import std/[options, tables, json, sets]
import misc/[event, id]
import events, document_editor
import bumpy
import ui/node

include dynlib_export

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

var viewIdCounter {.apprtl.}: int32 = 1

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

{.push apprtl.}
proc viewDump*(self: View): string
proc viewDesc*(self: View): string
proc viewKind*(self: View): string
proc viewDisplay*(self: View): string

proc viewClose*(view: View)
proc viewActivate*(view: View)
proc viewDeactivate*(view: View)
proc viewCheckDirty*(view: View)
proc viewMarkDirty*(self: View, notify: bool = true)
proc viewGetEventHandlers*(self: View, inject: Table[string, EventHandler]): seq[EventHandler]
proc viewGetActiveEditor*(self: View): Option[DocumentEditor]
proc viewActiveLeafView*(self: View): View
proc viewSaveState*(self: View): JsonNode
proc viewSaveLayout*(self: View, discardedViews: HashSet[Id]): JsonNode
proc viewCopy*(view: View): View

proc viewCreateUI(view: View, builder: UINodeBuilder): seq[OverlayFunction]
{.pop.}

when implModule:
  import std/[sets, json]
  method dump*(self: View): string {.base.} =
    if self.dumpImpl != nil:
      return self.dumpImpl(self)
    return "View"

  method desc*(self: View): string {.base.} =
    if self.descImpl != nil:
      return self.descImpl(self)
    return "View"

  method kind*(self: View): string {.base.} =
    if self.kindImpl != nil:
      return self.kindImpl(self)
    return ""

  method display*(self: View): string {.base.} =
    if self.displayImpl != nil:
      return self.displayImpl(self)
    return ""

  method copy*(self: View): View {.base.} =
    if self.copyImpl != nil:
      return self.copyImpl(self)
    assert(false)

  method close*(view: View) {.base.} =
    if view.closeImpl != nil:
      view.closeImpl(view)

  method activate*(view: View) {.base.} =
    if view.activateImpl != nil:
      view.activateImpl(view)
    else:
      if view.active:
        return
      view.active = true
      view.markDirtyBase()

  method deactivate*(view: View) {.base.} =
    if view.deactivateImpl != nil:
      view.deactivateImpl(view)
    else:
      if not view.active:
        return
      view.active = false
      view.markDirtyBase()

  method checkDirty*(view: View) {.base.} =
    if view.checkDirtyImpl != nil:
      view.checkDirtyImpl(view)

  method markDirty*(self: View, notify: bool = true) {.base.} =
    if self.markDirtyImpl != nil:
      self.markDirtyImpl(self, notify)
    else:
      self.markDirtyBase(notify)

  method createUI*(view: View, builder: UINodeBuilder): seq[OverlayFunction] {.base.} =
    if view.renderImpl != nil:
      return view.renderImpl(view, builder)
    return @[]

  method getEventHandlers*(self: View, inject: Table[string, EventHandler]): seq[EventHandler] {.base.} =
    if self.getEventHandlersImpl != nil:
      return self.getEventHandlersImpl(self, inject)

  method getActiveEditor*(self: View): Option[DocumentEditor] {.base.} =
    if self.getActiveEditorImpl != nil:
      return self.getActiveEditorImpl(self)

  method activeLeafView*(self: View): View {.base.} =
    if self.activeLeafViewImpl != nil:
      return self.activeLeafViewImpl(self)
    return self

  method saveState*(self: View): JsonNode {.base.} =
    if self.saveStateImpl != nil:
      return self.saveStateImpl(self)
    return nil

  method saveLayout*(self: View, discardedViews: HashSet[Id]): JsonNode {.base.} =
    if self.saveLayoutImpl != nil:
      return self.saveLayoutImpl(self, discardedViews)
    else:
      result = newJObject()
      result["id"] = self.id.toJson

  proc viewDump*(self: View): string = dump(self)
  proc viewDesc*(self: View): string = desc(self)
  proc viewKind*(self: View): string = kind(self)
  proc viewDisplay*(self: View): string = display(self)

  proc viewClose*(view: View) = close(view)
  proc viewActivate*(view: View) = activate(view)
  proc viewDeactivate*(view: View) = deactivate(view)
  proc viewCheckDirty*(view: View) = checkDirty(view)
  proc viewMarkDirty*(self: View, notify: bool = true) = markDirty(self, notify)
  proc viewGetEventHandlers*(self: View, inject: Table[string, EventHandler]): seq[EventHandler] = getEventHandlers(self, inject)
  proc viewGetActiveEditor*(self: View): Option[DocumentEditor] = getActiveEditor(self)
  proc viewActiveLeafView*(self: View): View = activeLeafView(self)
  proc viewSaveState*(self: View): JsonNode = saveState(self)
  proc viewSaveLayout*(self: View, discardedViews: HashSet[Id]): JsonNode = saveLayout(self, discardedViews)
  proc viewCopy*(view: View): View =
    if view.copyImpl != nil:
      view.copyImpl(view)
    else:
      copy(view)

  proc viewCreateUI(view: View, builder: UINodeBuilder): seq[OverlayFunction] = createUI(view, builder)

else:
  proc dump*(self: View): string = viewDump(self)
  proc desc*(self: View): string = viewDesc(self)
  proc kind*(self: View): string = viewKind(self)
  proc display*(self: View): string = viewDisplay(self)

  proc close*(view: View) = viewClose(view)
  proc activate*(view: View) = viewActivate(view)
  proc deactivate*(view: View) = viewDeactivate(view)
  proc checkDirty*(view: View) = viewCheckDirty(view)
  proc markDirty*(self: View, notify: bool = true) = viewMarkDirty(self, notify)
  proc getEventHandlers*(self: View, inject: Table[string, EventHandler]): seq[EventHandler] = viewGetEventHandlers(self, inject)
  proc getActiveEditor*(self: View): Option[DocumentEditor] = viewGetActiveEditor(self)
  proc activeLeafView*(self: View): View = viewActiveLeafView(self)
  proc saveState*(self: View): JsonNode = viewSaveState(self)
  proc saveLayout*(self: View, discardedViews: HashSet[Id]): JsonNode = viewSaveLayout(self, discardedViews)
  proc copy*(view: View): View = viewCopy(view)

  proc createUI*(view: View, builder: UINodeBuilder): seq[OverlayFunction] = viewCreateUI(view, builder)