import document, events, vmath, windy

from scripting_api import EditorId, newEditorId

type DocumentEditor* = ref object of RootObj
  id: EditorId
  eventHandler*: EventHandler
  renderHeader*: bool
  fillAvailableSpace*: bool

func id*(self: DocumentEditor): EditorId = self.id

proc init*(self: DocumentEditor) =
  self.id = newEditorId()

  self.renderHeader = true
  self.fillAvailableSpace = true

method canEdit*(self: DocumentEditor, document: Document): bool {.base.} =
  return false

method createWithDocument*(self: DocumentEditor, document: Document): DocumentEditor {.base.} =
  return nil

method getEventHandlers*(self: DocumentEditor): seq[EventHandler] {.base.} =
  return @[]

method handleDocumentChanged*(self: DocumentEditor) {.base.} =
  discard

method unregister*(self: DocumentEditor) {.base.} =
  discard

method handleScroll*(self: DocumentEditor, scroll: Vec2, mousePosWindow: Vec2) {.base.} =
  discard

method handleMousePress*(self: DocumentEditor, button: Button, mousePosWindow: Vec2) {.base.} =
  discard

method handleMouseRelease*(self: DocumentEditor, button: Button, mousePosWindow: Vec2) {.base.} =
  discard

method handleMouseMove*(self: DocumentEditor, mousePosWindow: Vec2, mousePosDelta: Vec2) {.base.} =
  discard