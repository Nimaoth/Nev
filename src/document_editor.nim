import std/[json]
import document, events, event, input, custom_logger, config_provider, id
import vmath, bumpy

from scripting_api import EditorId, newEditorId

logCategory "document-editor"

type DocumentEditor* = ref object of RootObj
  id*: EditorId
  userId*: Id
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
  self.userId = newId()

  self.renderHeader = true
  self.fillAvailableSpace = true

func dirty*(self: DocumentEditor): bool = self.mDirty

proc markDirty*(self: DocumentEditor, notify: bool = true) =
  if not self.mDirty and notify:
    self.onMarkedDirty.invoke()
  self.mDirty = true

proc resetDirty*(self: DocumentEditor) =
  self.mDirty = false

method handleActivate*(self: DocumentEditor) {.base.} = discard
method handleDeactivate*(self: DocumentEditor) {.base.} = discard

proc `active=`*(self: DocumentEditor, newActive: bool) =
  let changed = if newActive != self.active:
    self.markDirty()
    true
  else:
    false

  self.active = newActive
  if changed:
    if self.active:
      self.handleActivate()
    else:
      self.handleDeactivate()

func active*(self: DocumentEditor): bool = self.active

method shutdown*(self: DocumentEditor) {.base.} =
  discard

method canEdit*(self: DocumentEditor, document: Document): bool {.base.} =
  return false

method createWithDocument*(self: DocumentEditor, document: Document, configProvider: ConfigProvider): DocumentEditor {.base.} =
  return nil

method getDocument*(self: DocumentEditor): Document {.base.} = discard

method handleAction*(self: DocumentEditor, action: string, arg: string): EventResponse {.base.} = discard

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

method getStateJson*(self: DocumentEditor): JsonNode {.base.} =
  discard

method restoreStateJson*(self: DocumentEditor, state: JsonNode) {.base.} =
  discard