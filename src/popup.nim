import events, windy, vmath, bumpy

from scripting_api import PopupId, newPopupId

type Popup* = ref object of RootObj
  id: PopupId
  eventHandler*: EventHandler
  lastBounds*: Rect

func id*(self: Popup): PopupId = self.id

proc init*(self: Popup) =
  self.id = newPopupId()

method getEventHandlers*(self: Popup): seq[EventHandler] {.base.} =
  return @[self.eventHandler]

method handleScroll*(self: Popup, scroll: Vec2, mousePosWindow: Vec2) {.base.} =
  discard

method handleMousePress*(self: Popup, button: Button, mousePosWindow: Vec2) {.base.} =
  discard

method handleMouseRelease*(self: Popup, button: Button, mousePosWindow: Vec2) {.base.} =
  discard

method handleMouseMove*(self: Popup, mousePosWindow: Vec2, mousePosDelta: Vec2) {.base.} =
  discard