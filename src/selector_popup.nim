import std/[strutils, sugar, options, json, jsonutils, streams]
import bumpy, vmath
import editor, text_document, popup, events, util, rect_utils, scripting, event, input
from scripting_api as api import nil

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
    handleCanceled*: proc()
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
  return self.textEditor.getEventHandlers() & @[self.eventHandler]

proc getSelectorPopup(wrapper: api.SelectorPopup): Option[SelectorPopup] =
  if gEditor.isNil: return SelectorPopup.none
  if gEditor.getPopupForId(wrapper.id).getSome(editor):
    if editor of SelectorPopup:
      return editor.SelectorPopup.some
  return SelectorPopup.none

static:
  addTypeMap(SelectorPopup, api.SelectorPopup, getSelectorPopup)

proc toJson*(self: api.SelectorPopup, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["type"] = newJString("popup.selector")
  result["id"] = newJInt(self.id.int)

proc fromJsonHook*(t: var api.SelectorPopup, jsonNode: JsonNode) =
  t.id = api.EditorId(jsonNode["id"].jsonTo(int))

proc accept*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.selected < self.completions.len:
    self.handleItemConfirmed self.completions[self.selected]
  self.editor.popPopup(self)

proc cancel*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.handleCanceled != nil:
    self.handleCanceled()
  self.editor.popPopup(self)

proc prev*(self: SelectorPopup) {.expose("popup.selector").} =
  self.selected = if self.completions.len == 0:
    0
  else:
    (self.selected + self.completions.len - 1) mod self.completions.len

  if self.completions.len > 0 and self.handleItemSelected != nil:
    self.handleItemSelected self.completions[self.selected]

proc next*(self: SelectorPopup) {.expose("popup.selector").} =
  self.selected = if self.completions.len == 0:
    0
  else:
    (self.selected + 1) mod self.completions.len

  if self.completions.len > 0 and self.handleItemSelected != nil:
    self.handleItemSelected self.completions[self.selected]

genDispatcher("popup.selector")

proc handleAction*(self: SelectorPopup, action: string, arg: string): EventResponse =
  # echo "SelectorPopup.handleAction ", action, ", '", arg, "'"

  if self.editor.handleUnknownPopupAction(self, action, arg) == Handled:
    return Handled

  var args = newJArray()
  args.add api.SelectorPopup(id: self.id).toJson
  for a in newStringStream(arg).parseJsonFragments():
    args.add a
  if dispatch(action, args).isSome:
    return Handled

  return Ignored

proc handleTextChanged*(self: SelectorPopup) =
  self.updateCompletions()
  self.selected = 0

method handleScroll*(self: SelectorPopup, scroll: Vec2, mousePosWindow: Vec2) =
  self.selected = clamp(self.selected - scroll.y.int, 0, self.completions.len - 1)

method handleMousePress*(self: SelectorPopup, button: MouseButton, mousePosWindow: Vec2) =
  if button == MouseButton.Left:
    if self.getItemAtPixelPosition(mousePosWindow).getSome(item):
      self.handleItemConfirmed(item)
      self.editor.popPopup(self)

method handleMouseRelease*(self: SelectorPopup, button: MouseButton, mousePosWindow: Vec2) =
  discard

method handleMouseMove*(self: SelectorPopup, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
  discard

proc newSelectorPopup*(editor: Editor, getCompletions: proc(self: SelectorPopup, text: string): seq[SelectorItem]): SelectorPopup =
  var popup = SelectorPopup(editor: editor)
  popup.textEditor = newTextEditor(newTextDocument(), editor)
  popup.textEditor.setMode("insert")
  popup.textEditor.renderHeader = false
  popup.textEditor.lineNumbers = api.LineNumbers.None.some
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