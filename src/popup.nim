import std/[options, json]
import vmath, bumpy
import misc/[event, id]
import events, input
import ui/node

import document_editor

from scripting_api import EditorId, newEditorId

{.push gcsafe.}
{.push raises: [].}

type Popup* = ref object of RootObj
  id*: EditorId
  userId*: Id
  lastBounds*: Rect
  onMarkedDirty*: Event[void]
  mDirty: bool
  initImpl*: proc(self: Popup) {.gcsafe, raises: [].}
  deinitImpl*: proc(self: Popup) {.gcsafe, raises: [].}
  cancelImpl*: proc(self: Popup) {.gcsafe, raises: [].}
  getEventHandlersImpl*: proc(self: Popup): seq[EventHandler] {.gcsafe, raises: [].}
  handleScrollImpl*: proc(self: Popup, scroll: Vec2, mousePosWindow: Vec2) {.gcsafe, raises: [].}
  handleMousePressImpl*: proc(self: Popup, button: MouseButton, mousePosWindow: Vec2) {.gcsafe, raises: [].}
  handleMouseReleaseImpl*: proc(self: Popup, button: MouseButton, mousePosWindow: Vec2) {.gcsafe, raises: [].}
  handleMouseMoveImpl*: proc(self: Popup, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) {.gcsafe, raises: [].}
  getActiveEditorImpl*: proc(self: Popup): Option[DocumentEditor] {.gcsafe, raises: [].}
  handleActionImpl*: proc(self: Popup, action: string, arg: string): Option[JsonNode] {.gcsafe, raises: [].}
  renderImpl*: proc(self: Popup, builder: UINodeBuilder): seq[OverlayFunction] {.gcsafe, raises: [].}

func id*(self: Popup): EditorId = self.id

func dirty*(self: Popup): bool = self.mDirty

proc markDirty*(self: Popup) =
  if not self.mDirty:
    self.onMarkedDirty.invoke()
  self.mDirty = true

proc resetDirty*(self: Popup) =
  self.mDirty = false

proc init*(self: Popup) =
  self.id = newEditorId()
  self.userId = newId()
  if self.initImpl != nil:
    self.initImpl(self)

proc deinit*(self: Popup) =
  if self.deinitImpl != nil:
    self.deinitImpl(self)

proc cancel*(self: Popup) =
  if self.cancelImpl != nil:
    self.cancelImpl(self)

proc getEventHandlers*(self: Popup): seq[EventHandler] =
  if self.getEventHandlersImpl != nil:
    return self.getEventHandlersImpl(self)
  return @[]

proc handleScroll*(self: Popup, scroll: Vec2, mousePosWindow: Vec2) =
  if self.handleScrollImpl != nil:
    self.handleScrollImpl(self, scroll, mousePosWindow)

proc handleMousePress*(self: Popup, button: MouseButton, mousePosWindow: Vec2) =
  if self.handleMousePressImpl != nil:
    self.handleMousePressImpl(self, button, mousePosWindow)

proc handleMouseRelease*(self: Popup, button: MouseButton, mousePosWindow: Vec2) =
  if self.handleMouseReleaseImpl != nil:
    self.handleMouseReleaseImpl(self, button, mousePosWindow)

proc handleMouseMove*(self: Popup, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
  if self.handleMouseMoveImpl != nil:
    self.handleMouseMoveImpl(self, mousePosWindow, mousePosDelta, modifiers, buttons)

proc getActiveEditor*(self: Popup): Option[DocumentEditor] =
  if self.getActiveEditorImpl != nil:
    return self.getActiveEditorImpl(self)

proc handleAction*(self: Popup, action: string, arg: string): Option[JsonNode] =
  if self.handleActionImpl != nil:
    return self.handleActionImpl(self, action, arg)
  return JsonNode.none

proc createUI*(self: Popup, builder: UINodeBuilder): seq[OverlayFunction] =
  if self.renderImpl != nil:
    return self.renderImpl(self, builder)
  return @[]
