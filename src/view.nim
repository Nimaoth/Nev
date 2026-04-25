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

proc viewLeftLeaf*(self: View): View
proc viewRightLeaf*(self: View): View
proc viewTopLeaf*(self: View): View
proc viewBottomLeaf*(self: View): View
proc viewTryGetViewLeft*(self: View): View
proc viewTryGetViewRight*(self: View): View
proc viewTryGetViewUp*(self: View): View
proc viewTryGetViewDown*(self: View): View
{.pop.}

when implModule:
  import std/[sets, json]
  method dump*(self: View): string {.base.} = "View"

  method desc*(self: View): string {.base.} = "View"

  method kind*(self: View): string {.base.} = ""

  method display*(self: View): string {.base.} = ""

  method copy*(self: View): View {.base.} = assert(false)

  method close*(view: View) {.base.} =
    discard

  method activate*(view: View) {.base.} =
    view.active = true

  method deactivate*(view: View) {.base.} =
    view.active = false

  method checkDirty*(view: View) {.base.} =
    discard

  method markDirty*(self: View, notify: bool = true) {.base.} =
    self.markDirtyBase()

  method createUI*(view: View, builder: UINodeBuilder): seq[OverlayFunction] {.base.} =
    discard

  method getEventHandlers*(self: View, inject: Table[string, EventHandler]): seq[EventHandler] {.base.} =
    discard

  method getActiveEditor*(self: View): Option[DocumentEditor] {.base.} =
    discard

  method activeLeafView*(self: View): View {.base.} = self

  method saveState*(self: View): JsonNode {.base.} = nil

  method saveLayout*(self: View, discardedViews: HashSet[Id]): JsonNode {.base.} =
    result = newJObject()
    result["id"] = self.id.toJson

  method leftLeaf*(self: View): View {.base.} = self
  method rightLeaf*(self: View): View {.base.} = self
  method topLeaf*(self: View): View {.base.} = self
  method bottomLeaf*(self: View): View {.base.} = self

  method tryGetViewLeft*(self: View): View {.base.} = nil
  method tryGetViewRight*(self: View): View {.base.} = nil
  method tryGetViewUp*(self: View): View {.base.} = nil
  method tryGetViewDown*(self: View): View {.base.} = nil

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
  proc viewCopy*(view: View): View = copy(view)

  proc viewLeftLeaf*(self: View): View = leftLeaf(self)
  proc viewRightLeaf*(self: View): View = rightLeaf(self)
  proc viewTopLeaf*(self: View): View = topLeaf(self)
  proc viewBottomLeaf*(self: View): View = bottomLeaf(self)
  proc viewTryGetViewLeft*(self: View): View = tryGetViewLeft(self)
  proc viewTryGetViewRight*(self: View): View = tryGetViewRight(self)
  proc viewTryGetViewUp*(self: View): View = tryGetViewUp(self)
  proc viewTryGetViewDown*(self: View): View = tryGetViewDown(self)

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

  proc leftLeaf*(self: View): View = viewLeftLeaf(self)
  proc rightLeaf*(self: View): View = viewRightLeaf(self)
  proc topLeaf*(self: View): View = viewTopLeaf(self)
  proc bottomLeaf*(self: View): View = viewBottomLeaf(self)
  proc tryGetViewLeft*(self: View): View = viewTryGetViewLeft(self)
  proc tryGetViewRight*(self: View): View = viewTryGetViewRight(self)
  proc tryGetViewUp*(self: View): View = viewTryGetViewUp(self)
  proc tryGetViewDown*(self: View): View = viewTryGetViewDown(self)
