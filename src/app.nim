import std/[sequtils, strformat, strutils, tables, unicode, options, os, json, macros, macrocache, sugar, streams, deques, algorithm]
import asynctools/asyncipc
import misc/[id, util, timer, event, myjsonutils, traits, rect_utils, custom_logger, custom_async,
  array_set, delayed_task, regex, disposable_ref, rope_utils]
import ui/node
import scripting/[expose, scripting_base]
import platform/[platform, filesystem]
import workspaces/[workspace]
import config_provider, app_interface
import text/language/language_server_base, language_server_command_line
import input, events, document, document_editor, popup, dispatch_tables, theme, clipboard, app_options, selector_popup_builder, view, command_info, register
import text/[custom_treesitter]
import finder/[finder, previewer]
import compilation_config, vfs
import vcs/vcs
import service

import nimsumtree/[buffer, clock, rope]

import misc/async_process

when enableAst:
  import ast/[model, project]

import scripting/scripting_wasm

import scripting_api as api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, ModelDocumentEditor, Popup, SelectorPopup
from scripting_api import Backend

{.push gcsafe.}
{.push raises: [].}

logCategory "app"

const configDirName = "." & appName
const defaultSessionName = &".{appName}-session"

let platformName = when defined(windows):
  "windows"
elif defined(linux):
  "linux"
elif defined(wasm):
  "wasm"
else:
  "other"

type
  EditorView* = ref object of View
    document*: Document # todo: remove
    editor*: DocumentEditor

method activate*(view: EditorView) =
  view.active = true
  view.editor.active = true

method deactivate*(view: EditorView) =
  view.active = true
  view.editor.active = false

method markDirty*(view: EditorView, notify: bool = true) =
  view.dirty = true
  view.editor.markDirty(notify)

method getEventHandlers*(view: EditorView, inject: Table[string, EventHandler]): seq[EventHandler] =
  view.editor.getEventHandlers(inject)

method getActiveEditor*(self: EditorView): Option[DocumentEditor] =
  self.editor.some

type
  Layout* = ref object of RootObj
    discard
  HorizontalLayout* = ref object of Layout
    discard
  VerticalLayout* = ref object of Layout
    discard
  FibonacciLayout* = ref object of Layout
    discard
  LayoutProperties = ref object
    props: Table[string, float32]

type OpenEditor = object
  filename: string
  languageID: string
  appFile: bool
  workspaceId: string
  customOptions: JsonNode

type
  # todo: this isn't necessary anymore
  OpenWorkspaceKind {.pure.} = enum Local
  OpenWorkspace = object
    kind*: OpenWorkspaceKind
    id*: string
    name*: string
    settings*: JsonNode

type EditorState = object
  theme: string
  fontSize: float32 = 16
  lineDistance: float32 = 4
  fontRegular: string
  fontBold: string
  fontItalic: string
  fontBoldItalic: string
  fallbackFonts: seq[string]
  layout: string
  workspaceFolders: seq[OpenWorkspace]
  openEditors: seq[OpenEditor]
  hiddenEditors: seq[OpenEditor]
  commandHistory: seq[string]

  astProjectWorkspaceId: string
  astProjectPath: Option[string]

  debuggerState: Option[JsonNode]
  sessionData: JsonNode

type ScriptAction = object
  name: string
  scriptContext: ScriptContext

type
  App* = ref AppObject
  AppObject* = object
    backend: api.Backend
    platform*: Platform
    fontRegular*: string
    fontBold*: string
    fontItalic*: string
    fontBoldItalic*: string
    fallbackFonts: seq[string]
    clearAtlasTimer*: Timer
    timer*: Timer
    frameTimer*: Timer
    lastBounds*: Rect
    closeRequested*: bool
    appOptions: AppOptions

    fs*: Filesystem
    vfs*: VFS

    services: Services

    logNextFrameTime*: bool = false
    disableLogFrameTime*: bool = true
    logBuffer = ""

    registers: Table[string, Register]
    recordingKeys: seq[string]
    recordingCommands: seq[string]
    bIsReplayingKeys: bool = false
    bIsReplayingCommands: bool = false

    eventHandlerConfigs: Table[string, EventHandlerConfig]
    commandInfos*: CommandInfos
    commandDescriptions*: Table[string, string]

    options: JsonNode
    sessionData: JsonNode
    callbacks: Table[string, int]

    workspace*: Workspace

    wasmScriptContext*: ScriptContextWasm
    initializeCalled: bool

    currentScriptContext: Option[ScriptContext] = ScriptContext.none

    statusBarOnTop*: bool
    inputHistory*: string
    clearInputHistoryTask: DelayedTask

    currentViewInternal: int
    views*: seq[View]
    hiddenViews*: seq[View]
    layout*: Layout
    layout_props*: LayoutProperties
    maximizeView*: bool

    activeEditorInternal: Option[EditorId]
    editorHistory: Deque[EditorId]

    theme*: Theme
    loadedFontSize: float
    loadedLineDistance: float

    documents*: seq[Document]
    editors*: Table[EditorId, DocumentEditor]
    popups*: seq[Popup]

    onEditorRegistered*: Event[DocumentEditor]
    onEditorDeregistered*: Event[DocumentEditor]
    onConfigChanged*: Event[void]

    logDocument: Document

    commandHistory: seq[string]
    currentHistoryEntry: int = 0
    languageServerCommandLine: LanguageServer
    commandLineTextEditor: DocumentEditor
    eventHandler*: EventHandler
    commandLineEventHandlerHigh*: EventHandler
    commandLineEventHandlerLow*: EventHandler
    commandLineMode*: bool

    modeEventHandler: EventHandler
    currentMode*: string
    leaders: seq[string]

    editorDefaults: seq[DocumentEditor]

    scriptActions: Table[string, ScriptAction]

    sessionFile*: string

    gitIgnore: Globs

    currentLocationListIndex: int
    finderItems: seq[FinderItem]
    previewer: Option[DisposableRef[Previewer]]

    closeUnusedDocumentsTask: DelayedTask

    homeDir: string

var gEditor* {.exportc.}: App = nil

implTrait ConfigProvider, App:
  proc getConfigValue(self: App, path: string): Option[JsonNode] =
    let node = self.options{path.split(".")}
    if node.isNil:
      return JsonNode.none
    return node.some

  proc setConfigValue(self: App, path: string, value: JsonNode) =
    try:
      let pathItems = path.split(".")
      var node = self.options
      for key in pathItems[0..^2]:
        if node.kind != JObject:
          return
        if not node.contains(key):
          node[key] = newJObject()
        node = node[key]
      if node.isNil or node.kind != JObject:
        return
      node[pathItems[^1]] = value
    except KeyError:
      discard

  proc onConfigChanged*(self: App): ptr Event[void] = self.onConfigChanged.addr

proc handleLog(self: App, level: Level, args: openArray[string])
proc getEventHandlerConfig*(self: App, context: string): EventHandlerConfig
proc setRegisterTextAsync*(self: App, text: string, register: string = ""): Future[void]
proc getRegisterTextAsync*(self: App, register: string = ""): Future[string]
proc setRegisterAsync*(self: App, register: string, value: sink Register): Future[void]
proc getRegisterAsync*(self: App, register: string, res: ptr Register): Future[bool]
proc recordCommand*(self: App, command: string, args: string)
proc openWorkspaceFile*(self: App, path: string, append: bool = false): Option[DocumentEditor]
proc openFile*(self: App, path: string, appFile: bool = false): Option[DocumentEditor]
proc handleModeChanged*(self: App, editor: DocumentEditor, oldMode: string, newMode: string)
proc invokeCallback*(self: App, context: string, args: JsonNode): bool
proc invokeAnyCallback*(self: App, context: string, args: JsonNode): JsonNode
proc registerEditor*(self: App, editor: DocumentEditor): void
proc unregisterEditor*(self: App, editor: DocumentEditor): void
proc tryActivateEditor*(self: App, editor: DocumentEditor): void
proc getActiveEditor*(self: App): Option[DocumentEditor]
proc getEditorForId*(self: App, id: EditorId): Option[DocumentEditor]
proc getEditorForPath*(self: App, path: string): Option[DocumentEditor]
proc getPopupForId*(self: App, id: EditorId): Option[Popup]
proc pushSelectorPopup*(self: App, builder: SelectorPopupBuilder): ISelectorPopup
proc pushPopup*(self: App, popup: Popup)
proc popPopup*(self: App, popup: Popup)
proc help*(self: App, about: string = "")
proc getAllDocuments*(self: App): seq[Document]
proc setHandleInputs*(self: App, context: string, value: bool)
proc setLocationList*(self: App, list: seq[FinderItem], previewer: Option[Previewer] = Previewer.none)
proc getDocument*(self: App, path: string, appFile = false): Option[Document]
proc getOrOpenDocument*(self: App, path: string, appFile = false, load = true): Option[Document]
proc tryCloseDocument*(self: App, document: Document, force: bool): bool
proc closeUnusedDocuments*(self: App)
proc tryOpenExisting*(self: App, path: string, appFile: bool = false, append: bool = false): Option[DocumentEditor]
proc setOption*(self: App, option: string, value: JsonNode, override: bool = true)
proc addCommandScript*(self: App, context: string, subContext: string, keys: string, action: string, arg: string = "", description: string = "", source: tuple[filename: string, line: int, column: int] = ("", 0, 0))
proc currentEventHandlers*(self: App): seq[EventHandler]
proc getEditorsForDocument(self: App, document: Document): seq[DocumentEditor]
proc showEditor*(self: App, editorId: EditorId, viewIndex: Option[int] = int.none)
proc getServices*(self: App): Services
proc getService*(self: App, name: string): Option[Service]
proc addService*(self: App, name: string, service: Service)

proc createView(self: App, editorState: OpenEditor): View

proc setFlag*(self: App, flag: string, value: bool)
proc toggleFlag*(self: App, flag: string)

implTrait AppInterface, App:
  proc platform*(self: App): Platform = self.platform

  getEventHandlerConfig(EventHandlerConfig, App, string)

  setRegisterTextAsync(Future[void], App, string, string)
  getRegisterTextAsync(Future[string], App, string)
  setRegisterAsync(Future[void], App, string, sink Register)
  getRegisterAsync(Future[bool], App, string, ptr Register)
  recordCommand(void, App, string, string)

  proc configProvider*(self: App): ConfigProvider = self.asConfigProvider
  proc onEditorRegisteredEvent*(self: App): ptr Event[DocumentEditor] = self.onEditorRegistered.addr
  proc onEditorDeregisteredEvent*(self: App): ptr Event[DocumentEditor] = self.onEditorDeregistered.addr

  openWorkspaceFile(Option[DocumentEditor], App, string, bool)
  openFile(Option[DocumentEditor], App, string)
  handleModeChanged(void, App, DocumentEditor, string, string)
  invokeCallback(bool, App, string, JsonNode)
  invokeAnyCallback(JsonNode, App, string, JsonNode)
  registerEditor(void, App, DocumentEditor)
  tryActivateEditor(void, App, DocumentEditor)
  getActiveEditor(Option[DocumentEditor], App)
  unregisterEditor(void, App, DocumentEditor)
  getEditorForId(Option[DocumentEditor], App, EditorId)
  getEditorForPath(Option[DocumentEditor], App, string)
  getPopupForId(Option[Popup], App, EditorId)
  pushSelectorPopup(ISelectorPopup, App, SelectorPopupBuilder)
  pushPopup(void, App, Popup)
  popPopup(void, App, Popup)
  getAllDocuments(seq[Document], App)
  setLocationList(void, App, seq[FinderItem], Option[Previewer])
  getDocument(Option[Document], App, string, bool)
  getOrOpenDocument(Option[Document], App, string, bool, bool)
  tryCloseDocument(bool, App, Document, bool)
  getServices(Services, App)
  getService(Option[Service], App, string)
  addService(void, App, string, Service)

type
  AppLogger* = ref object of Logger
    app: App

method log*(self: AppLogger, level: Level, args: varargs[string, `$`]) =
  {.cast(gcsafe).}:
    self.app.handleLog(level, @args)

proc handleKeyPress*(self: App, input: int64, modifiers: Modifiers)
proc handleKeyRelease*(self: App, input: int64, modifiers: Modifiers)
proc handleRune*(self: App, input: int64, modifiers: Modifiers)
proc handleDropFile*(self: App, path, content: string)

proc openWorkspaceKind(workspaceFolder: Workspace): OpenWorkspaceKind
proc setWorkspaceFolder(self: App, workspace: Workspace): Future[bool]
proc setLayout*(self: App, layout: string)

template withScriptContext(self: App, scriptContext: untyped, body: untyped): untyped =
  if scriptContext.isNotNil:
    let oldScriptContext = self.currentScriptContext
    {.push hint[ConvFromXtoItselfNotNeeded]:off.}
    self.currentScriptContext = scriptContext.ScriptContext.some
    {.pop.}
    defer:
      self.currentScriptContext = oldScriptContext
    body

proc registerEditor*(self: App, editor: DocumentEditor): void =
  let filename = if editor.getDocument().isNotNil: editor.getDocument().filename else: ""
  log lvlInfo, fmt"registerEditor {editor.id} '{filename}'"
  self.editors[editor.id] = editor
  self.onEditorRegistered.invoke editor

proc unregisterEditor*(self: App, editor: DocumentEditor): void =
  let filename = if editor.getDocument().isNotNil: editor.getDocument().filename else: ""
  log lvlInfo, fmt"unregisterEditor {editor.id} '{filename}'"
  self.editors.del(editor.id)
  self.onEditorDeregistered.invoke editor

proc invokeCallback*(self: App, context: string, args: JsonNode): bool =
  try:
    if not self.callbacks.contains(context):
      return false
    let id = self.callbacks[context]

    withScriptContext self, self.wasmScriptContext:
      if self.wasmScriptContext.handleCallback(id, args):
        return true
    return false
  except CatchableError:
    log(lvlError, fmt"Failed to run script handleCallback {context}: {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())
    return false

proc invokeAnyCallback*(self: App, context: string, args: JsonNode): JsonNode =
  # debugf"invokeAnyCallback {context}: {args}"
  if self.callbacks.contains(context):
    try:
      let id = self.callbacks[context]

      withScriptContext self, self.wasmScriptContext:
        let res = self.wasmScriptContext.handleAnyCallback(id, args)
        if res.isNotNil:
          return res
      return nil
    except CatchableError:
      log(lvlError, fmt"Failed to run script handleAnyCallback {context}: {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())
      return nil

  else:
    try:
      withScriptContext self, self.wasmScriptContext:
        let res = self.wasmScriptContext.handleScriptAction(context, args)
        if res.isNotNil:
          return res
      return nil
    except CatchableError:
      log(lvlError, fmt"Failed to run script handleScriptAction {context}: {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())
      return nil

method layoutViews*(layout: Layout, props: LayoutProperties, bounds: Rect, views: int): seq[Rect] {.base.} =
  return @[bounds]

method layoutViews*(layout: HorizontalLayout, props: LayoutProperties, bounds: Rect, views: int): seq[Rect] =
  let mainSplit = props.props.getOrDefault("main-split", 0.5)
  result = @[]
  var rect = bounds
  for i in 0..<views:
    let ratio = if i == 0 and views > 1: mainSplit else: 1.0 / (views - i).float32
    let (view_rect, remaining) = rect.splitV(ratio.percent)
    rect = remaining
    result.add view_rect

method layoutViews*(layout: VerticalLayout, props: LayoutProperties, bounds: Rect, views: int): seq[Rect] =
  let mainSplit = props.props.getOrDefault("main-split", 0.5)
  result = @[]
  var rect = bounds
  for i in 0..<views:
    let ratio = if i == 0 and views > 1: mainSplit else: 1.0 / (views - i).float32
    let (view_rect, remaining) = rect.splitH(ratio.percent)
    rect = remaining
    result.add view_rect

method layoutViews*(layout: FibonacciLayout, props: LayoutProperties, bounds: Rect, views: int): seq[Rect] =
  let mainSplit = props.props.getOrDefault("main-split", 0.5)
  result = @[]
  var rect = bounds
  for i in 0..<views:
    let ratio = if i == 0 and views > 1: mainSplit elif i == views - 1: 1.0 else: 0.5
    let (view_rect, remaining) = if i mod 2 == 0: rect.splitV(ratio.percent) else: rect.splitH(ratio.percent)
    rect = remaining
    result.add view_rect

proc handleModeChanged*(self: App, editor: DocumentEditor, oldMode: string, newMode: string) =
  try:
    withScriptContext self, self.wasmScriptContext:
      self.wasmScriptContext.handleEditorModeChanged(editor, oldMode, newMode)
  except CatchableError:
    log(lvlError, fmt"Failed to run script handleDocumentModeChanged '{oldMode} -> {newMode}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

proc handleAction(self: App, action: string, arg: string, record: bool): Option[JsonNode]
proc getFlag*(self: App, flag: string, default: bool = false): bool

proc createEditorForDocument(self: App, document: Document): DocumentEditor =
  for editor in self.editorDefaults:
    if editor.canEdit document:
      result = editor.createWithDocument(document, self.asConfigProvider)
      result.injectDependencies self.asAppInterface, self.fs
      discard result.onMarkedDirty.subscribe () => self.platform.requestRender()
      return

  log(lvlError, "No editor found which can edit " & $document)
  return nil

proc getOption*[T](editor: App, path: string, default: Option[T] = T.none): Option[T] =
  try:
    template createScriptGetOption(editor, path, defaultValue, accessor: untyped): untyped {.used.} =
      block:
        if editor.isNil:
          return default
        let node = editor.options{path.split(".")}
        if node.isNil:
          return default
        accessor(node, defaultValue)

    when T is bool:
      return createScriptGetOption(editor, path, T.default, getBool).some
    elif T is enum:
      return parseEnum[T](createScriptGetOption(editor, path, "", getStr)).some.catch(default)
    elif T is Ordinal:
      return createScriptGetOption(editor, path, T.default.int, getInt).T.some
    elif T is float32 | float64:
      return createScriptGetOption(editor, path, T.default, getFloat).some
    elif T is string:
      return createScriptGetOption(editor, path, T.default, getStr).some
    elif T is JsonNode:
      if editor.isNil:
        return default
      let node = editor.options{path.split(".")}
      if node.isNil:
        return default
      return node.some
    else:
      {.fatal: ("Can't get option with type " & $T).}

  except:
    return T.none

proc getOption*[T](editor: App, path: string, default: T = T.default): T =
  try:
    template createScriptGetOption(editor, path, defaultValue, accessor: untyped): untyped {.used.} =
      block:
        if editor.isNil:
          return default
        let node = editor.options{path.split(".")}
        if node.isNil:
          return default
        accessor(node, defaultValue)

    when T is bool:
      return createScriptGetOption(editor, path, default, getBool)
    elif T is enum:
      return parseEnum[T](createScriptGetOption(editor, path, "", getStr), default)
    elif T is Ordinal:
      return createScriptGetOption(editor, path, default, getInt)
    elif T is float32 | float64:
      return createScriptGetOption(editor, path, default, getFloat)
    elif T is string:
      return createScriptGetOption(editor, path, default, getStr)
    elif T is JsonNode:
      if editor.isNil:
        return default
      let node = editor.options{path.split(".")}
      if node.isNil:
        return default
      return node
    else:
      {.fatal: ("Can't get option with type " & $T).}

  except:
    return default

proc setOption*[T](editor: App, path: string, value: T) =
  template createScriptSetOption(editor, path, value, constructor: untyped): untyped =
    block:
      if editor.isNil:
        return
      let pathItems = path.split(".")
      var node = editor.options
      for key in pathItems[0..^2]:
        if node.kind != JObject:
          return
        if not node.contains(key):
          node[key] = newJObject()
        node = node[key]
      if node.isNil or node.kind != JObject:
        return
      node[pathItems[^1]] = constructor(value)

  try:
    when T is bool:
      editor.createScriptSetOption(path, value, newJBool)
    elif T is Ordinal:
      editor.createScriptSetOption(path, value, newJInt)
    elif T is float32 | float64:
      editor.createScriptSetOption(path, value, newJFloat)
    elif T is string:
      editor.createScriptSetOption(path, value, newJString)
    else:
      {.fatal: ("Can't set option with type " & $T).}

    editor.onConfigChanged.invoke()
    editor.platform.requestRender(true)

  except:
    discard

proc currentView*(self: App): int = self.currentViewInternal

proc tryGetCurrentView(self: App): Option[View] =
  if self.currentView >= 0 and self.currentView < self.views.len:
    self.views[self.currentView].some
  else:
    View.none

proc tryGetCurrentEditorView(self: App): Option[EditorView] =
  if self.tryGetCurrentView().getSome(view) and view of EditorView:
    view.EditorView.some
  else:
    EditorView.none

proc updateActiveEditor*(self: App, addToHistory = true) =
  if self.tryGetCurrentEditorView().getSome(view):
    if addToHistory and self.activeEditorInternal.getSome(id) and id != view.editor.id:
      self.editorHistory.addLast id
    self.activeEditorInternal = view.editor.id.some

proc `currentView=`(self: App, newIndex: int, addToHistory = true) =
  self.currentViewInternal = newIndex
  self.updateActiveEditor(addToHistory)

proc addView*(self: App, view: View, addToHistory = true, append = false) =
  let maxViews = getOption[int](self, "editor.maxViews", int.high)

  while maxViews > 0 and self.views.len > maxViews:
    self.views[self.views.high].deactivate()
    self.hiddenViews.add self.views.pop()

  if append:
    self.currentView = self.views.high

  if self.views.len == maxViews:
    self.views[self.currentView].deactivate()
    self.hiddenViews.add self.views[self.currentView]
    self.views[self.currentView] = view
  elif append:
    self.views.add view
  else:
    if self.currentView < 0:
      self.currentView = 0
    self.views.insert(view, self.currentView)

  if self.currentView < 0:
    self.currentView = 0

  view.markDirty()

  self.updateActiveEditor(addToHistory)
  self.platform.requestRender()

proc createView*(self: App, document: Document): View =
  var editor = self.createEditorForDocument document
  return EditorView(document: document, editor: editor)

proc createAndAddView*(self: App, document: Document, append = false): DocumentEditor =
  var editor = self.createEditorForDocument document
  var view = EditorView(document: document, editor: editor)
  self.addView(view, append=append)
  return editor

proc tryActivateEditor*(self: App, editor: DocumentEditor): void =
  if self.popups.len > 0:
    return
  for i, view in self.views:
    if view of EditorView and view.EditorView.editor == editor:
      self.currentView = i

proc pushPopup*(self: App, popup: Popup) =
  popup.init()
  self.popups.add popup
  discard popup.onMarkedDirty.subscribe () => self.platform.requestRender()
  self.platform.requestRender()

proc popPopup*(self: App, popup: Popup) =
  if self.popups.len > 0 and self.popups[self.popups.high] == popup:
    popup.deinit()
    discard self.popups.pop
  self.platform.requestRender()

proc getEventHandlerConfig*(self: App, context: string): EventHandlerConfig =
  if not self.eventHandlerConfigs.contains(context):
    let parentConfig = if context != "":
      let index = context.rfind(".")
      if index >= 0:
        self.getEventHandlerConfig(context[0..<index])
      else:
        self.getEventHandlerConfig("")
    else:
      nil

    self.eventHandlerConfigs[context] = newEventHandlerConfig(context, parentConfig)
    self.eventHandlerConfigs[context].setLeaders(self.leaders)

  return self.eventHandlerConfigs[context].catch(EventHandlerConfig())

proc getEditorForId*(self: App, id: EditorId): Option[DocumentEditor] =
  self.editors.withValue(id, editor):
    return editor[].some

  if self.commandLineTextEditor.id == id:
    return self.commandLineTextEditor.some

  return DocumentEditor.none

proc getEditorForPath*(self: App, path: string): Option[DocumentEditor] =
  let path = self.workspace.getAbsolutePath(path)
  return self.tryOpenExisting(path)

proc getPopupForId*(self: App, id: EditorId): Option[Popup] =
  for popup in self.popups:
    if popup.id == id:
      return popup.some

  return Popup.none

proc getAllDocuments*(self: App): seq[Document] =
  for it in self.editors.values:
    result.incl it.getDocument

import text/[text_editor, text_document]
import text/language/debugger
import text/language/lsp_client
when enableAst:
  import ast/[model_document]
import selector_popup
import finder/[workspace_file_previewer, open_editor_previewer]
import collab

# todo: remove this function
proc setLocationList(self: App, list: seq[FinderItem], previewer: Option[Previewer] = Previewer.none) =
  self.currentLocationListIndex = 0
  self.finderItems = list
  self.previewer = previewer.toDisposableRef

proc setLocationList(self: App, list: seq[FinderItem],
    previewer: sink Option[DisposableRef[Previewer]] = DisposableRef[Previewer].none) =
  self.currentLocationListIndex = 0
  self.finderItems = list
  self.previewer = previewer.move

proc setTheme*(self: App, path: string) =
  log(lvlInfo, fmt"Loading theme {path}")
  if theme.loadFromFile(self.fs, path).getSome(theme):
    self.theme = theme
    {.gcsafe.}:
      gTheme = theme
  else:
    log(lvlError, fmt"Failed to load theme {path}")
  self.platform.requestRender()

proc getCommandLineTextEditor*(self: App): TextDocumentEditor = self.commandLineTextEditor.TextDocumentEditor

proc runConfigCommands(self: App, key: string) =
  let startupCommands = self.getOption(key, newJArray())
  if startupCommands.isNil or startupCommands.kind != JArray:
    return

  for command in startupCommands:
    if command.kind == JString:
      let (action, arg) = command.getStr.parseAction
      log lvlInfo, &"[runConfigCommands: {key}] {action} {arg}"
      discard self.handleAction(action, arg, record=false)
    if command.kind == JArray:
      let action = command[0].getStr
      let arg = command.elems[1..^1].mapIt($it).join(" ")
      log lvlInfo, &"[runConfigCommands: {key}] {action} {arg}"
      discard self.handleAction(action, arg, record=false)

proc initScripting(self: App, options: AppOptions) {.async.} =
  if not options.disableWasmPlugins:
    try:
      log(lvlInfo, fmt"load wasm configs")
      self.wasmScriptContext = new ScriptContextWasm
      self.wasmScriptContext.vfs = VFSWasmContext()
      self.vfs.mount("plugs://", self.wasmScriptContext.vfs)

      withScriptContext self, self.wasmScriptContext:
        let t1 = startTimer()
        await self.wasmScriptContext.init("./config", self.fs)
        log(lvlInfo, fmt"init wasm configs ({t1.elapsed.ms}ms)")

        let t2 = startTimer()
        discard self.wasmScriptContext.postInitialize()
        log(lvlInfo, fmt"post init wasm configs ({t2.elapsed.ms}ms)")
    except CatchableError:
      log lvlError, &"Failed to load wasm configs: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

  self.runConfigCommands("wasm-plugin-post-load-commands")
  self.runConfigCommands("plugin-post-load-commands")

  log lvlInfo, &"Finished loading plugins"

proc setupDefaultKeybindings(self: App) =
  log lvlInfo, fmt"Applying default builtin keybindings"

  let editorConfig = self.getEventHandlerConfig("editor")
  let textConfig = self.getEventHandlerConfig("editor.text")
  let textCompletionConfig = self.getEventHandlerConfig("editor.text.completion")
  let commandLineConfig = self.getEventHandlerConfig("command-line-high")
  let selectorPopupConfig = self.getEventHandlerConfig("popup.selector")

  self.setHandleInputs("editor.text", true)
  setOption[string](self, "editor.text.cursor.movement.", "both")
  setOption[bool](self, "editor.text.cursor.wide.", false)

  editorConfig.addCommand("", "<C-x><C-x>", "quit")
  editorConfig.addCommand("", "<CAS-r>", "reload-plugin")
  editorConfig.addCommand("", "<C-w><LEFT>", "prev-view")
  editorConfig.addCommand("", "<C-w><RIGHT>", "next-view")
  editorConfig.addCommand("", "<C-w><C-x>", "close-current-view true")
  editorConfig.addCommand("", "<C-w><C-X>", "close-current-view false")
  editorConfig.addCommand("", "<C-s>", "write-file")
  editorConfig.addCommand("", "<C-w><C-w>", "command-line")
  editorConfig.addCommand("", "<C-o>", "choose-file \"new\"")
  editorConfig.addCommand("", "<C-h>", "choose-open \"new\"")

  textConfig.addCommand("", "<LEFT>", "move-cursor-column -1")
  textConfig.addCommand("", "<RIGHT>", "move-cursor-column 1")
  textConfig.addCommand("", "<HOME>", "move-first \"line\"")
  textConfig.addCommand("", "<END>", "move-last \"line\"")
  textConfig.addCommand("", "<UP>", "move-cursor-line -1")
  textConfig.addCommand("", "<DOWN>", "move-cursor-line 1")
  textConfig.addCommand("", "<S-LEFT>", "move-cursor-column -1 \"last\"")
  textConfig.addCommand("", "<S-RIGHT>", "move-cursor-column 1 \"last\"")
  textConfig.addCommand("", "<S-UP>", "move-cursor-line -1 \"last\"")
  textConfig.addCommand("", "<S-DOWN>", "move-cursor-line 1 \"last\"")
  textConfig.addCommand("", "<S-HOME>", "move-first \"line\" \"last\"")
  textConfig.addCommand("", "<S-END>", "move-last \"line\" \"last\"")
  textConfig.addCommand("", "<C-LEFT>", "move-cursor-column -1 \"last\"")
  textConfig.addCommand("", "<C-RIGHT>", "move-cursor-column 1 \"last\"")
  textConfig.addCommand("", "<C-UP>", "move-cursor-line -1 \"last\"")
  textConfig.addCommand("", "<C-DOWN>", "move-cursor-line 1 \"last\"")
  textConfig.addCommand("", "<C-HOME>", "move-first \"line\" \"last\"")
  textConfig.addCommand("", "<C-END>", "move-last \"line\" \"last\"")
  textConfig.addCommand("", "<BACKSPACE>", "delete-left")
  textConfig.addCommand("", "<DELETE>", "delete-right")
  textConfig.addCommand("", "<ENTER>", "insert-text \"\\n\"")
  textConfig.addCommand("", "<SPACE>", "insert-text \" \"")
  textConfig.addCommand("", "<C-k>", "get-completions")

  textConfig.addCommand("", "<C-z>", "undo")
  textConfig.addCommand("", "<C-y>", "redo")
  textConfig.addCommand("", "<C-c>", "copy")
  textConfig.addCommand("", "<C-v>", "paste")

  textCompletionConfig.addCommand("", "<ESCAPE>", "hide-completions")
  textCompletionConfig.addCommand("", "<C-p>", "select-prev-completion")
  textCompletionConfig.addCommand("", "<C-n>", "select-next-completion")
  textCompletionConfig.addCommand("", "<C-y>", "apply-selected-completion")

  commandLineConfig.addCommand("", "<ESCAPE>", "exit-command-line")
  commandLineConfig.addCommand("", "<ENTER>", "execute-command-line")

  selectorPopupConfig.addCommand("", "<ENTER>", "accept")
  selectorPopupConfig.addCommand("", "<TAB>", "accept")
  selectorPopupConfig.addCommand("", "<ESCAPE>", "cancel")
  selectorPopupConfig.addCommand("", "<UP>", "prev")
  selectorPopupConfig.addCommand("", "<DOWN>", "next")
  selectorPopupConfig.addCommand("", "<C-u>", "prev-x")
  selectorPopupConfig.addCommand("", "<C-d>", "next-x")

proc testApplicationPath*(path: string): (bool, string) =
  ## Returns true as the first value if the path starts with 'app:'
  ## The second return value is the path without the 'app:'.
  result = (false, path)
  if path.startsWith "app:":
    return (true, path[4..^1])

proc restoreStateFromConfig*(self: App, state: var EditorState) =
  try:
    let (isAppFile, path) = self.sessionFile.testApplicationPath()
    let stateJson = if isAppFile:
      self.fs.loadApplicationFile(path).parseJson
    else:
      self.fs.loadFile(path).parseJson

    state = stateJson.jsonTo(EditorState, JOptions(allowMissingKeys: true, allowExtraKeys: true))
    log(lvlInfo, fmt"Restoring session {self.sessionFile}")

    if not state.theme.isEmptyOrWhitespace:
      try:
        self.setTheme(state.theme)
      except CatchableError:
        log(lvlError, fmt"Failed to load theme: {getCurrentExceptionMsg()}")

    if not state.layout.isEmptyOrWhitespace:
      self.setLayout(state.layout)

    let fontSize = max(state.fontSize.float, 10.0)
    self.loadedFontSize = fontSize
    self.platform.fontSize = fontSize
    self.loadedLineDistance = state.lineDistance.float
    self.platform.lineDistance = state.lineDistance.float
    if state.fontRegular.len > 0: self.fontRegular = state.fontRegular
    if state.fontBold.len > 0: self.fontBold = state.fontBold
    if state.fontItalic.len > 0: self.fontItalic = state.fontItalic
    if state.fontBoldItalic.len > 0: self.fontBoldItalic = state.fontBoldItalic
    if state.fallbackFonts.len > 0: self.fallbackFonts = state.fallbackFonts

    self.platform.setFont(self.fontRegular, self.fontBold, self.fontItalic, self.fontBoldItalic, self.fallbackFonts)

    self.sessionData = state.sessionData
  except CatchableError:
    log(lvlError, fmt"Failed to load previous state from config file: {getCurrentExceptionMsg()}")

proc loadKeybindingsFromJson*(self: App, json: JsonNode, filename: string) =
  try:
    let oldScriptContext = self.currentScriptContext
    self.currentScriptContext = ScriptContext.none
    defer:
      self.currentScriptContext = oldScriptContext

    for (scope, commands) in json.fields.pairs:
      for (keys, command) in commands.fields.pairs:
        if command.kind == JString:
          let commandStr = command.getStr
          let spaceIndex = commandStr.find(" ")

          let (name, args) = if spaceIndex == -1:
            (commandStr, "")
          else:
            (commandStr[0..<spaceIndex], commandStr[spaceIndex+1..^1])

          # todo: line
          self.addCommandScript(scope, "", keys, name, args, source = (filename, 0, 0))

        elif command.kind == JObject:
          let name = command["command"].getStr
          let args = command["args"].elems.mapIt($it).join(" ")
          let description = command.fields.getOrDefault("description", newJString("")).getStr
          # todo: line
          self.addCommandScript(scope, "", keys, name, args, description, source = (filename, 0, 0))

  except CatchableError:
    log(lvlError, &"Failed to load keybindings from json: {getCurrentExceptionMsg()}\n{json.pretty}")

proc loadSettingsFrom*(self: App, directory: string,
    loadFile: proc(self: App, context: string, path: string): Future[Option[string]] {.gcsafe, raises: [].}) {.async.} =

  {.gcsafe.}:
    let filenames = [
      &"{directory}/settings.json",
      &"{directory}/settings-{platformName}.json",
      &"{directory}/settings-{self.backend}.json",
      &"{directory}/settings-{platformName}-{self.backend}.json",
    ]

  let settings = allFinished(
    loadFile(self, "settings", filenames[0]),
    loadFile(self, "settings", filenames[1]),
    loadFile(self, "settings", filenames[2]),
    loadFile(self, "settings", filenames[3]),
  ).await.mapIt(it.read)

  assert filenames.len == settings.len

  for i in 0..<filenames.len:
    if settings[i].isSome:
      try:
        log lvlInfo, &"Apply settings from {filenames[i]}"
        let json = settings[i].get.parseJson()
        self.setOption("", json, override=false)

      except CatchableError:
        log(lvlError, &"Failed to load settings from {filenames[i]}: {getCurrentExceptionMsg()}")

proc loadKeybindings*(self: App, directory: string,
    loadFile: proc(self: App, context: string, path: string): Future[Option[string]] {.gcsafe, raises: [].}) {.async.} =

  {.gcsafe.}:
    let filenames = [
      &"{directory}/keybindings.json",
      &"{directory}/keybindings-{platformName}.json",
      &"{directory}/keybindings-{self.backend}.json",
      &"{directory}/keybindings-{platformName}-{self.backend}.json",
    ]

  let settings = allFinished(
    loadFile(self, "keybindings", filenames[0]),
    loadFile(self, "keybindings", filenames[1]),
    loadFile(self, "keybindings", filenames[2]),
    loadFile(self, "keybindings", filenames[3]),
  ).await.mapIt(it.read)

  for i in 0..<filenames.len:
    if settings[i].isSome:
      try:
        log lvlInfo, &"Apply keybindings from {filenames[i]}"
        let json = settings[i].get.parseJson()
        self.loadKeybindingsFromJson(json, filenames[i])

      except CatchableError:
        log(lvlError, fmt"Failed to load keybindings from {filenames[i]}: {getCurrentExceptionMsg()}")

proc loadConfigFileFromAppDir(self: App, context: string, path: string):
    Future[Option[string]] {.async.} =
  try:
    log lvlInfo, &"Try load {context} from app:{path}"
    let content = await self.fs.loadApplicationFileAsync(path)
    if content.len > 0:
      return content.some
  except CatchableError:
    log(lvlError, fmt"Failed to load {context} from app dir: {getCurrentExceptionMsg()}")

  return string.none

proc loadConfigFileFromHomeDir(self: App, context: string, path: string):
    Future[Option[string]] {.async.} =
  try:
    if self.homeDir.len == 0:
      log lvlInfo, &"No home directory"
      return

    log lvlInfo, &"Try load {context} from {self.homeDir}/{path}"
    let content = await self.fs.loadFileAsync(self.homeDir // path)
    if content.len > 0:
      return content.some
  except CatchableError:
    log(lvlError, fmt"Failed to load {context} from home {self.homeDir}: {getCurrentExceptionMsg()}")

  return string.none

proc loadConfigFileFromWorkspaceDir(self: App, context: string, path: string):
    Future[Option[string]] {.async.} =
  try:
    log lvlInfo, &"Try load {context} from {self.workspace.name}/{path}"
    let content = await self.workspace.loadFile(path)
    if content.len > 0:
      return content.some
  except CatchableError:
    log(lvlError,
      fmt"Failed to load {context} from workspace {self.workspace.name}: {getCurrentExceptionMsg()}")

  return string.none

proc loadOptionsFromAppDir*(self: App) {.async.} =
  await allFutures(
    self.loadSettingsFrom("config", loadConfigFileFromAppDir),
    self.loadKeybindings("config", loadConfigFileFromAppDir)
  )

proc loadOptionsFromHomeDir*(self: App) {.async.} =
  await allFutures(
    self.loadSettingsFrom(configDirName, loadConfigFileFromHomeDir),
    self.loadKeybindings(configDirName, loadConfigFileFromHomeDir)
  )

proc loadOptionsFromWorkspace*(self: App) {.async.} =
  await allFutures(
    self.loadSettingsFrom(configDirName, loadConfigFileFromWorkspaceDir),
    self.loadKeybindings(configDirName, loadConfigFileFromWorkspaceDir)
  )

# import asynchttpserver, asyncnet

# proc processClient(client: AsyncSocket) {.async.} =
#   log lvlInfo, &"Process client"
#   let self: App = ({.gcsafe.}: gEditor)

#   try:
#     while not client.isClosed:
#       let line = await client.recvLine()
#       if line.len == 0:
#         break

#       log lvlInfo, &"Run command from client: '{line}'"
#       let command = line
#       let (action, arg) = parseAction(command)
#       let response = self.handleAction(action, arg, record=true)
#       if response.getSome(r):
#         await client.send($r & "\n")
#       else:
#         await client.send("\n")

#   except:
#     log lvlError, &"Failed to read data from connection: {getCurrentExceptionMsg()}"

# proc serve(port: Port, savePort: bool) {.async.} =
#   var server: AsyncSocket

#   try:
#     server = newAsyncSocket()
#     server.setSockOpt(OptReuseAddr, true)
#     server.bindAddr(port)
#     server.listen()
#     let actualPort = server.getLocalAddr()[1]
#     log lvlInfo, &"Listen for connections on port {actualPort.int}"
#     if savePort:
#       let fileName = getTempDir() / (appName & "_port_" & $os.getCurrentProcessId())
#       log lvlInfo, &"Write port to {fileName}"
#       self.fs.saveFile(fileName, $actualPort.int)
#   except:
#     log lvlError, &"Failed to create server on port {port.int}: {getCurrentExceptionMsg()}"
#     return

#   while true:
#     let client = await server.accept()

#     asyncSpawn processClient(client)

# proc listenForConnection*(self: App, port: Port) {.async.} =
#   await serve(port, self.getFlag("command-server.save-file", false))

# proc listenForIpc(self: App, id: int) {.async.} =
#   try:
#     let ipcName = appName & "-" & $id
#     log lvlInfo, &"Listen for ipc commands through {ipcName}"
#     let  ipc = createIpc(ipcName).catch:
#       log lvlWarn, &"Ipc port 0 already occupied"
#       return

#     var inBuffer: array[1024, char]

#     defer: ipc.close()

#     let readHandle = open(ipcName, sideReader)
#     defer: readHandle.close()

#     while not self.closeRequested:
#       let c = await readHandle.readInto(cast[pointer](inBuffer[0].addr), inBuffer.len)
#       # todo: handle arbitrary message size
#       if c > 0:
#         let message = inBuffer[0..<c].join()
#         log lvlInfo, &"Run command from client: '{message}'"

#         try:
#           if message.startsWith("-r:") or message.startsWith("-R:"):
#             let (action, arg) = parseAction(message[3..^1])
#             # todo: send response
#             discard self.handleAction(action, arg, record=true)
#           elif message.startsWith("-p:"):
#             let setting = message[3..^1]
#             let i = setting.find("=")
#             if i == -1:
#               log lvlError, &"Invalid setting '{setting}', expected 'path.to.setting=value'"
#               continue

#             let path = setting[0..<i]
#             let value = setting[(i + 1)..^1].parseJson.catch:
#               log lvlError, &"Failed to parse value as json for '{setting}': {getCurrentExceptionMsg()}"
#               continue

#             log lvlInfo, &"Set {setting}"
#             self.setOption(path, value)
#           else:
#             discard self.openFile(message)

#         except:
#           log lvlError, &"Failed to run ipc command: {getCurrentExceptionMsg()}"

#   except:
#     log lvlError, &"Failed to open/read ipc messages: {getCurrentExceptionMsg()}"

proc applySettingsFromAppOptions(self: App) =
  log lvlInfo, &"Apply settings provided through command line"
  for setting in self.appOptions.settings:
    let i = setting.find("=")
    if i == -1:
      log lvlError, &"Invalid setting '{setting}', expected 'path.to.setting=value'"
      continue

    let path = setting[0..<i]
    let value = setting[(i + 1)..^1].parseJson.catch:
      log lvlError, &"Failed to parse value as json for '{setting}': {getCurrentExceptionMsg()}"
      continue

    log lvlInfo, &"Set {setting}"
    self.setOption(path, value)

proc runEarlyCommandsFromAppOptions(self: App) =
  log lvlInfo, &"Run early commands provided through command line"
  for command in self.appOptions.earlyCommands:
    let (action, args) = command.parseAction
    let res = self.handleAction(action, args, record=false)
    log lvlInfo, &"'{command}' -> {res}"

proc runLateCommandsFromAppOptions(self: App) =
  log lvlInfo, &"Run late commands provided through command line"
  for command in self.appOptions.lateCommands:
    let (action, args) = command.parseAction
    let res = self.handleAction(action, args, record=false)
    log lvlInfo, &"'{command}' -> {res}"

proc finishInitialization*(self: App, state: EditorState): Future[void]

proc newApp*(backend: api.Backend, platform: Platform, fs: Filesystem, services: Services, options = AppOptions()): Future[App] {.async.} =
  var self = App()

  {.gcsafe.}:
    gEditor = self
    gAppInterface = self.asAppInterface
    self.fs = fs
    self.platform = platform

    logger.addLogger AppLogger(app: self, fmtStr: "")

  log lvlInfo, fmt"Creating App with backend {backend} and options {options}"

  self.backend = backend
  self.statusBarOnTop = false
  self.appOptions = options
  self.services = services

  self.vfs = VFS()
  self.vfs.mount("", VFSNull())
  self.vfs.mount("plugs://", VFSNull())

  discard platform.onKeyPress.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleKeyPress(event.input, event.modifiers)
  discard platform.onKeyRelease.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleKeyRelease(event.input, event.modifiers)
  discard platform.onRune.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleRune(event.input, event.modifiers)
  discard platform.onDropFile.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleDropFile(event.path, event.content)
  discard platform.onCloseRequested.subscribe proc() {.gcsafe, raises: [].} = self.closeRequested = true

  self.timer = startTimer()
  self.frameTimer = startTimer()

  self.homeDir = getHomeDir().normalizePathUnix.catch:
    log lvlError, &"Failed to get home directory: {getCurrentExceptionMsg()}"
    ""

  self.layout = HorizontalLayout()
  self.layout_props = LayoutProperties(props: {"main-split": 0.5.float32}.toTable)

  self.registers = initTable[string, Register]()

  self.platform.fontSize = 16
  self.platform.lineDistance = 4

  self.fontRegular = "./fonts/DejaVuSansMono.ttf"
  self.fontBold = "./fonts/DejaVuSansMono-Bold.ttf"
  self.fontItalic = "./fonts/DejaVuSansMono-Oblique.ttf"
  self.fontBoldItalic = "./fonts/DejaVuSansMono-BoldOblique.ttf"
  self.fallbackFonts.add "fonts/Noto_Sans_Symbols_2/NotoSansSymbols2-Regular.ttf"
  self.fallbackFonts.add "fonts/NotoEmoji/NotoEmoji.otf"

  self.commandInfos = CommandInfos()

  self.editorDefaults.add TextDocumentEditor()
  when enableAst:
    self.editorDefaults.add ModelDocumentEditor()

  self.options = newJObject()

  self.setupDefaultKeybindings()

  await self.loadOptionsFromAppDir()
  await self.loadOptionsFromHomeDir()
  log lvlInfo, &"Finished loading app and user settings"

  self.applySettingsFromAppOptions()

  self.logDocument = newTextDocument(self.asConfigProvider, self.fs, "log", load=false, createLanguageServer=false)
  self.documents.add self.logDocument

  self.theme = defaultTheme()
  {.gcsafe.}:
    gTheme = self.theme

  self.currentView = 0

  self.gitIgnore = parseGlobs(self.fs.loadApplicationFile(".gitignore"))

  assignEventHandler(self.eventHandler, self.getEventHandlerConfig("editor")):
    onAction:
      if self.handleAction(action, arg, record=true).isSome:
        Handled
      else:
        Ignored
    onInput:
      Ignored

  assignEventHandler(self.commandLineEventHandlerHigh, self.getEventHandlerConfig("command-line-high")):
    onAction:
      if self.handleAction(action, arg, record=true).isSome:
        Handled
      else:
        Ignored
    onInput:
      Ignored

  assignEventHandler(self.commandLineEventHandlerLow, self.getEventHandlerConfig("command-line-low")):
    onAction:
      if self.handleAction(action, arg, record=true).isSome:
        Handled
      else:
        Ignored
    onInput:
      Ignored

  self.commandLineMode = false

  self.languageServerCommandLine = newLanguageServerCommandLine(self.asAppInterface, self.commandInfos)
  let commandLineTextDocument = newTextDocument(self.asConfigProvider, self.fs, language="command-line".some, languageServer=self.languageServerCommandLine.some)
  self.documents.add commandLineTextDocument
  self.commandLineTextEditor = newTextEditor(commandLineTextDocument, self.asAppInterface, self.fs, self.asConfigProvider)
  self.commandLineTextEditor.renderHeader = false
  self.getCommandLineTextEditor.usage = "command-line"
  self.getCommandLineTextEditor.disableScrolling = true
  self.getCommandLineTextEditor.lineNumbers = api.LineNumbers.None.some
  self.getCommandLineTextEditor.hideCursorWhenInactive = true
  discard self.commandLineTextEditor.onMarkedDirty.subscribe () => self.platform.requestRender()

  var state = EditorState()
  if not options.dontRestoreConfig:
    if options.sessionOverride.getSome(session):
      self.sessionFile = session
    elif options.fileToOpen.isSome:
      # Don't restore a session when opening a specific file.
      discard
    elif fileExists(defaultSessionName):
      self.sessionFile = defaultSessionName
    else:
      self.sessionFile = "app:" & defaultSessionName

    if self.sessionFile != "":
      self.restoreStateFromConfig(state)
    else:
      log lvlInfo, &"Don't restore session file."

  if self.sessionData.isNil:
    self.sessionData = newJObject()

  self.commandHistory = state.commandHistory

  let closeUnusedDocumentsTimerS = self.getOption("editor.close-unused-documents-timer", 10)
  self.closeUnusedDocumentsTask = startDelayed(closeUnusedDocumentsTimerS * 1000, repeat=true):
    self.closeUnusedDocuments()

  createDebugger(self.asAppInterface, state.debuggerState.get(newJObject()))

  self.runEarlyCommandsFromAppOptions()

  log lvlInfo, &"Finished creating app"

  asyncSpawn self.finishInitialization(state)

  return self

proc finishInitialization*(self: App, state: EditorState) {.async.} =

  self.runConfigCommands("startup-commands")

  # if self.getOption("command-server.port", Port.none).getSome(port):
  #   asyncSpawn self.listenForConnection(port)

  if self.getFlag("editor.restore-open-workspaces", true):
    for wf in state.workspaceFolders:
      var workspace: Workspace = nil
      case wf.kind
      of OpenWorkspaceKind.Local:
        workspace = newWorkspaceFolderLocal(wf.settings)

      workspace.id = wf.id.parseId
      workspace.name = wf.name
      if self.setWorkspaceFolder(workspace).await:
        log(lvlInfo, fmt"Restoring workspace {workspace.name} ({workspace.id})")

  # Open current working dir as local workspace if no workspace exists yet
  if self.workspace.isNil:
    log lvlInfo, "No workspace open yet, opening current working directory as local workspace"
    discard await self.setWorkspaceFolder newWorkspaceFolderLocal(".")

  when enableAst:
    if self.workspace.isNotNil:
      setProjectWorkspace(self.workspace)

  # Restore open editors
  if self.appOptions.fileToOpen.getSome(filePath):
    discard self.openFile(filePath)

  elif self.getFlag("editor.restore-open-editors", true):
    for editorState in state.openEditors:
      let view = self.createView(editorState)
      if view.isNil:
        continue

      self.addView(view, append=true)
      if editorState.customOptions.isNotNil and view of EditorView:
        view.EditorView.editor.restoreStateJson(editorState.customOptions)

    for editorState in state.hiddenEditors:
      let view = self.createView(editorState)
      if view.isNil:
        continue

      self.hiddenViews.add view
      if editorState.customOptions.isNotNil and view of EditorView:
        view.EditorView.editor.restoreStateJson(editorState.customOptions)

  if self.views.len == 0:
    if self.hiddenViews.len > 0:
      self.addView self.hiddenViews.pop
    else:
      self.help()

  asyncSpawn self.initScripting(self.appOptions)

  self.runLateCommandsFromAppOptions()

  log lvlInfo, &"Finished initializing app"

  # todo
  # asyncSpawn self.listenForIpc(0)
  # asyncSpawn self.listenForIpc(os.getCurrentProcessId())

proc saveAppState*(self: App)
proc printStatistics*(self: App)

proc shutdown*(self: App) =
  # Clear log document so we don't log to it as it will be destroyed.
  self.printStatistics()

  self.saveAppState()

  self.logDocument = nil

  for popup in self.popups:
    popup.deinit()

  let editors = collect(for e in self.editors.values: e)
  for editor in editors:
    editor.deinit()

  for document in self.documents:
    document.deinit()

  if self.wasmScriptContext.isNotNil:
    self.wasmScriptContext.deinit()

  self.languageServerCommandLine.stop()

  {.gcsafe.}:
    gAppInterface = nil
  self[] = AppObject()

  {.gcsafe.}:
    custom_treesitter.freeDynamicLibraries()

proc handleLog(self: App, level: Level, args: openArray[string]) =
  let str = substituteLog(defaultFmtStr, level, args) & "\n"
  if self.logDocument.isNotNil:
    for view in self.views:
      if view of EditorView and view.EditorView.document == self.logDocument:
        let editor = view.EditorView.editor.TextDocumentEditor
        editor.bScrollToEndOnInsert = true

    let selection = self.logDocument.TextDocument.lastCursor.toSelection
    discard self.logDocument.TextDocument.edit([selection], [selection], [self.logBuffer & str])
    self.logBuffer = ""

  else:
    self.logBuffer.add str

proc getEditor(): Option[App] =
  {.gcsafe.}:
    if gEditor.isNil: return App.none
    return gEditor.some

static:
  addInjector(App, getEditor)

proc reapplyConfigKeybindingsAsync(self: App, app: bool = false, home: bool = false, workspace: bool = false)
    {.async.} =
  log lvlInfo, &"reapplyConfigKeybindingsAsync app={app}, home={home}, workspace={workspace}"
  if app:
    await self.loadKeybindings("config", loadConfigFileFromAppDir)
  if home:
    await self.loadKeybindings(configDirName, loadConfigFileFromHomeDir)
  if workspace:
    await self.loadKeybindings(configDirName, loadConfigFileFromWorkspaceDir)

proc reapplyConfigKeybindings*(self: App, app: bool = false, home: bool = false, workspace: bool = false)
    {.expose("editor").} =
  asyncSpawn self.reapplyConfigKeybindingsAsync(app, home, workspace)

proc splitView*(self: App) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  if self.tryGetCurrentEditorView().getSome(view):
    discard self.createAndAddView(view.document, append = true)

proc runExternalCommand*(self: App, command: string, args: seq[string] = @[], workingDir: string = "") {.expose("editor").} =
  proc handleOutput(line: string) {.gcsafe.} =
    {.gcsafe.}:
      log lvlInfo, &"[{command}] {line}"
  proc handleError(line: string) {.gcsafe.} =
    {.gcsafe.}:
      log lvlError, &"[{command}] {line}"
  asyncSpawn runProcessAsyncCallback(command, args, workingDir, handleOutput, handleError)

proc disableLogFrameTime*(self: App, disable: bool) {.expose("editor").} =
  self.disableLogFrameTime = disable

proc enableDebugPrintAsyncAwaitStackTrace*(self: App, enable: bool) {.expose("editor").} =
  when defined(debugAsyncAwaitMacro):
    debugPrintAsyncAwaitStackTrace = enable

proc showDebuggerView*(self: App) {.expose("editor").} =
  for view in self.views:
    if view of DebuggerView:
      return

  for i, view in self.hiddenViews:
    if view of DebuggerView:
      self.hiddenViews.delete i
      self.addView(view, false)
      return

  self.addView(DebuggerView(), false)

proc setLocationListFromCurrentPopup*(self: App) {.expose("editor").} =
  if self.popups.len == 0:
    return

  let popup = self.popups[self.popups.high]
  if not (popup of SelectorPopup):
    log lvlError, &"Not a selector popup"
    return

  let selector = popup.SelectorPopup
  if selector.textEditor.isNil or selector.finder.isNil or selector.finder.filteredItems.isNone:
    return

  let list = selector.finder.filteredItems.get
  var items = newSeqOfCap[FinderItem](list.len)
  for i in 0..<list.len:
    items.add list[i]

  self.setLocationList(items, selector.previewer.clone())

proc getBackend*(self: App): Backend {.expose("editor").} =
  return self.backend

proc getHostOs*(self: App): string {.expose("editor").} =
  when defined(linux):
    return "linux"
  elif defined(windows):
    return "windows"
  else:
    return "unknown"

proc loadApplicationFile*(self: App, path: string): Option[string] {.expose("editor").} =
  ## Load a file from the application directory (path is relative to the executable)
  return self.fs.loadApplicationFile(path).some

proc toggleShowDrawnNodes*(self: App) {.expose("editor").} =
  self.platform.showDrawnNodes = not self.platform.showDrawnNodes

proc openDocument*(self: App, path: string, appFile = false, load = true): Option[Document] =

  try:
    log lvlInfo, &"Open new document '{path}'"
    let document: Document = when enableAst:
      if path.endsWith(".ast-model"):
        newModelDocument(path, app=appFile, workspaceFolder=self.workspace.some)
      else:
        newTextDocument(self.asConfigProvider, self.fs, path,
          app=appFile, workspaceFolder=self.workspace.some, load=load)
    else:
      newTextDocument(self.asConfigProvider, self.fs, path,
        app=appFile, workspaceFolder=self.workspace.some, load=load)

    log lvlInfo, &"Opened new document '{path}'"
    self.documents.add document
    return document.some

  except CatchableError:
    log(lvlError, fmt"[getOrOpenDocument] Failed to load file '{path}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())
    return Document.none

proc getDocument*(self: App, path: string, appFile = false): Option[Document] =
  for document in self.documents:
    if document.workspace == self.workspace.some and document.appFile == appFile and document.filename == path:
      return document.some

  return Document.none

proc getOrOpenDocument*(self: App, path: string, appFile = false, load = true): Option[Document] =
  result = self.getDocument(path, appFile)
  if result.isSome:
    return

  return self.openDocument(path, appFile, load)

# todo: change return type to Option[View]
proc createView(self: App, editorState: OpenEditor): View =
  let document = self.getOrOpenDocument(editorState.filename, editorState.appFile).getOr:
    log(lvlError, fmt"Failed to restore file {editorState.filename} from previous session")
    return

  return self.createView(document)

proc setMaxViews*(self: App, maxViews: int, openExisting: bool = false) {.expose("editor").} =
  ## Set the maximum number of views that can be open at the same time
  ## Closes any views that exceed the new limit

  log lvlInfo, fmt"[setMaxViews] {maxViews}"
  setOption[int](self, "editor.maxViews", maxViews)
  while maxViews > 0 and self.views.len > maxViews:
    self.views[self.views.high].deactivate()
    self.hiddenViews.add self.views.pop()

  while openExisting and self.views.len < maxViews and self.hiddenViews.len > 0:
    self.views.add self.hiddenViews.pop()

  self.currentView = self.currentView.clamp(0, self.views.high)

  self.updateActiveEditor(false)
  self.platform.requestRender()

proc openWorkspaceKind(workspaceFolder: Workspace): OpenWorkspaceKind =
  if workspaceFolder of WorkspaceFolderLocal:
    return OpenWorkspaceKind.Local
  assert false

proc saveAppState*(self: App) {.expose("editor").} =
  # Save some state
  var state = EditorState()
  state.theme = self.theme.path

  when enableAst:
    if gProjectWorkspace.isNotNil:
      state.astProjectWorkspaceId = $gProjectWorkspace.id
    if gProject.isNotNil:
      state.astProjectPath = gProject.path.some

  if self.backend == api.Backend.Terminal:
    state.fontSize = self.loadedFontSize
    state.lineDistance = self.loadedLineDistance
  else:
    state.fontSize = self.platform.fontSize
    state.lineDistance = self.platform.lineDistance

  state.fontRegular = self.fontRegular
  state.fontBold = self.fontBold
  state.fontItalic = self.fontItalic
  state.fontBoldItalic = self.fontBoldItalic
  state.fallbackFonts = self.fallbackFonts

  state.commandHistory = self.commandHistory
  state.sessionData = self.sessionData

  if getDebugger().getSome(debugger):
    state.debuggerState = debugger.getStateJson().some

  if self.layout of HorizontalLayout:
    state.layout = "horizontal"
  elif self.layout of VerticalLayout:
    state.layout = "vertical"
  else:
    state.layout = "fibonacci"

  # Save open workspace folders
  let kind = self.workspace.openWorkspaceKind()

  state.workspaceFolders.add OpenWorkspace(
    kind: kind,
    id: $self.workspace.id,
    name: self.workspace.name,
    settings: self.workspace.settings
  )

  # Save open editors
  proc getEditorState(view: EditorView): Option[OpenEditor] =
    if view.document.filename == "":
      return OpenEditor.none
    if view.document of TextDocument and view.document.TextDocument.staged:
      return OpenEditor.none
    if view.document == self.logDocument:
      return OpenEditor.none

    try:
      let customOptions = view.editor.getStateJson()
      if view.document of TextDocument:
        let document = TextDocument(view.document)
        return OpenEditor(
          filename: document.filename, languageId: document.languageId, appFile: document.appFile,
          workspaceId: document.workspace.map(wf => $wf.id).get(""),
          customOptions: customOptions ?? newJObject()
          ).some
      else:
        when enableAst:
          if view.document of ModelDocument:
            let document = ModelDocument(view.document)
            return OpenEditor(
              filename: document.filename, languageId: "am", appFile: document.appFile,
              workspaceId: document.workspace.map(wf => $wf.id).get(""),
              customOptions: customOptions ?? newJObject()
              ).some
    except CatchableError:
      log lvlError, fmt"Failed to get editor state for {view.document.filename}: {getCurrentExceptionMsg()}"
      return OpenEditor.none

  for view in self.views:
    if view of EditorView and view.EditorView.getEditorState().getSome(editorState):
      state.openEditors.add editorState

  for view in self.hiddenViews:
    if view of EditorView and view.EditorView.getEditorState().getSome(editorState):
      state.hiddenEditors.add editorState

  if self.sessionFile != "":
    try:
      let serialized = state.toJson
      let (isAppFile, path) = self.sessionFile.testApplicationPath()
      if isAppFile:
        self.fs.saveApplicationFile(path, serialized.pretty)
      else:
        self.fs.saveFile(path, serialized.pretty)
    except:
      discard

proc requestRender*(self: App, redrawEverything: bool = false) {.expose("editor").} =
  self.platform.requestRender(redrawEverything)

proc setHandleInputs*(self: App, context: string, value: bool) {.expose("editor").} =
  self.getEventHandlerConfig(context).setHandleInputs(value)

proc setHandleActions*(self: App, context: string, value: bool) {.expose("editor").} =
  self.getEventHandlerConfig(context).setHandleActions(value)

proc setConsumeAllActions*(self: App, context: string, value: bool) {.expose("editor").} =
  self.getEventHandlerConfig(context).setConsumeAllActions(value)

proc setConsumeAllInput*(self: App, context: string, value: bool) {.expose("editor").} =
  self.getEventHandlerConfig(context).setConsumeAllInput(value)

proc setWorkspaceFolder(self: App, workspace: Workspace): Future[bool] {.async.} =
  log(lvlInfo, fmt"Opening workspace {workspace.name}")

  if workspace.id == idNone():
    workspace.id = newId()

  self.workspace = workspace
  self.vfs.mount "", VFSWorkspace(workspace: workspace)

  self.services.getService(WorkspaceService).get.workspace = workspace

  {.gcsafe.}:
    if gWorkspace.isNil:
      setGlobalWorkspace(workspace)

  await self.loadOptionsFromWorkspace()

  return true

proc clearWorkspaceCaches*(self: App) {.expose("editor").} =
  self.workspace.clearDirectoryCache()

proc callScriptAction*(self: App, context: string, args: JsonNode): JsonNode {.expose("editor").} =
  if not self.scriptActions.contains(context):
    log lvlError, fmt"Unknown script action '{context}'"
    return nil
  let action = self.scriptActions[context]
  try:
    withScriptContext self, action.scriptContext:
      return action.scriptContext.handleScriptAction(context, args)
    log lvlError, fmt"No script context for action '{context}'"
    return nil
  except CatchableError:
    log(lvlError, fmt"Failed to run script action {context}: {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())
    return nil

proc addScriptAction*(self: App, name: string, docs: string = "",
    params: seq[tuple[name: string, typ: string]] = @[], returnType: string = "", active: bool = false,
    context: string = "script")
    {.expose("editor").} =

  if self.scriptActions.contains(name):
    log lvlError, fmt"Duplicate script action {name}"
    return

  if self.currentScriptContext.isNone:
    log lvlError, fmt"addScriptAction({name}) should only be called from a script"
    return

  self.scriptActions[name] = ScriptAction(name: name, scriptContext: self.currentScriptContext.get)

  proc dispatch(arg: JsonNode): JsonNode =
    return self.callScriptAction(name, arg)

  let signature = "(" & params.mapIt(it[0] & ": " & it[1]).join(", ") & ")" & returnType
  {.gcsafe.}:
    if active:
      extendActiveDispatchTable context, ExposedFunction(name: name, docs: docs, dispatch: dispatch, params: params, returnType: returnType, signature: signature)
    else:
      extendGlobalDispatchTable context, ExposedFunction(name: name, docs: docs, dispatch: dispatch, params: params, returnType: returnType, signature: signature)

proc invalidateCommandToKeysMap*(self: App) =
  self.commandInfos.invalidate()

proc rebuildCommandToKeysMap*(self: App) =
  self.commandInfos.rebuild(self.eventHandlerConfigs)

proc openLocalWorkspaceAsync(self: App, path: string) {.async.} =
  discard await self.setWorkspaceFolder newWorkspaceFolderLocal(path)

proc openLocalWorkspace*(self: App, path: string) {.expose("editor").} =
  let path = if path.isAbsolute: path else: path.absolutePath.catch().valueOr(path)
  asyncSpawn self.openLocalWorkspaceAsync(path)

proc getFlag*(self: App, flag: string, default: bool = false): bool {.expose("editor").} =
  return getOption[bool](self, flag, default)

proc setFlag*(self: App, flag: string, value: bool) {.expose("editor").} =
  setOption[bool](self, flag, value)

proc toggleFlag*(self: App, flag: string) {.expose("editor").} =
  let newValue = not self.getFlag(flag)
  log lvlInfo, fmt"toggleFlag '{flag}' -> {newValue}"
  self.setFlag(flag, newValue)
  self.platform.requestRender(true)

proc extendJson*(a: var JsonNode, b: JsonNode, extend: bool) =
  if not extend:
    a = b
    return

  func parse(action: string): (string, bool) =
    if action.startsWith("+"):
      (action[1..^1], true)
    else:
      (action, false)

  if (a.kind, b.kind) == (JObject, JObject):
    for (action, value) in b.fields.pairs:
      let (key, extend) = action.parse()
      if a.hasKey(key):
        a.fields[key].extendJson(value, extend)
      else:
        a[key] = value

  elif (a.kind, b.kind) == (JArray, JArray):
    for value in b.elems:
      a.elems.add value

  else:
    a = b

proc setOption*(self: App, option: string, value: JsonNode, override: bool = true) {.expose("editor").} =
  if self.isNil:
    return

  self.platform.requestRender(true)

  try:
    if option == "":
      if not override:
        self.options.extendJson(value, true)
      else:
        self.options = value
      self.onConfigChanged.invoke()
      return

    let pathItems = option.split(".")
    var node = self.options
    for key in pathItems[0..^2]:
      if node.kind != JObject:
        return
      if not node.contains(key):
        node[key] = newJObject()
      node = node[key]
    if node.isNil or node.kind != JObject:
      return

    let key = pathItems[^1]
    if not override and node.hasKey(key):
      node.fields[key].extendJson(value, true)
    else:
      node[key] = value

    self.onConfigChanged.invoke()
  except:
    discard

proc quit*(self: App) {.expose("editor").} =
  self.closeRequested = true

proc quitImmediately*(self: App, exitCode: int = 0) {.expose("editor").} =
  quit(exitCode)

proc help*(self: App, about: string = "") {.expose("editor").} =
  const introductionMd = staticRead"../docs/getting_started.md"
  let docsPath = "docs/getting_started.md"
  let textDocument = newTextDocument(self.asConfigProvider, self.fs, docsPath, introductionMd, app=true, load=true)
  self.documents.add textDocument
  textDocument.load()
  discard self.createAndAddView(textDocument)

proc loadWorkspaceFileImpl(self: App, path: string, callback: string) {.async.} =
  let content = await self.workspace.loadFile(path)

  discard self.callScriptAction(callback, content.some.toJson)

proc loadWorkspaceFile*(self: App, path: string, callback: string) {.expose("editor").} =
  asyncSpawn self.loadWorkspaceFileImpl(path, callback)

proc writeWorkspaceFile*(self: App, path: string, content: string) {.expose("editor").} =
  log lvlInfo, &"[writeWorkspaceFile] {path}"
  asyncSpawn self.workspace.saveFile(path, content)

proc changeFontSize*(self: App, amount: float32) {.expose("editor").} =
  self.platform.fontSize = self.platform.fontSize + amount.float
  log lvlInfo, fmt"current font size: {self.platform.fontSize}"
  self.platform.requestRender(true)

proc changeLineDistance*(self: App, amount: float32) {.expose("editor").} =
  self.platform.lineDistance = self.platform.lineDistance + amount.float
  log lvlInfo, fmt"current line distance: {self.platform.lineDistance}"
  self.platform.requestRender(true)

proc platformTotalLineHeight*(self: App): float32 {.expose("editor").} =
  return self.platform.totalLineHeight

proc platformLineHeight*(self: App): float32 {.expose("editor").} =
  return self.platform.lineHeight

proc platformLineDistance*(self: App): float32 {.expose("editor").} =
  return self.platform.lineDistance

proc changeLayoutProp*(self: App, prop: string, change: float32) {.expose("editor").} =
  self.layout_props.props.mgetOrPut(prop, 0) += change
  self.platform.requestRender(true)

proc toggleStatusBarLocation*(self: App) {.expose("editor").} =
  self.statusBarOnTop = not self.statusBarOnTop
  self.platform.requestRender(true)

proc logs*(self: App, scrollToBottom: bool = false) {.expose("editor").} =
  let editors = self.getEditorsForDocument(self.logDocument)
  let editor = if editors.len > 0:
    self.showEditor(editors[0].id)
    editors[0]
  else:
    self.createAndAddView(self.logDocument)

  if scrollToBottom and editor of TextDocumentEditor:
    let editor = editor.TextDocumentEditor
    editor.moveLast("file")
    editor.selection = editor.selection.last.toSelection

proc toggleConsoleLogger*(self: App) {.expose("editor").} =
  {.gcsafe.}:
    logger.toggleConsoleLogger()

proc getViewForEditor*(self: App, editor: DocumentEditor): Option[int] =
  ## Returns the index of the view for the given editor.
  for i, view in self.views:
    if view of EditorView and view.EditorView.editor == editor:
      return i.some

  return int.none

proc getHiddenViewForEditor*(self: App, editor: DocumentEditor): Option[int] =
  ## Returns the index of the hidden view for the given editor.
  for i, view in self.hiddenViews:
    if view of EditorView and view.EditorView.editor == editor:
      return i.some

  return int.none

proc getHiddenViewForEditor*(self: App, editorId: EditorId): Option[int] =
  ## Returns the index of the hidden view for the given editor.
  for i, view in self.hiddenViews:
    if view of EditorView and view.EditorView.editor.id == editorId:
      return i.some

  return int.none

proc showEditor*(self: App, editorId: EditorId, viewIndex: Option[int] = int.none) {.expose("editor").} =
  ## Make the given editor visible
  ## If viewIndex is none, the editor will be opened in the currentView,
  ## Otherwise the editor will be opened in the view with the given index.

  let editor = self.getEditorForId(editorId).getOr:
    log lvlError, &"No editor with id {editorId} exists"
    return

  assert editor.getDocument().isNotNil

  log lvlInfo, &"showEditor editorId={editorId}, viewIndex={viewIndex}, filename={editor.getDocument().filename}"

  for i, view in self.views:
    if view of EditorView and view.EditorView.editor == editor:
      self.currentView = i
      return

  let hiddenView = self.getHiddenViewForEditor(editor)
  let view: View = if hiddenView.getSome(index):
    let view = self.hiddenViews[index]
    self.hiddenViews.removeSwap(index)
    view
  else:
    EditorView(document: editor.getDocument(), editor: editor)

  if viewIndex.getSome(_):
    # todo
    log lvlError, &"Not implemented: showEditor({editorId}, {viewIndex})"
  else:
    let oldView = self.views[self.currentView]
    oldView.deactivate()
    self.hiddenViews.add oldView

    self.views[self.currentView] = view
    view.activate()

proc getVisibleEditors*(self: App): seq[EditorId] {.expose("editor").} =
  ## Returns a list of all editors which are currently shown
  for view in self.views:
    if view of EditorView:
      result.add view.EditorView.editor.id

proc getHiddenEditors*(self: App): seq[EditorId] {.expose("editor").} =
  ## Returns a list of all editors which are currently hidden
  for view in self.hiddenViews:
    if view of EditorView:
      result.add view.EditorView.editor.id

proc getExistingEditor*(self: App, path: string): Option[EditorId] {.expose("editor").} =
  ## Returns an existing editor for the given file if one exists,
  ## or none otherwise.
  defer:
    log lvlInfo, &"getExistingEditor {path} -> {result}"

  if path.len == 0:
    return EditorId.none

  for id, editor in self.editors.pairs:
    if editor.getDocument() == nil:
      continue
    if editor.getDocument().filename != path:
      continue
    return id.some

  return EditorId.none

proc getOrOpenEditor*(self: App, path: string): Option[EditorId] {.expose("editor").} =
  ## Returns an existing editor for the given file if one exists,
  ## otherwise a new editor is created for the file.
  ## The returned editor will not be shown automatically.
  defer:
    log lvlInfo, &"getOrOpenEditor {path} -> {result}"

  if path.len == 0:
    return EditorId.none

  if self.getExistingEditor(path).getSome(id):
    return id.some

  let path = self.workspace.getAbsolutePath(path)
  let document = self.openDocument(path).getOr:
    return EditorId.none

  let editor = self.createEditorForDocument document
  return editor.id.some

proc closeEditor*(self: App, editor: DocumentEditor, removeFromViews: bool = true) =
  let document = editor.getDocument()
  log lvlInfo, fmt"closeEditor: '{editor.getDocument().filename}'"

  editor.deinit()

  if removeFromViews:
    for i, view in self.hiddenViews:
      if view of EditorView and view.EditorView.editor == editor:
        self.hiddenViews.removeShift(i)
        break

    for i, view in self.views:
      if view of EditorView and view.EditorView.editor == editor:
        self.views.removeShift(i)
        break

  if document == self.logDocument:
    return

  var hasAnotherEditor = false
  for id, editor in self.editors.pairs:
    if editor.getDocument() == document:
      hasAnotherEditor = true
      break

  if not hasAnotherEditor:
    log lvlInfo, fmt"Document has no other editors, closing it."
    document.deinit()
    self.documents.del(document)

proc closeView*(self: App, index: int, keepHidden: bool = true, restoreHidden: bool = true) {.expose("editor").} =
  ## Closes the current view. If `keepHidden` is true the view is not closed but hidden instead.
  let view = self.views[index]
  self.views.delete index

  if restoreHidden and self.hiddenViews.len > 0:
    let viewToRestore = self.hiddenViews.pop
    self.views.insert(viewToRestore, index)

  if self.views.len == 0:
    if self.hiddenViews.len > 0:
      let view = self.hiddenViews.pop
      self.addView view
    else:
      self.help()

  if keepHidden:
    self.hiddenViews.add view
  else:
    if view of EditorView:
      self.closeEditor(view.EditorView.editor)

  self.platform.requestRender()

proc closeCurrentView*(self: App, keepHidden: bool = true, restoreHidden: bool = true) {.expose("editor").} =
  self.closeView(self.currentView, keepHidden, restoreHidden)
  self.currentView = self.currentView.clamp(0, self.views.len - 1)

proc closeOtherViews*(self: App, keepHidden: bool = true) {.expose("editor").} =
  ## Closes all views except for the current one. If `keepHidden` is true the views are not closed but hidden instead.

  let view = self.views[self.currentView]

  for i, view in self.views:
    if i != self.currentView:
      if keepHidden:
        self.hiddenViews.add view
      else:
        if view of EditorView:
          self.closeEditor(view.EditorView.editor, removeFromViews = false)

  self.views.setLen 1
  self.views[0] = view
  self.currentView = 0
  self.platform.requestRender()

proc getEditorsForDocument(self: App, document: Document): seq[DocumentEditor] =
  for id, editor in self.editors.pairs:
    if editor.getDocument() == document:
      result.add editor

proc closeUnusedDocuments*(self: App) =
  let documents = self.documents
  for document in documents:
    if document == self.logDocument:
      continue

    let editors = self.getEditorsForDocument(document)
    if editors.len > 0:
      continue

    discard self.tryCloseDocument(document, true)

    # Only close one document on each iteration so we don't create spikes
    break

proc tryCloseDocument*(self: App, document: Document, force: bool): bool =
  if document == self.logDocument:
    return false

  logScope lvlInfo, &"tryCloseDocument: '{document.filename}', force: {force}"

  let editorsToClose = self.getEditorsForDocument(document)

  if editorsToClose.len > 0 and not force:
    log lvlInfo, &"Don't close document because there are still {editorsToClose.len} editors using it"
    return false

  for editor in editorsToClose:
    log lvlInfo, &"Force close editor for '{document.filename}'"
    if self.getViewForEditor(editor).getSome(index):
      self.closeView(index, keepHidden = false, restoreHidden = true)
    elif self.getHiddenViewForEditor(editor).getSome(index):
      self.hiddenViews.removeShift(index)
    else:
      editor.deinit()

  self.documents.del(document)

  document.deinit()

  return true

proc getServices*(self: App): Services =
  self.services

proc getService*(self: App, name: string): Option[Service] =
  self.services.getService(name)

proc addService*(self: App, name: string, service: Service) =
  self.services.addService(name, service)

proc moveCurrentViewToTop*(self: App) {.expose("editor").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    self.views.delete(self.currentView)
    self.views.insert(view, 0)
  self.currentView = 0
  self.platform.requestRender()

proc nextView*(self: App) {.expose("editor").} =
  self.currentView = if self.views.len == 0: 0 else: (self.currentView + 1) mod self.views.len
  self.platform.requestRender()

proc prevView*(self: App) {.expose("editor").} =
  self.currentView = if self.views.len == 0: 0 else: (self.currentView + self.views.len - 1) mod self.views.len
  self.platform.requestRender()

proc toggleMaximizeView*(self: App) {.expose("editor").} =
  self.maximizeView = not self.maximizeView
  self.platform.requestRender()

proc moveCurrentViewPrev*(self: App) {.expose("editor").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    let index = (self.currentView + self.views.len - 1) mod self.views.len
    self.views.delete(self.currentView)
    self.views.insert(view, index)
    self.currentView = index
  self.platform.requestRender()

proc moveCurrentViewNext*(self: App) {.expose("editor").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    let index = (self.currentView + 1) mod self.views.len
    self.views.delete(self.currentView)
    self.views.insert(view, index)
    self.currentView = index
  self.platform.requestRender()

proc setLayout*(self: App, layout: string) {.expose("editor").} =
  self.layout = case layout
    of "horizontal": HorizontalLayout()
    of "vertical": VerticalLayout()
    of "fibonacci": FibonacciLayout()
    else: FibonacciLayout()
  self.platform.requestRender()

proc commandLine*(self: App, initialValue: string = "") {.expose("editor").} =
  self.getCommandLineTextEditor.document.content = initialValue
  if self.commandHistory.len == 0:
    self.commandHistory.add ""
  self.commandHistory[0] = ""
  self.currentHistoryEntry = 0
  self.commandLineMode = true
  self.getCommandLineTextEditor.setMode("insert")
  self.rebuildCommandToKeysMap()
  self.platform.requestRender()

proc exitCommandLine*(self: App) {.expose("editor").} =
  self.getCommandLineTextEditor.document.content = ""
  self.getCommandLineTextEditor.hideCompletions()
  self.commandLineMode = false
  self.platform.requestRender()

proc selectPreviousCommandInHistory*(self: App) {.expose("editor").} =
  if self.commandHistory.len == 0:
    self.commandHistory.add ""

  let command = self.getCommandLineTextEditor.document.contentString
  if command != self.commandHistory[self.currentHistoryEntry]:
    self.currentHistoryEntry = 0
    self.commandHistory[0] = command

  self.currentHistoryEntry += 1
  if self.currentHistoryEntry >= self.commandHistory.len:
    self.currentHistoryEntry = 0

  self.getCommandLineTextEditor.document.content = self.commandHistory[self.currentHistoryEntry]
  self.getCommandLineTextEditor.moveLast("file", Both)
  self.platform.requestRender()

proc selectNextCommandInHistory*(self: App) {.expose("editor").} =
  if self.commandHistory.len == 0:
    self.commandHistory.add ""

  let command = self.getCommandLineTextEditor.document.contentString
  if command != self.commandHistory[self.currentHistoryEntry]:
    self.currentHistoryEntry = 0
    self.commandHistory[0] = command

  self.currentHistoryEntry -= 1
  if self.currentHistoryEntry < 0:
    self.currentHistoryEntry = self.commandHistory.high

  self.getCommandLineTextEditor.document.content = self.commandHistory[self.currentHistoryEntry]
  self.getCommandLineTextEditor.moveLast("file", Both)
  self.platform.requestRender()

proc executeCommandLine*(self: App): bool {.expose("editor").} =
  defer:
    self.platform.requestRender()
  self.commandLineMode = false
  let command = self.getCommandLineTextEditor.document.contentString.replace("\n", "")

  if (let i = self.commandHistory.find(command); i >= 0):
    self.commandHistory.delete i

  if self.commandHistory.len == 0:
    self.commandHistory.add ""

  self.commandHistory.insert command, 1

  let maxHistorySize = self.getOption("editor.command-line.history-size", 100)
  if self.commandHistory.len > maxHistorySize:
    self.commandHistory.setLen maxHistorySize

  var (action, arg) = command.parseAction
  self.getCommandLineTextEditor.document.content = ""

  if arg.startsWith("\\"):
    arg = $newJString(arg[1..^1])

  return self.handleAction(action, arg, record=true).isSome

proc writeFile*(self: App, path: string = "", appFile: bool = false) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  if self.getActiveEditor().getSome(editor) and editor.getDocument().isNotNil:
    try:
      editor.getDocument().save(path, appFile)
    except CatchableError:
      log(lvlError, fmt"Failed to write file '{path}': {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())

proc loadFile*(self: App, path: string = "") {.expose("editor").} =
  defer:
    self.platform.requestRender()

  if self.getActiveEditor().getSome(editor) and editor.getDocument().isNotNil:
    try:
      editor.getDocument().load(path)
      editor.handleDocumentChanged()
    except CatchableError:
      log(lvlError, fmt"Failed to load file '{path}': {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())

proc loadWorkspaceFile*(self: App, path: string) =
  if self.tryGetCurrentEditorView().getSome(view) and view.document.isNotNil:
    defer:
      self.platform.requestRender()
    try:
      view.document.workspace = self.workspace.some
      view.document.load(path)
      view.editor.handleDocumentChanged()
    except CatchableError:
      log(lvlError, fmt"Failed to load file '{path}': {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())

proc tryOpenExisting*(self: App, path: string, appFile: bool = false, append: bool = false): Option[DocumentEditor] =
  for i, view in self.views:
    if view of EditorView and view.EditorView.document.filename == path and
        (view.EditorView.document.workspace == self.workspace.some or
        view.EditorView.document.appFile == appFile):
      log(lvlInfo, fmt"Reusing open editor in view {i}")
      self.currentView = i
      return view.EditorView.editor.some

  for i, view in self.hiddenViews:
    if view of EditorView and view.EditorView.document.filename == path and
        (view.EditorView.document.workspace == self.workspace.some or
        view.EditorView.document.appFile == appFile):
      log(lvlInfo, fmt"Reusing hidden view")
      self.hiddenViews.delete i
      self.addView(view, append=append)
      return view.EditorView.editor.some

  return DocumentEditor.none

proc tryOpenExisting*(self: App, editor: EditorId, addToHistory = true): Option[DocumentEditor] =
  for i, view in self.views:
    if view of EditorView and view.EditorView.editor.id == editor:
      log(lvlInfo, fmt"Reusing open editor in view {i}")
      `currentView=`(self, i, addToHistory)
      return view.EditorView.editor.some

  for i, view in self.hiddenViews:
    if view of EditorView and view.EditorView.editor.id == editor:
      log(lvlInfo, fmt"Reusing hidden view")
      self.hiddenViews.delete i
      self.addView(view, addToHistory)
      return view.EditorView.editor.some

  return DocumentEditor.none

proc openFile*(self: App, path: string, appFile: bool = false): Option[DocumentEditor] =
  defer:
    self.platform.requestRender()

  log lvlInfo, fmt"[openFile] Open file '{path}' (appFile = {appFile})"
  if self.tryOpenExisting(path, appFile, append = false).getSome(ed):
    log lvlInfo, fmt"[openFile] found existing editor"
    return ed.some

  log lvlInfo, fmt"Open file '{path}'"

  let document = self.getOrOpenDocument(path, appFile=appFile).getOr:
    log(lvlError, fmt"Failed to load file {path}")
    return DocumentEditor.none

  return self.createAndAddView(document).some

proc openWorkspaceFile*(self: App, path: string, append: bool = false): Option[DocumentEditor] =
  defer:
    self.platform.requestRender()

  let path = self.workspace.getAbsolutePath(path)

  log lvlInfo, fmt"[openWorkspaceFile] Open file '{path}' in workspace {self.workspace.name} ({self.workspace.id})"
  if self.tryOpenExisting(path, append = append).getSome(editor):
    log lvlInfo, fmt"[openWorkspaceFile] found existing editor"
    return editor.some

  let document = self.getOrOpenDocument(path).getOr:
    log(lvlError, fmt"Failed to load file {path}")
    return DocumentEditor.none

  return self.createAndAddView(document, append = append).some

proc loadTheme*(self: App, name: string) {.expose("editor").} =
  self.setTheme(fmt"themes/{name}.json")

proc chooseTheme*(self: App) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  let originalTheme = self.theme.path

  proc getItems(): seq[FinderItem] {.gcsafe, raises: [].} =
    var items = newSeq[FinderItem]()
    let themesDir = self.fs.getApplicationFilePath("./themes")
    try:
      for file in walkDirRec(themesDir, relative=true):
        if file.endsWith ".json":
          let (relativeDirectory, name, _) = file.splitFile
          items.add FinderItem(
            displayName: name,
            data: fmt"{themesDir}/{file}",
            detail: "themes" / relativeDirectory,
          )
    except:
      discard

    return items

  let source = newSyncDataSource(getItems)
  var finder = newFinder(source, filterAndSort=true)
  finder.filterThreshold = float.low

  var popup = newSelectorPopup(self.asAppInterface, self.fs, "theme".some, finder.some)
  popup.scale.x = 0.35

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    if theme.loadFromFile(self.fs, item.data).getSome(theme):
      self.theme = theme
      {.gcsafe.}:
        gTheme = theme
      self.platform.requestRender(true)

      return true

  popup.handleItemSelected = proc(item: FinderItem) =
    if theme.loadFromFile(self.fs, item.data).getSome(theme):
      self.theme = theme
      {.gcsafe.}:
        gTheme = theme
      self.platform.requestRender(true)

  popup.handleCanceled = proc() =
    if theme.loadFromFile(self.fs, originalTheme).getSome(theme):
      self.theme = theme
      {.gcsafe.}:
        gTheme = theme
      self.platform.requestRender(true)

  self.pushPopup popup

proc createFile*(self: App, path: string) {.expose("editor").} =
  let fullPath = if path.isAbsolute:
    path.normalizePathUnix
  else:
    path.absolutePath.catch().valueOr(path).normalizePathUnix

  log lvlInfo, fmt"createFile: '{path}'"

  let document = self.openDocument(fullPath, load=false).getOr:
    log(lvlError, fmt"Failed to create file {path}")
    return

  discard self.createAndAddView(document)

proc pushSelectorPopup*(self: App, builder: SelectorPopupBuilder): ISelectorPopup =
  var popup = newSelectorPopup(self.asAppInterface, self.fs, builder.scope, builder.finder, builder.previewer.toDisposableRef)
  popup.scale.x = builder.scaleX
  popup.scale.y = builder.scaleY
  popup.previewScale = builder.previewScale
  popup.sizeToContentY = builder.sizeToContentY
  popup.previewVisible = builder.previewVisible
  popup.maxDisplayNameWidth = builder.maxDisplayNameWidth
  popup.maxColumnWidth = builder.maxColumnWidth

  if builder.handleItemSelected.isNotNil:
    popup.handleItemSelected = proc(item: FinderItem) =
      builder.handleItemSelected(popup.asISelectorPopup, item)

  if builder.handleItemConfirmed.isNotNil:
    popup.handleItemConfirmed = proc(item: FinderItem): bool =
      return builder.handleItemConfirmed(popup.asISelectorPopup, item)

  if builder.handleCanceled.isNotNil:
    popup.handleCanceled = proc() =
      builder.handleCanceled(popup.asISelectorPopup)

  for command, handler in builder.customActions.pairs:
    capture handler:
      popup.addCustomCommand command, proc(popup: SelectorPopup, args: JsonNode): bool =
        return handler(popup.asISelectorPopup, args)

  self.pushPopup popup

type
  WorkspaceFilesDataSource* = ref object of DataSource
    workspace: Workspace
    onWorkspaceFileCacheUpdatedHandle: Option[Id]

proc newWorkspaceFilesDataSource(workspace: Workspace): WorkspaceFilesDataSource =
  new result
  result.workspace = workspace

proc handleCachedFilesUpdated(self: WorkspaceFilesDataSource) =
  var list = newItemList(self.workspace.cachedFiles.len)

  for i in 0..self.workspace.cachedFiles.high:
    let path = self.workspace.cachedFiles[i]
    let relPath = self.workspace.getRelativePathSync(path).get(path)
    let (dir, name) = relPath.splitPath
    list[i] = FinderItem(
      displayName: name,
      detail: dir,
      data: path,
    )

  self.onItemsChanged.invoke list

method close*(self: WorkspaceFilesDataSource) =
  if self.onWorkspaceFileCacheUpdatedHandle.getSome(handle):
    self.workspace.onCachedFilesUpdated.unsubscribe(handle)
  self.onWorkspaceFileCacheUpdatedHandle = Id.none

method setQuery*(self: WorkspaceFilesDataSource, query: string) =
  if self.onWorkspaceFileCacheUpdatedHandle.isSome:
    return

  self.handleCachedFilesUpdated()
  self.workspace.recomputeFileCache()

  self.onWorkspaceFileCacheUpdatedHandle = some(self.workspace.onCachedFilesUpdated.subscribe () => self.handleCachedFilesUpdated())

proc createVfs*(self: App, config: JsonNode): Option[VFS] =
  result = VFS.none
  if config.kind != JObject:
    log lvlError, &"Invalid config, expected object, got {config}"
    return

  let typ = config.fields.getOrDefault("type", newJNull()).getStr.catch:
    log lvlError, &"Invalid config, expected string property 'type', got {config}"
    return

  template expect(value: untyped, msg: untyped, got: untyped): untyped =
    try:
      value
    except:
      log lvlError, "Invalid config, expected " & msg & ", got " & got
      return

  case typ
  of "link":
    let targetName = config.fields.getOrDefault("target", newJNull()).getStr.expect("string 'target'", $config)
    let (target, sub) = self.vfs.getVFS(targetName)
    if sub != "":
      log lvlError, &"Unknown target '{targetName}', unmatched: '{sub}'"
      return VFS.none

    let targetPrefix = config.fields.getOrDefault("targetPrefix", newJString("")).getStr.expect("string 'targetPrefix'", $config)

    log lvlInfo, &"create VFSLink {target.name}, {target.prefix}, {targetPrefix}"
    result = VFSLink(
      target: target,
      targetPrefix: targetPrefix,
    ).VFS.some

  else:
    log lvlError, &"Invalid VFS config, unknown type '{typ}'"
    return VFS.none

proc mountVfs*(self: App, parentPath: string, prefix: string, config: JsonNode) {.expose("editor").} =
  log lvlInfo, &"Mount VFS '{parentPath}', '{prefix}', {config}"
  let (vfs, _) = self.vfs.getVFS(parentPath)
  if self.createVfs(config).getSome(newVFS):
    vfs.mount(prefix, newVFS)

proc browseKeybinds*(self: App, preview: bool = true, scaleX: float = 0.9, scaleY: float = 0.8, previewScale: float = 0.4) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  proc getItems(): seq[FinderItem] {.gcsafe, raises: [].} =
    var items = newSeq[FinderItem]()
    for (context, c) in self.eventHandlerConfigs.pairs:
      if not c.commands.contains(""):
        continue
      for (keys, commandInfo) in c.commands[""].pairs:
        var name = commandInfo.command

        let key = context & keys
        self.commandDescriptions.withValue(key, val):
          name = val[]

        items.add(FinderItem(
          displayName: name,
          filterText: commandInfo.command & " |" & keys,
          detail: keys & "\t" & context & "\t" & commandInfo.command & "\t" & commandInfo.source.filename,
          data: $ %*{
            "path": commandInfo.source.filename,
            "line": commandInfo.source.line - 1,
            "column": commandInfo.source.column - 1,
          },
        ))

    return items

  let previewer = if preview:
    newWorkspaceFilePreviewer(self.workspace, self.vfs, self.fs, self.asConfigProvider, reuseExistingDocuments = false).Previewer.toDisposableRef.some
  else:
    DisposableRef[Previewer].none

  let source = newSyncDataSource(getItems)
  let finder = newFinder(source, filterAndSort=true)
  var popup = newSelectorPopup(self.asAppInterface, self.fs, "file".some, finder.some, previewer)
  popup.scale.x = scaleX
  popup.scale.y = scaleY
  popup.previewScale = previewScale

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let (path, location, _) = item.parsePathAndLocationFromItemData().getOr:
      log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
        fmt"Expected path or json object with path property {item}"
      return

    var targetSelection = location.mapIt(it.toSelection)
    if popup.getPreviewSelection().getSome(selection):
      targetSelection = selection.some

    let pathNorm = self.vfs.normalize(path)

    let editor = self.openWorkspaceFile(pathNorm)
    if editor.getSome(editor) and editor of TextDocumentEditor and targetSelection.isSome:
      editor.TextDocumentEditor.targetSelection = targetSelection.get
      editor.TextDocumentEditor.centerCursor()
    return true

  self.pushPopup popup

proc chooseFile*(self: App, preview: bool = true, scaleX: float = 0.8, scaleY: float = 0.8, previewScale: float = 0.5) {.expose("editor").} =
  ## Opens a file dialog which shows all files in the currently open workspaces
  ## Press <ENTER> to select a file
  ## Press <ESCAPE> to close the dialogue

  defer:
    self.platform.requestRender()

  let workspace = self.workspace

  let previewer = if preview:
    newWorkspaceFilePreviewer(workspace, self.fs, self.asConfigProvider).Previewer.toDisposableRef.some
  else:
    DisposableRef[Previewer].none

  let finder = newFinder(newWorkspaceFilesDataSource(workspace), filterAndSort=true)
  var popup = newSelectorPopup(self.asAppInterface, self.fs, "file".some, finder.some, previewer)
  popup.scale.x = scaleX
  popup.scale.y = scaleY
  popup.previewScale = previewScale

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    discard self.openWorkspaceFile(item.data)
    return true

  self.pushPopup popup

proc openLastEditor*(self: App) {.expose("editor").} =
  if self.hiddenViews.len > 0:
    let view = self.hiddenViews.pop()
    self.addView(view, addToHistory=false, append=false)

proc chooseOpen*(self: App, preview: bool = true, scaleX: float = 0.8, scaleY: float = 0.8, previewScale: float = 0.6) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  proc getItems(): seq[FinderItem] {.gcsafe, raises: [].} =
    var items = newSeq[FinderItem]()
    let allViews = self.views & self.hiddenViews
    for i in countdown(allViews.high, 0):
      let view = allViews[i]
      if not (view of EditorView):
        continue

      let document = view.EditorView.editor.getDocument
      let path = view.EditorView.document.filename
      let isDirty = view.EditorView.document.lastSavedRevision != view.EditorView.document.revision
      let dirtyMarker = if isDirty: "*" else: " "
      let activeMarker = if i == self.currentView:
        "#"
      elif i < self.views.len:
        "👁"
      else:
        " "

      let (directory, name) = path.splitPath
      var relativeDirectory = directory
      var data = path
      if document.workspace.getSome(workspace):
        relativeDirectory = workspace.getRelativePathSync(directory).get(directory)
        data = workspace.encodePath(path).string

      if relativeDirectory == ".":
        relativeDirectory = ""

      items.add FinderItem(
        displayName: activeMarker & dirtyMarker & name,
        filterText: name,
        data: $view.EditorView.editor.id,
        detail: relativeDirectory,
      )

    return items

  let source = newSyncDataSource(getItems)
  var finder = newFinder(source, filterAndSort=true)
  finder.filterThreshold = float.low

  let previewer = if preview:
    newOpenEditorPreviewer(self.asConfigProvider).Previewer.toDisposableRef.some
  else:
    DisposableRef[Previewer].none

  var popup = newSelectorPopup(self.asAppInterface, self.fs, "open".some, finder.some, previewer)
  popup.scale.x = scaleX
  popup.scale.y = scaleY
  popup.previewScale = previewScale

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let editorId = item.data.parseInt.EditorId.catch:
      log lvlError, fmt"Failed to parse editor id from data '{item}'"
      return true

    discard self.tryOpenExisting(editorId)
    return true

  popup.addCustomCommand "close-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    let item = popup.getSelectedItem().getOr:
      return true

    let editorId = item.data.parseInt.EditorId.catch:
      log lvlError, fmt"Failed to parse editor id from data '{item}'"
      return true

    if self.getEditorForId(editorId).getSome(editor):
      self.closeEditor(editor)

    source.retrigger()
    return true

  self.pushPopup popup

proc chooseOpenDocument*(self: App) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  proc getItems(): seq[FinderItem] {.gcsafe, raises: [].} =
    var items = newSeq[FinderItem]()
    for document in self.documents:
      if document == self.logDocument or document == self.commandLineTextEditor.getDocument():
        continue

      let path = document.filename
      let isDirty = document.lastSavedRevision != document.revision
      let dirtyMarker = if isDirty: "*" else: " "

      let (directory, name) = path.splitPath
      var relativeDirectory = directory
      var data = path
      if document.workspace.getSome(workspace):
        relativeDirectory = workspace.getRelativePathSync(directory).get(directory)
        data = workspace.encodePath(path).string

      if relativeDirectory == ".":
        relativeDirectory = ""

      let infoText = if document.appFile:
        "app"
      elif document.workspace.isSome:
        "workspace"
      else:
        "unknown"

      items.add FinderItem(
        displayName: dirtyMarker & name,
        filterText: name,
        data: data,
        detail: &"{relativeDirectory}\t{infoText}",
      )

    return items

  let source = newSyncDataSource(getItems)
  var finder = newFinder(source, filterAndSort=true)
  finder.filterThreshold = float.low

  var popup = newSelectorPopup(self.asAppInterface, self.fs, "open".some, finder.some)
  popup.scale.x = 0.35

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    if item.data.WorkspacePath.decodePath().getSome(path):
      if self.getDocument(path.path).getSome(document):
        discard self.createAndAddView(document)
    else:
      if self.getDocument(item.data).getSome(document):
        discard self.createAndAddView(document)
      else:
        log lvlError, fmt"Failed to open location {item}"

    return true

  popup.addCustomCommand "close-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    if popup.getSelectedItem().getSome(item):
      if item.data.WorkspacePath.decodePath().getSome(path):
        if self.getDocument(path.path).getSome(document):
          discard self.tryCloseDocument(document, force=true)
          source.retrigger()
      else:
        if self.getDocument(item.data).getSome(document):
          discard self.tryCloseDocument(document, force=true)
          source.retrigger()

    return true

  self.pushPopup popup

proc gotoNextLocation*(self: App) {.expose("editor").} =
  if self.finderItems.len == 0:
    return

  self.currentLocationListIndex = (self.currentLocationListIndex + 1) mod self.finderItems.len
  let item = self.finderItems[self.currentLocationListIndex]

  let (path, location, _) = item.parsePathAndLocationFromItemData().getOr:
    log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
      fmt"Expected path or json object with path property {item}"
    return

  log lvlInfo, &"[gotoNextLocation] Found {path}:{location}"

  let editor = self.openWorkspaceFile(path)
  if editor.getSome(editor) and editor of TextDocumentEditor and location.isSome:
    editor.TextDocumentEditor.targetSelection = location.get.toSelection
    editor.TextDocumentEditor.centerCursor()

proc gotoPrevLocation*(self: App) {.expose("editor").} =
  if self.finderItems.len == 0:
    return

  self.currentLocationListIndex = (self.currentLocationListIndex - 1 + self.finderItems.len) mod self.finderItems.len
  let item = self.finderItems[self.currentLocationListIndex]

  let (path, location, _) = item.parsePathAndLocationFromItemData().getOr:
    log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
      fmt"Expected path or json object with path property {item}"
    return

  log lvlInfo, &"[gotoPrevLocation] Found {path}:{location}"

  let editor = self.openWorkspaceFile(path)
  if editor.getSome(editor) and editor of TextDocumentEditor and location.isSome:
    editor.TextDocumentEditor.targetSelection = location.get.toSelection
    editor.TextDocumentEditor.centerCursor()

proc chooseLocation*(self: App) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  proc getItems(): seq[FinderItem] {.gcsafe, raises: [].} =
    return self.finderItems

  let source = newSyncDataSource(getItems)
  var finder = newFinder(source, filterAndSort=true)

  var popup = newSelectorPopup(self.asAppInterface, self.fs, "open".some, finder.some, self.previewer.clone())

  popup.scale.x = if self.previewer.isSome: 0.8 else: 0.4

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let (path, location, _) = item.parsePathAndLocationFromItemData().getOr:
      log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
        fmt"Expected path or json object with path property {item}"
      return

    var targetSelection = location.mapIt(it.toSelection)
    if popup.getPreviewSelection().getSome(selection):
      targetSelection = selection.some

    let editor = self.openWorkspaceFile(path)
    if editor.getSome(editor) and editor of TextDocumentEditor and targetSelection.isSome:
      editor.TextDocumentEditor.targetSelection = targetSelection.get
      editor.TextDocumentEditor.centerCursor()

    return true

  self.pushPopup popup

proc searchWorkspaceItemList(workspace: Workspace, query: string, maxResults: int): Future[ItemList] {.async.} =
  let searchResults = workspace.searchWorkspace(query, maxResults).await
  log lvlInfo, fmt"Found {searchResults.len} results"

  var list = newItemList(searchResults.len)
  for i, info in searchResults:
    var relativePath = workspace.getRelativePathSync(info.path).get(info.path)
    if relativePath == ".":
      relativePath = ""

    list[i] = FinderItem(
      displayName: info.text,
      data: $ %*{
        "path": info.path,
        "line": info.line - 1,
        "column": info.column,
      },
      detail: fmt"{relativePath}:{info.line}"
    )

  return list

type
  WorkspaceSearchDataSource* = ref object of DataSource
    workspace: Workspace
    query: string
    delayedTask: DelayedTask
    minQueryLen: int = 2
    maxResults: int = 1000

proc getWorkspaceSearchResults(self: WorkspaceSearchDataSource): Future[void] {.async.} =
  if self.query.len < self.minQueryLen:
    return

  let t = startTimer()
  let list = self.workspace.searchWorkspaceItemList(self.query, self.maxResults).await
  debugf"[searchWorkspace] {t.elapsed.ms}ms"
  self.onItemsChanged.invoke list

proc newWorkspaceSearchDataSource(workspace: Workspace, maxResults: int): WorkspaceSearchDataSource =
  new result
  result.workspace = workspace
  result.maxResults = maxResults

method close*(self: WorkspaceSearchDataSource) =
  self.delayedTask.deinit()
  self.delayedTask = nil

method setQuery*(self: WorkspaceSearchDataSource, query: string) =
  self.query = query

  if self.delayedTask.isNil:
    self.delayedTask = startDelayed(500, repeat=false):
      asyncSpawn self.getWorkspaceSearchResults()
  else:
    self.delayedTask.reschedule()

proc searchGlobalInteractive*(self: App) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  let workspace = self.workspace

  let maxResults = getOption[int](self, "editor.max-search-results", 1000)
  let source = newWorkspaceSearchDataSource(workspace, maxResults)
  var finder = newFinder(source, filterAndSort=true)

  var popup = newSelectorPopup(self.asAppInterface, self.fs, "search".some, finder.some,
    newWorkspaceFilePreviewer(workspace, self.fs, self.asConfigProvider).Previewer.toDisposableRef.some)
  popup.scale.x = 0.85
  popup.scale.y = 0.85

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let (path, location, _) = item.parsePathAndLocationFromItemData().getOr:
      log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
        fmt"Expected path or json object with path property {item}"
      return

    var targetSelection = location.mapIt(it.toSelection)
    if popup.getPreviewSelection().getSome(selection):
      targetSelection = selection.some

    let editor = self.openWorkspaceFile(path)
    if editor.getSome(editor) and editor of TextDocumentEditor and targetSelection.isSome:
      editor.TextDocumentEditor.targetSelection = targetSelection.get
      editor.TextDocumentEditor.centerCursor()
    return true

  self.pushPopup popup

proc searchGlobal*(self: App, query: string) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  let workspace = self.workspace

  let maxResults = getOption[int](self, "editor.max-search-results", 1000)
  let source = newAsyncCallbackDataSource () => workspace.searchWorkspaceItemList(query, maxResults)
  var finder = newFinder(source, filterAndSort=true)

  var popup = newSelectorPopup(self.asAppInterface, self.fs, "search".some, finder.some,
    newWorkspaceFilePreviewer(workspace, self.fs, self.asConfigProvider).Previewer.toDisposableRef.some)
  popup.scale.x = 0.85
  popup.scale.y = 0.85

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let (path, location, _) = item.parsePathAndLocationFromItemData().getOr:
      log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
        fmt"Expected path or json object with path property {item}"
      return

    var targetSelection = location.mapIt(it.toSelection)
    if popup.getPreviewSelection().getSome(selection):
      targetSelection = selection.some

    let editor = self.openWorkspaceFile(path)
    if editor.getSome(editor) and editor of TextDocumentEditor and targetSelection.isSome:
      editor.TextDocumentEditor.targetSelection = targetSelection.get
      editor.TextDocumentEditor.centerCursor()
    return true

  self.pushPopup popup

proc getChangedFilesFromGitAsync(workspace: Workspace, all: bool): Future[ItemList] {.async.} =
  let vcsList = workspace.getAllVersionControlSystems()
  var items = newSeq[FinderItem]()

  for vcs in vcsList:
    let fileInfos = await vcs.getChangedFiles()

    for info in fileInfos:
      let (directory, name) = info.path.splitPath
      var relativeDirectory = workspace.getRelativePathSync(directory).get(directory)

      if relativeDirectory == ".":
        relativeDirectory = ""

      if info.stagedStatus != None and info.stagedStatus != Untracked:
        var info1 = info
        info1.unstagedStatus = None

        var info2 = info
        info2.stagedStatus = None

        items.add FinderItem(
          displayName: $info1.stagedStatus & $info1.unstagedStatus & " " & name,
          data: $ %info1,
          detail: relativeDirectory & "\t" & vcs.root,
        )
        items.add FinderItem(
          displayName: $info2.stagedStatus & $info2.unstagedStatus & " " & name,
          data: $ %info2,
          detail: relativeDirectory & "\t" & vcs.root,
        )
      else:
        items.add FinderItem(
          displayName: $info.stagedStatus & $info.unstagedStatus & " " & name,
          data: $ %info,
          detail: relativeDirectory & "\t" & vcs.root,
        )

    if not all:
      break

  return newItemList(items)

proc stageSelectedFileAsync(popup: SelectorPopup, workspace: Workspace,
    source: AsyncCallbackDataSource): Future[void] {.async.} =

  log lvlInfo, fmt"Stage selected entry ({popup.selected})"

  let item = popup.getSelectedItem().getOr:
    return

  let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
    log lvlError, fmt"Failed to parse file info from item: {item}"
    return
  debugf"staged selected {fileInfo}"

  if workspace.getVcsForFile(fileInfo.path).getSome(vcs):
    let res = await vcs.stageFile(fileInfo.path)
    debugf"add finished: {res}"
    if popup.textEditor.isNil:
      return

    source.retrigger()

proc unstageSelectedFileAsync(popup: SelectorPopup, workspace: Workspace,
    source: AsyncCallbackDataSource): Future[void] {.async.} =

  log lvlInfo, fmt"Unstage selected entry ({popup.selected})"

  let item = popup.getSelectedItem().getOr:
    return

  let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
    log lvlError, fmt"Failed to parse file info from item: {item}"
    return
  debugf"unstaged selected {fileInfo}"

  if workspace.getVcsForFile(fileInfo.path).getSome(vcs):
    let res = await vcs.unstageFile(fileInfo.path)
    debugf"unstage finished: {res}"
    if popup.textEditor.isNil:
      return

    source.retrigger()

proc revertSelectedFileAsync(popup: SelectorPopup, workspace: Workspace,
    source: AsyncCallbackDataSource): Future[void] {.async.} =

  log lvlInfo, fmt"Revert selected entry ({popup.selected})"

  let item = popup.getSelectedItem().getOr:
    return

  let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
    log lvlError, fmt"Failed to parse file info from item: {item}"
    return
  debugf"revert-selected {fileInfo}"

  if workspace.getVcsForFile(fileInfo.path).getSome(vcs):
    let res = await vcs.revertFile(fileInfo.path)
    debugf"revert finished: {res}"
    if popup.textEditor.isNil:
      return

    source.retrigger()

proc diffStagedFileAsync(self: App, workspace: Workspace, path: string): Future[void] {.async.} =
  log lvlInfo, fmt"Diff staged '({path})'"

  let stagedDocument = newTextDocument(self.asConfigProvider, self.fs, path, load = false,
    workspaceFolder = workspace.some, createLanguageServer = false)
  stagedDocument.staged = true
  stagedDocument.readOnly = true

  let editor = self.createAndAddView(stagedDocument).TextDocumentEditor
  editor.updateDiff()

proc installTreesitterParserAsync*(self: App, language: string, host: string) {.async.} =
  try:
    let (language, repo) = if (let i = language.find("/"); i != -1):
      let first = i + 1
      let k = language.find("/", first)
      let last = if k == -1:
        language.len
      else:
        k

      (language[first..<last].replace("tree-sitter-", "").replace("-", "_"), language)
    else:
      (language, self.getOption(&"languages.{language}.treesitter", ""))

    let queriesSubDir = self.getOption(&"languages.{language}.treesitter-queries", "").catch("")

    log lvlInfo, &"Install treesitter parser for {language} from {repo}"
    let parts = repo.split("/")
    if parts.len < 2:
      log lvlError, &"Invalid value for languages.{language}.treesitter: '{repo}'. Expected 'user/repo'"
      return

    let languagesRoot = self.fs.getApplicationFilePath("languages")
    let userName = parts[0]
    let repoName = parts[1]
    let subFolder = parts[2..^1].join("/")
    let repoPath = languagesRoot // repoName
    let grammarPath = repoPath // subFolder
    let queryDir = languagesRoot // language // "queries"
    let url = &"https://{host}/{userName}/{repoName}"

    if not dirExists(repoPath):
      log lvlInfo, &"[installTreesitterParser] clone repository {url}"
      let (output, err) = await runProcessAsyncOutput("git", @["clone", url], workingDir=languagesRoot)
      log lvlInfo, &"git clone {url}:\nstdout:{output.indent(1)}\nstderr:\n{err.indent(1)}\nend"

    else:
      log lvlInfo, &"[installTreesitterParser] Update repository {url}"
      let (output, err) = await runProcessAsyncOutput("git", @["pull"], workingDir=repoPath)
      log lvlInfo, &"git pull:\nstdout:{output.indent(1)}\nstderr:\n{err.indent(1)}\nend"

    block:
      log lvlInfo, &"Copy highlight queries"

      let queryDirs = if queriesSubDir != "":
        @[repoPath // queriesSubDir]
      else:
        let highlightQueries = await self.fs.findFile(repoPath, r"highlights.scm$")
        highlightQueries.mapIt(it.splitPath.head)

      for path in queryDirs:
        let list = await self.fs.getApplicationDirectoryListing(path)
        for f in list.files:
          if f.endsWith(".scm"):
            let fileName = f.splitPath.tail
            log lvlInfo, &"Copy '{f}' to '{queryDir}'"
            discard await self.fs.copyFile(f, queryDir // fileName)

    block:
      let (output, err) = await runProcessAsyncOutput("tree-sitter", @["build", "--wasm", grammarPath],
        workingDir=languagesRoot)
      log lvlInfo, &"tree-sitter build --wasm {repoPath}:\nstdout:{output.indent(1)}\nstderr:\n{err.indent(1)}\nend"

  except:
    log lvlError, &"Failed to install treesitter parser for {language}: {getCurrentExceptionMsg()}"

proc installTreesitterParser*(self: App, language: string, host: string = "github.com") {.
    expose("editor").} =

  ## Install a treesitter parser by downloading the repository and building a wasm module.
  ## `language` can either be a language id (`nim`, `cpp`, `markdown`, etc), `<username>/<repository>`
  ## or `<username>/<repository>/<some/path>`.
  ##
  ## todo: copy queries to `languages/<language>/queries`
  ##
  ## If you specify a language id then the repository name will be read from the setting
  ## `languages.<language>.treesitter`
  ##
  ## The repository will be cloned in `<installdir>/languages/<repository>`.
  ##
  ## ## Requirements:
  ## - `git`
  ## - `tree-sitter-cli` (`npm install tree-sitter-cli` or `cargo install tree-sitter-cli`)
  ## All required programs need to be in `PATH`.
  ##
  ## ## Example:
  ## - Assuming `languages.cpp.treesitter` is set to "tree-sitter/tree-sitter-cpp"
  ## - `install-treesitter-parser "cpp"` will clone/pull the repository
  ##   `https://github.com/tree-sitter/tree-sitter-cpp` and then build the parser
  ## - `install-treesitter-parser "tree-sitter/tree-sitter-ocaml/grammars/ocaml"` will clone/pull
  ##   the repository `https://github.com/tree-sitter/tree-sitter-ocaml` and then build the parser from
  ##   the directory `<installdir>/languages/tree-sitter-ocaml/grammars/ocaml`

  asyncSpawn self.installTreesitterParserAsync(language, host)

proc chooseGitActiveFiles*(self: App, all: bool = false) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  let workspace = self.workspace

  let source = newAsyncCallbackDataSource () =>
    workspace.getChangedFilesFromGitAsync(all)
  var finder = newFinder(source, filterAndSort=true)

  let previewer = newWorkspaceFilePreviewer(workspace, self.fs, self.asConfigProvider,
    openNewDocuments=true)

  var popup = newSelectorPopup(self.asAppInterface, self.fs, "git".some, finder.some,
    previewer.Previewer.toDisposableRef.some)

  popup.scale.x = 1
  popup.scale.y = 0.9
  popup.previewScale = 0.75

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
      log lvlError, fmt"Failed to parse git file info from item: {item}"
      return true

    if fileInfo.stagedStatus != None:
      asyncSpawn self.diffStagedFileAsync(workspace, fileInfo.path)

    else:
      let currentVersionEditor = self.openWorkspaceFile(fileInfo.path)
      if currentVersionEditor.getSome(editor):
        if editor of TextDocumentEditor:
          editor.TextDocumentEditor.updateDiff()
          if popup.getPreviewSelection().getSome(selection):
            editor.TextDocumentEditor.selection = selection
            editor.TextDocumentEditor.centerCursor()

    return true

  popup.addCustomCommand "stage-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    asyncSpawn popup.stageSelectedFileAsync(workspace, source)
    return true

  popup.addCustomCommand "unstage-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    asyncSpawn popup.unstageSelectedFileAsync(workspace, source)
    return true

  popup.addCustomCommand "revert-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    asyncSpawn popup.revertSelectedFileAsync(workspace, source)
    return true

  popup.addCustomCommand "diff-staged", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    let item = popup.getSelectedItem().getOr:
      return

    let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
      log lvlError, fmt"Failed to parse get file info from item: {item}"
      return true
    debugf"diff-staged {fileInfo}"

    asyncSpawn self.diffStagedFileAsync(workspace, fileInfo.path)
    return true

  self.pushPopup popup

proc getItemsFromDirectory(workspace: Workspace, directory: string): Future[ItemList] {.async.} =

  let listing = await workspace.getDirectoryListing(directory)

  var list = newItemList(listing.files.len + listing.folders.len)

  # todo: use unicode icons on all targets once rendering is fixed
  const fileIcon = "🗎 "
  const folderIcon = "🗀"

  var i = 0
  proc addItem(path: string, isFile: bool) =
    let (directory, name) = path.splitPath
    var relativeDirectory = workspace.getRelativePathSync(directory).get(directory)

    if relativeDirectory == ".":
      relativeDirectory = ""

    let icon = if isFile: fileIcon else: folderIcon
    list[i] = FinderItem(
      displayName: icon & " " & name,
      filterText: name,
      data: $ %*{
        "path": path,
        "isFile": isFile,
      },
      detail: path,
    )
    inc i

  for file in listing.files:
    addItem(file, true)

  for dir in listing.folders:
    addItem(dir, false)

  return list

proc exploreFiles*(self: App, root: string = "") {.expose("editor").} =
  defer:
    self.platform.requestRender()

  let workspace = self.workspace

  let currentDirectory = new string
  currentDirectory[] = root

  let source = newAsyncCallbackDataSource () => workspace.getItemsFromDirectory(currentDirectory[])
  var finder = newFinder(source, filterAndSort=true)
  finder.filterThreshold = float.low

  var popup = newSelectorPopup(self.asAppInterface, self.fs, "file-explorer".some, finder.some,
    newWorkspaceFilePreviewer(workspace, self.fs, self.asConfigProvider).Previewer.toDisposableRef.some)
  popup.scale.x = 0.85
  popup.scale.y = 0.85

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let fileInfo = item.data.parseJson.jsonTo(tuple[path: string, isFile: bool]).catch:
      log lvlError, fmt"Failed to parse file info from item: {item}"
      return true

    if fileInfo.isFile:
      if self.openWorkspaceFile(fileInfo.path).getSome(editor):
        if editor of TextDocumentEditor and popup.getPreviewSelection().getSome(selection):
          editor.TextDocumentEditor.selection = selection
          editor.TextDocumentEditor.centerCursor()
      return true
    else:
      currentDirectory[] = fileInfo.path
      popup.textEditor.document.content = ""
      source.retrigger()
      return false

  popup.addCustomCommand "go-up", proc(popup: SelectorPopup, args: JsonNode): bool =
    let parent = currentDirectory[].parentDir
    log lvlInfo, fmt"go up: {currentDirectory[]} -> {parent}"
    currentDirectory[] = parent

    popup.textEditor.document.content = ""
    source.retrigger()
    return true

  self.pushPopup popup

proc exploreUserConfigDir*(self: App) {.expose("editor").} =
  if self.homeDir.len == 0:
    log lvlInfo, &"No home directory"
    return

  self.exploreFiles(self.homeDir // configDirName)

proc exploreAppConfigDir*(self: App) {.expose("editor").} =
  self.exploreFiles(self.fs.getApplicationFilePath("config"))

proc exploreHelp*(self: App) {.expose("editor").} =
  self.exploreFiles(self.fs.getApplicationFilePath("docs"))

proc exploreWorkspacePrimary*(self: App) {.expose("editor").} =
  self.exploreFiles(self.workspace.getWorkspacePath())

proc exploreCurrentFileDirectory*(self: App) {.expose("editor").} =
  if self.tryGetCurrentEditorView().getSome(view) and view.document.isNotNil:
    self.exploreFiles(view.document.filename.splitPath.head)

proc openPreviousEditor*(self: App) {.expose("editor").} =
  if self.editorHistory.len == 0:
    return

  let editor = self.editorHistory.popLast

  if self.tryGetCurrentEditorView().getSome(view):
    self.editorHistory.addFirst view.editor.id

  discard self.tryOpenExisting(editor, addToHistory=false)
  self.platform.requestRender()

proc openNextEditor*(self: App) {.expose("editor").} =
  if self.editorHistory.len == 0:
    return

  let editor = self.editorHistory.popFirst

  if self.tryGetCurrentEditorView().getSome(view):
    self.editorHistory.addLast view.editor.id

  discard self.tryOpenExisting(editor, addToHistory=false)
  self.platform.requestRender()

proc setGithubAccessToken*(self: App, token: string) {.expose("editor").} =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  self.fs.saveApplicationFile("GithubAccessToken", token)

proc clearScriptActionsFor(self: App, scriptContext: ScriptContext) =
  var keysToRemove: seq[string]
  for (key, value) in self.scriptActions.pairs:
    if value.scriptContext == scriptContext:
      keysToRemove.add key

  for key in keysToRemove:
    self.scriptActions.del key

proc reloadPluginAsync*(self: App) {.async.} =
  if self.wasmScriptContext.isNotNil:
    log lvlInfo, "Reload wasm plugins"
    try:
      self.clearScriptActionsFor(self.wasmScriptContext)

      let t1 = startTimer()
      withScriptContext self, self.wasmScriptContext:
        await self.wasmScriptContext.reload()
      log(lvlInfo, fmt"Reload wasm plugins ({t1.elapsed.ms}ms)")

      withScriptContext self, self.wasmScriptContext:
        let t2 = startTimer()
        discard self.wasmScriptContext.postInitialize()
        log(lvlInfo, fmt"Post init wasm plugins ({t2.elapsed.ms}ms)")

      log lvlInfo, &"Successfully reloaded wasm plugins"
    except CatchableError:
      log lvlError, &"Failed to reload wasm plugins: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc reloadConfigAsync*(self: App) {.async.} =
  await self.loadOptionsFromAppDir()
  await self.loadOptionsFromHomeDir()
  await self.loadOptionsFromWorkspace()

proc reloadConfig*(self: App, clearOptions: bool = false) {.expose("editor").} =
  ## Reloads settings.json and keybindings.json from the app directory, home directory and workspace
  log lvlInfo, &"Reload config"
  if clearOptions:
    self.options = newJObject()
  asyncSpawn self.reloadConfigAsync()

proc reloadPlugin*(self: App) {.expose("editor").} =
  log lvlInfo, &"Reload current plugin"
  asyncSpawn self.reloadPluginAsync()

proc reloadState*(self: App) {.expose("editor").} =
  ## Reloads some of the state stored in the session file (default: config/config.json)
  var state = EditorState()
  if self.sessionFile != "":
    self.restoreStateFromConfig(state)
  self.requestRender()

proc saveSession*(self: App, sessionFile: string = "") {.expose("editor").} =
  ## Reloads some of the state stored in the session file (default: config/config.json)
  let sessionFile = if sessionFile == "": defaultSessionName else: sessionFile
  self.sessionFile = sessionFile
  self.saveAppState()
  self.requestRender()

proc logOptions*(self: App) {.expose("editor").} =
  log(lvlInfo, self.options.pretty)

proc dumpKeymapGraphViz*(self: App, context: string = "") {.expose("editor").} =
  for handler in self.currentEventHandlers():
    if context == "" or handler.config.context == context:
      self.fs.saveApplicationFile(handler.config.context & ".dot", handler.dfa.dumpGraphViz)

proc clearCommands*(self: App, context: string) {.expose("editor").} =
  log(lvlInfo, fmt"Clearing keybindings for {context}")
  self.getEventHandlerConfig(context).clearCommands()
  self.invalidateCommandToKeysMap()

proc getAllEditors*(self: App): seq[EditorId] {.expose("editor").} =
  for id in self.editors.keys:
    result.add id

proc getModeConfig(self: App, mode: string): EventHandlerConfig =
  return self.getEventHandlerConfig("editor." & mode)

proc setMode*(self: App, mode: string) {.expose("editor").} =
  defer:
    self.platform.requestRender()
  if mode.len == 0:
    self.modeEventHandler = nil
  else:
    let config = self.getModeConfig(mode)
    assignEventHandler(self.modeEventHandler, config):
      onAction:
        if self.handleAction(action, arg, record=true).isSome:
          Handled
        else:
          Ignored
      onInput:
        Ignored

  self.currentMode = mode

proc mode*(self: App): string {.expose("editor").} =
  return self.currentMode

proc getContextWithMode(self: App, context: string): string {.expose("editor").} =
  return context & "." & $self.currentMode

proc currentEventHandlers*(self: App): seq[EventHandler] =
  result = @[self.eventHandler]

  let modeOnTop = getOption[bool](self, self.getContextWithMode("editor.custom-mode-on-top"), true)
  if not self.modeEventHandler.isNil and not modeOnTop:
    result.add self.modeEventHandler

  if self.commandLineMode:
    result.add self.getCommandLineTextEditor.getEventHandlers({"above-mode": self.commandLineEventHandlerLow}.toTable)
    result.add self.commandLineEventHandlerHigh
  elif self.popups.len > 0:
    result.add self.popups[self.popups.high].getEventHandlers()
  elif self.tryGetCurrentView().getSome(view):
      result.add view.getEventHandlers(initTable[string, EventHandler]())

  if not self.modeEventHandler.isNil and modeOnTop:
    result.add self.modeEventHandler

proc clearInputHistoryDelayed*(self: App) =
  let clearInputHistoryDelay = getOption[int](self, "editor.clear-input-history-delay", 3000)
  if self.clearInputHistoryTask.isNil:
    self.clearInputHistoryTask = startDelayed(clearInputHistoryDelay, repeat=false):
      self.inputHistory.setLen 0
      self.platform.requestRender()
  else:
    self.clearInputHistoryTask.interval = clearInputHistoryDelay
    self.clearInputHistoryTask.reschedule()

proc recordInputToHistory*(self: App, input: string) =
  let recordInput = getOption[bool](self, "editor.record-input-history", true)
  if not recordInput:
    return

  self.inputHistory.add input
  const maxLen = 50
  if self.inputHistory.len > maxLen:
    self.inputHistory = self.inputHistory[(self.inputHistory.len - maxLen)..^1]

proc handleKeyPress*(self: App, input: int64, modifiers: Modifiers) =
  # logScope lvlDebug, &"handleKeyPress {inputToString(input, modifiers)}"
  self.logNextFrameTime = true

  for register in self.recordingKeys:
    if not self.registers.contains(register) or self.registers[register].kind != RegisterKind.Text:
      self.registers[register] = Register(kind: RegisterKind.Text, text: "")
    self.registers[register].text.add inputToString(input, modifiers)

  try:
    case self.currentEventHandlers.handleEvent(input, modifiers)
    of Progress:
      self.recordInputToHistory(inputToString(input, modifiers))
      self.platform.preventDefault()
      self.platform.requestRender()
    of Failed, Canceled, Handled:
      self.recordInputToHistory(inputToString(input, modifiers) & " ")
      self.clearInputHistoryDelayed()
      self.platform.preventDefault()
      self.platform.requestRender()
    of Ignored:
      discard
  except:
    discard

proc handleKeyRelease*(self: App, input: int64, modifiers: Modifiers) =
  discard

proc handleRune*(self: App, input: int64, modifiers: Modifiers) =
  # debugf"handleRune {inputToString(input, modifiers)}"
  self.logNextFrameTime = true

  try:
    let modifiers = if input.isAscii and input.char.isAlphaNumeric: modifiers else: {}
    case self.currentEventHandlers.handleEvent(input, modifiers):
    of Progress:
      self.recordInputToHistory(inputToString(input, modifiers))
      self.platform.preventDefault()
      self.platform.requestRender()
    of Failed, Canceled, Handled:
      self.recordInputToHistory(inputToString(input, modifiers) & " ")
      self.clearInputHistoryDelayed()
      self.platform.preventDefault()
      self.platform.requestRender()
    of Ignored:
      discard
      self.platform.preventDefault()
  except:
    discard

proc handleDropFile*(self: App, path, content: string) =
  let document = newTextDocument(self.asConfigProvider, self.fs, path, content)
  self.documents.add document
  discard self.createAndAddView(document)

proc scriptRunAction*(action: string, arg: string) {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return
    discard gEditor.handleAction(action, arg, record=false)

proc scriptLog*(message: string) {.expose("editor").} =
  logNoCategory lvlInfo, fmt"[script] {message}"

proc changeAnimationSpeed*(self: App, factor: float) {.expose("editor").} =
  self.platform.builder.animationSpeedModifier *= factor
  log lvlInfo, fmt"{self.platform.builder.animationSpeedModifier}"

proc setLeader*(self: App, leader: string) {.expose("editor").} =
  self.leaders = @[leader]
  for config in self.eventHandlerConfigs.values:
    config.setLeaders self.leaders

proc setLeaders*(self: App, leaders: seq[string]) {.expose("editor").} =
  self.leaders = leaders
  for config in self.eventHandlerConfigs.values:
    config.setLeaders self.leaders

proc addLeader*(self: App, leader: string) {.expose("editor").} =
  self.leaders.add leader
  for config in self.eventHandlerConfigs.values:
    config.setLeaders self.leaders

proc registerPluginSourceCode*(self: App, path: string, content: string) {.expose("editor").} =
  if self.currentScriptContext.getSome(scriptContext):
    asyncSpawn self.vfs.write(scriptContext.getCurrentContext() & path, content)

proc addCommandScript*(self: App, context: string, subContext: string, keys: string, action: string, arg: string = "", description: string = "", source: tuple[filename: string, line: int, column: int] = ("", 0, 0)) {.expose("editor").} =
  let command = if arg.len == 0: action else: action & " " & arg
  # log(lvlInfo, fmt"Adding command to '{context}': ('{subContext}', '{keys}', '{command}')")

  let (context, subContext) = if (let i = context.find('#'); i != -1):
    (context[0..<i], context[i+1..^1] & subContext)
  else:
    (context, subContext)

  if description.len > 0:
    self.commandDescriptions[context & subContext & keys] = description

  var source = source
  if self.currentScriptContext.getSome(scriptContext):
    source.filename = scriptContext.getCurrentContext() & source.filename

  self.getEventHandlerConfig(context).addCommand(subContext, keys, command, source)
  self.invalidateCommandToKeysMap()

proc removeCommand*(self: App, context: string, keys: string) {.expose("editor").} =
  # log(lvlInfo, fmt"Removing command from '{context}': '{keys}'")
  self.getEventHandlerConfig(context).removeCommand(keys)
  self.invalidateCommandToKeysMap()

proc getActivePopup*(): EditorId {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return EditorId(-1)
    if gEditor.popups.len > 0:
      return gEditor.popups[gEditor.popups.high].id

  return EditorId(-1)

proc getActiveEditor*(): EditorId {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return EditorId(-1)
    if gEditor.commandLineMode:
      return gEditor.commandLineTextEditor.id

    if gEditor.popups.len > 0 and gEditor.popups[gEditor.popups.high].getActiveEditor().getSome(editor):
      return editor.id

    if gEditor.tryGetCurrentView().getSome(view) and view.getActiveEditor().getSome(editor):
      return editor.id

  return EditorId(-1)

proc getActiveEditor*(self: App): Option[DocumentEditor] =
  if self.commandLineMode:
    return self.commandLineTextEditor.some

  if self.popups.len > 0 and self.popups[self.popups.high].getActiveEditor().getSome(editor):
    return editor.some

  if self.tryGetCurrentEditorView().getSome(view):
    return view.editor.some

  return DocumentEditor.none

proc logRootNode*(self: App) {.expose("editor").} =
  let str = self.platform.builder.root.dump(true)
  debug "logRootNode: ", str

proc getEditorInView*(index: int): EditorId {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return EditorId(-1)
    if index >= 0 and index < gEditor.views.len and gEditor.views[index] of EditorView:
      return gEditor.views[index].EditorView.editor.id

  return EditorId(-1)

proc scriptIsSelectorPopup*(editorId: EditorId): bool {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return false
    if gEditor.getPopupForId(editorId).getSome(popup):
      return popup of SelectorPopup
  return false

proc scriptIsTextEditor*(editorId: EditorId): bool {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return false
    if gEditor.getEditorForId(editorId).getSome(editor):
      return editor of TextDocumentEditor
  return false

proc scriptIsAstEditor*(editorId: EditorId): bool {.expose("editor").} =
  return false

proc scriptIsModelEditor*(editorId: EditorId): bool {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return false
    when enableAst:
      if gEditor.getEditorForId(editorId).getSome(editor):
        return editor of ModelDocumentEditor
  return false

proc scriptRunActionFor*(editorId: EditorId, action: string, arg: string) {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return
    defer:
      gEditor.platform.requestRender()
    if gEditor.getEditorForId(editorId).getSome(editor):
      discard editor.handleAction(action, arg, record=false)
    elif gEditor.getPopupForId(editorId).getSome(popup):
      discard popup.eventHandler.handleAction(action, arg)

proc scriptInsertTextInto*(editorId: EditorId, text: string) {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return
    defer:
      gEditor.platform.requestRender()
    if gEditor.getEditorForId(editorId).getSome(editor):
      discard editor.eventHandler.handleInput(text)

proc scriptTextEditorSelection*(editorId: EditorId): Selection {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return ((0, 0), (0, 0))
    defer:
      gEditor.platform.requestRender()
    if gEditor.getEditorForId(editorId).getSome(editor):
      if editor of TextDocumentEditor:
        let editor = TextDocumentEditor(editor)
        return editor.selection
    return ((0, 0), (0, 0))

proc scriptSetTextEditorSelection*(editorId: EditorId, selection: Selection) {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return
    defer:
      gEditor.platform.requestRender()
    if gEditor.getEditorForId(editorId).getSome(editor):
      if editor of TextDocumentEditor:
        editor.TextDocumentEditor.selection = selection

proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return @[((0, 0), (0, 0))]
    if gEditor.getEditorForId(editorId).getSome(editor):
      if editor of TextDocumentEditor:
        let editor = TextDocumentEditor(editor)
        return editor.selections
    return @[((0, 0), (0, 0))]

proc scriptSetTextEditorSelections*(editorId: EditorId, selections: seq[Selection]) {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return
    defer:
      gEditor.platform.requestRender()
    if gEditor.getEditorForId(editorId).getSome(editor):
      if editor of TextDocumentEditor:
        editor.TextDocumentEditor.selections = selections

proc scriptGetTextEditorLine*(editorId: EditorId, line: int): string {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return ""
    if gEditor.getEditorForId(editorId).getSome(editor):
      if editor of TextDocumentEditor:
        let editor = TextDocumentEditor(editor)
        if line >= 0 and line < editor.document.numLines:
          return $editor.document.getLine(line)
    return ""

proc scriptGetTextEditorLineCount*(editorId: EditorId): int {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return 0
    if gEditor.getEditorForId(editorId).getSome(editor):
      if editor of TextDocumentEditor:
        let editor = TextDocumentEditor(editor)
        return editor.document.numLines
    return 0

template createScriptGetOption(path, default, accessor: untyped): untyped =
  block:
    {.gcsafe.}:
      if gEditor.isNil:
        return default
      let node = gEditor.options{path.split(".")}
      if node.isNil:
        return default
      accessor(node, default)

template createScriptSetOption(path, value: untyped): untyped =
  block:
    {.gcsafe.}:
      if gEditor.isNil:
        return
      defer:
        gEditor.platform.requestRender()
      let pathItems = path.split(".")
      var node = gEditor.options
      for key in pathItems[0..^2]:
        if node.kind != JObject:
          return
        if not node.contains(key):
          node[key] = newJObject()
        node = node[key]
      if node.isNil or node.kind != JObject:
        return
      node[pathItems[^1]] = value
      gEditor.onConfigChanged.invoke()

proc setSessionDataJson*(self: App, path: string, value: JsonNode, override: bool = true) {.expose("editor").} =
  if self.isNil or path.len == 0:
    return

  try:
    let pathItems = path.split(".")
    var node = self.sessionData
    for key in pathItems[0..^2]:
      if node.kind != JObject:
        return
      if not node.contains(key):
        node[key] = newJObject()
      node = node[key]
    if node.isNil or node.kind != JObject:
      return

    let key = pathItems[^1]
    if not override and node.hasKey(key):
      node.fields[key].extendJson(value, true)
    else:
      node[key] = value

    self.onConfigChanged.invoke()
  except:
    discard

proc getSessionDataJson*(self: App, path: string, default: JsonNode): JsonNode {.expose("editor").} =
  if self.isNil:
    return default
  let node = self.sessionData{path.split(".")}
  if node.isNil:
    return default
  return node

proc scriptGetOptionJson*(path: string, default: JsonNode): JsonNode {.expose("editor").} =
  block:
    {.gcsafe.}:
      if gEditor.isNil:
        return default
      let node = gEditor.options{path.split(".")}
      if node.isNil:
        return default
      return node

proc scriptGetOptionInt*(path: string, default: int): int {.expose("editor").} =
  result = createScriptGetOption(path, default, getInt)

proc scriptGetOptionFloat*(path: string, default: float): float {.expose("editor").} =
  result = createScriptGetOption(path, default, getFloat)

proc scriptGetOptionBool*(path: string, default: bool): bool {.expose("editor").} =
  result = createScriptGetOption(path, default, getBool)

proc scriptGetOptionString*(path: string, default: string): string {.expose("editor").} =
  result = createScriptGetOption(path, default, getStr)

proc scriptSetOptionInt*(path: string, value: int) {.expose("editor").} =
  createScriptSetOption(path, newJInt(value))

proc scriptSetOptionFloat*(path: string, value: float) {.expose("editor").} =
  createScriptSetOption(path, newJFloat(value))

proc scriptSetOptionBool*(path: string, value: bool) {.expose("editor").} =
  createScriptSetOption(path, newJBool(value))

proc scriptSetOptionString*(path: string, value: string) {.expose("editor").} =
  createScriptSetOption(path, newJString(value))

proc scriptSetCallback*(path: string, id: int) {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return
    gEditor.callbacks[path] = id

proc setRegisterTextAsync*(self: App, text: string, register: string = ""): Future[void] {.async.} =
  self.registers[register] = Register(kind: RegisterKind.Text, text: text)
  if register.len == 0:
    setSystemClipboardText(text)

proc getRegisterTextAsync*(self: App, register: string = ""): Future[string] {.async.} =
  if register.len == 0:
    let text = getSystemClipboardText().await
    if text.isSome:
      return text.get

  if self.registers.contains(register):
    return self.registers[register].getText()

  return ""

proc setRegisterAsync*(self: App, register: string, value: sink Register): Future[void] {.async.} =
  if register.len == 0:
    setSystemClipboardText(value.getText())
  self.registers[register] = value.move

proc getRegisterAsync*(self: App, register: string, res: ptr Register): Future[bool] {.async.} =
  if register.len == 0:
    var text = getSystemClipboardText().await
    if text.isSome:
      if text.get.len > 1024:
        var rope: Rope
        if createRopeAsync(text.get.addr, rope.addr).await.getSome(errorIndex):
          log lvlWarn, &"Large clipboard contains invalid utf8 at index {errorIndex}, can't use rope"
          res[] = Register(kind: Text, text: text.get.move)
        else:
          res[] = Register(kind: Rope, rope: rope.move)

      else:
        res[] = Register(kind: Text, text: text.get.move)
      return true

  if self.registers.contains(register):
    res[] = self.registers[register].clone()
    return true

  return false

proc setRegisterText*(self: App, text: string, register: string = "") {.expose("editor").} =
  self.registers[register] = Register(kind: RegisterKind.Text, text: text)

proc getRegisterText*(self: App, register: string): string {.expose("editor").} =
  if register.len == 0:
    log lvlError, fmt"getRegisterText: Register name must not be empty. Use getRegisterTextAsync() instead."
    return ""

  if self.registers.contains(register):
    return self.registers[register].getText()

  return ""

proc startRecordingKeys*(self: App, register: string) {.expose("editor").} =
  log lvlInfo, &"Start recording keys into '{register}'"
  self.recordingKeys.incl register

proc stopRecordingKeys*(self: App, register: string) {.expose("editor").} =
  log lvlInfo, &"Stop recording keys into '{register}'"
  self.recordingKeys.excl register

proc startRecordingCommands*(self: App, register: string) {.expose("editor").} =
  log lvlInfo, &"Start recording commands into '{register}'"
  self.recordingCommands.incl register

proc stopRecordingCommands*(self: App, register: string) {.expose("editor").} =
  log lvlInfo, &"Stop recording commands into '{register}'"
  self.recordingCommands.excl register

proc isReplayingCommands*(self: App): bool {.expose("editor").} = self.bIsReplayingCommands
proc isReplayingKeys*(self: App): bool {.expose("editor").} = self.bIsReplayingKeys
proc isRecordingCommands*(self: App, registry: string): bool {.expose("editor").} = self.recordingCommands.contains(registry)

proc replayCommands*(self: App, register: string) {.expose("editor").} =
  if not self.registers.contains(register) or self.registers[register].kind != RegisterKind.Text:
    log lvlError, fmt"No commands recorded in register '{register}'"
    return

  if self.bIsReplayingCommands:
    log lvlError, fmt"replayCommands '{register}': Already replaying commands"
    return

  log lvlInfo, &"replayCommands '{register}':\n{self.registers[register].text}"
  self.bIsReplayingCommands = true
  defer:
    self.bIsReplayingCommands = false

  for command in self.registers[register].text.splitLines:
    let (action, arg) = parseAction(command)
    discard self.handleAction(action, arg, record=false)

proc replayKeys*(self: App, register: string) {.expose("editor").} =
  if not self.registers.contains(register) or self.registers[register].kind != RegisterKind.Text:
    log lvlError, fmt"No commands recorded in register '{register}'"
    return

  if self.bIsReplayingKeys:
    log lvlError, fmt"replayKeys '{register}': Already replaying keys"
    return

  log lvlInfo, &"replayKeys '{register}': {self.registers[register].text}"
  self.bIsReplayingKeys = true
  defer:
    self.bIsReplayingKeys = false

  for (inputCode, mods, _) in parseInputs(self.registers[register].text):
    self.handleKeyPress(inputCode.a, mods)

proc inputKeys*(self: App, input: string) {.expose("editor").} =
  for (inputCode, mods, _) in parseInputs(input):
    self.handleKeyPress(inputCode.a, mods)

proc collectGarbage*(self: App) {.expose("editor").} =
  log lvlInfo, "collectGarbage"
  try:
    GC_FullCollect()
  except:
    log lvlError, &"Failed to collect garbage: {getCurrentExceptionMsg()}"

proc printStatistics*(self: App) {.expose("editor").} =
  {.gcsafe.}:
    try:
      var result = "\n"
      result.add &"Backend: {self.backend}\n"

      result.add &"Registers:\n"
      for (key, value) in self.registers.mpairs:
        result.add &"    {key}: {value}\n"

      result.add &"RecordingKeys:\n"
      for key in self.recordingKeys:
        result.add &"    {key}"

      result.add &"RecordingCommands:\n"
      for key in self.recordingKeys:
        result.add &"    {key}"

      result.add &"Event Handlers: {self.eventHandlerConfigs.len}\n"
        # eventHandlerConfigs: Table[string, EventHandlerConfig]

      result.add &"Options: {self.options.pretty.len}\n"
      result.add &"Callbacks: {self.callbacks.len}\n"
      result.add &"Script Actions: {self.scriptActions.len}\n"

      result.add &"Input History: {self.inputHistory}\n"
      result.add &"Editor History: {self.editorHistory}\n"

      result.add &"Command History: {self.commandHistory.len}\n"
      # for command in self.commandHistory:
      #   result.add &"    {command}\n"

      result.add &"Text documents: {allTextDocuments.len}\n"
      for document in allTextDocuments:
        result.add document.getStatisticsString().indent(4)
        result.add "\n\n"

      result.add &"Text editors: {allTextEditors.len}\n"
      for editor in allTextEditors:
        result.add editor.getStatisticsString().indent(4)
        result.add "\n\n"

      # todo
        # languageServerCommandLine: LanguageServer
        # commandLineTextEditor: DocumentEditor

        # logDocument: Document
        # documents*: seq[Document]
        # editors*: Table[EditorId, DocumentEditor]
        # popups*: seq[Popup]

        # theme*: Theme
        # wasmScriptContext*: ScriptContextWasm

        # workspace*: Workspace
      result.add &"Platform:\n{self.platform.getStatisticsString().indent(4)}\n"
      result.add &"UI:\n{self.platform.builder.getStatisticsString().indent(4)}\n"

      log lvlInfo, result
    except:
      discard

genDispatcher("editor")
addGlobalDispatchTable "editor", genDispatchTable("editor")

proc recordCommand*(self: App, command: string, args: string) =
  for register in self.recordingCommands:
    if not self.registers.contains(register) or self.registers[register].kind != RegisterKind.Text:
      self.registers[register] = Register(kind: RegisterKind.Text, text: "")
    if self.registers[register].text.len > 0:
      self.registers[register].text.add "\n"
    self.registers[register].text.add command & " " & args

proc handleAction(self: App, action: string, arg: string, record: bool): Option[JsonNode] =
  let t = startTimer()
  if not self.bIsReplayingCommands:
    log lvlInfo, &"[handleAction] '{action} {arg}'"
  defer:
    if not self.bIsReplayingCommands:
      let elapsed = t.elapsed
      log lvlInfo, &"[handleAction] '{action} {arg}' took {elapsed.ms} ms"

  try:
    if record:
      self.recordCommand(action, arg)

    var args = newJArray()
    try:
      for a in newStringStream(arg).parseJsonFragments():
        args.add a
    except CatchableError:
      log(lvlError, fmt"Failed to parse arguments '{arg}': {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())

    if action.startsWith("."): # active action
      if lsp_client.dispatchEvent(action[1..^1], args).getSome(r):
        return r.some

      if self.getActiveEditor().getSome(editor):
        return editor.handleAction(action[1..^1], arg, record=false)

      log lvlError, fmt"No current view"
      return JsonNode.none

    # todo: there's got to be better way than putting all these here manually
    if collab.dispatchEvent(action, args).getSome(r):
      return r.some

    if debugger.dispatchEvent(action, args).getSome(r):
      return r.some

    try:
      withScriptContext self, self.wasmScriptContext:
        let res = self.wasmScriptContext.handleScriptAction(action, args)
        if res.isNotNil:
          return res.some
    except CatchableError:
      log(lvlError, fmt"Failed to dispatch action '{action} {arg}': {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())

    try:
      return dispatch(action, args)
    except CatchableError:
      log(lvlError, fmt"Failed to dispatch action '{action} {arg}': {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())

  except:
    discard

  return JsonNode.none

template generatePluginBindings*(): untyped =
  createEditorWasmImportConstructor()
