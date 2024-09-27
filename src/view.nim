import std/[options, tables]
import events, document_editor

type
  View* = ref object of RootObj
    dirty*: bool
    active*: bool

  DebuggerView* = ref object of View

method activate*(view: View) {.base, gcsafe, raises: [].} =
  view.active = true

method deactivate*(view: View) {.base, gcsafe, raises: [].} =
  view.active = false

method markDirty*(view: View, notify: bool = true) {.base, gcsafe, raises: [].} =
  view.dirty = true

method getEventHandlers*(self: View, inject: Table[string, EventHandler]): seq[EventHandler] {.base, gcsafe, raises: [].} =
  discard

method getActiveEditor*(self: View): Option[DocumentEditor] {.base, gcsafe, raises: [].} =
  discard
