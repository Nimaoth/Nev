import std/[sugar, options, json, streams, tables]
import bumpy, vmath
import misc/[util, rect_utils, event, myjsonutils, fuzzy_matching, traits, custom_logger, disposable_ref]
import scripting/[expose, scripting_base]
import app_interface, text/text_editor, popup, events,
  selector_popup_builder, dispatch_tables, layout, service
from scripting_api as api import Selection, ToggleBool, toToggleBool, applyTo
import finder/[finder, previewer]
import platform/filesystem

export popup, selector_popup_builder, service

{.push gcsafe.}

logCategory "selector"

type
  SelectorPopup* = ref object of Popup
    app*: AppInterface
    services*: Services
    layout*: LayoutService
    events*: EventHandlerService
    plugins: PluginService
    textEditor*: TextDocumentEditor
    previewEditor*: TextDocumentEditor
    selected*: int
    scrollOffset*: int
    handleItemConfirmed*: proc(finderItem: FinderItem): bool {.gcsafe, raises: [].}
    handleItemSelected*: proc(finderItem: FinderItem) {.gcsafe, raises: [].}
    handleCanceled*: proc() {.gcsafe, raises: [].}
    lastContentBounds*: Rect
    lastItems*: seq[tuple[index: int, bounds: Rect]]

    previewEventHandler: EventHandler
    customEventHandler: EventHandler

    scale*: Vec2
    previewScale*: float = 0.5
    sizeToContentY*: bool = true
    maxDisplayNameWidth*: int = 50
    maxColumnWidth*: int = 60

    customCommands: Table[string, proc(popup: SelectorPopup, args: JsonNode): bool {.gcsafe, raises: [].}]

    maxItemsToShow: int = 50

    completionMatchPositions: Table[int, seq[int]]
    finder*: Finder
    previewer*: Option[DisposableRef[Previewer]]
    previewVisible*: bool = true

    focusPreview*: bool

proc getSearchString*(self: SelectorPopup): string {.gcsafe, raises: [].}
proc closed*(self: SelectorPopup): bool {.gcsafe, raises: [].}
proc getSelectedItem*(self: SelectorPopup): Option[FinderItem] {.gcsafe, raises: [].}

implTrait ISelectorPopup, SelectorPopup:
  getSearchString(string, SelectorPopup)
  closed(bool, SelectorPopup)
  getSelectedItem(Option[FinderItem], SelectorPopup)

proc closed*(self: SelectorPopup): bool =
  return self.textEditor.isNil

proc getCompletionMatches*(self: SelectorPopup, i: int, pattern: string, text: string,
    config: FuzzyMatchConfig): seq[int] =

  if self.completionMatchPositions.contains(i):
    return self.completionMatchPositions[i]

  discard matchFuzzySublime(pattern, text, result, true, config)
  self.completionMatchPositions[i] = result

method deinit*(self: SelectorPopup) {.gcsafe, raises: [].} =
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
    command: proc(popup: SelectorPopup, args: JsonNode): bool {.gcsafe, raises: [].}) =
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

proc getSelectorPopup(wrapper: api.SelectorPopup): Option[SelectorPopup] {.gcsafe, raises: [].} =
  {.gcsafe.}:
    if gServices.isNil: return SelectorPopup.none
    let layout = gServices.getService(LayoutService).get
    if layout.getPopupForId(wrapper.id).getSome(editor):
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

proc setPreviewVisible*(self: SelectorPopup, visible: bool) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  assert self.finder.isNotNil
  self.previewVisible = visible

  if visible and self.finder.filteredItems.getSome(list) and list.filteredLen > 0:
    if not self.handleItemSelected.isNil:
      self.handleItemSelected list[self.selected]

    if self.previewer.isSome:
      assert self.previewEditor.isNotNil
      self.previewer.get.get.previewItem(list[self.selected], self.previewEditor)

  self.markDirty()

proc togglePreview*(self: SelectorPopup) {.expose("popup.selector").} =
  self.setPreviewVisible(not self.previewVisible)

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

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0:
    assert self.selected >= 0
    assert self.selected < list.filteredLen
    result = list[self.selected].some

proc accept*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  if self.handleItemConfirmed.isNil:
    return

  assert self.finder.isNotNil

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0:
    assert self.selected >= 0
    assert self.selected < list.filteredLen
    let handled = self.handleItemConfirmed list[self.selected]
    if handled:
      self.layout.popPopup(self)

proc cancel*(self: SelectorPopup) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  if self.handleCanceled != nil:
    self.handleCanceled()
  self.layout.popPopup(self)

proc sort*(self: SelectorPopup, sort: ToggleBool) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return
  assert self.finder.isNotNil
  sort.applyTo(self.finder.sort)

  # Retrigger filter and sort
  self.finder.setQuery(self.getSearchString())

proc setMinScore*(self: SelectorPopup, value: float, add: bool = false) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  assert self.finder.isNotNil

  if add:
    self.finder.minScore += value
  else:
    self.finder.minScore = value

  log lvlInfo, "New minScore: {self.finder.minScore}"

  # Retrigger filter and sort
  self.finder.setQuery(self.getSearchString())
  self.markDirty()

proc prev*(self: SelectorPopup, count: int = 1) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  assert self.finder.isNotNil

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0:
    self.selected = (self.selected + max(0, list.filteredLen - count)) mod list.filteredLen

    if not self.handleItemSelected.isNil:
      self.handleItemSelected list[self.selected]

    if self.previewer.isSome:
      assert self.previewEditor.isNotNil
      self.previewer.get.get.previewItem(list[self.selected], self.previewEditor)

  self.markDirty()

proc next*(self: SelectorPopup, count: int = 1) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  assert self.finder.isNotNil

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0:
    self.selected = (self.selected + count) mod list.filteredLen

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

proc handleAction*(self: SelectorPopup, action: string, arg: string): EventResponse {.gcsafe, raises: [].} =
  # debugf"SelectorPopup.handleAction {action} '{arg}'"
  if self.textEditor.isNil:
    return

  try:
    if self.customCommands.contains(action):
      var args = newJArray()
      for a in newStringStream(arg).parseJsonFragments():
        args.add a
      if self.customCommands[action](self, args):
        return Handled

    var args = newJArray()
    args.add api.SelectorPopup(id: self.id).toJson
    for a in newStringStream(arg).parseJsonFragments():
      args.add a

    if self.plugins.invokeAnyCallback(action, args).isNotNil:
      return Handled

    if dispatch(action, args).isSome:
      return Handled

    return Ignored
  except:
    log lvlError, fmt"Failed to dispatch action '{action} {arg}': {getCurrentExceptionMsg()}"
    log lvlError, getCurrentException().getStackTrace()

  return Failed

proc handleTextChanged*(self: SelectorPopup) =
  if self.textEditor.isNil:
    return

  assert self.finder.isNotNil

  self.selected = 0

  self.finder.setQuery(self.getSearchString())

  if self.previewer.isSome:
    self.previewer.get.get.delayPreview()

  if self.handleItemSelected.isNotNil and self.finder.filteredItems.getSome(list) and list.filteredLen > 0:

    self.handleItemSelected list[0]

  self.markDirty()

proc handleItemsUpdated*(self: SelectorPopup) {.gcsafe, raises: [].} =
  if self.textEditor.isNil or self.finder.isNil:
    return

  self.completionMatchPositions.clear()

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0:
    self.selected = self.selected.clamp(0, list.filteredLen - 1)

    if not self.handleItemSelected.isNil:
      self.handleItemSelected list[self.selected]

    if self.previewer.isSome:
      assert self.previewEditor.isNotNil
      self.previewer.get.get.previewItem(list[self.selected], self.previewEditor)

  else:
    self.selected = 0

  self.markDirty()

proc newSelectorPopup*(app: AppInterface, fs: Filesystem, scopeName = string.none, finder = Finder.none,
    previewer: sink Option[DisposableRef[Previewer]] = DisposableRef[Previewer].none): SelectorPopup =

  log lvlInfo, "[newSelectorPopup] " & $scopeName

  # todo: make finder not Option
  assert finder.isSome
  assert finder.get.isNotNil

  let services = app.getServices()

  var popup = SelectorPopup(app: app)
  popup.services = services
  popup.layout = services.getService(LayoutService).get
  popup.events = services.getService(EventHandlerService).get
  popup.plugins = services.getService(PluginService).get
  popup.scale = vec2(0.5, 0.5)
  let document = newTextDocument(services, fs, createLanguageServer=false)
  popup.textEditor = newTextEditor(document, app, fs, services)
  popup.textEditor.usage = "search-bar"
  popup.textEditor.setMode("insert")
  popup.textEditor.renderHeader = false
  popup.textEditor.lineNumbers = api.LineNumbers.None.some
  popup.textEditor.document.singleLine = true
  popup.textEditor.disableScrolling = true
  popup.textEditor.disableCompletions = true
  popup.textEditor.active = true

  discard popup.textEditor.document.textChanged.subscribe (arg: TextDocument) =>
    popup.handleTextChanged()

  discard popup.textEditor.onMarkedDirty.subscribe () =>
    popup.markDirty()

  popup.previewer = previewer.move
  if popup.previewer.isSome:

    # todo: make sure this previewDocument is destroyed, we're overriding it right now
    # in the previewer with a temp document or an existing one
    let previewDocument = newTextDocument(services, fs, createLanguageServer=false)
    previewDocument.readOnly = true

    popup.previewEditor = newTextEditor(previewDocument, app, fs, services)
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

  assignEventHandler(popup.eventHandler, popup.events.getEventHandlerConfig("popup.selector")):
    onAction:
      popup.handleAction action, arg
    onInput:
      Ignored

  assignEventHandler(popup.previewEventHandler, popup.events.getEventHandlerConfig("popup.selector.preview")):
    onAction:
      popup.handleAction action, arg
    onInput:
      Ignored

  if scopeName.isSome:
     assignEventHandler(popup.customEventHandler, popup.events.getEventHandlerConfig("popup.selector." & scopeName.get)):
      onAction:
        popup.handleAction action, arg
      onInput:
        Ignored

  return popup
