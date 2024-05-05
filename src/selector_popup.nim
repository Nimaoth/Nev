import std/[strutils, sugar, options, json, streams, tables]
import bumpy, vmath
import misc/[util, rect_utils, comb_sort, timer, event, custom_async, custom_logger,
  cancellation_token, myjsonutils, fuzzy_matching, traits]
import app_interface, text/text_editor, popup, events, scripting/expose, input,
  selector_popup_builder, file_selector_item, dispatch_tables
from scripting_api as api import Selection
import finder/finder

export popup, selector_popup_builder

logCategory "selector"
createJavascriptPrototype("popup.selector")

type
  CompletionProviderSync* = proc(popup: SelectorPopup, text: string): seq[SelectorItem]
  CompletionProviderAsync* = proc(popup: SelectorPopup, text: string): Future[seq[SelectorItem]]
  CompletionProviderAsyncIter* = proc(popup: SelectorPopup, text: string): Future[void]

  SelectorPopup* = ref object of Popup
    app*: AppInterface
    textEditor*: TextDocumentEditor
    selected*: int
    scrollOffset*: int
    completions*: seq[SelectorItem]
    handleItemConfirmed*: proc(item: SelectorItem): bool
    handleItemSelected*: proc(item: SelectorItem)
    handleItemConfirmed2*: proc(finderItem: FinderItem): bool
    handleItemSelected2*: proc(finderItem: FinderItem)
    handleCanceled*: proc()
    getCompletions*: CompletionProviderSync
    getCompletionsAsync*: CompletionProviderAsync
    getCompletionsAsyncIter*: CompletionProviderAsyncIter
    lastContentBounds*: Rect
    lastItems*: seq[tuple[index: int, bounds: Rect]]

    customEventHandler: EventHandler

    scale*: Vec2

    customCommands: Table[string, proc(popup: SelectorPopup, args: JsonNode): bool]

    maxItemsToShow: int = 50

    cancellationToken*: CancellationToken

    updateInProgress*: bool = false
    updated*: bool = false

    # sort stuff
    useAutoSort: bool = false
    sortSteps: int = 5
    sortTimeboxMs: float = 5
    startSortGap: int = 1
    lastSortGap: int = 1
    autoSortActive: bool = false
    sortFunction*: proc(a, b: SelectorItem): int

    completionMatchPositions: Table[int, seq[int]]
    finder*: Finder

  NamedSelectorItem* = ref object of SelectorItem
    name*: string

proc getSearchString*(self: SelectorPopup): string
proc updateCompletions*(self: SelectorPopup)
proc enableAutoSort*(self: SelectorPopup)
proc closed*(self: SelectorPopup): bool

implTrait ISelectorPopup, SelectorPopup:
  getSearchString(string, SelectorPopup)
  updateCompletions(void, SelectorPopup)
  enableAutoSort(void, SelectorPopup)
  closed(bool, SelectorPopup)

proc closed*(self: SelectorPopup): bool =
  return self.textEditor.isNil

proc getCompletionMatches*(self: SelectorPopup, i: int, pattern: string, text: string,
    config: FuzzyMatchConfig): seq[int] =

  if self.completionMatchPositions.contains(i):
    return self.completionMatchPositions[i]

  discard matchFuzzySublime(pattern, text, result, true, config)
  self.completionMatchPositions[i] = result

proc getCompletionMatches*(self: SelectorItem, pattern: string, text: string,
    config: FuzzyMatchConfig): seq[int] =

  if not self.hasCompletionMatchPositions:
    self.completionMatchPositions.setLen 0
    discard matchFuzzySublime(pattern, text, self.completionMatchPositions, true, config)
    self.hasCompletionMatchPositions = true

  return self.completionMatchPositions

method changed*(self: NamedSelectorItem, other: SelectorItem): bool =
  let other = other.NamedSelectorItem
  return self.name != other.name

method deinit*(self: SelectorPopup) =
  log lvlInfo, "Destroy selector popup"
  if self.cancellationToken.isNotNil:
    self.cancellationToken.cancel()

  if self.finder.isNotNil:
    self.finder.deinit()
    self.finder = nil

  let document = self.textEditor.document
  self.textEditor.deinit()
  document.deinit()

  self[] = default(typeof(self[]))

proc addCustomCommand*(self: SelectorPopup, name: string,
    command: proc(popup: SelectorPopup, args: JsonNode): bool) =
  self.customCommands[name] = command

proc getSearchString*(self: SelectorPopup): string =
  if self.textEditor.isNil:
    return ""
  return self.textEditor.document.contentString

proc autoSort(self: SelectorPopup) {.async.} =
  if self.textEditor.isNil:
    return

  if self.sortFunction.isNil:
    log lvlError, &"No sort function specified for popup"
    return

  self.autoSortActive = true
  defer:
    self.autoSortActive = false

  while true:
    self.markDirty()

    # echo "sort ", self.lastSortGap
    var t = startTimer()
    var iterations = 0
    while t.elapsed.ms < self.sortTimeboxMs:
      if self.completions.combSort(
          self.sortFunction, Ascending, steps = self.sortSteps, gap = self.lastSortGap):
        return

      if self.lastSortGap > 1:
        self.lastSortGap = int(self.lastSortGap.float / 1.3)
      iterations += 1

    # echo iterations, " iterations, ", t.elapsed.ms, "ms"

    await sleepAsync(1)
    if self.textEditor.isNil:
      return

proc enableAutoSort*(self: SelectorPopup) =
  self.useAutoSort = true
  self.lastSortGap = self.startSortGap
  # self.completions.shuffle()
  if self.autoSortActive:
    return
  asyncCheck self.autoSort()

proc setCompletions(self: SelectorPopup, newCompletions: seq[SelectorItem]) =
  if self.textEditor.isNil:
    return

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
  if self.textEditor.isNil:
    return

  self.setCompletions(newCompletions)
  self.updated = true

proc updateCompletionsAsyncIter(self: SelectorPopup): Future[void] {.async.} =
  let text = self.textEditor.document.content.join
  # self.setCompletions @[]
  await self.getCompletionsAsyncIter(self, text)
  self.updated = true

proc getItemAtPixelPosition(self: SelectorPopup, posWindow: Vec2): Option[SelectorItem] =
  result = SelectorItem.none
  for (index, rect) in self.lastItems:
    if rect.contains(posWindow) and index >= 0 and index <= self.completions.high:
      return self.completions[self.completions.high - index].some

method getEventHandlers*(self: SelectorPopup): seq[EventHandler] =
  if self.textEditor.isNil:
    return @[]
  result = self.textEditor.getEventHandlers(initTable[string, EventHandler]()) & @[self.eventHandler]
  if self.customEventHandler.isNotNil:
    result.add self.customEventHandler

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

proc updateCompletions*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  let text = self.textEditor.document.content.join
  if not self.getCompletions.isNil:
    let newCompletions = self.getCompletions(self, text)
    self.setCompletions(newCompletions)
    self.updated = true
  elif not self.getCompletionsAsync.isNil:
    asyncCheck self.updateCompletionsAsync()
  elif not self.getCompletionsAsyncIter.isNil:
    asyncCheck self.updateCompletionsAsyncIter()
  else:
    log(lvlError, fmt"No completion provider set on popup {self.id}")

proc getSelectedItem*(self: SelectorPopup): JsonNode {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return newJNull()

  if self.selected < self.completions.len:
    let selected = self.completions[self.completions.high - self.selected]
    return selected.itemToJson
  return newJNull()

proc accept*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  if not self.handleItemConfirmed.isNil and self.selected < self.completions.len:
    let handled = self.handleItemConfirmed self.completions[self.completions.high - self.selected]
    if not handled:
      return

  if self.finder.isNotNil and
      self.finder.filteredItems.getSome(items) and
      not self.handleItemConfirmed2.isNil and self.selected < self.completions.len:
    let finderItemIndex = self.completions[self.completions.high - self.selected].finderItemIndex
    if finderItemIndex >= 0 and finderItemIndex < items.len:
      let handled = self.handleItemConfirmed2 items[finderItemIndex]
      if not handled:
        return

  self.app.popPopup(self)

proc cancel*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  if self.handleCanceled != nil:
    self.handleCanceled()
  self.app.popPopup(self)

proc prev*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  self.selected = if self.completions.len == 0:
    0
  else:
    (self.selected + self.completions.len - 1) mod self.completions.len

  if self.completions.len > 0 and self.handleItemSelected != nil:
    self.handleItemSelected self.completions[self.completions.high - self.selected]

  if self.finder.isNotNil and
      self.finder.filteredItems.getSome(items) and
      not self.handleItemSelected2.isNil and self.selected < self.completions.len:
    let finderItemIndex = self.completions[self.completions.high - self.selected].finderItemIndex
    if finderItemIndex >= 0 and finderItemIndex < items.len:
      self.handleItemSelected2 items[finderItemIndex]

  self.markDirty()

proc next*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  self.selected = if self.completions.len == 0:
    0
  else:
    (self.selected + 1) mod self.completions.len

  if self.completions.len > 0 and self.handleItemSelected != nil:
    self.handleItemSelected self.completions[self.completions.high - self.selected]

  self.markDirty()

genDispatcher("popup.selector")
addActiveDispatchTable "popup.selector", genDispatchTable("popup.selector")

proc handleAction*(self: SelectorPopup, action: string, arg: string): EventResponse =
  # debugf"SelectorPopup.handleAction {action} '{arg}'"
  if self.textEditor.isNil:
    return

  if self.customCommands.contains(action):
    var args = newJArray()
    for a in newStringStream(arg).parseJsonFragments():
      args.add a
    if self.customCommands[action](self, args):
      return Handled

  if self.app.handleUnknownPopupAction(self, action, arg) == Handled:
    return Handled

  var args = newJArray()
  args.add api.SelectorPopup(id: self.id).toJson
  for a in newStringStream(arg).parseJsonFragments():
    args.add a

  if self.app.invokeAnyCallback(action, args).isNotNil:
    return Handled

  if dispatch(action, args).isSome:
    return Handled

  return Ignored

proc handleTextChanged*(self: SelectorPopup) =
  if self.textEditor.isNil:
    return

  if self.finder.isNotNil:
    self.finder.setQuery(self.getSearchString())

  self.updateCompletions()
  self.selected = 0

  if not self.handleItemSelected.isNil and self.selected < self.completions.len:
    self.handleItemSelected self.completions[self.completions.high - self.selected]

  self.markDirty()

proc handleItemsUpdated*(self: SelectorPopup) =
  if self.textEditor.isNil or self.finder.isNil:
    return

  self.completions.setLen 0
  self.completionMatchPositions.clear()

  if self.finder.filteredItems.getSome(list) and list.len > 0:
    for i, item in list.items:
      if item.score < 0:
        continue
      self.completions.add FileSelectorItem(
        finderItemIndex: i,
        name: item.displayName,
        directory: item.detail,
        path: item.data,
        score: item.score
      )

  self.selected = self.selected.clamp(0, self.completions.len - 1)
  self.markDirty()

method handleScroll*(self: SelectorPopup, scroll: Vec2, mousePosWindow: Vec2) =
  if self.textEditor.isNil:
    return

  self.selected = clamp(self.selected - scroll.y.int, 0, self.completions.len - 1)

method handleMousePress*(self: SelectorPopup, button: MouseButton, mousePosWindow: Vec2) =
  if self.textEditor.isNil:
    return

  if button == MouseButton.Left:
    if self.getItemAtPixelPosition(mousePosWindow).getSome(item):
      if not self.handleItemConfirmed.isNil:
        if not self.handleItemConfirmed(item):
          return

      self.app.popPopup(self)

method handleMouseRelease*(self: SelectorPopup, button: MouseButton, mousePosWindow: Vec2) =
  discard

method handleMouseMove*(self: SelectorPopup, mousePosWindow: Vec2, mousePosDelta: Vec2,
    modifiers: Modifiers, buttons: set[MouseButton]) =
  discard

proc newSelectorPopup*(app: AppInterface, scopeName: Option[string] = string.none,
    finder: Option[Finder] = Finder.none): SelectorPopup =
  var popup = SelectorPopup(app: app)
  popup.scale = vec2(0.5, 0.5)
  let document = newTextDocument(app.configProvider, createLanguageServer=false)
  popup.textEditor = newTextEditor(document, app, app.configProvider)
  popup.textEditor.setMode("insert")
  popup.textEditor.renderHeader = false
  popup.textEditor.lineNumbers = api.LineNumbers.None.some
  popup.textEditor.document.singleLine = true
  popup.textEditor.disableScrolling = true
  popup.textEditor.disableCompletions = true
  popup.textEditor.active = true

  discard popup.textEditor.document.textInserted.subscribe (
      arg: tuple[document: TextDocument, location: Selection, text: string]) =>
    popup.handleTextChanged()

  discard popup.textEditor.document.textDeleted.subscribe (
      arg: tuple[document: TextDocument, location: Selection]) =>
    popup.handleTextChanged()

  discard popup.textEditor.onMarkedDirty.subscribe () =>
    popup.markDirty()

  if finder.getSome(finder):
    popup.finder = finder
    discard popup.finder.onItemsChanged.subscribe () => popup.handleItemsUpdated()
    popup.finder.setQuery("")

  popup.eventHandler = eventHandler(app.getEventHandlerConfig("popup.selector")):
    onAction:
      popup.handleAction action, arg
    onInput:
      Ignored

  if scopeName.isSome:
    popup.customEventHandler = eventHandler(app.getEventHandlerConfig("popup.selector." & scopeName.get)):
      onAction:
        popup.handleAction action, arg
      onInput:
        Ignored

  return popup