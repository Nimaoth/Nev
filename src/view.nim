import std/[options, tables, json]
import misc/[event, id]
import events, document_editor
import bumpy

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

proc viewClose(view: View) {.apprtl.}
proc viewActivate(view: View) {.apprtl.}
proc viewDeactivate(view: View) {.apprtl.}
proc viewCheckDirty(view: View) {.apprtl.}
proc viewMarkDirty(self: View, notify: bool = true) {.apprtl.}
proc viewGetEventHandlers(self: View, inject: Table[string, EventHandler]): seq[EventHandler] {.apprtl.}
proc viewGetActiveEditor(self: View): Option[DocumentEditor] {.apprtl.}
proc viewSaveState(self: View): JsonNode {.apprtl.}

when implModule:
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

  method getEventHandlers*(self: View, inject: Table[string, EventHandler]): seq[EventHandler] {.base.} =
    discard

  method getActiveEditor*(self: View): Option[DocumentEditor] {.base.} =
    discard

  method saveState*(self: View): JsonNode {.base.} = nil

  proc viewClose(view: View) = close(view)
  proc viewActivate(view: View) = activate(view)
  proc viewDeactivate(view: View) = deactivate(view)
  proc viewCheckDirty(view: View) = checkDirty(view)
  proc viewMarkDirty(self: View, notify: bool = true) = markDirty(self, notify)
  proc viewGetEventHandlers(self: View, inject: Table[string, EventHandler]): seq[EventHandler] = getEventHandlers(self, inject)
  proc viewGetActiveEditor(self: View): Option[DocumentEditor] = getActiveEditor(self)
  proc viewSaveState(self: View): JsonNode = saveState(self)

else:
  proc close*(view: View) = viewClose(view)
  proc activate*(view: View) = viewActivate(view)
  proc deactivate*(view: View) = viewDeactivate(view)
  proc checkDirty*(view: View) = viewCheckDirty(view)
  proc markDirty*(self: View, notify: bool = true) = viewMarkDirty(self, notify)
  proc getEventHandlers*(self: View, inject: Table[string, EventHandler]): seq[EventHandler] = viewGetEventHandlers(self, inject)
  proc getActiveEditor*(self: View): Option[DocumentEditor] = viewGetActiveEditor(self)
  proc saveState*(self: View): JsonNode = viewSaveState(self)
