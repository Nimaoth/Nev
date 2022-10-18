import events

from scripting_api import EditorId, newEditorId

type Popup* = ref object of RootObj
  id: EditorId
  eventHandler*: EventHandler

var nextEditorId = 0

func id*(self: Popup): EditorId = self.id

proc init*(self: Popup) =
  self.id = newEditorId()

method getEventHandlers*(self: Popup): seq[EventHandler] {.base.} =
  return @[self.eventHandler]
