import std/[options, tables, json]
import misc/[event, id]
import events, document_editor

{.push gcsafe.}
{.push raises: [].}

type
  View* = ref object of RootObj
    mId*: Id
    active*: bool
    mDirty: bool
    onMarkedDirty*: Event[void]

  DebuggerView* = ref object of View

proc id*(self: View): Id =
  if self.mId == idNone():
    self.mId = newId()
  self.mId

proc initView*(self: View) =
  self.mId = newId()

func dirty*(self: View): bool = self.mDirty

proc resetDirty*(self: View) =
  self.mDirty = false

method close*(view: View) {.base.} =
  discard

method activate*(view: View) {.base.} =
  view.active = true

method deactivate*(view: View) {.base.} =
  view.active = false

proc markDirtyBase*(self: View, notify: bool = true) =
  if not self.mDirty and notify:
    self.mDirty = true
    self.onMarkedDirty.invoke()
  else:
    self.mDirty = true

method markDirty*(self: View, notify: bool = true) {.base.} =
  self.markDirtyBase()

method getEventHandlers*(self: View, inject: Table[string, EventHandler]): seq[EventHandler] {.base.} =
  discard

method getActiveEditor*(self: View): Option[DocumentEditor] {.base.} =
  discard

method saveState*(self: View): JsonNode {.base.} = nil
