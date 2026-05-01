import std/[sugar, options, json, streams, tables]
import bumpy, vmath
import misc/[util, rect_utils, event, myjsonutils, fuzzy_matching, custom_logger, disposable_ref, rope_utils, jsonex]
import nimsumtree/[rope, buffer]
import popup, events,
  selector_popup_builder, layout/layout, service, config_provider, view, command_service
from scripting_api as api import Selection, ToggleBool, toToggleBool, applyTo
import finder/[finder, previewer]
import search_component, document_editor, text_component, text_editor_component, config_component
import ui/node
export popup, selector_popup_builder, service

import scripting/[expose], dispatch_tables

{.push gcsafe.}

logCategory "selector"

declareSettings SelectorSettings, "selector":
  declare baseMode, string, "popup.selector"
  declare minScore, float, 0

type
  SelectorPopup* = ref object of Popup
    services*: Services
    layout*: LayoutService
    events*: EventHandlerService
    editors: DocumentEditorService
    commands: CommandService
    textEditor*: DocumentEditor
    previewEditor*: DocumentEditor
    previewView*: View
    selected*: int
    scrollOffset*: int
    scrollToSelected*: bool
    handleItemConfirmed*: proc(finderItem: FinderItem): bool {.gcsafe, raises: [].}
    handleItemSelected*: proc(finderItem: FinderItem) {.gcsafe, raises: [].}
    handleCanceled*: proc() {.gcsafe, raises: [].}
    lastContentBounds*: Rect
    lastItems*: seq[tuple[index: int, bounds: Rect]]
    accepted: bool = false

    settings: SelectorSettings

    eventHandlers: Table[string,  EventHandler]

    viewMarkedDirtyHandle: Id
    configChangedHandle: Id

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

    scope*: string
    title*: string

    cachedFinderItems*: seq[FinderItem]
    cachedScrollOffset*: int

var createUIImpl*: proc(self: SelectorPopup, builder: UINodeBuilder): seq[OverlayFunction] {.closure, gcsafe, raises: [],}

proc getSearchString*(self: SelectorPopup): string {.gcsafe, raises: [].}
proc closed*(self: SelectorPopup): bool {.gcsafe, raises: [].}
proc getSelectedItem*(self: SelectorPopup): Option[FinderItem] {.gcsafe, raises: [].}
proc handleItemsUpdated*(self: SelectorPopup) {.gcsafe, raises: [].}
proc pop*(self: SelectorPopup) {.gcsafe, raises: [].}

proc closed*(self: SelectorPopup): bool =
  return self.textEditor.isNil

proc getCompletionMatches*(self: SelectorPopup, i: int, pattern: string, text: string,
    config: FuzzyMatchConfig): seq[int] =

  if self.completionMatchPositions.contains(i):
    return self.completionMatchPositions[i]

  if self.finder.filteredItems.getSome(items) and i < items.len:
    let query = if self.finder.skipFirstQuery and self.finder.queries.len > 1:
      self.finder.queries[1]
    else:
      self.finder.queries[0]
    discard matchFuzzy(query, text, result, true, config)
  else:
    discard matchFuzzy(pattern, text, result, true, config)
  self.completionMatchPositions[i] = result

proc selectorPopupInit*(self: SelectorPopup) {.gcsafe, raises: [].} =
  self.handleItemsUpdated()

proc selectorPopupDeinit*(self: SelectorPopup) {.gcsafe, raises: [].} =
  logScope lvlInfo, &"[deinit] Destroying selector popup"

  let config = self.services.getService(ConfigService).get.runtime
  config.onConfigChanged.unsubscribe(self.configChangedHandle)

  if self.finder.isNotNil:
    self.finder.deinit()

  self.editors.closeEditor(self.textEditor)

  if self.previewEditor.isNotNil:
    self.editors.closeEditor(self.previewEditor)

  self[] = default(typeof(self[]))

proc addCustomCommand*(self: SelectorPopup, name: string,
    command: proc(popup: SelectorPopup, args: JsonNode): bool {.gcsafe, raises: [].}) =
  self.customCommands[name] = command

proc getSearchString*(self: SelectorPopup): string =
  if self.textEditor.isNil or self.textEditor.currentDocument.isNil:
    return ""
  return self.textEditor.currentDocument.getTextComponent().mapIt($it.content).get("")

proc setSearchString*(self: SelectorPopup, query: string) =
  if self.textEditor.isNil or self.textEditor.currentDocument.isNil:
    return
  if self.textEditor.currentDocument.getTextComponent().getSome(text):
    text.content = query

proc getPreviewSelection*(self: SelectorPopup): Option[Selection] =
  if self.previewEditor.isNil:
    return Selection.none
  return self.previewEditor.getTextEditorComponent().mapIt(it.selection.toSelection)

proc selectorPopupGetActiveEditor(self: SelectorPopup): Option[DocumentEditor] =
  if self.focusPreview and self.previewEditor.isNotNil:
    return self.previewEditor.DocumentEditor.some
  if not self.focusPreview and self.textEditor.isNotNil:
    return self.textEditor.DocumentEditor.some

  return DocumentEditor.none

proc getEventHandler(self: SelectorPopup, context: string): EventHandler =
  if context notin self.eventHandlers:
    var eventHandler: EventHandler
    assignEventHandler(eventHandler, self.events.getEventHandlerConfig(context)):
      onAction:
        if self.handleAction(action, arg).isSome:
          Handled
        else:
          Ignored
      onInput:
        Ignored

    self.eventHandlers[context] = eventHandler
    return eventHandler

  return self.eventHandlers[context]

proc selectorPopupGetEventHandlers*(self: SelectorPopup): seq[EventHandler] =
  if self.textEditor.isNil:
    return @[]

  if self.focusPreview and self.previewView.isNotNil:
    let eventHandler = self.getEventHandler(self.settings.baseMode.get() & ".preview")
    result = self.previewView.getEventHandlers(initTable[string, EventHandler]()) & @[eventHandler]
  elif self.focusPreview and self.previewEditor.isNotNil:
    let eventHandler = self.getEventHandler(self.settings.baseMode.get() & ".preview")
    result = self.previewEditor.getEventHandlers(initTable[string, EventHandler]()) & @[eventHandler]
  else:
    let eventHandler = self.getEventHandler(self.settings.baseMode.get())
    result = self.textEditor.getEventHandlers(initTable[string, EventHandler]()) & @[eventHandler]

    if self.scope != "":
      let eventHandler = self.getEventHandler(self.settings.baseMode.get() & "." & self.scope)
      result.add eventHandler

proc getSelectorPopup(wrapper: api.SelectorPopup): Option[SelectorPopup] {.gcsafe, raises: [].} =
  {.gcsafe.}:
    if getServices().isNil: return SelectorPopup.none
    let layout = getServices().getService(LayoutService).get
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

proc updatePreview(self: SelectorPopup, item: FinderItem) =
  if self.previewer.isSome:
    let view = self.previewer.get.get.previewItem(item)
    if view != self.previewView:
      if self.previewView != nil:
        self.previewView.onMarkedDirty.unsubscribe(self.viewMarkedDirtyHandle)

      self.previewView = view

      if self.previewView != nil:
        self.viewMarkedDirtyHandle = self.previewView.onMarkedDirty.subscribe () =>
          self.markDirty()

    if view == nil and self.previewEditor.isNotNil:
      self.previewer.get.get.previewItem(item, self.previewEditor)

proc updatePreview(self: SelectorPopup) =
  if self.previewer.isSome and self.finder.filteredItems.getSome(list) and list.filteredLen > 0 and list.isValidIndex(self.selected):
    self.updatePreview(list[self.selected])

proc setPreviewVisible*(self: SelectorPopup, visible: bool) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  assert self.finder.isNotNil
  self.previewVisible = visible

  if visible and self.finder.filteredItems.getSome(list) and list.filteredLen > 0 and list.isValidIndex(self.selected):
    if not self.handleItemSelected.isNil:
      self.handleItemSelected list[self.selected]

    self.updatePreview()

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

proc getNumItems*(self: SelectorPopup): int =
  assert self.finder.isNotNil

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0:
    return list.filteredLen

proc getSelectedItem*(self: SelectorPopup): Option[FinderItem] =
  assert self.finder.isNotNil

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0 and list.isValidIndex(self.selected):
    assert self.selected >= 0
    assert self.selected < list.filteredLen
    result = list[self.selected].some

proc pop*(self: SelectorPopup) {.expose("popup.selector").} =
  self.layout.popPopup(self)

proc accept*(self: SelectorPopup) {.expose("popup.selector").} =
  self.accepted = true
  if self.textEditor.isNil:
    return

  if self.handleItemConfirmed.isNil:
    return

  assert self.finder.isNotNil

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0 and list.isValidIndex(self.selected):
    assert self.selected >= 0
    assert self.selected < list.filteredLen
    let handled = self.handleItemConfirmed list[self.selected]
    if handled:
      self.layout.popPopup(self)

proc selectorPopupCancel*(self: SelectorPopup) =
  if self.accepted:
    return

  if self.textEditor.isNil:
    return

  if self.handleCanceled != nil:
    self.handleCanceled()

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

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0 and list.isValidIndex(self.selected):
    self.selected = (self.selected + max(0, list.filteredLen - count)) mod list.filteredLen

    if not self.handleItemSelected.isNil:
      self.handleItemSelected list[self.selected]

    self.scrollToSelected = true
    self.updatePreview()

  self.markDirty()

proc next*(self: SelectorPopup, count: int = 1) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  assert self.finder.isNotNil

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0 and list.isValidIndex(self.selected):
    self.selected = (self.selected + count) mod list.filteredLen

    if not self.handleItemSelected.isNil:
      self.handleItemSelected list[self.selected]

    self.scrollToSelected = true
    self.updatePreview()

  self.markDirty()

proc setFocusPreview*(self: SelectorPopup, focus: bool) {.expose("popup.selector").} =
  if self.previewer.isNone:
    return

  if self.previewView != nil:
    if focus:
      self.previewer.get.get.activate()
      self.previewView.activate()
    else:
      self.previewer.get.get.deactivate()
      self.previewView.deactivate()
  else:
    self.previewEditor.markDirty()

  self.focusPreview = focus
  self.markDirty()

proc toggleFocusPreview*(self: SelectorPopup) {.expose("popup.selector").} =
  self.setFocusPreview(not self.focusPreview)

genDispatcher("popup.selector")
addActiveDispatchTable "popup.selector", genDispatchTable("popup.selector")

proc selectorPopupHandleAction*(self: SelectorPopup, action: string, arg: string): Option[JsonNode] {.gcsafe, raises: [].} =
  # debugf"SelectorPopup.handleAction {action} '{arg}'"
  if self.textEditor.isNil:
    return JsonNode.none

  try:
    if self.customCommands.contains(action):
      var args = newJArray()
      for a in newStringStream(arg).parseJsonFragments():
        args.add a
      if self.customCommands[action](self, args):
        return newJNull().some

    var args = newJArray()
    args.add api.SelectorPopup(id: self.id).toJson
    for a in newStringStream(arg).parseJsonFragments():
      args.add a

    let res2 = dispatch(action, args)
    if res2.isSome:
      return res2

    let res = self.commands.executeCommand(action & " " & arg)
    if res.isSome:
      return newJString(res.get).some
  except:
    log lvlError, fmt"Failed to dispatch command '{action} {arg}': {getCurrentExceptionMsg()}"
    log lvlError, getCurrentException().getStackTrace()
    return JsonNode.none

  log lvlError, fmt"Unknown command '{action}'"
  return JsonNode.none

proc handleTextChanged*(self: SelectorPopup) =
  if self.textEditor.isNil:
    return

  assert self.finder.isNotNil

  self.selected = 0

  self.finder.setQuery(self.getSearchString())

  if self.previewer.isSome:
    self.previewer.get.get.delayPreview()

  if self.handleItemSelected.isNotNil and self.finder.filteredItems.getSome(list) and list.filteredLen > 0 and list.isValidIndex(0):

    self.handleItemSelected list[0]

  self.markDirty()

proc handleItemsUpdated*(self: SelectorPopup) {.gcsafe, raises: [].} =
  if self.textEditor.isNil or self.finder.isNil:
    return

  self.completionMatchPositions.clear()

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0 and list.isValidIndex(self.selected):
    self.selected = self.selected.clamp(0, list.filteredLen - 1)

    if not self.handleItemSelected.isNil:
      self.handleItemSelected list[self.selected]

    self.updatePreview()

  else:
    self.selected = 0

  self.scrollToSelected = true

  self.markDirty()

proc newSelectorPopup*(services: Services, scopeName = string.none, finder = Finder.none,
    previewer: sink Option[DisposableRef[Previewer]] = DisposableRef[Previewer].none): SelectorPopup =

  log lvlInfo, "[newSelectorPopup] " & $scopeName

  # todo: make finder not Option
  assert finder.isSome
  assert finder.get.isNotNil

  var popup = SelectorPopup()
  popup.services = services
  popup.layout = services.getService(LayoutService).get
  popup.events = services.getService(EventHandlerService).get
  popup.editors = services.getService(DocumentEditorService).get
  popup.commands = services.getService(CommandService).get
  popup.settings = SelectorSettings.new(services.getService(ConfigService).get.runtime)
  popup.scale = vec2(0.5, 0.5)
  popup.scope = scopeName.get("")
  popup.initImpl = proc(self: Popup) = selectorPopupInit(self.SelectorPopup)
  popup.deinitImpl = proc(self: Popup) = selectorPopupDeinit(self.SelectorPopup)
  popup.getActiveEditorImpl = proc(self: Popup): Option[DocumentEditor] = selectorPopupGetActiveEditor(self.SelectorPopup)
  popup.getEventHandlersImpl = proc(self: Popup): seq[EventHandler] = selectorPopupGetEventHandlers(self.SelectorPopup)
  popup.cancelImpl = proc(self: Popup) = selectorPopupCancel(self.SelectorPopup)
  popup.handleActionImpl = proc(self: Popup, action: string, arg: string): Option[JsonNode] = selectorPopupHandleAction(self.SelectorPopup, action, arg)
  popup.renderImpl = proc(self: Popup, builder: UINodeBuilder): seq[OverlayFunction] =
    {.gcsafe.}:
      createUIImpl(self.SelectorPopup, builder)

  let document = popup.editors.createDocument("text", "ed://.selector-popup-search-bar", load = false, %%*{"createLanguageServer": false})
  document.usage = "search-bar"
  popup.textEditor = popup.editors.createEditorForDocument(document, %%*{
    "usage": "search-bar",
    "settings": {
      "text.disable-completions": true,
      "ui.line-numbers": "none",
      "ui.whitespace-char": " ",
      "text.cursor-margin": 0,
      "text.disable-scrolling": true,
      "text.default-mode": "vim.insert",
      "text.highlight-matches.enable": false,
    },
  }).get(nil)
  popup.textEditor.renderHeader = false
  popup.textEditor.active = true

  finder.get.minScore = popup.settings.minScore.get()

  discard popup.textEditor.currentDocument.getTextComponent().get.onEdit.subscribe (args: tuple[oldText: Rope, patch: Patch[Point]]) =>
    popup.handleTextChanged()

  discard popup.textEditor.onMarkedDirty.subscribe () =>
    popup.markDirty()

  popup.previewer = previewer.move
  if popup.previewer.isSome:

    # todo: make sure this previewDocument is destroyed, we're overriding it right now
    # in the previewer with a temp document or an existing one
    let previewDocument = popup.editors.createDocument("text", "ed://selector_popup_preview", load = false, %%*{"createLanguageServer": false})
    previewDocument.readOnly = true

    popup.previewEditor = popup.editors.createEditorForDocument(previewDocument, %%*{
      "usage": "preview",
    }).get(nil)
    popup.previewEditor.renderHeader = true

    discard popup.previewEditor.onMarkedDirty.subscribe () =>
      popup.markDirty()

  if finder.getSome(finder):
    popup.finder = finder
    discard popup.finder.onItemsChanged.subscribe () => popup.handleItemsUpdated()
    popup.finder.setQuery("")

  let config = services.getService(ConfigService).get.runtime
  popup.configChangedHandle = config.onConfigChanged.subscribe proc(key: string) =
    if popup.finder.isNil:
      return
    if key == "" or key == "finder" or key == "finder.scoring":
      popup.finder.setQuery(popup.getSearchString())

  return popup

proc asISelectorPopup*(self: SelectorPopup): ISelectorPopup =
  result.getSearchString = proc(): string {.gcsafe, raises: [].} = self.getSearchString()
  result.closed = proc(): bool {.gcsafe, raises: [].} = self.closed()
  result.getSelectedItem = proc(): Option[FinderItem] {.gcsafe, raises: [].} = self.getSelectedItem()
  result.pop = proc() {.gcsafe, raises: [].} = self.pop()
  result.preview = proc(item: FinderItem) {.gcsafe, raises: [].} = self.updatePreview(item)
