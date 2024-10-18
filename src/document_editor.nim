import std/[json, tables, options]
import vmath, bumpy
import misc/[event, custom_logger, id]
import document, events, input, config_provider
import platform/filesystem

from scripting_api import EditorId, newEditorId

{.push gcsafe.}
{.push raises: [].}

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
  fs*: Filesystem

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

method handleActivate*(self: DocumentEditor) {.base, gcsafe, raises: [].} = discard
method handleDeactivate*(self: DocumentEditor) {.base, gcsafe, raises: [].} = discard

method getNamespace*(self: DocumentEditor): string {.base, gcsafe, raises: [].} = discard

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

method deinit*(self: DocumentEditor) {.base, gcsafe, raises: [].} =
  discard

method canEdit*(self: DocumentEditor, document: Document): bool {.base, gcsafe, raises: [].} =
  return false

method createWithDocument*(self: DocumentEditor, document: Document, configProvider: ConfigProvider): DocumentEditor {.base, gcsafe, raises: [].} =
  return nil

method getDocument*(self: DocumentEditor): Document {.base, gcsafe, raises: [].} = discard

method handleAction*(self: DocumentEditor, action: string, arg: string, record: bool = true): Option[JsonNode] {.base, gcsafe, raises: [].} = discard

method getEventHandlers*(self: DocumentEditor, inject: Table[string, EventHandler]): seq[EventHandler] {.base, gcsafe, raises: [].} =
  return @[]

method handleDocumentChanged*(self: DocumentEditor) {.base, gcsafe, raises: [].} =
  discard

method unregister*(self: DocumentEditor) {.base, gcsafe, raises: [].} =
  discard

method handleScroll*(self: DocumentEditor, scroll: Vec2, mousePosWindow: Vec2) {.base, gcsafe, raises: [].} =
  discard

method handleMousePress*(self: DocumentEditor, button: MouseButton, mousePosWindow: Vec2, modifiers: Modifiers) {.base, gcsafe, raises: [].} =
  discard

method handleMouseRelease*(self: DocumentEditor, button: MouseButton, mousePosWindow: Vec2) {.base, gcsafe, raises: [].} =
  discard

method handleMouseMove*(self: DocumentEditor, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) {.base, gcsafe, raises: [].} =
  discard

method getStateJson*(self: DocumentEditor): JsonNode {.base, gcsafe, raises: [].} =
  return newJObject()

method restoreStateJson*(self: DocumentEditor, state: JsonNode) {.base, gcsafe, raises: [].} =
  discard

method getStatisticsString*(self: DocumentEditor): string {.base, gcsafe, raises: [].} = discard

import app_interface
method injectDependencies*(self: DocumentEditor, ed: AppInterface, fs: Filesystem) {.base, gcsafe, raises: [].} =
  discard
