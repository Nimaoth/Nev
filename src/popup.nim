import events

type Popup* = ref object of RootObj
  eventHandler*: EventHandler

method getEventHandlers*(self: Popup): seq[EventHandler] {.base.} =
  return @[self.eventHandler]
