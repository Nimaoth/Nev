import document, events

from scripting_api import EditorId, newEditorId

type DocumentEditor* = ref object of RootObj
  id: EditorId
  eventHandler*: EventHandler
  renderHeader*: bool
  fillAvailableSpace*: bool

var nextEditorId = 0

func id*(self: DocumentEditor): EditorId = self.id

proc init*(self: DocumentEditor) =
  self.id = newEditorId()

  self.renderHeader = true
  self.fillAvailableSpace = true

method canEdit*(self: DocumentEditor, document: Document): bool {.base.} =
  return false

method createWithDocument*(self: DocumentEditor, document: Document): DocumentEditor {.base, locks: "unknown".} =
  return nil

method getEventHandlers*(self: DocumentEditor): seq[EventHandler] {.base.} =
  return @[]

method handleDocumentChanged*(self: DocumentEditor) {.base, locks: "unknown".} =
  discard

method unregister*(self: DocumentEditor) {.base.} =
  discard