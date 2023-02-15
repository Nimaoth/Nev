import document, events, vmath, bumpy, input

from scripting_api import EditorId, newEditorId

type DocumentEditor* = ref object of RootObj
  id*: EditorId
  eventHandler*: EventHandler
  renderHeader*: bool
  fillAvailableSpace*: bool
  lastContentBounds*: Rect
  dirty*: bool ## Set to true to trigger rerender
  active: bool

func id*(self: DocumentEditor): EditorId = self.id

proc init*(self: DocumentEditor) =
  self.id = newEditorId()

  self.renderHeader = true
  self.fillAvailableSpace = true

proc `active=`*(self: DocumentEditor, newActive: bool) =
  self.dirty = self.dirty or (newActive != self.active)
  self.active = newActive

proc active*(self: DocumentEditor): bool = self.active

method shutdown*(self: DocumentEditor) {.base.} =
  discard

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

method handleMousePress*(self: DocumentEditor, button: MouseButton, mousePosWindow: Vec2) {.base.} =
  discard

method handleMouseRelease*(self: DocumentEditor, button: MouseButton, mousePosWindow: Vec2) {.base.} =
  discard

method handleMouseMove*(self: DocumentEditor, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) {.base.} =
  discard