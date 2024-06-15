import std/[options, tables]
import events, document_editor

type
  View* = ref object of RootObj
    dirty*: bool
    active*: bool

  DebuggerView* = ref object of View

method activate*(view: View) {.base.} =
  view.active = true

method deactivate*(view: View) {.base.} =
  view.active = false

method markDirty*(view: View, notify: bool = true) {.base.} =
  view.dirty = true

method getEventHandlers*(self: View, inject: Table[string, EventHandler]): seq[EventHandler] {.base.} =
  discard

method getActiveEditor*(self: View): Option[DocumentEditor] {.base.} =
  discard
