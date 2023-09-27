import std/[strutils, sugar, options, json, streams, random]
import bumpy, vmath
import app_interface, text/text_editor, popup, events, util, rect_utils, scripting/expose, event, input, custom_async, custom_logger, cancellation_token, myjsonutils
import comb_sort, timer
from scripting_api as api import nil

export popup

logCategory "selector"
createJavascriptPrototype("popup.selector")

type
  SelectorItem* = ref object of RootObj
    score*: float32

  CompletionProviderSync* = proc(popup: SelectorPopup, text: string): seq[SelectorItem]
  CompletionProviderAsync* = proc(popup: SelectorPopup, text: string): Future[seq[SelectorItem]]
  CompletionProviderAsyncIter* = proc(popup: SelectorPopup, text: string): Future[void]

  SelectorPopup* = ref object of Popup
    app*: AppInterface
    textEditor*: TextDocumentEditor
    selected*: int
    scrollOffset*: int
    completions*: seq[SelectorItem]
    handleItemConfirmed*: proc(item: SelectorItem)
    handleItemSelected*: proc(item: SelectorItem)
    handleCanceled*: proc()
    getCompletions*: CompletionProviderSync
    getCompletionsAsync*: CompletionProviderAsync
    getCompletionsAsyncIter*: CompletionProviderAsyncIter
    lastContentBounds*: Rect
    lastItems*: seq[tuple[index: int, bounds: Rect]]

    maxItemsToShow: int = 50

    cancellationToken*: CancellationToken

    # sort stuff
    useAutoSort: bool = false
    sortSteps: int = 5
    sortTimeboxMs: float = 5
    startSortGap: int = 1
    lastSortGap: int = 1
    autoSortActive: bool = false
    sortFunction*: proc(a, b: SelectorItem): int

method changed*(self: SelectorItem, other: SelectorItem): bool {.base.} = discard

proc autoSort(self: SelectorPopup) {.async.} =
  self.autoSortActive = true
  defer:
    self.autoSortActive = false

  while true:
    self.markDirty()

    # echo "sort ", self.lastSortGap
    var t = startTimer()
    var iterations = 0
    while t.elapsed.ms < self.sortTimeboxMs:
      if self.completions.combSort(self.sortFunction, Ascending, steps = self.sortSteps, gap = self.lastSortGap):
        return

      if self.lastSortGap > 1:
        self.lastSortGap = int(self.lastSortGap.float / 1.3)
      iterations += 1

    # echo iterations, " iterations, ", t.elapsed.ms, "ms"

    await sleepAsync(1)

proc enableAutoSort*(self: SelectorPopup) =
  self.useAutoSort = true
  self.lastSortGap = self.startSortGap
  # self.completions.shuffle()
  if self.autoSortActive:
    return
  asyncCheck self.autoSort()

proc setCompletions(self: SelectorPopup, newCompletions: seq[SelectorItem]) =
  self.markDirty()

  self.completions = newCompletions
  self.lastSortGap = self.startSortGap

  if self.useAutoSort and not self.autoSortActive:
    self.enableAutoSort()

  if self.completions.len > 0:
    self.selected = self.selected.clamp(0, self.completions.len - 1)

    if not self.handleItemSelected.isNil:
      self.handleItemSelected self.completions[self.completions.high - self.selected]
  else:
    self.selected = 0

proc updateCompletionsAsync(self: SelectorPopup): Future[void] {.async.} =
  let text = self.textEditor.document.content.join
  let newCompletions = await self.getCompletionsAsync(self, text)
  self.setCompletions(newCompletions)

proc updateCompletionsAsyncIter(self: SelectorPopup): Future[void] {.async.} =
  let text = self.textEditor.document.content.join
  # self.setCompletions @[]
  await self.getCompletionsAsyncIter(self, text)

proc updateCompletions*(self: SelectorPopup) =
  let text = self.textEditor.document.content.join
  if not self.getCompletions.isNil:
    let newCompletions = self.getCompletions(self, text)
    self.setCompletions(newCompletions)
  elif not self.getCompletionsAsync.isNil:
    asyncCheck self.updateCompletionsAsync()
  elif not self.getCompletionsAsyncIter.isNil:
    asyncCheck self.updateCompletionsAsyncIter()
  else:
    log(lvlError, fmt"No completion provider set on popup {self.id}")

proc getItemAtPixelPosition(self: SelectorPopup, posWindow: Vec2): Option[SelectorItem] =
  result = SelectorItem.none
  for (index, rect) in self.lastItems:
    if rect.contains(posWindow) and index >= 0 and index <= self.completions.high:
      return self.completions[self.completions.high - index].some

method getEventHandlers*(self: SelectorPopup): seq[EventHandler] =
  return self.textEditor.getEventHandlers() & @[self.eventHandler]

proc getSelectorPopup(wrapper: api.SelectorPopup): Option[SelectorPopup] =
  if gAppInterface.isNil: return SelectorPopup.none
  if gAppInterface.getPopupForId(wrapper.id).getSome(editor):
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
  if not self.handleItemConfirmed.isNil and self.selected < self.completions.len:
    self.handleItemConfirmed self.completions[self.completions.high - self.selected]
  self.app.popPopup(self)

  self.markDirty()

proc cancel*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.handleCanceled != nil:
    self.handleCanceled()
  self.app.popPopup(self)

  self.markDirty()

proc prev*(self: SelectorPopup) {.expose("popup.selector").} =
  self.selected = if self.completions.len == 0:
    0
  else:
    (self.selected + self.completions.len - 1) mod self.completions.len

  if self.completions.len > 0 and self.handleItemSelected != nil:
    self.handleItemSelected self.completions[self.completions.high - self.selected]

  self.markDirty()

proc next*(self: SelectorPopup) {.expose("popup.selector").} =
  self.selected = if self.completions.len == 0:
    0
  else:
    (self.selected + 1) mod self.completions.len

  if self.completions.len > 0 and self.handleItemSelected != nil:
    self.handleItemSelected self.completions[self.completions.high - self.selected]

  self.markDirty()

genDispatcher("popup.selector")

proc handleAction*(self: SelectorPopup, action: string, arg: string): EventResponse =
  # echo "SelectorPopup.handleAction ", action, ", '", arg, "'"

  if self.app.handleUnknownPopupAction(self, action, arg) == Handled:
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

  if not self.handleItemSelected.isNil and self.selected < self.completions.len:
    self.handleItemSelected self.completions[self.completions.high - self.selected]

  self.markDirty()

method handleScroll*(self: SelectorPopup, scroll: Vec2, mousePosWindow: Vec2) =
  self.selected = clamp(self.selected - scroll.y.int, 0, self.completions.len - 1)

method handleMousePress*(self: SelectorPopup, button: MouseButton, mousePosWindow: Vec2) =
  if button == MouseButton.Left:
    if self.getItemAtPixelPosition(mousePosWindow).getSome(item):
      if not self.handleItemConfirmed.isNil:
        self.handleItemConfirmed(item)

      self.app.popPopup(self)

method handleMouseRelease*(self: SelectorPopup, button: MouseButton, mousePosWindow: Vec2) =
  discard

method handleMouseMove*(self: SelectorPopup, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
  discard

proc newSelectorPopup*(app: AppInterface): SelectorPopup =
  var popup = SelectorPopup(app: app)
  popup.textEditor = newTextEditor(newTextDocument(app.configProvider), app, app.configProvider)
  popup.textEditor.setMode("insert")
  popup.textEditor.renderHeader = false
  popup.textEditor.lineNumbers = api.LineNumbers.None.some
  popup.textEditor.document.singleLine = true
  popup.textEditor.disableScrolling = true
  popup.textEditor.disableCompletions = true
  popup.textEditor.active = true
  discard popup.textEditor.document.textChanged.subscribe (doc: TextDocument) => popup.handleTextChanged()
  discard popup.textEditor.onMarkedDirty.subscribe () => popup.markDirty()

  popup.eventHandler = eventHandler(app.getEventHandlerConfig("popup.selector")):
    onAction:
      popup.handleAction action, arg
    onInput:
      Ignored

  return popup