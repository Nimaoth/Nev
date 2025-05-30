import std/[options, tables]
import misc/[event]
import events, document_editor

{.push gcsafe.}
{.push raises: [].}

type
  View* = ref object of RootObj
    active*: bool
    mDirty: bool
    onMarkedDirty*: Event[void]

  DebuggerView* = ref object of View

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
