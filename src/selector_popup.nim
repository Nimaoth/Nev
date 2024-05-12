import std/[sugar, options, json, streams, tables]
import bumpy, vmath
import misc/[util, rect_utils, event, myjsonutils, fuzzy_matching, traits, custom_logger, disposable_ref]
import app_interface, text/text_editor, popup, events, scripting/expose,
  selector_popup_builder, dispatch_tables
from scripting_api as api import Selection
import finder/[finder, previewer]

export popup, selector_popup_builder

logCategory "selector"
createJavascriptPrototype("popup.selector")

type
  SelectorPopup* = ref object of Popup
    app*: AppInterface
    textEditor*: TextDocumentEditor
    previewEditor*: TextDocumentEditor
    selected*: int
    scrollOffset*: int
    handleItemConfirmed*: proc(finderItem: FinderItem): bool
    handleItemSelected*: proc(finderItem: FinderItem)
    handleCanceled*: proc()
    lastContentBounds*: Rect
    lastItems*: seq[tuple[index: int, bounds: Rect]]

    previewEventHandler: EventHandler
    customEventHandler: EventHandler

    scale*: Vec2
    previewScale*: float = 0.5

    customCommands: Table[string, proc(popup: SelectorPopup, args: JsonNode): bool]

    maxItemsToShow: int = 50

    itemList: ItemList

    completionMatchPositions: Table[int, seq[int]]
    finder*: Finder
    previewer*: Option[DisposableRef[Previewer]]

    focusPreview*: bool

proc getSearchString*(self: SelectorPopup): string
proc closed*(self: SelectorPopup): bool

implTrait ISelectorPopup, SelectorPopup:
  getSearchString(string, SelectorPopup)
  closed(bool, SelectorPopup)

proc closed*(self: SelectorPopup): bool =
  return self.textEditor.isNil

proc getCompletionMatches*(self: SelectorPopup, i: int, pattern: string, text: string,
    config: FuzzyMatchConfig): seq[int] =

  if self.completionMatchPositions.contains(i):
    return self.completionMatchPositions[i]

  discard matchFuzzySublime(pattern, text, result, true, config)
  self.completionMatchPositions[i] = result

method deinit*(self: SelectorPopup) =
  logScope lvlInfo, &"[deinit] Destroying selector popup"

  if self.finder.isNotNil:
    self.finder.deinit()

  let document = self.textEditor.document
  self.textEditor.deinit()
  document.deinit()

  if self.previewEditor.isNotNil:
    self.previewEditor.deinit()

  self[] = default(typeof(self[]))

proc addCustomCommand*(self: SelectorPopup, name: string,
    command: proc(popup: SelectorPopup, args: JsonNode): bool) =
  self.customCommands[name] = command

proc getSearchString*(self: SelectorPopup): string =
  if self.textEditor.isNil:
    return ""
  return self.textEditor.document.contentString

proc getPreviewSelection*(self: SelectorPopup): Option[Selection] =
  if self.previewEditor.isNil:
    return Selection.none
  return self.previewEditor.selection.some

method getActiveEditor*(self: SelectorPopup): Option[DocumentEditor] =
  if self.focusPreview and self.previewEditor.isNotNil:
    return self.previewEditor.DocumentEditor.some
  if not self.focusPreview and self.textEditor.isNotNil:
    return self.textEditor.DocumentEditor.some

  return DocumentEditor.none

method getEventHandlers*(self: SelectorPopup): seq[EventHandler] =
  if self.textEditor.isNil:
    return @[]

  if self.focusPreview and self.previewEditor.isNotNil:
    result = self.previewEditor.getEventHandlers(initTable[string, EventHandler]()) & @[self.previewEventHandler]
  else:
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

proc getSelectedItemJson*(self: SelectorPopup): JsonNode {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return newJNull()

  # todo
  # if self.selected < self.completions.len:
  #   let selected = self.completions[self.completions.high - self.selected]
  #   return selected.itemToJson
  return newJNull()

proc getSelectedItem*(self: SelectorPopup): Option[FinderItem] =
  assert self.finder.isNotNil

  if self.finder.filteredItems.getSome(list) and list.len > 0:
    assert self.selected >= 0
    assert self.selected < list.len
    result = list[self.selected].some

proc accept*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  if self.handleItemConfirmed.isNil:
    return

  assert self.finder.isNotNil

  if self.finder.filteredItems.getSome(list) and list.len > 0:
    assert self.selected >= 0
    assert self.selected < list.len
    let handled = self.handleItemConfirmed list[self.selected]
    if handled:
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

  assert self.finder.isNotNil

  if self.finder.filteredItems.getSome(list) and list.len > 0:
    self.selected = (self.selected + list.len - 1) mod list.len

    if not self.handleItemSelected.isNil:
      self.handleItemSelected list[self.selected]

    if self.previewer.isSome:
      assert self.previewEditor.isNotNil
      self.previewer.get.get.previewItem(list[self.selected], self.previewEditor)

  self.markDirty()

proc next*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  assert self.finder.isNotNil

  if self.finder.filteredItems.getSome(list) and list.len > 0:
    self.selected = (self.selected + 1) mod list.len

    if not self.handleItemSelected.isNil:
      self.handleItemSelected list[self.selected]

    if self.previewer.isSome:
      assert self.previewEditor.isNotNil
      self.previewer.get.get.previewItem(list[self.selected], self.previewEditor)

  self.markDirty()

proc toggleFocusPreview*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.previewEditor.isNil:
    return

  self.focusPreview = not self.focusPreview
  self.markDirty()
  self.previewEditor.markDirty()

proc setFocusPreview*(self: SelectorPopup, focus: bool) {.expose("popup.selector").} =
  if self.previewEditor.isNil:
    return

  self.focusPreview = focus
  self.markDirty()
  self.previewEditor.markDirty()

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

  assert self.finder.isNotNil

  self.selected = 0

  self.finder.setQuery(self.getSearchString())

  if self.previewer.isSome:
    self.previewer.get.get.delayPreview()

  if self.handleItemSelected.isNotNil and
      self.finder.filteredItems.getSome(list) and list.len > 0:

    self.handleItemSelected list[0]

  self.markDirty()

proc handleItemsUpdated*(self: SelectorPopup) =
  if self.textEditor.isNil or self.finder.isNil:
    return

  self.completionMatchPositions.clear()

  if self.finder.filteredItems.getSome(list) and list.len > 0:
    self.selected = self.selected.clamp(0, list.len - 1)

    if not self.handleItemSelected.isNil:
      self.handleItemSelected list[self.selected]

    if self.previewer.isSome:
      assert self.previewEditor.isNotNil
      self.previewer.get.get.previewItem(list[self.selected], self.previewEditor)

  else:
    self.selected = 0

  self.markDirty()

proc newSelectorPopup*(app: AppInterface, scopeName = string.none, finder = Finder.none,
    previewer: sink Option[DisposableRef[Previewer]] = DisposableRef[Previewer].none): SelectorPopup =

  log lvlInfo, "[newSelectorPopup] " & $scopeName

  # todo: make finder not Option
  assert finder.isSome
  assert finder.get.isNotNil

  var popup = SelectorPopup(app: app)
  popup.scale = vec2(0.5, 0.5)
  let document = newTextDocument(app.configProvider, createLanguageServer=false)
  popup.textEditor = newTextEditor(document, app, app.configProvider)
  popup.textEditor.usage = "search-bar"
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

  popup.previewer = previewer.move
  if popup.previewer.isSome:

    # todo: make sure this previewDocument is destroyed, we're overriding it right now
    # in the previewer with a temp document or an existing one
    let previewDocument = newTextDocument(app.configProvider, createLanguageServer=false)
    previewDocument.readOnly = true

    popup.previewEditor = newTextEditor(previewDocument, app, app.configProvider)
    popup.previewEditor.usage = "preview"
    popup.previewEditor.renderHeader = true
    popup.previewEditor.lineNumbers = api.LineNumbers.None.some
    popup.previewEditor.disableCompletions = true

    discard popup.previewEditor.onMarkedDirty.subscribe () =>
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

  popup.previewEventHandler = eventHandler(app.getEventHandlerConfig("popup.selector.preview")):
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
