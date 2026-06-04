import std/[options, json]
import vmath, bumpy
import misc/[event, id]
import input_handler/input_handler
import ui/node, view

import document_editor

from scripting_api import EditorId, newEditorId

{.push gcsafe.}
{.push raises: [].}

type Popup* = ref object of View
  userId*: Id
  lastBounds*: Rect
  scale*: Vec2
  initImpl*: proc(self: Popup) {.gcsafe, raises: [].}
  handleScrollImpl*: proc(self: Popup, scroll: Vec2, mousePosWindow: Vec2) {.gcsafe, raises: [].}
  handleMousePressImpl*: proc(self: Popup, button: MouseButton, mousePosWindow: Vec2) {.gcsafe, raises: [].}
  handleMouseReleaseImpl*: proc(self: Popup, button: MouseButton, mousePosWindow: Vec2) {.gcsafe, raises: [].}
  handleMouseMoveImpl*: proc(self: Popup, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) {.gcsafe, raises: [].}
  handleActionImpl*: proc(self: Popup, action: string, arg: string): Option[JsonNode] {.gcsafe, raises: [].}
  handleAddedToLayoutImpl*: proc(self: Popup) {.gcsafe, raises: [].}

proc init*(self: Popup) =
  self.userId = newId()
  if self.initImpl != nil:
    self.initImpl(self)

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

proc handleAction*(self: Popup, action: string, arg: string): Option[JsonNode] =
  if self.handleActionImpl != nil:
    return self.handleActionImpl(self, action, arg)
  return JsonNode.none

proc handleAddedToLayout*(self: Popup) =
  if self.handleAddedToLayoutImpl != nil:
    self.handleAddedToLayoutImpl(self)
