import document, events, event, vmath, bumpy, input, custom_logger

from scripting_api import EditorId, newEditorId

type DocumentEditor* = ref object of RootObj
  id*: EditorId
  eventHandler*: EventHandler
  renderHeader*: bool
  fillAvailableSpace*: bool
  lastContentBounds*: Rect
  onMarkedDirty*: Event[void]
  mDirty: bool ## Set to true to trigger rerender
  active: bool

func id*(self: DocumentEditor): EditorId = self.id

proc init*(self: DocumentEditor) =
  self.id = newEditorId()

  self.renderHeader = true
  self.fillAvailableSpace = true

func dirty*(self: DocumentEditor): bool = self.mDirty

proc markDirty*(self: DocumentEditor) =
  if not self.mDirty:
    self.onMarkedDirty.invoke()
  self.mDirty = true

proc resetDirty*(self: DocumentEditor) =
  self.mDirty = false

proc `active=`*(self: DocumentEditor, newActive: bool) =
  if newActive != self.active:
    self.markDirty()

  self.active = newActive

func active*(self: DocumentEditor): bool = self.active

method shutdown*(self: DocumentEditor) {.base.} =
  discard

method canEdit*(self: DocumentEditor, document: Document): bool {.base.} =
  return false

method createWithDocument*(self: DocumentEditor, document: Document): DocumentEditor {.base.} =
  return nil

method getDocument*(self: DocumentEditor): Document {.base.} = discard

method getEventHandlers*(self: DocumentEditor): seq[EventHandler] {.base.} =
  return @[]

method handleDocumentChanged*(self: DocumentEditor) {.base.} =
  discard

method unregister*(self: DocumentEditor) {.base.} =
  discard

method handleScroll*(self: DocumentEditor, scroll: Vec2, mousePosWindow: Vec2) {.base.} =
  discard

method handleMousePress*(self: DocumentEditor, button: MouseButton, mousePosWindow: Vec2, modifiers: Modifiers) {.base.} =
  discard

method handleMouseRelease*(self: DocumentEditor, button: MouseButton, mousePosWindow: Vec2) {.base.} =
  discard

method handleMouseMove*(self: DocumentEditor, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) {.base.} =
  discard