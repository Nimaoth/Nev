import events, input, vmath, bumpy

from scripting_api import EditorId, newEditorId

type Popup* = ref object of RootObj
  id: EditorId
  eventHandler*: EventHandler
  lastBounds*: Rect

func id*(self: Popup): EditorId = self.id

proc init*(self: Popup) =
  self.id = newEditorId()

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