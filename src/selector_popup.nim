import std/[strutils, sugar, options]
import bumpy, vmath, windy
import editor, text_document, popup, events, util, rect_utils

type
  SelectorItem* = ref object of RootObj
    score*: float32

  SelectorPopup* = ref object of Popup
    editor*: Editor
    textEditor*: TextDocumentEditor
    selected*: int
    completions*: seq[SelectorItem]
    handleItemConfirmed*: proc(item: SelectorItem)
    handleItemSelected*: proc(item: SelectorItem)
    getCompletions*: proc(self: SelectorPopup, text: string): seq[SelectorItem]
    lastContentBounds*: Rect
    lastItems*: seq[tuple[index: int, bounds: Rect]]

proc updateCompletions(self: SelectorPopup) =
  let text = self.textEditor.document.content.join

  self.completions = self.getCompletions(self, text)

  if self.completions.len > 0:
    self.selected = self.selected.clamp(0, self.completions.len - 1)
  else:
    self.selected = 0

proc getItemAtPixelPosition(self: SelectorPopup, posWindow: Vec2): Option[SelectorItem] =
  result = SelectorItem.none
  for (index, rect) in self.lastItems:
    if rect.contains(posWindow) and index >= 0 and index <= self.completions.high:
      return self.completions[index].some

method getEventHandlers*(self: SelectorPopup): seq[EventHandler] =
  return @[self.eventHandler] & self.textEditor.eventHandler

proc handleAction*(self: SelectorPopup, action: string, arg: string): EventResponse =
  case action
  of "accept":
    if self.selected < self.completions.len:
      self.handleItemConfirmed self.completions[self.selected]
    self.editor.popPopup(self)

  of "cancel":
    self.editor.popPopup(self)

  of "prev":
    self.selected = if self.completions.len == 0:
      0
    else:
      (self.selected + self.completions.len - 1) mod self.completions.len

    if self.completions.len > 0 and self.handleItemSelected != nil:
      self.handleItemSelected self.completions[self.selected]

  of "next":
    self.selected = if self.completions.len == 0:
      0
    else:
      (self.selected + 1) mod self.completions.len

    if self.completions.len > 0 and self.handleItemSelected != nil:
      self.handleItemSelected self.completions[self.selected]

  else:
    return self.editor.handleUnknownPopupAction(self, action, arg)

  return Handled

proc handleTextChanged*(self: SelectorPopup) =
  self.updateCompletions()
  self.selected = 0

method handleScroll*(self: SelectorPopup, scroll: Vec2, mousePosWindow: Vec2) =
  self.selected = clamp(self.selected - scroll.y.int, 0, self.completions.len - 1)

method handleMousePress*(self: SelectorPopup, button: Button, mousePosWindow: Vec2) =
  if button == MouseLeft:
    if self.getItemAtPixelPosition(mousePosWindow).getSome(item):
      self.handleItemConfirmed(item)
      self.editor.popPopup(self)

method handleMouseRelease*(self: SelectorPopup, button: Button, mousePosWindow: Vec2) =
  discard

method handleMouseMove*(self: SelectorPopup, mousePosWindow: Vec2, mousePosDelta: Vec2) =
  discard

proc newSelectorPopup*(editor: Editor, getCompletions: proc(self: SelectorPopup, text: string): seq[SelectorItem]): SelectorPopup =
  var popup = SelectorPopup(editor: editor)
  popup.textEditor = newTextEditor(newTextDocument(), editor)
  popup.textEditor.renderHeader = false
  popup.textEditor.document.singleLine = true
  discard popup.textEditor.document.textChanged.subscribe (doc: TextDocument) => popup.handleTextChanged()
  popup.getCompletions = getCompletions

  popup.eventHandler = eventHandler(editor.getEventHandlerConfig("popup.selector")):
    onAction:
      popup.handleAction action, arg
    onInput:
      Ignored

  popup.updateCompletions()
  if popup.completions.len > 0 and popup.handleItemSelected != nil:
    popup.handleItemSelected popup.completions[0]

  return popup