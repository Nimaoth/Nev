import std/[sugar, options, json, streams, tables]
import bumpy, vmath
import misc/[util, rect_utils, event, myjsonutils, fuzzy_matching, traits, custom_logger, disposable_ref]
import scripting/[expose]
import app_interface, text/text_editor, popup, events,
  selector_popup_builder, dispatch_tables, layout, service, config_provider, view, command_service
from scripting_api as api import Selection, ToggleBool, toToggleBool, applyTo
import finder/[finder, previewer]
import plugin_service

export popup, selector_popup_builder, service

{.push gcsafe.}

logCategory "selector"

declareSettings SelectorSettings, "selector":
  declare baseMode, string, "popup.selector"

type
  SelectorPopup* = ref object of Popup
    services*: Services
    layout*: LayoutService
    events*: EventHandlerService
    plugins: PluginService
    editors: DocumentEditorService
    commands: CommandService
    textEditor*: TextDocumentEditor
    previewEditor*: TextDocumentEditor
    previewView*: View
    selected*: int
    scrollOffset*: int
    handleItemConfirmed*: proc(finderItem: FinderItem): bool {.gcsafe, raises: [].}
    handleItemSelected*: proc(finderItem: FinderItem) {.gcsafe, raises: [].}
    handleCanceled*: proc() {.gcsafe, raises: [].}
    lastContentBounds*: Rect
    lastItems*: seq[tuple[index: int, bounds: Rect]]

    settings: SelectorSettings

    eventHandlers: Table[string,  EventHandler]

    viewMarkedDirtyHandle: Id

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

proc getSearchString*(self: SelectorPopup): string {.gcsafe, raises: [].}
proc closed*(self: SelectorPopup): bool {.gcsafe, raises: [].}
proc getSelectedItem*(self: SelectorPopup): Option[FinderItem] {.gcsafe, raises: [].}
proc handleItemsUpdated*(self: SelectorPopup) {.gcsafe, raises: [].}
proc pop*(self: SelectorPopup) {.gcsafe, raises: [].}

implTrait ISelectorPopup, SelectorPopup:
  getSearchString(string, SelectorPopup)
  closed(bool, SelectorPopup)
  getSelectedItem(Option[FinderItem], SelectorPopup)
  pop(void, SelectorPopup)

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
    discard matchFuzzySublime(query, text, result, true, config)
  else:
    discard matchFuzzySublime(pattern, text, result, true, config)
  self.completionMatchPositions[i] = result

method initImpl*(self: SelectorPopup) {.gcsafe, raises: [].} =
  self.handleItemsUpdated()

method deinit*(self: SelectorPopup) {.gcsafe, raises: [].} =
  logScope lvlInfo, &"[deinit] Destroying selector popup"

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

method getEventHandlers*(self: SelectorPopup): seq[EventHandler] =
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

proc updatePreview(self: SelectorPopup) =
  if self.previewer.isSome and self.finder.filteredItems.getSome(list) and list.filteredLen > 0:
    let view = self.previewer.get.get.previewItem(list[self.selected])
    if view != self.previewView:
      if self.previewView != nil:
        self.previewView.onMarkedDirty.unsubscribe(self.viewMarkedDirtyHandle)

      self.previewView = view

      if self.previewView != nil:
        self.viewMarkedDirtyHandle = self.previewView.onMarkedDirty.subscribe () =>
          self.markDirty()

    if view == nil and self.previewEditor.isNotNil:
      self.previewer.get.get.previewItem(list[self.selected], self.previewEditor)

proc setPreviewVisible*(self: SelectorPopup, visible: bool) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  assert self.finder.isNotNil
  self.previewVisible = visible

  if visible and self.finder.filteredItems.getSome(list) and list.filteredLen > 0:
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

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0:
    assert self.selected >= 0
    assert self.selected < list.filteredLen
    result = list[self.selected].some

proc pop*(self: SelectorPopup) {.expose("popup.selector").} =
  self.layout.popPopup(self)

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

    self.updatePreview()

  self.markDirty()

proc next*(self: SelectorPopup, count: int = 1) {.expose("popup.selector").} =
  if self.textEditor.isNil:
    return

  assert self.finder.isNotNil

  if self.finder.filteredItems.getSome(list) and list.filteredLen > 0:
    self.selected = (self.selected + count) mod list.filteredLen

    if not self.handleItemSelected.isNil:
      self.handleItemSelected list[self.selected]

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

method handleAction*(self: SelectorPopup, action: string, arg: string): Option[JsonNode] {.gcsafe, raises: [].} =
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

    let res1 = self.plugins.invokeAnyCallback(action, args)
    if res1.isNotNil:
      return res1.some

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

    self.updatePreview()

  else:
    self.selected = 0

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
  popup.plugins = services.getService(PluginService).get
  popup.editors = services.getService(DocumentEditorService).get
  popup.commands = services.getService(CommandService).get
  popup.settings = SelectorSettings.new(services.getService(ConfigService).get.runtime)
  popup.scale = vec2(0.5, 0.5)
  popup.scope = scopeName.get("")
  let document = newTextDocument(services, createLanguageServer=false, filename="ed://.selector-popup-search-bar")
  popup.textEditor = newTextEditor(document, services)
  popup.textEditor.usage = "search-bar"
  popup.textEditor.renderHeader = false
  popup.textEditor.uiSettings.lineNumbers.set(api.LineNumbers.None)
  popup.textEditor.settings.highlightMatches.enable.set(false)
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
    let previewDocument = newTextDocument(services, createLanguageServer=false, filename="ed://selector_popup_preview")
    previewDocument.readOnly = true

    popup.previewEditor = newTextEditor(previewDocument, services)
    popup.previewEditor.usage = "preview"
    popup.previewEditor.renderHeader = true
    popup.previewEditor.uiSettings.lineNumbers.set(api.LineNumbers.None)
    popup.previewEditor.disableCompletions = true
    popup.previewEditor.settings.cursorMargin.set(0.0)

    discard popup.previewEditor.onMarkedDirty.subscribe () =>
      popup.markDirty()

  if finder.getSome(finder):
    popup.finder = finder
    discard popup.finder.onItemsChanged.subscribe () => popup.handleItemsUpdated()
    popup.finder.setQuery("")

  return popup
