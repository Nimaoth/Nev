import vmath, bumpy
import misc/[event, id]
import events, input

from scripting_api import EditorId, newEditorId

type Popup* = ref object of RootObj
  id*: EditorId
  userId*: Id
  eventHandler*: EventHandler
  lastBounds*: Rect
  onMarkedDirty*: Event[void]
  mDirty: bool

func id*(self: Popup): EditorId = self.id

func dirty*(self: Popup): bool = self.mDirty

proc markDirty*(self: Popup) =
  if not self.mDirty:
    self.onMarkedDirty.invoke()
  self.mDirty = true

proc resetDirty*(self: Popup) =
  self.mDirty = false

proc init*(self: Popup) =
  self.id = newEditorId()
  self.userId = newId()

method deinit*(self: Popup) {.base.} = discard

method getEventHandlers*(self: Popup): seq[EventHandler] {.base.} =
  return @[self.eventHandler]

method handleScroll*(self: Popup, scroll: Vec2, mousePosWindow: Vec2) {.base.} =
  discard

method handleMousePress*(self: Popup, button: MouseButton, mousePosWindow: Vec2) {.base.} =
  discard

method handleMouseRelease*(self: Popup, button: MouseButton, mousePosWindow: Vec2) {.base.} =
  discard

method handleMouseMove*(self: Popup, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) {.base.} =
  discard