import std/[sequtils, strformat, strutils, tables, unicode, options, os, algorithm, json, macros, macrocache, sugar, streams, deques]
import misc/[id, util, timer, event, cancellation_token, myjsonutils, traits, rect_utils, custom_logger, custom_async, fuzzy_matching, array_set, delayed_task, regex]
import ui/node
import scripting/[expose, scripting_base]
import platform/[platform, filesystem]
import workspaces/[workspace]
import config_provider, app_interface
import text/language/language_server_base, language_server_absytree_commands
import input, events, document, document_editor, popup, dispatch_tables, theme, clipboard, app_options
import text/[custom_treesitter]
import compilation_config

when enableAst:
  import ast/[model, project]

when not defined(js):
  import text/diff_git

when enableNimscript and not defined(js):
  import scripting/scripting_nim

import scripting/scripting_wasm

import scripting_api as api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, ModelDocumentEditor, Popup, SelectorPopup
from scripting_api import Backend

logCategory "app"
createJavascriptPrototype("editor")

type View* = ref object
  document*: Document
  editor*: DocumentEditor

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
  OpenWorkspaceKind {.pure.} = enum Local, AbsytreeServer, Github
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

type
  RegisterKind* {.pure.} = enum Text, AstNode
  Register* = object
    case kind*: RegisterKind
    of Text:
      text*: string
    of AstNode:
      when enableAst:
        node*: AstNode

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

    logFrameTime*: bool = false

    registers: Table[string, Register]
    recordingKeys: seq[string]
    recordingCommands: seq[string]
    bIsReplayingKeys: bool = false
    bIsReplayingCommands: bool = false

    eventHandlerConfigs: Table[string, EventHandlerConfig]

    options: JsonNode
    callbacks: Table[string, int]

    workspace*: Workspace

    scriptContext*: ScriptContext
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

    logDocument: Document

    commandHistory: seq[string]
    currentHistoryEntry: int = 0
    absytreeCommandsServer: LanguageServer
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

    gitIgnorePatterns: seq[Regex]

var gEditor* {.exportc.}: App = nil

implTrait ConfigProvider, App:
  proc getConfigValue(self: App, path: string): Option[JsonNode] =
    let node = self.options{path.split(".")}
    if node.isNil:
      return JsonNode.none
    return node.some

  proc setConfigValue(self: App, path: string, value: JsonNode) =
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

proc handleLog(self: App, level: Level, args: openArray[string])
proc getEventHandlerConfig*(self: App, context: string): EventHandlerConfig
proc setRegisterTextAsync*(self: App, text: string, register: string = ""): Future[void] {.async.}
proc getRegisterTextAsync*(self: App, register: string = ""): Future[string] {.async.}
proc recordCommand*(self: App, command: string, args: string)
proc openWorkspaceFile*(self: App, path: string, folder: WorkspaceFolder): Option[DocumentEditor]
proc openFile*(self: App, path: string, app: bool = false): Option[DocumentEditor]
proc handleUnknownDocumentEditorAction*(self: App, editor: DocumentEditor, action: string, args: JsonNode): EventResponse
proc handleUnknownPopupAction*(self: App, popup: Popup, action: string, arg: string): EventResponse
proc handleModeChanged*(self: App, editor: DocumentEditor, oldMode: string, newMode: string)
proc invokeCallback*(self: App, context: string, args: JsonNode): bool
proc invokeAnyCallback*(self: App, context: string, args: JsonNode): JsonNode
proc registerEditor*(self: App, editor: DocumentEditor): void
proc unregisterEditor*(self: App, editor: DocumentEditor): void
proc tryActivateEditor*(self: App, editor: DocumentEditor): void
proc getEditorForId*(self: App, id: EditorId): Option[DocumentEditor]
proc getPopupForId*(self: App, id: EditorId): Option[Popup]
proc createSelectorPopup*(self: App): Popup
proc pushPopup*(self: App, popup: Popup)
proc popPopup*(self: App, popup: Popup)
proc openSymbolsPopup*(self: App, symbols: seq[Symbol], handleItemSelected: proc(symbol: Symbol), handleItemConfirmed: proc(symbol: Symbol), handleCanceled: proc())
proc help*(self: App, about: string = "")
proc getAllDocuments*(self: App): seq[Document]
proc setHandleInputs*(self: App, context: string, value: bool)

implTrait AppInterface, App:
  proc platform*(self: App): Platform = self.platform

  getEventHandlerConfig(EventHandlerConfig, App, string)

  setRegisterTextAsync(Future[void], App, string, string)
  getRegisterTextAsync(Future[string], App, string)
  recordCommand(void, App, string, string)

  proc configProvider*(self: App): ConfigProvider = self.asConfigProvider

  openWorkspaceFile(Option[DocumentEditor], App, string, WorkspaceFolder)
  openFile(Option[DocumentEditor], App, string)
  handleUnknownDocumentEditorAction(EventResponse, App, DocumentEditor, string, JsonNode)
  handleUnknownPopupAction(EventResponse, App, Popup, string, string)
  handleModeChanged(void, App, DocumentEditor, string, string)
  invokeCallback(bool, App, string, JsonNode)
  invokeAnyCallback(JsonNode, App, string, JsonNode)
  registerEditor(void, App, DocumentEditor)
  tryActivateEditor(void, App, DocumentEditor)
  unregisterEditor(void, App, DocumentEditor)
  getEditorForId(Option[DocumentEditor], App, EditorId)
  getPopupForId(Option[Popup], App, EditorId)
  createSelectorPopup(Popup, App)
  pushPopup(void, App, Popup)
  popPopup(void, App, Popup)
  openSymbolsPopup(void, App, seq[Symbol], proc(symbol: Symbol), proc(symbol: Symbol), proc())
  getAllDocuments(seq[Document], App)

type
  AppLogger* = ref object of Logger
    app: App

method log*(self: AppLogger, level: Level, args: varargs[string, `$`]) {.gcsafe.} =
  {.cast(gcsafe).}:
    self.app.handleLog(level, @args)

proc handleKeyPress*(self: App, input: int64, modifiers: Modifiers)
proc handleKeyRelease*(self: App, input: int64, modifiers: Modifiers)
proc handleRune*(self: App, input: int64, modifiers: Modifiers)
proc handleMousePress*(self: App, button: MouseButton, modifiers: Modifiers, mousePosWindow: Vec2)
proc handleMouseRelease*(self: App, button: MouseButton, modifiers: Modifiers, mousePosWindow: Vec2)
proc handleMouseMove*(self: App, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton])
proc handleScroll*(self: App, scroll: Vec2, mousePosWindow: Vec2, modifiers: Modifiers)
proc handleDropFile*(self: App, path, content: string)

proc openWorkspaceKind(workspaceFolder: WorkspaceFolder): OpenWorkspaceKind
proc addWorkspaceFolder(self: App, workspaceFolder: WorkspaceFolder): bool
proc getWorkspaceFolder(self: App, id: Id): Option[WorkspaceFolder]
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
  if not self.callbacks.contains(context):
    return false
  let id = self.callbacks[context]
  try:
    withScriptContext self, self.scriptContext:
      if self.scriptContext.handleCallback(id, args):
        return true
    withScriptContext self, self.wasmScriptContext:
      if self.wasmScriptContext.handleCallback(id, args):
        return true
    return false
  except CatchableError:
    log(lvlError, fmt"Failed to run script handleCallback {id}: {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())
    return false

proc invokeAnyCallback*(self: App, context: string, args: JsonNode): JsonNode =
  # debugf"invokeAnyCallback {context}: {args}"
  if self.callbacks.contains(context):
    let id = self.callbacks[context]
    try:
      withScriptContext self, self.scriptContext:
        let res = self.scriptContext.handleAnyCallback(id, args)
        if res.isNotNil:
          return res

      withScriptContext self, self.wasmScriptContext:
        let res = self.wasmScriptContext.handleAnyCallback(id, args)
        if res.isNotNil:
          return res
      return nil
    except CatchableError:
      log(lvlError, fmt"Failed to run script handleAnyCallback {id}: {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())
      return nil

  else:
    try:
      withScriptContext self, self.scriptContext:
        let res = self.scriptContext.handleScriptAction(context, args)
        if res.isNotNil:
          return res

      withScriptContext self, self.wasmScriptContext:
        let res = self.wasmScriptContext.handleScriptAction(context, args)
        if res.isNotNil:
          return res
      return nil
    except CatchableError:
      log(lvlError, fmt"Failed to run script handleScriptAction {context}: {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())
      return nil

proc getText(register: var Register): string =
  case register.kind
  of Text:
    return register.text
  of AstNode:
    assert false
    return ""

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

proc handleUnknownPopupAction*(self: App, popup: Popup, action: string, arg: string): EventResponse =
  try:
    var args = newJArray()
    for a in newStringStream(arg).parseJsonFragments():
      args.add a

    withScriptContext self, self.scriptContext:
      if self.scriptContext.handleUnknownPopupAction(popup, action, args):
        return Handled
    withScriptContext self, self.wasmScriptContext:
      if self.wasmScriptContext.handleUnknownPopupAction(popup, action, args):
        return Handled
  except CatchableError:
    log(lvlError, fmt"Failed to run script handleUnknownPopupAction '{action} {arg}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

  return Failed

proc handleUnknownDocumentEditorAction*(self: App, editor: DocumentEditor, action: string, args: JsonNode): EventResponse =
  try:
    withScriptContext self, self.scriptContext:
      if self.scriptContext.handleUnknownDocumentEditorAction(editor, action, args):
        return Handled
    withScriptContext self, self.wasmScriptContext:
      if self.wasmScriptContext.handleUnknownDocumentEditorAction(editor, action, args):
        return Handled
  except CatchableError:
    log(lvlError, fmt"Failed to run script handleUnknownDocumentEditorAction '{action} {args}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

  return Failed

proc handleModeChanged*(self: App, editor: DocumentEditor, oldMode: string, newMode: string) =
  try:
    withScriptContext self, self.scriptContext:
      self.scriptContext.handleEditorModeChanged(editor, oldMode, newMode)
    withScriptContext self, self.wasmScriptContext:
      self.wasmScriptContext.handleEditorModeChanged(editor, oldMode, newMode)
  except CatchableError:
    log(lvlError, fmt"Failed to run script handleDocumentModeChanged '{oldMode} -> {newMode}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

proc handleAction(self: App, action: string, arg: string, record: bool): bool
proc getFlag*(self: App, flag: string, default: bool = false): bool

proc createEditorForDocument(self: App, document: Document): DocumentEditor =
  for editor in self.editorDefaults:
    if editor.canEdit document:
      return editor.createWithDocument(document, self.asConfigProvider)

  log(lvlError, "No editor found which can edit " & $document)
  return nil

proc getOption*[T](editor: App, path: string, default: T = T.default): T =
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

  editor.platform.requestRender(true)

proc setFlag*(self: App, flag: string, value: bool)
proc toggleFlag*(self: App, flag: string)

proc updateActiveEditor*(self: App, addToHistory = true) =
  if self.currentViewInternal >= 0 and self.currentViewInternal < self.views.len:
    if addToHistory and self.activeEditorInternal.getSome(id) and id != self.views[self.currentViewInternal].editor.id:
      self.editorHistory.addLast id
    self.activeEditorInternal = self.views[self.currentViewInternal].editor.id.some

proc currentView*(self: App): int = self.currentViewInternal
proc `currentView=`(self: App, newIndex: int, addToHistory = true) =
  self.currentViewInternal = newIndex
  self.updateActiveEditor(addToHistory)

proc addView*(self: App, view: View, addToHistory = true, append = false) =
  let maxViews = getOption[int](self, "editor.maxViews", int.high)

  while maxViews > 0 and self.views.len > maxViews:
    self.views[self.views.high].editor.active = false
    self.hiddenViews.add self.views.pop()

  if append:
    self.currentView = self.views.high

  if self.views.len == maxViews:
    self.views[self.currentView].editor.active = false
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

  view.editor.markDirty()

  self.updateActiveEditor(addToHistory)
  self.platform.requestRender()

proc createView*(self: App, document: Document): View =
  var editor = self.createEditorForDocument document
  editor.injectDependencies self.asAppInterface
  discard editor.onMarkedDirty.subscribe () => self.platform.requestRender()
  return View(document: document, editor: editor)

proc createView(self: App, editorState: OpenEditor): View

proc createAndAddView*(self: App, document: Document, append = false): DocumentEditor =
  var editor = self.createEditorForDocument document
  editor.injectDependencies self.asAppInterface
  discard editor.onMarkedDirty.subscribe () => self.platform.requestRender()
  var view = View(document: document, editor: editor)
  self.addView(view, append=append)
  return editor

proc tryActivateEditor*(self: App, editor: DocumentEditor): void =
  if self.popups.len > 0:
    return
  for i, view in self.views:
    if view.editor == editor:
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

  return self.eventHandlerConfigs[context]

proc getEditorForId*(self: App, id: EditorId): Option[DocumentEditor] =
  if self.editors.contains(id):
    return self.editors[id].some

  if self.commandLineTextEditor.id == id:
    return self.commandLineTextEditor.some

  return DocumentEditor.none

proc getPopupForId*(self: App, id: EditorId): Option[Popup] =
  for popup in self.popups:
    if popup.id == id:
      return popup.some

  return Popup.none

proc getAllDocuments*(self: App): seq[Document] =
  for it in self.editors.values:
    result.incl it.getDocument

import text/[text_editor, text_document]
when enableAst:
  import ast/[model_document]
import selector_popup

type FileSelectorItem* = ref object of SelectorItem
  name*: string
  directory*: string
  path*: string
  workspaceFolder*: Option[WorkspaceFolder]

type ThemeSelectorItem* = ref object of FileSelectorItem
  discard

method changed*(self: FileSelectorItem, other: SelectorItem): bool =
  let other = other.FileSelectorItem
  return self.path != other.path

method itemToJson*(self: FileSelectorItem): JsonNode = %*{
    "score": self.score,
    "path": self.path,
    "name": self.name,
    "directory": self.directory,
    "workspace": if self.workspaceFolder.getSome(workspace):
        workspace.id.toJson
      else:
        newJNull()
  }

method changed*(self: ThemeSelectorItem, other: SelectorItem): bool =
  let other = other.ThemeSelectorItem
  return self.name != other.name or self.path != other.path

proc setTheme*(self: App, path: string) =
  log(lvlInfo, fmt"Loading theme {path}")
  if theme.loadFromFile(path).getSome(theme):
    self.theme = theme
    gTheme = theme
  else:
    log(lvlError, fmt"Failed to load theme {path}")
  self.platform.requestRender()

when enableNimscript and not defined(js):
  var createScriptContext: proc(filepath: string, searchPaths: seq[string]): Future[Option[ScriptContext]] = nil

proc getCommandLineTextEditor*(self: App): TextDocumentEditor = self.commandLineTextEditor.TextDocumentEditor

proc initScripting(self: App, options: AppOptions) {.async.} =
  if not options.disableWasmPlugins:
    try:
      log(lvlInfo, fmt"load wasm configs")
      self.wasmScriptContext = new ScriptContextWasm

      withScriptContext self, self.wasmScriptContext:
        let t1 = startTimer()
        await self.wasmScriptContext.init("./config")
        log(lvlInfo, fmt"init wasm configs ({t1.elapsed.ms}ms)")

        let t2 = startTimer()
        discard self.wasmScriptContext.postInitialize()
        log(lvlInfo, fmt"post init wasm configs ({t2.elapsed.ms}ms)")
    except CatchableError:
      log(lvlError, fmt"Failed to load wasm configs: {(getCurrentExceptionMsg())}{'\n'}{(getCurrentException().getStackTrace())}")

  when enableNimscript and not defined(js):
    await sleepAsync(1)

    if not options.disableNimScriptPlugins:
      try:
        var searchPaths = @["app://src", "app://scripting"]
        let searchPathsJson = self.options{@["scripting", "search-paths"]}
        if not searchPathsJson.isNil:
          for sp in searchPathsJson:
            searchPaths.add sp.getStr

        for path in searchPaths.mitems:
          if path.hasPrefix("app://", rest):
            path = fs.getApplicationFilePath(rest)

        if createScriptContext("./config/absytree_config.nim", searchPaths).await.getSome(scriptContext):
          self.scriptContext = scriptContext
        else:
          log lvlError, "Failed to create nim script context"

        withScriptContext self, self.scriptContext:
          log(lvlInfo, fmt"init nim script config")
          await self.scriptContext.init("./config")
          log(lvlInfo, fmt"post init nim script config")
          discard self.scriptContext.postInitialize()

        log(lvlInfo, fmt"finished configs")
        self.initializeCalled = true
      except CatchableError:
        log(lvlError, fmt"Failed to load config: {(getCurrentExceptionMsg())}{'\n'}{(getCurrentException().getStackTrace())}")

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
  editorConfig.addCommand("", "<CAS-r>", "reload-config")
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
      fs.loadApplicationFile(path).parseJson
    else:
      fs.loadFile(path).parseJson

    state = stateJson.jsonTo(EditorState, JOptions(allowMissingKeys: true, allowExtraKeys: true))
    log(lvlInfo, fmt"Restoring session {self.sessionFile}")

    if not state.theme.isEmptyOrWhitespace:
      try:
        self.setTheme(state.theme)
      except CatchableError:
        log(lvlError, fmt"Failed to load theme: {getCurrentExceptionMsg()}")

    if not state.layout.isEmptyOrWhitespace:
      self.setLayout(state.layout)

    self.loadedFontSize = state.fontSize.float
    self.platform.fontSize = state.fontSize.float
    self.loadedLineDistance = state.lineDistance.float
    self.platform.lineDistance = state.lineDistance.float
    if state.fontRegular.len > 0: self.fontRegular = state.fontRegular
    if state.fontBold.len > 0: self.fontBold = state.fontBold
    if state.fontItalic.len > 0: self.fontItalic = state.fontItalic
    if state.fontBoldItalic.len > 0: self.fontBoldItalic = state.fontBoldItalic
    if state.fallbackFonts.len > 0: self.fallbackFonts = state.fallbackFonts

    self.platform.setFont(self.fontRegular, self.fontBold, self.fontItalic, self.fontBoldItalic, self.fallbackFonts)
  except CatchableError:
    log(lvlError, fmt"Failed to load previous state from config file: {getCurrentExceptionMsg()}")

proc newEditor*(backend: api.Backend, platform: Platform, options = AppOptions()): Future[App] {.async.} =
  var self = App()

  # Emit this to set the editor prototype to editor_prototype, which needs to be set up before calling this
  when defined(js):
    {.emit: [self, " = jsCreateWithPrototype(editor_prototype, ", self, ");"].}
    # This " is here to fix syntax highlighting

  addHandler AppLogger(app: self)

  log lvlInfo, fmt"Creating App with backend {backend} and options {options}"

  gEditor = self
  gAppInterface = self.asAppInterface
  self.platform = platform
  self.backend = backend
  self.statusBarOnTop = false

  discard platform.onKeyPress.subscribe proc(event: auto): void = self.handleKeyPress(event.input, event.modifiers)
  discard platform.onKeyRelease.subscribe proc(event: auto): void = self.handleKeyRelease(event.input, event.modifiers)
  discard platform.onRune.subscribe proc(event: auto): void = self.handleRune(event.input, event.modifiers)
  discard platform.onMousePress.subscribe proc(event: auto): void = self.handleMousePress(event.button, event.modifiers, event.pos)
  discard platform.onMouseRelease.subscribe proc(event: auto): void = self.handleMouseRelease(event.button, event.modifiers, event.pos)
  discard platform.onMouseMove.subscribe proc(event: auto): void = self.handleMouseMove(event.pos, event.delta, event.modifiers, event.buttons)
  discard platform.onScroll.subscribe proc(event: auto): void = self.handleScroll(event.scroll, event.pos, event.modifiers)
  discard platform.onDropFile.subscribe proc(event: auto): void = self.handleDropFile(event.path, event.content)
  discard platform.onCloseRequested.subscribe proc() = self.closeRequested = true

  self.timer = startTimer()
  self.frameTimer = startTimer()

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

  self.editorDefaults.add TextDocumentEditor()
  when enableAst:
    self.editorDefaults.add ModelDocumentEditor()

  self.workspace.new()

  self.logDocument = newTextDocument(self.asConfigProvider, "log", load=false, createLanguageServer=false)
  self.documents.add self.logDocument

  self.theme = defaultTheme()
  gTheme = self.theme
  self.currentView = 0

  self.options = newJObject()

  self.setupDefaultKeybindings()

  let gitIgnorePatternsString = fs.loadApplicationFile(".gitignore")
  for line in gitIgnorePatternsString.splitLines():
    if line.isEmptyOrWhitespace:
      continue
    self.gitIgnorePatterns.add glob(line)

  self.eventHandler = eventHandler(self.getEventHandlerConfig("editor")):
    onAction:
      if self.handleAction(action, arg, record=true):
        Handled
      else:
        Ignored
    onInput:
      Ignored

  self.commandLineEventHandlerHigh = eventHandler(self.getEventHandlerConfig("command-line-high")):
    onAction:
      if self.handleAction(action, arg, record=true):
        Handled
      else:
        Ignored
    onInput:
      Ignored

  self.commandLineEventHandlerLow = eventHandler(self.getEventHandlerConfig("command-line-low")):
    onAction:
      if self.handleAction(action, arg, record=true):
        Handled
      else:
        Ignored
    onInput:
      Ignored

  self.commandLineMode = false

  self.absytreeCommandsServer = newLanguageServerAbsytreeCommands()
  let commandLineTextDocument = newTextDocument(self.asConfigProvider, language="absytree-commands".some, languageServer=self.absytreeCommandsServer.some)
  self.documents.add commandLineTextDocument
  self.commandLineTextEditor = newTextEditor(commandLineTextDocument, self.asAppInterface, self.asConfigProvider)
  self.commandLineTextEditor.renderHeader = false
  self.commandLineTextEditor.TextDocumentEditor.disableScrolling = true
  self.commandLineTextEditor.TextDocumentEditor.lineNumbers = api.LineNumbers.None.some
  self.getCommandLineTextEditor.hideCursorWhenInactive = true
  discard self.commandLineTextEditor.onMarkedDirty.subscribe () => self.platform.requestRender()


  var state = EditorState()
  if not options.dontRestoreConfig:
    if options.sessionOverride.getSome(session):
      self.sessionFile = session
    elif options.fileToOpen.isSome:
      # Don't restore a session when opening a specific file.
      discard
    else:
      when not defined(js):
        # In the browser we don't have access to the local file system.
        # Outside the browser we look for a session file in the current directory.
        if fileExists(".absytree-session"):
          self.sessionFile = ".absytree-session"
      else:
        self.sessionFile = "app:config/config.json"

    if self.sessionFile != "":
      self.restoreStateFromConfig(state)
    else:
      log lvlInfo, &"Don't restore session file."

  try:
    if not options.dontRestoreOptions:
      self.options = fs.loadApplicationFile("./config/options.json").parseJson
      log(lvlInfo, fmt"Restoring options")

  except CatchableError:
    log(lvlError, fmt"Failed to load previous options from options file: {getCurrentExceptionMsg()}")

  self.commandHistory = state.commandHistory

  if self.getFlag("editor.restore-open-workspaces", true):
    for wf in state.workspaceFolders:
      var folder: WorkspaceFolder = case wf.kind
      of OpenWorkspaceKind.Local:
        when not defined(js):
          newWorkspaceFolderLocal(wf.settings)
        else:
          log lvlError, fmt"Failed to restore local workspace, local workspaces not available in js. Workspace: {wf}"
          continue

      of OpenWorkspaceKind.AbsytreeServer: newWorkspaceFolderAbsytreeServer(wf.settings)
      of OpenWorkspaceKind.Github: newWorkspaceFolderGithub(wf.settings)

      folder.id = wf.id.parseId
      folder.name = wf.name
      if self.addWorkspaceFolder(folder):
        log(lvlInfo, fmt"Restoring workspace {folder.name} ({folder.id})")

  # Open current working dir as local workspace if no workspace exists yet
  if self.workspace.folders.len == 0:
    when not defined(js):
      log lvlInfo, "No workspace open yet, opening current working directory as local workspace"
      discard self.addWorkspaceFolder newWorkspaceFolderLocal(".")

  when enableAst:
    if state.astProjectWorkspaceId != "":
      if self.getWorkspaceFolder(state.astProjectWorkspaceId.parseId).getSome(ws):
        setProjectWorkspace(ws)
      else:
        log lvlError, fmt"Failed to restore project workspace {state.astProjectWorkspaceId}"

    if gProjectWorkspace.isNil and self.workspace.folders.len > 0:
      log lvlWarn, fmt"Use first workspace as project workspace"
      setProjectWorkspace(self.workspace.folders[0])

  # Restore open editors
  if options.fileToOpen.getSome(filePath):
    discard self.openFile(filePath)

  elif self.getFlag("editor.restore-open-editors", true):
    for editorState in state.openEditors:
      let view = self.createView(editorState)
      if view.isNil:
        continue

      self.addView(view, append=true)
      if editorState.customOptions.isNotNil:
        view.editor.restoreStateJson(editorState.customOptions)

    for editorState in state.hiddenEditors:
      let view = self.createView(editorState)
      if view.isNil:
        continue

      self.hiddenViews.add view
      if editorState.customOptions.isNotNil:
        view.editor.restoreStateJson(editorState.customOptions)

  if self.views.len == 0:
    if self.hiddenViews.len > 0:
      self.addView self.hiddenViews.pop
    else:
      self.help()

  asyncCheck self.initScripting(options)

  return self

proc saveAppState*(self: App)
proc printStatistics*(self: App)

proc shutdown*(self: App) =
  # Clear log document so we don't log to it as it will be destroyed.
  self.printStatistics()

  self.saveAppState()

  self.logDocument = nil

  let editors = collect(for e in self.editors.values: e)
  for editor in editors:
    editor.deinit()

  for popup in self.popups:
    popup.deinit()

  for document in self.documents:
    document.deinit()

  if self.scriptContext.isNotNil:
    self.scriptContext.deinit()
  if self.wasmScriptContext.isNotNil:
    self.wasmScriptContext.deinit()

  self.absytreeCommandsServer.stop()

  gAppInterface = nil
  self[] = AppObject()

  custom_treesitter.freeDynamicLibraries()

var logBuffer = ""
proc handleLog(self: App, level: Level, args: openArray[string]) =
  let str = substituteLog(defaultFmtStr, level, args) & "\n"
  if self.logDocument.isNotNil:
    let selection = self.logDocument.TextDocument.lastCursor.toSelection
    discard self.logDocument.TextDocument.insert([selection], [selection], [logBuffer & str])
    logBuffer = ""

    for view in self.views:
      if view.document == self.logDocument:
        let editor = view.editor.TextDocumentEditor
        if editor.selection == selection:
          editor.selection = editor.document.lastCursor.toSelection
          editor.scrollToCursor()
  else:
    logBuffer.add str

proc getEditor(): Option[App] =
  if gEditor.isNil: return App.none
  return gEditor.some

static:
  addInjector(App, getEditor)

proc getBackend*(self: App): Backend {.expose("editor").} =
  return self.backend

proc getHostOs*(self: App): string {.expose("editor").} =
  when defined(linux):
    return "linux"
  elif defined(windows):
    return "windows"
  elif defined(js):
    return "browser"
  else:
    return "unknown"

proc loadApplicationFile*(self: App, path: string): Option[string] {.expose("editor").} =
  ## Load a file from the application directory (path is relative to the executable)
  return fs.loadApplicationFile(path).some

proc toggleShowDrawnNodes*(self: App) {.expose("editor").} =
  self.platform.showDrawnNodes = not self.platform.showDrawnNodes

proc createView(self: App, editorState: OpenEditor): View =
  let workspaceFolder = self.getWorkspaceFolder(editorState.workspaceId.parseId)
  let document = try:
    when enableAst:
      if editorState.filename.endsWith(".am") or editorState.filename.endsWith(".ast-model"):
        newModelDocument(editorState.filename, editorState.appFile, workspaceFolder)
      else:
        newTextDocument(self.asConfigProvider, editorState.filename, "", editorState.appFile, workspaceFolder, load=true)
    else:
      newTextDocument(self.asConfigProvider, editorState.filename, "", editorState.appFile, workspaceFolder, load=true)
  except CatchableError:
    log(lvlError, fmt"Failed to restore file {editorState.filename} from previous session: {getCurrentExceptionMsg()}")
    return

  self.documents.add document
  return self.createView(document)

proc setMaxViews*(self: App, maxViews: int, openExisting: bool = false) {.expose("editor").} =
  ## Set the maximum number of views that can be open at the same time
  ## Closes any views that exceed the new limit

  log lvlInfo, fmt"[setMaxViews] {maxViews}"
  setOption[int](self, "editor.maxViews", maxViews)
  while maxViews > 0 and self.views.len > maxViews:
    self.views[self.views.high].editor.active = false
    self.hiddenViews.add self.views.pop()

  while openExisting and self.views.len < maxViews and self.hiddenViews.len > 0:
    self.views.add self.hiddenViews.pop()

  self.currentView = self.currentView.clamp(0, self.views.high)

  self.updateActiveEditor(false)
  self.platform.requestRender()

proc openWorkspaceKind(workspaceFolder: WorkspaceFolder): OpenWorkspaceKind =
  when not defined(js):
    if workspaceFolder of WorkspaceFolderLocal:
      return OpenWorkspaceKind.Local
  if workspaceFolder of WorkspaceFolderAbsytreeServer:
    return OpenWorkspaceKind.AbsytreeServer
  if workspaceFolder of WorkspaceFolderGithub:
    return OpenWorkspaceKind.Github
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

  if self.layout of HorizontalLayout:
    state.layout = "horizontal"
  elif self.layout of VerticalLayout:
    state.layout = "vertical"
  else:
    state.layout = "fibonacci"

  # Save open workspace folders
  for workspaceFolder in self.workspace.folders:
    let kind = workspaceFolder.openWorkspaceKind()

    state.workspaceFolders.add OpenWorkspace(
      kind: kind,
      id: $workspaceFolder.id,
      name: workspaceFolder.name,
      settings: workspaceFolder.settings
    )

  # Save open editors
  proc getEditorState(view: View): Option[OpenEditor] =
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
    if view.getEditorState().getSome(editorState):
      state.openEditors.add editorState

  for view in self.hiddenViews:
    if view.getEditorState().getSome(editorState):
      state.hiddenEditors.add editorState

  if self.sessionFile != "":
    let serialized = state.toJson
    let (isAppFile, path) = self.sessionFile.testApplicationPath()
    if isAppFile:
      fs.saveApplicationFile(path, serialized.pretty)
    else:
      fs.saveFile(path, serialized.pretty)

  fs.saveApplicationFile("./config/options.json", self.options.pretty)

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

proc addWorkspaceFolder(self: App, workspaceFolder: WorkspaceFolder): bool =
  for wf in self.workspace.folders:
    if wf.openWorkspaceKind == workspaceFolder.openWorkspaceKind and wf.settings == workspaceFolder.settings:
      return false
  if workspaceFolder.id == idNone():
    workspaceFolder.id = newId()
  log(lvlInfo, fmt"Opening workspace {workspaceFolder.name}")
  self.workspace.folders.add workspaceFolder
  return true

proc getWorkspaceFolder(self: App, id: Id): Option[WorkspaceFolder] =
  for wf in self.workspace.folders:
    if wf.id == id:
      return wf.some
  return WorkspaceFolder.none

proc clearWorkspaceCaches*(self: App) {.expose("editor").} =
  for wf in self.workspace.folders:
    wf.clearDirectoryCache()

proc openGithubWorkspace*(self: App, user: string, repository: string, branchOrHash: string) {.expose("editor").} =
  discard self.addWorkspaceFolder newWorkspaceFolderGithub(user, repository, branchOrHash)

proc openAbsytreeServerWorkspace*(self: App, url: string) {.expose("editor").} =
  discard self.addWorkspaceFolder newWorkspaceFolderAbsytreeServer(url)

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

proc addScriptAction*(self: App, name: string, docs: string = "", params: seq[tuple[name: string, typ: string]] = @[], returnType: string = "") {.expose("editor").} =
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
  extendGlobalDispatchTable "script", ExposedFunction(name: name, docs: docs, dispatch: dispatch, params: params, returnType: returnType, signature: signature)

when not defined(js):
  proc openLocalWorkspace*(self: App, path: string) {.expose("editor").} =
    let path = if path.isAbsolute: path else: path.absolutePath
    discard self.addWorkspaceFolder newWorkspaceFolderLocal(path)

proc getFlag*(self: App, flag: string, default: bool = false): bool {.expose("editor").} =
  return getOption[bool](self, flag, default)

proc setFlag*(self: App, flag: string, value: bool) {.expose("editor").} =
  setOption[bool](self, flag, value)

proc toggleFlag*(self: App, flag: string) {.expose("editor").} =
  let newValue = not self.getFlag(flag)
  log lvlInfo, fmt"toggleFlag '{flag}' -> {newValue}"
  self.setFlag(flag, newValue)
  self.platform.requestRender(true)

proc setOption*(self: App, option: string, value: JsonNode) {.expose("editor").} =
  if self.isNil:
    return

  self.platform.requestRender(true)

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
  node[pathItems[^1]] = value

proc quit*(self: App) {.expose("editor").} =
  self.closeRequested = true

proc help*(self: App, about: string = "") {.expose("editor").} =
  const introductionMd = staticRead"../docs/getting_started.md"
  let docsPath = "docs/getting_started.md"
  let textDocument = newTextDocument(self.asConfigProvider, docsPath, introductionMd, app=true, load=true)
  self.documents.add textDocument
  textDocument.load()
  discard self.createAndAddView(textDocument)

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

proc createAndAddView*(self: App) {.expose("editor").} =
  let document = newTextDocument(self.asConfigProvider)
  self.documents.add document
  discard self.createAndAddView(document)

proc logs*(self: App) {.expose("editor").} =
  discard self.createAndAddView(self.logDocument)

proc toggleConsoleLogger*(self: App) {.expose("editor").} =
  logger.toggleConsoleLogger()

proc getOpenEditors*(self: App): seq[EditorId] {.expose("editor").} =
  for view in self.views:
    result.add view.editor.id

proc getHiddenEditors*(self: App): seq[EditorId] {.expose("editor").} =
  for view in self.hiddenViews:
    result.add view.editor.id

proc closeEditor*(self: App, editor: DocumentEditor) =
  let document = editor.getDocument()
  log lvlInfo, fmt"closeEditor: '{editor.getDocument().filename}'"

  editor.deinit()

  for i, view in self.hiddenViews:
    if view.editor == editor:
      self.hiddenViews.removeShift(i)
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
    self.closeEditor(view.editor)

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
        self.closeEditor(view.editor)

  self.views.setLen 1
  self.views[0] = view
  self.currentView = 0
  self.platform.requestRender()

proc closeEditor*(self: App, path: string) {.expose("editor").} =
  log lvlInfo, fmt"close editor with path: '{path}'"
  let fullPath = if path.isAbsolute:
    path.normalizePathUnix
  else:
    path.absolutePath.normalizePathUnix

  for i, view in self.views:
    let document = view.editor.getDocument()
    if document.isNil:
      continue
    if document.filename == fullPath:
      self.closeView(i, keepHidden=false)
      return

  for editor in self.editors.values:
    if editor.getDocument().isNil:
      continue
    if editor.getDocument().filename == fullPath:
      self.closeEditor(editor)
      break

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
  self.getCommandLineTextEditor.document.content = @[initialValue]
  if self.commandHistory.len == 0:
    self.commandHistory.add ""
  self.commandHistory[0] = ""
  self.currentHistoryEntry = 0
  self.commandLineMode = true
  self.commandLineTextEditor.TextDocumentEditor.setMode("insert")
  self.platform.requestRender()

proc exitCommandLine*(self: App) {.expose("editor").} =
  self.getCommandLineTextEditor.document.content = @[""]
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
  let command = self.getCommandLineTextEditor.document.content.join("")

  if (let i = self.commandHistory.find(command); i >= 0):
    self.commandHistory.delete i

  if self.commandHistory.len == 0:
    self.commandHistory.add ""

  self.commandHistory.insert command, 1

  let maxHistorySize = self.getOption("editor.command-line.history-size", 100)
  if self.commandHistory.len > maxHistorySize:
    self.commandHistory.setLen maxHistorySize

  var (action, arg) = command.parseAction
  self.getCommandLineTextEditor.document.content = @[""]

  if arg.startsWith("\\"):
    arg = $newJString(arg[1..^1])

  return self.handleAction(action, arg, record=true)

proc writeFile*(self: App, path: string = "", app: bool = false) {.expose("editor").} =
  defer:
    self.platform.requestRender()
  if self.currentView >= 0 and self.currentView < self.views.len and self.views[self.currentView].document != nil:
    try:
      self.views[self.currentView].document.save(path, app)
    except CatchableError:
      log(lvlError, fmt"Failed to write file '{path}': {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())

proc loadFile*(self: App, path: string = "") {.expose("editor").} =
  defer:
    self.platform.requestRender()
  if self.currentView >= 0 and self.currentView < self.views.len and self.views[self.currentView].document != nil:
    try:
      self.views[self.currentView].document.load(path)
      self.views[self.currentView].editor.handleDocumentChanged()
    except CatchableError:
      log(lvlError, fmt"Failed to load file '{path}': {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())

proc loadWorkspaceFile*(self: App, path: string, folder: WorkspaceFolder) =
  defer:
    self.platform.requestRender()
  if self.currentView >= 0 and self.currentView < self.views.len and self.views[self.currentView].document != nil:
    try:
      self.views[self.currentView].document.workspace = folder.some
      self.views[self.currentView].document.load(path)
      self.views[self.currentView].editor.handleDocumentChanged()
    except CatchableError:
      log(lvlError, fmt"Failed to load file '{path}': {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())

proc tryOpenExisting*(self: App, path: string, folder: Option[WorkspaceFolder]): Option[DocumentEditor] =
  for i, view in self.views:
    if view.document.filename == path and view.document.workspace == folder:
      log(lvlInfo, fmt"Reusing open editor in view {i}")
      self.currentView = i
      return view.editor.some

  for i, view in self.hiddenViews:
    if view.document.filename == path and view.document.workspace == folder:
      log(lvlInfo, fmt"Reusing hidden view")
      self.hiddenViews.delete i
      self.addView(view)
      return view.editor.some

  return DocumentEditor.none

proc tryOpenExisting*(self: App, editor: EditorId, addToHistory = true): Option[DocumentEditor] =
  for i, view in self.views:
    if view.editor.id == editor:
      log(lvlInfo, fmt"Reusing open editor in view {i}")
      `currentView=`(self, i, addToHistory)
      return view.editor.some

  for i, view in self.hiddenViews:
    if view.editor.id == editor:
      log(lvlInfo, fmt"Reusing hidden view")
      self.hiddenViews.delete i
      self.addView(view, addToHistory)
      return view.editor.some

  return DocumentEditor.none

proc openFile*(self: App, path: string, app: bool = false): Option[DocumentEditor] =
  defer:
    self.platform.requestRender()

  log lvlInfo, fmt"[openFile] Open file '{path}' (app = {app})"
  if self.tryOpenExisting(path, WorkspaceFolder.none).getSome(ed):
    log lvlInfo, fmt"[openFile] found existing editor"
    return ed.some

  log lvlInfo, fmt"Open file '{path}'"

  let document = try:
    when enableAst:
      if path.endsWith(".am") or path.endsWith(".ast-model"):
        newModelDocument(path, app, WorkspaceFolder.none)
      else:
        newTextDocument(self.asConfigProvider, path, "", app, load=true)
    else:
      newTextDocument(self.asConfigProvider, path, "", app, load=true)
  except CatchableError:
    log(lvlError, fmt"[openFile] Failed to load file '{path}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())
    return DocumentEditor.none

  self.documents.add document
  return self.createAndAddView(document).some

proc openWorkspaceFile*(self: App, path: string, folder: WorkspaceFolder): Option[DocumentEditor] =
  defer:
    self.platform.requestRender()

  let path = folder.getAbsolutePath(path)

  log lvlInfo, fmt"[openWorkspaceFile] Open file '{path}' in workspace {folder.name} ({folder.id})"
  if self.tryOpenExisting(path, folder.some).getSome(editor):
    log lvlInfo, fmt"[openWorkspaceFile] found existing editor"
    return editor.some

  let document = try:
    when enableAst:
      if path.endsWith(".am") or path.endsWith(".ast-model"):
        newModelDocument(path, false, folder.some)
      else:
        newTextDocument(self.asConfigProvider, path, "", false, folder.some, load=true)
    else:
      newTextDocument(self.asConfigProvider, path, "", false, folder.some, load=true)
  except CatchableError:
    log(lvlError, fmt"[openWorkspaceFile] Failed to load file '{path}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())
    return DocumentEditor.none

  self.documents.add document
  return self.createAndAddView(document).some

proc removeFromLocalStorage*(self: App) {.expose("editor").} =
  ## Browser only
  ## Clears the content of the current document in local storage
  when defined(js):
    proc clearStorage(path: cstring) {.importjs: "window.localStorage.removeItem(#);".}
    if self.currentView >= 0 and self.currentView < self.views.len and self.views[self.currentView].document != nil:
      if self.views[self.currentView].document of TextDocument:
        clearStorage(self.views[self.currentView].document.TextDocument.filename.cstring)
        return

      when enableAst:
        if self.views[self.currentView].document of ModelDocument:
          clearStorage(self.views[self.currentView].document.ModelDocument.filename.cstring)
          return

      log lvlError, fmt"removeFromLocalStorage: Unknown document type"

proc createSelectorPopup*(self: App): Popup =
  return newSelectorPopup(self.asAppInterface)

proc loadTheme*(self: App, name: string) {.expose("editor").} =
  self.setTheme(fmt"themes/{name}.json")

proc chooseTheme*(self: App) {.expose("editor").} =
  defer:
    self.platform.requestRender()
  let originalTheme = self.theme.path

  var popup = newSelectorPopup(self.asAppInterface, "theme".some)
  popup.getCompletions = proc(popup: SelectorPopup, text: string): seq[SelectorItem] =
    let themesDir = fs.getApplicationFilePath("./themes")
    for file in walkDirRec(themesDir, relative=true):
      if file.endsWith ".json":
        let (relativeDirectory, name, _) = file.splitFile
        let score = matchFuzzySublime(text, file, defaultPathMatchingConfig).score.float
        result.add ThemeSelectorItem(name: name, directory: "themes" / relativeDirectory, path: fmt"{themesDir}/{file}", score: score)

    result.sort((a, b) => cmp(a.ThemeSelectorItem.score, b.ThemeSelectorItem.score), Ascending)

  popup.handleItemSelected = proc(item: SelectorItem) =
    if theme.loadFromFile(item.ThemeSelectorItem.path).getSome(theme):
      self.theme = theme
      gTheme = theme
      self.platform.requestRender(true)

  popup.handleItemConfirmed = proc(item: SelectorItem): bool =
    if theme.loadFromFile(item.ThemeSelectorItem.path).getSome(theme):
      self.theme = theme
      gTheme = theme
      self.platform.requestRender(true)
    return true

  popup.handleCanceled = proc() =
    if theme.loadFromFile(originalTheme).getSome(theme):
      self.theme = theme
      gTheme = theme
      self.platform.requestRender(true)

  popup.updateCompletions()

  self.pushPopup popup

proc createFile*(self: App, path: string) {.expose("editor").} =
  let fullPath = if path.isAbsolute:
    path.normalizePathUnix
  else:
    path.absolutePath.normalizePathUnix

  log lvlInfo, fmt"createFile: '{path}'"

  # todo: handle workspace better
  let workspace = if self.workspace.folders.len > 0:
    self.workspace.folders[0].some
  else:
    WorkspaceFolder.none

  let document = try:
    when enableAst:
      if path.endsWith(".am") or path.endsWith(".ast-model"):
        newModelDocument(fullPath, false, workspace)
      else:
        newTextDocument(self.asConfigProvider, fullPath, "", false, workspace, load=false)
    else:
      newTextDocument(self.asConfigProvider, fullPath, "", false, workspace, load=false)
  except CatchableError:
    log(lvlError, fmt"[createFile] Failed to create file '{path}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())
    return

  self.documents.add document
  discard self.createAndAddView(document)

proc chooseFile*(self: App, view: string = "new") {.expose("editor").} =
  ## Opens a file dialog which shows all files in the currently open workspaces
  ## Press <ENTER> to select a file
  ## Press <ESCAPE> to close the dialogue

  defer:
    self.platform.requestRender()

  var popup = newSelectorPopup(self.asAppInterface, "file".some)
  popup.scale.x = 0.5
  var sortCancellationToken = newCancellationToken()

  var ignorePatterns = self.gitIgnorePatterns
  if ignorePatterns.len == 0:
    # todo
    ignorePatterns.add glob("**/nimcache")
    ignorePatterns.add glob("**/rust_test/target")
    ignorePatterns.add glob("int")
    ignorePatterns.add glob(".git")
    ignorePatterns.add glob(".vs")
    ignorePatterns.add glob("*.dll")
    ignorePatterns.add glob("*.exe")
    ignorePatterns.add glob("*.pdb")
    ignorePatterns.add glob("*.ilk")
    ignorePatterns.add glob("*.wasm")
    ignorePatterns.add glob("*.ttf")
    ignorePatterns.add glob("*.bin")
    ignorePatterns.add glob("*.o")

  proc handleDirectory(folder: WorkspaceFolder, cancellationToken: CancellationToken, files: seq[string]): Future[void] {.async.} =
    if cancellationToken.canceled or popup.textEditor.isNil:
      return

    var timer = startTimer()
    let folder = folder
    for file in files:
      let score = matchFuzzySublime(popup.getSearchString, file, defaultPathMatchingConfig).score.float
      let (directory, name) = file.splitPath
      var relativeDirectory = folder.getRelativePath(directory).await
      if relativeDirectory.isSome and relativeDirectory.get == ".":
        relativeDirectory = "".some
      popup.completions.add FileSelectorItem(path: file, name: name, directory: relativeDirectory.get(directory), score: score, workspaceFolder: folder.some)

      if timer.elapsed.ms > 7:
        await sleepAsync(1)

        if cancellationToken.canceled or popup.textEditor.isNil:
          return

        timer = startTimer()

    # popup.completions.sort((a, b) => cmp(a.FileSelectorItem.score, b.FileSelectorItem.score), Ascending)
    popup.enableAutoSort()
    popup.markDirty()

  popup.getCompletionsAsyncIter = proc(popup: SelectorPopup, text: string): Future[void] {.async.} =
    if not popup.cancellationToken.isNil:
      sortCancellationToken.cancel()
      let cancellationToken = newCancellationToken()
      sortCancellationToken = cancellationToken

      var timer = startTimer()

      var i = 0
      var startIndex = 0
      while i < popup.completions.len:
        defer: inc i

        if cancellationToken.canceled or popup.textEditor.isNil:
          return

        let score = matchFuzzySublime(popup.getSearchString(), popup.completions[i].FileSelectorItem.path, defaultPathMatchingConfig).score.float

        popup.completions[i].score = score
        popup.completions[i].hasCompletionMatchPositions = false

        if timer.elapsed.ms > 7:
          await sleepAsync(1)
          if cancellationToken.canceled or popup.textEditor.isNil:
            return

          startIndex = i + 1
          timer = startTimer()

      popup.enableAutoSort()

      return

    var cancellationToken = newCancellationToken()
    popup.cancellationToken = cancellationToken

    for folder in self.workspace.folders:
      var folder = folder
      log lvlInfo, fmt"Start iterateDirectoryRec"
      await iterateDirectoryRec(folder, "", cancellationToken, ignorePatterns, proc(files: seq[string]): Future[void] {.async.} =
          handleDirectory(folder, cancellationToken, files).await
      )

      log lvlInfo, fmt"Finished iterateDirectoryRec"

      if cancellationToken.canceled or popup.textEditor.isNil:
        return

  popup.handleItemConfirmed = proc(item: SelectorItem): bool =
    case view
    of "current":
      if item.FileSelectorItem.workspaceFolder.isSome:
        self.loadWorkspaceFile(item.FileSelectorItem.path, item.FileSelectorItem.workspaceFolder.get)
      else:
        self.loadFile(item.FileSelectorItem.path)
    of "new":
      if item.FileSelectorItem.workspaceFolder.isSome:
        discard self.openWorkspaceFile(item.FileSelectorItem.path, item.FileSelectorItem.workspaceFolder.get)
      else:
        discard self.openFile(item.FileSelectorItem.path)
    else:
      log(lvlError, fmt"Unknown argument {view}")
    return true

  popup.updateCompletions()
  popup.sortFunction = proc(a, b: SelectorItem): int = cmp(a.FileSelectorItem.score, b.FileSelectorItem.score)
  popup.enableAutoSort()

  self.pushPopup popup

proc chooseOpen*(self: App, view: string = "new") {.expose("editor").} =
  defer:
    self.platform.requestRender()

  var popup = newSelectorPopup(self.asAppInterface, "open".some)
  popup.scale.x = 0.3

  popup.getCompletions = proc(popup: SelectorPopup, text: string): seq[SelectorItem] =
    let allViews = self.views & self.hiddenViews
    for view in allViews:
      let document = view.editor.getDocument
      let path = view.document.filename
      let score = matchFuzzySublime(text, path, defaultPathMatchingConfig).score.float
      let isDirty = view.document.lastSavedRevision != view.document.revision
      let dirtyMarker = if isDirty: "*" else: " "

      let (directory, name) = path.splitPath
      var relativeDirectory = if document.workspace.getSome(workspace):
        workspace.getRelativePathSync(directory)
      else:
        string.none

      if relativeDirectory.isSome and relativeDirectory.get == ".":
        relativeDirectory = "".some

      result.add FileSelectorItem(name: dirtyMarker & name, path: path, directory: relativeDirectory.get(directory), score: score, workspaceFolder: document.workspace)

    result.sort((a, b) => cmp(a.FileSelectorItem.score, b.FileSelectorItem.score), Ascending)

  popup.handleItemConfirmed = proc(item: SelectorItem): bool =
    case view
    of "current":
      if item.FileSelectorItem.workspaceFolder.isSome:
        self.loadWorkspaceFile(item.FileSelectorItem.path, item.FileSelectorItem.workspaceFolder.get)
      else:
        self.loadFile(item.FileSelectorItem.path)
    of "new":
      if item.FileSelectorItem.workspaceFolder.isSome:
        discard self.openWorkspaceFile(item.FileSelectorItem.path, item.FileSelectorItem.workspaceFolder.get)
      else:
        discard self.openFile(item.FileSelectorItem.path)
    else:
      log(lvlError, fmt"Unknown argument {view}")
    return true

  popup.updateCompletions()

  self.pushPopup popup

type SearchFileSelectorItem* = ref object of FileSelectorItem
  searchResult*: string
  line*: int
  column*: int

proc searchWorkspace(popup: SelectorPopup, workspace: WorkspaceFolder, query: string, text: string): Future[seq[SelectorItem]] {.async.} =
  if popup.updateInProgress:
    return popup.completions

  popup.updateInProgress = true
  defer:
    popup.updateInProgress = false

  var res: seq[SelectorItem]

  if not popup.updated:
    let searchResults = workspace.searchWorkspace(query).await
    if popup.textEditor.isNil:
      return res

    let searchText = popup.getSearchString
    log lvlInfo, fmt"Found {searchResults.len} results"

    for info in searchResults:
      let name = info.text & " |" & info.path.extractFilename & ":" & $info.line
      let score = matchFuzzySublime(searchText, name, defaultPathMatchingConfig).score.float
      res.add SearchFileSelectorItem(name: name, searchResult: info.text, path: info.path, score: score, workspaceFolder: workspace.some, line: info.line)
  else:
    for item in popup.completions.mitems:
      item.hasCompletionMatchPositions = false
      item.score = matchFuzzySublime(text, item.SearchFileSelectorItem.name, defaultPathMatchingConfig).score.float

    res = popup.completions

  res.sort((a, b) => cmp(a.FileSelectorItem.score, b.FileSelectorItem.score), Ascending)
  return res

proc searchGlobal*(self: App, query: string) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  var popup = newSelectorPopup(self.asAppInterface, "search".some)
  popup.scale.x = 0.75

  popup.getCompletionsAsync = proc(popup: SelectorPopup, text: string): Future[seq[SelectorItem]] =
    return popup.searchWorkspace(self.workspace.folders[0], query, text)

  popup.handleItemConfirmed = proc(item: SelectorItem): bool =
    let editor = if item.FileSelectorItem.workspaceFolder.isSome:
      self.openWorkspaceFile(item.FileSelectorItem.path, item.FileSelectorItem.workspaceFolder.get)
    else:
      self.openFile(item.FileSelectorItem.path)

    if editor.getSome(editor) and editor of TextDocumentEditor:
      editor.TextDocumentEditor.targetSelection = (item.SearchFileSelectorItem.line - 1, item.SearchFileSelectorItem.column - 1).toSelection
      editor.TextDocumentEditor.centerCursor()
    return true

  popup.updateCompletions()
  popup.sortFunction = proc(a, b: SelectorItem): int = cmp(a.FileSelectorItem.score, b.FileSelectorItem.score)
  popup.enableAutoSort()

  self.pushPopup popup

when not defined(js):
  type GitFileSelectorItem* = ref object of FileSelectorItem
    info: GitFileInfo

  proc getChangedFilesFromGitAsync(popup: SelectorPopup, text: string, workspace: Option[WorkspaceFolder]): Future[seq[SelectorItem]] {.async.} =
    if popup.updateInProgress:
      return popup.completions

    popup.updateInProgress = true
    defer:
      popup.updateInProgress = false

    if not popup.updated:
      let fileInfos = getChangedFiles().await
      if popup.textEditor.isNil:
        return

      let searchText = popup.getSearchString

      for info in fileInfos:
        let name = $info.stagedStatus & $info.unstagedStatus & " " & info.path
        let score = matchFuzzySublime(searchText, name, defaultPathMatchingConfig).score.float
        result.add GitFileSelectorItem(name: name, path: info.path, score: score, workspaceFolder: workspace, info: info)
    else:
      for item in popup.completions.mitems:
        item.hasCompletionMatchPositions = false
        item.score = matchFuzzySublime(text, item.GitFileSelectorItem.name, defaultPathMatchingConfig).score.float

      result = popup.completions

    result.sort((a, b) => cmp(a.GitFileSelectorItem.score, b.GitFileSelectorItem.score), Ascending)

  proc stageSelectedFileAsync(popup: SelectorPopup): Future[void] {.async.} =
    log lvlInfo, fmt"Stage selected entry ({popup.selected})"

    let item = popup.completions[popup.completions.high - popup.selected].GitFileSelectorItem
    let res = stageFile(item.info.path).await
    debugf"git add finished: {res}"
    if popup.textEditor.isNil:
      return

    popup.updated = false
    popup.updateCompletions()

  proc unstageSelectedFileAsync(popup: SelectorPopup): Future[void] {.async.} =
    log lvlInfo, fmt"Unstage selected entry ({popup.selected})"

    let item = popup.completions[popup.completions.high - popup.selected].GitFileSelectorItem
    let res = unstageFile(item.info.path).await
    debugf"git unstage finished: {res}"
    if popup.textEditor.isNil:
      return

    popup.updated = false
    popup.updateCompletions()

  proc revertSelectedFileAsync(popup: SelectorPopup): Future[void] {.async.} =
    log lvlInfo, fmt"Revert selected entry ({popup.selected})"

    let item = popup.completions[popup.completions.high - popup.selected].GitFileSelectorItem
    let res = revertFile(item.info.path).await
    debugf"git revert finished: {res}"
    if popup.textEditor.isNil:
      return

    popup.updated = false
    popup.updateCompletions()

  proc diffStagedFileAsync(self: App, path: string): Future[void] {.async.} =
    log lvlInfo, fmt"Diff staged '({path})'"

    let stagedDocument = newTextDocument(self.asConfigProvider, path, load = false, createLanguageServer = false)
    stagedDocument.staged = true
    stagedDocument.readOnly = true

    let editor = self.createAndAddView(stagedDocument).TextDocumentEditor
    editor.updateDiff()

proc chooseGitActiveFiles*(self: App) {.expose("editor").} =
  when defined(js):
    log lvlError, fmt"chooseGitActiveFiles not implemented yet for js backend"
    let editorWorking = self.views[self.currentView].editor
    if editorWorking of TextDocumentEditor:
      editorWorking.TextDocumentEditor.updateDiff()

  else:
    defer:
      self.platform.requestRender()

    let workspace = if self.workspace.folders.len > 0:
      self.workspace.folders[0].some
    else:
      WorkspaceFolder.none

    var popup = newSelectorPopup(self.asAppInterface, "git".some)
    popup.scale.x = 0.3

    popup.getCompletionsAsync = proc(popup: SelectorPopup, text: string): Future[seq[SelectorItem]] =
      return getChangedFilesFromGitAsync(popup, text, workspace)

    popup.handleItemConfirmed = proc(item: SelectorItem): bool =
      let item = item.GitFileSelectorItem

      if item.info.stagedStatus != None:
        asyncCheck self.diffStagedFileAsync(item.info.path)

      else:
        let currentVersionEditor = if item.workspaceFolder.isSome:
          self.openWorkspaceFile(item.path, item.workspaceFolder.get)
        else:
          self.openFile(item.path)

        if currentVersionEditor.getSome(editor):
          if editor of TextDocumentEditor:
            editor.TextDocumentEditor.updateDiff()
      return true

    popup.addCustomCommand "stage-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
      if popup.textEditor.isNil:
        return false
      if popup.completions.len == 0:
        return false

      asyncCheck popup.stageSelectedFileAsync()
      return true

    popup.addCustomCommand "unstage-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
      if popup.textEditor.isNil:
        return false
      if popup.completions.len == 0:
        return false

      asyncCheck popup.unstageSelectedFileAsync()
      return true

    popup.addCustomCommand "revert-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
      if popup.textEditor.isNil:
        return false
      if popup.completions.len == 0:
        return false

      asyncCheck popup.revertSelectedFileAsync()
      return true

    popup.addCustomCommand "diff-staged", proc(popup: SelectorPopup, args: JsonNode): bool =
      if popup.textEditor.isNil:
        return false
      if popup.completions.len == 0:
        return false

      let item = popup.completions[popup.completions.high - popup.selected].GitFileSelectorItem
      asyncCheck self.diffStagedFileAsync(item.info.path)
      return true

    popup.updateCompletions()

    self.pushPopup popup

type ExplorerFileSelectorItem* = ref object of FileSelectorItem
  isFile*: bool = false

when not defined(js):
  proc getItemsFromDirectory(popup: SelectorPopup, workspace: WorkspaceFolder, directory: string): Future[seq[SelectorItem]] {.async.} =
    if popup.updateInProgress:
      return popup.completions

    popup.updateInProgress = true
    defer:
      popup.updateInProgress = false

    if not popup.updated:
      let listing = await workspace.getDirectoryListing(directory)
      if popup.textEditor.isNil:
        return popup.completions

      let text = popup.getSearchString()

      var completions = newSeq[SelectorItem]()

      # todo: use unicode icons on all targets once rendering is fixed
      const fileIcon = "🗎 "
      const folderIcon = "🗀"

      for file in listing.files:
        let score = matchFuzzySublime(text, file, defaultPathMatchingConfig).score.float
        completions.add ExplorerFileSelectorItem(path: file, name: fileIcon & " " & file, isFile: true, score: score, workspaceFolder: workspace.some)

      for dir in listing.folders:
        let score = matchFuzzySublime(text, dir, defaultPathMatchingConfig).score.float
        completions.add ExplorerFileSelectorItem(path: dir, name: folderIcon & " " & dir, isFile: false, score: score, workspaceFolder: workspace.some)

      return completions
    else:
      let text = popup.getSearchString()
      for item in popup.completions.mitems:
        item.hasCompletionMatchPositions = false
        item.score = matchFuzzySublime(text, item.ExplorerFileSelectorItem.path, defaultPathMatchingConfig).score.float
      return popup.completions

proc exploreFiles*(self: App) {.expose("editor").} =
  when not defined(js):
    defer:
      self.platform.requestRender()

    if self.workspace.folders.len == 0:
      log lvlError, &"Failed to open file explorer, no workspace"
      return

    let workspace = self.workspace.folders[0]

    var popup = newSelectorPopup(self.asAppInterface, "file-explorer".some)
    popup.scale.x = 0.4

    let currentDirectory = new string
    currentDirectory[] = ""

    popup.getCompletionsAsync = proc(popup: SelectorPopup, text: string): Future[seq[SelectorItem]] =
      return popup.getItemsFromDirectory(workspace, currentDirectory[])

    popup.handleItemConfirmed = proc(item: SelectorItem): bool =
      let item = item.ExplorerFileSelectorItem
      if item.isFile:
        if item.workspaceFolder.isSome:
          discard self.openWorkspaceFile(item.path, item.workspaceFolder.get)
        else:
          discard self.openFile(item.path)
        return true
      else:
        currentDirectory[] = item.path
        popup.textEditor.document.content = ""
        popup.updated = false
        popup.updateCompletions()
        return false

    popup.addCustomCommand "go-up", proc(popup: SelectorPopup, args: JsonNode): bool =
      let parent = currentDirectory[].parentDir
      log lvlInfo, fmt"go up: {currentDirectory[]} -> {parent}"
      currentDirectory[] = parent

      popup.textEditor.document.content = ""

      popup.updated = false
      popup.updateCompletions()
      return false

    popup.sortFunction = proc(a, b: SelectorItem): int = cmp(a.FileSelectorItem.score, b.FileSelectorItem.score)
    popup.updateCompletions()
    popup.enableAutoSort()

    self.pushPopup popup

type TextSymbolSelectorItem* = ref object of SelectorItem
  symbol*: Symbol

method changed*(self: TextSymbolSelectorItem, other: SelectorItem): bool =
  let other = other.TextSymbolSelectorItem
  return self.symbol != other.symbol

method itemToJson*(self: TextSymbolSelectorItem): JsonNode = self[].toJson

proc openSymbolsPopup*(self: App, symbols: seq[Symbol], handleItemSelected: proc(symbol: Symbol), handleItemConfirmed: proc(symbol: Symbol), handleCanceled: proc()) =
  defer:
    self.platform.requestRender()

  let fuzzyMatchSublime = self.configProvider.getFlag("editor.fuzzy-match-sublime", true)

  var popup = newSelectorPopup(self.asAppInterface)
  popup.getCompletions = proc(popup: SelectorPopup, text: string): seq[SelectorItem] =
    for i in countdown(symbols.high, 0):
      let score = if fuzzyMatchSublime:
        matchFuzzySublime(text, symbols[i].name, defaultPathMatchingConfig).score.float
      else:
        matchFuzzy(symbols[i].name, text)

      result.add TextSymbolSelectorItem(symbol: symbols[i], score: score)

    if text.len > 0:
      result.sort((a, b) => cmp(a.TextSymbolSelectorItem.score, b.TextSymbolSelectorItem.score), Ascending)

  popup.handleItemSelected = proc(item: SelectorItem) =
    let symbol = item.TextSymbolSelectorItem.symbol
    handleItemSelected(symbol)

  popup.handleItemConfirmed = proc(item: SelectorItem): bool =
    let symbol = item.TextSymbolSelectorItem.symbol
    handleItemConfirmed(symbol)
    return true

  popup.handleCanceled = handleCanceled

  popup.updateCompletions()

  self.pushPopup popup

proc openPreviousEditor*(self: App) {.expose("editor").} =
  if self.editorHistory.len == 0:
    return

  let editor = self.editorHistory.popLast

  if self.currentView >= 0 and self.currentView < self.views.len:
    self.editorHistory.addFirst self.views[self.currentView].editor.id

  discard self.tryOpenExisting(editor, addToHistory=false)
  self.platform.requestRender()

proc openNextEditor*(self: App) {.expose("editor").} =
  if self.editorHistory.len == 0:
    return

  let editor = self.editorHistory.popFirst

  if self.currentView >= 0 and self.currentView < self.views.len:
    self.editorHistory.addLast self.views[self.currentView].editor.id

  discard self.tryOpenExisting(editor, addToHistory=false)
  self.platform.requestRender()

proc setGithubAccessToken*(self: App, token: string) {.expose("editor").} =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  fs.saveApplicationFile("GithubAccessToken", token)

proc clearScriptActionsFor(self: App, scriptContext: ScriptContext) =
  var keysToRemove: seq[string]
  for (key, value) in self.scriptActions.pairs:
    if value.scriptContext == scriptContext:
      keysToRemove.add key

  for key in keysToRemove:
    self.scriptActions.del key

proc reloadConfigAsync*(self: App) {.async.} =
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

  if self.scriptContext.isNotNil:
    try:
      self.clearScriptActionsFor(self.scriptContext)
      withScriptContext self, self.scriptContext:
        await self.scriptContext.reload()
      if not self.initializeCalled:
        withScriptContext self, self.scriptContext:
          discard self.scriptContext.postInitialize()
        self.initializeCalled = true
    except CatchableError:
      log lvlError, &"Failed to reload nimscript config: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc reloadConfig*(self: App) {.expose("editor").} =
  asyncCheck self.reloadConfigAsync()

proc reloadState*(self: App) {.expose("editor").} =
  ## Reloads some of the state stored in the session file (default: config/config.json)
  var state = EditorState()
  if self.sessionFile != "":
    self.restoreStateFromConfig(state)
  self.requestRender()

proc saveSession*(self: App, sessionFile: string = "") {.expose("editor").} =
  ## Reloads some of the state stored in the session file (default: config/config.json)
  self.sessionFile = sessionFile
  if self.sessionFile != "":
    self.saveAppState()
  self.requestRender()

proc logOptions*(self: App) {.expose("editor").} =
  log(lvlInfo, self.options.pretty)

proc clearCommands*(self: App, context: string) {.expose("editor").} =
  log(lvlInfo, fmt"Clearing keybindings for {context}")
  self.getEventHandlerConfig(context).clearCommands()

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
    self.modeEventHandler = eventHandler(config):
      onAction:
        if self.handleAction(action, arg, record=true):
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
  elif self.currentView >= 0 and self.currentView < self.views.len:
    result.add self.views[self.currentView].editor.getEventHandlers(initTable[string, EventHandler]())

  if not self.modeEventHandler.isNil and modeOnTop:
    result.add self.modeEventHandler

proc handleMousePress*(self: App, button: MouseButton, modifiers: Modifiers, mousePosWindow: Vec2) =
  # Check popups
  for i in 0..self.popups.high:
    let popup = self.popups[self.popups.high - i]
    if popup.lastBounds.contains(mousePosWindow):
      popup.handleMousePress(button, mousePosWindow)
      return

  # Check views
  let rects = self.layout.layoutViews(self.layout_props, self.lastBounds, self.views.len)
  for i, view in self.views:
    if i >= rects.len:
      return
    if rects[i].contains(mousePosWindow):
      self.currentView = i
      view.editor.handleMousePress(button, mousePosWindow, modifiers)
      return

proc handleMouseRelease*(self: App, button: MouseButton, modifiers: Modifiers, mousePosWindow: Vec2) =
  # Check popups
  for i in 0..self.popups.high:
    let popup = self.popups[self.popups.high - i]
    if popup.lastBounds.contains(mousePosWindow):
      popup.handleMouseRelease(button, mousePosWindow)
      return

  # Check views
  let rects = self.layout.layoutViews(self.layout_props, self.lastBounds, self.views.len)
  for i, view in self.views:
    if i >= rects.len:
      return
    if self.currentView == i and rects[i].contains(mousePosWindow):
      view.editor.handleMouseRelease(button, mousePosWindow)
      return

proc handleMouseMove*(self: App, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
  # Check popups
  for i in 0..self.popups.high:
    let popup = self.popups[self.popups.high - i]
    if popup.lastBounds.contains(mousePosWindow):
      popup.handleMouseMove(mousePosWindow, mousePosDelta, modifiers, buttons)
      return

  # Check views
  let rects = self.layout.layoutViews(self.layout_props, self.lastBounds, self.views.len)
  for i, view in self.views:
    if i >= rects.len:
      return
    if self.currentView == i and rects[i].contains(mousePosWindow):
      view.editor.handleMouseMove(mousePosWindow, mousePosDelta, modifiers, buttons)
      return

proc handleScroll*(self: App, scroll: Vec2, mousePosWindow: Vec2, modifiers: Modifiers) =
  # Check popups
  for i in 0..self.popups.high:
    let popup = self.popups[self.popups.high - i]
    if popup.lastBounds.contains(mousePosWindow):
      popup.handleScroll(scroll, mousePosWindow)
      return

  # Check views
  for i, view in self.views:
    if view.editor.lastContentBounds.contains(mousePosWindow):
      view.editor.handleScroll(scroll, mousePosWindow)
      return

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
  # debugf"handleKeyPress {inputToString(input, modifiers)}"
  self.logFrameTime = true

  for register in self.recordingKeys:
    if not self.registers.contains(register) or self.registers[register].kind != RegisterKind.Text:
      self.registers[register] = Register(kind: Text, text: "")
    self.registers[register].text.add inputToString(input, modifiers)

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

proc handleKeyRelease*(self: App, input: int64, modifiers: Modifiers) =
  discard

proc handleRune*(self: App, input: int64, modifiers: Modifiers) =
  # debugf"handleRune {inputToString(input, modifiers)}"
  self.logFrameTime = true

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

proc handleDropFile*(self: App, path, content: string) =
  let document = newTextDocument(self.asConfigProvider, path, content)
  self.documents.add document
  discard self.createAndAddView(document)

proc scriptRunAction*(action: string, arg: string) {.expose("editor").} =
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

proc addCommandScript*(self: App, context: string, subContext: string, keys: string, action: string, arg: string = "") {.expose("editor").} =
  let command = if arg.len == 0: action else: action & " " & arg
  # log(lvlInfo, fmt"Adding command to '{context}': ('{subContext}', '{keys}', '{command}')")

  let (context, subContext) = if (let i = context.find('#'); i != -1):
    (context[0..<i], context[i+1..^1] & subContext)
  else:
    (context, subContext)

  self.getEventHandlerConfig(context).addCommand(subContext, keys, command)

proc removeCommand*(self: App, context: string, keys: string) {.expose("editor").} =
  # log(lvlInfo, fmt"Removing command from '{context}': '{keys}'")
  self.getEventHandlerConfig(context).removeCommand(keys)

proc getActivePopup*(): EditorId {.expose("editor").} =
  if gEditor.isNil:
    return EditorId(-1)
  if gEditor.popups.len > 0:
    return gEditor.popups[gEditor.popups.high].id

  return EditorId(-1)

proc getActiveEditor*(): EditorId {.expose("editor").} =
  if gEditor.isNil:
    return EditorId(-1)
  if gEditor.commandLineMode:
    return gEditor.commandLineTextEditor.id
  if gEditor.currentView >= 0 and gEditor.currentView < gEditor.views.len:
    return gEditor.views[gEditor.currentView].editor.id

  return EditorId(-1)

when defined(js):
  proc getActiveEditor2*(self: App): DocumentEditor {.expose("editor"), nodispatch, nojsonwrapper.} =
    if gEditor.isNil:
      return nil
    if gEditor.commandLineMode:
      return gEditor.commandLineTextEditor
    if gEditor.currentView >= 0 and gEditor.currentView < gEditor.views.len:
      return gEditor.views[gEditor.currentView].editor

    return nil
else:
  proc getActiveEditor2*(self: App): EditorId {.expose("editor").} =
    ## Returns the active editor instance
    return getActiveEditor()

proc loadCurrentConfig*(self: App) {.expose("editor").} =
  ## Opens the default config file in a new view.
  let document = newTextDocument(self.asConfigProvider, "./config/absytree_config.nim", fs.loadApplicationFile("./config/absytree_config.nim"), true)
  self.documents.add document
  discard self.createAndAddView(document)

proc logRootNode*(self: App) {.expose("editor").} =
  let str = self.platform.builder.root.dump(true)
  debug "logRootNode: ", str

proc sourceCurrentDocument*(self: App) {.expose("editor").} =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  when defined(js):
    proc evalJs(str: cstring) {.importjs("eval(#)").}
    proc confirmJs(msg: cstring): bool {.importjs("confirm(#)").}
    let editor = self.getActiveEditor2()
    if editor of TextDocumentEditor:
      let document = editor.TextDocumentEditor.document
      let contentStrict = "\"use strict\";\n" & document.contentString
      log lvlWarn, contentStrict

      if confirmJs((fmt"You are about to eval() some javascript ({document.filename}). Look in the console to see what's in there.").cstring):
        evalJs(contentStrict.cstring)
      else:
        log(lvlWarn, fmt"Did not load config file because user declined.")

proc getEditor*(index: int): EditorId {.expose("editor").} =
  if gEditor.isNil:
    return EditorId(-1)
  if index >= 0 and index < gEditor.views.len:
    return gEditor.views[index].editor.id

  return EditorId(-1)

proc scriptIsSelectorPopup*(editorId: EditorId): bool {.expose("editor").} =
  if gEditor.isNil:
    return false
  if gEditor.getPopupForId(editorId).getSome(popup):
    return popup of SelectorPopup
  return false

proc scriptIsTextEditor*(editorId: EditorId): bool {.expose("editor").} =
  if gEditor.isNil:
    return false
  if gEditor.getEditorForId(editorId).getSome(editor):
    return editor of TextDocumentEditor
  return false

proc scriptIsAstEditor*(editorId: EditorId): bool {.expose("editor").} =
  return false

proc scriptIsModelEditor*(editorId: EditorId): bool {.expose("editor").} =
  if gEditor.isNil:
    return false
  when enableAst:
    if gEditor.getEditorForId(editorId).getSome(editor):
      return editor of ModelDocumentEditor
  return false

proc scriptRunActionFor*(editorId: EditorId, action: string, arg: string) {.expose("editor").} =
  if gEditor.isNil:
    return
  defer:
    gEditor.platform.requestRender()
  if gEditor.getEditorForId(editorId).getSome(editor):
    discard editor.handleAction(action, arg, record=false)
  elif gEditor.getPopupForId(editorId).getSome(popup):
    discard popup.eventHandler.handleAction(action, arg)

proc scriptInsertTextInto*(editorId: EditorId, text: string) {.expose("editor").} =
  if gEditor.isNil:
    return
  defer:
    gEditor.platform.requestRender()
  if gEditor.getEditorForId(editorId).getSome(editor):
    discard editor.eventHandler.handleInput(text)

proc scriptTextEditorSelection*(editorId: EditorId): Selection {.expose("editor").} =
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
  if gEditor.isNil:
    return
  defer:
    gEditor.platform.requestRender()
  if gEditor.getEditorForId(editorId).getSome(editor):
    if editor of TextDocumentEditor:
      editor.TextDocumentEditor.selection = selection

proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] {.expose("editor").} =
  if gEditor.isNil:
    return @[((0, 0), (0, 0))]
  if gEditor.getEditorForId(editorId).getSome(editor):
    if editor of TextDocumentEditor:
      let editor = TextDocumentEditor(editor)
      return editor.selections
  return @[((0, 0), (0, 0))]

proc scriptSetTextEditorSelections*(editorId: EditorId, selections: seq[Selection]) {.expose("editor").} =
  if gEditor.isNil:
    return
  defer:
    gEditor.platform.requestRender()
  if gEditor.getEditorForId(editorId).getSome(editor):
    if editor of TextDocumentEditor:
      editor.TextDocumentEditor.selections = selections

proc scriptGetTextEditorLine*(editorId: EditorId, line: int): string {.expose("editor").} =
  if gEditor.isNil:
    return ""
  if gEditor.getEditorForId(editorId).getSome(editor):
    if editor of TextDocumentEditor:
      let editor = TextDocumentEditor(editor)
      if line >= 0 and line < editor.document.content.len:
        return editor.document.content[line]
  return ""

proc scriptGetTextEditorLineCount*(editorId: EditorId): int {.expose("editor").} =
  if gEditor.isNil:
    return 0
  if gEditor.getEditorForId(editorId).getSome(editor):
    if editor of TextDocumentEditor:
      let editor = TextDocumentEditor(editor)
      return editor.document.content.len
  return 0

template createScriptGetOption(path, default, accessor: untyped): untyped =
  block:
    if gEditor.isNil:
      return default
    let node = gEditor.options{path.split(".")}
    if node.isNil:
      return default
    accessor(node, default)

template createScriptSetOption(path, value: untyped): untyped =
  block:
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
  if gEditor.isNil:
    return
  gEditor.callbacks[path] = id

proc setRegisterTextAsync*(self: App, text: string, register: string = ""): Future[void] {.async.} =
  self.registers[register] = Register(kind: Text, text: text)
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

proc setRegisterText*(self: App, text: string, register: string = "") {.expose("editor").} =
  self.registers[register] = Register(kind: Text, text: text)

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
  when not defined(js):
    log lvlInfo, "collectGarbage"
    GC_FullCollect()

proc printStatistics*(self: App) {.expose("editor").} =
  var result = "\n"
  result.add &"Backend: {self.backend}\n"

  result.add &"Registers:\n"
  for (key, value) in self.registers.pairs:
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
    # absytreeCommandsServer: LanguageServer
    # commandLineTextEditor: DocumentEditor

    # logDocument: Document
    # documents*: seq[Document]
    # editors*: Table[EditorId, DocumentEditor]
    # popups*: seq[Popup]

    # theme*: Theme
    # scriptContext*: ScriptContext
    # wasmScriptContext*: ScriptContextWasm

    # workspace*: Workspace
  result.add &"Platform:\n{self.platform.getStatisticsString().indent(4)}\n"
  result.add &"UI:\n{self.platform.builder.getStatisticsString().indent(4)}\n"

  log lvlInfo, result

genDispatcher("editor")
addGlobalDispatchTable "editor", genDispatchTable("editor")

proc recordCommand*(self: App, command: string, args: string) =
  for register in self.recordingCommands:
    if not self.registers.contains(register) or self.registers[register].kind != RegisterKind.Text:
      self.registers[register] = Register(kind: Text, text: "")
    if self.registers[register].text.len > 0:
      self.registers[register].text.add "\n"
    self.registers[register].text.add command & " " & args

proc handleAction(self: App, action: string, arg: string, record: bool): bool =
  # log(lvlInfo, "Action '$1 $2'" % [action, arg])

  if record:
    self.recordCommand(action, arg)

  if action.startsWith("."): # active action
    if self.currentView >= 0 and self.currentView < gEditor.views.len:
      let editor = self.views[gEditor.currentView].editor
      return case editor.handleAction(action[1..^1], arg, record=false)
      of Handled:
        true
      else:
        false

    log lvlError, fmt"No current view"
    return false

  var args = newJArray()
  try:
    for a in newStringStream(arg).parseJsonFragments():
      args.add a
  except CatchableError:
    log(lvlError, fmt"Failed to parse arguments '{arg}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

  try:
    withScriptContext self, self.scriptContext:
      if self.scriptContext.handleGlobalAction(action, args):
        return true
  except CatchableError:
    log(lvlError, fmt"Failed to run script handleGlobalAction '{action} {arg}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

  try:
    withScriptContext self, self.wasmScriptContext:
      if self.wasmScriptContext.handleGlobalAction(action, args):
        return true
  except CatchableError:
    log(lvlError, fmt"Failed to run script handleGlobalAction '{action} {arg}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

  try:
    withScriptContext self, self.scriptContext:
      let res = self.scriptContext.handleScriptAction(action, args)
      if res.isNotNil:
        return true

    withScriptContext self, self.wasmScriptContext:
      let res = self.wasmScriptContext.handleScriptAction(action, args)
      if res.isNotNil:
        return true
  except CatchableError:
    log(lvlError, fmt"Failed to dispatch action '{action} {arg}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

  try:
    return dispatch(action, args).isSome
  except CatchableError:
    log(lvlError, fmt"Failed to dispatch action '{action} {arg}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

  return true

template createNimScriptContextConstructorAndGenerateBindings*(): untyped =
  when enableNimscript and not defined(js):
    proc createAddins(): VmAddins =
      addCallable(myImpl):
        proc postInitialize(): bool
      addCallable(myImpl):
        proc handleGlobalAction(action: string, args: JsonNode): bool
      addCallable(myImpl):
        proc handleEditorAction(id: EditorId, action: string, args: JsonNode): bool
      addCallable(myImpl):
        proc handleEditorModeChanged(id: EditorId, oldMode: string, newMode: string)
      addCallable(myImpl):
        proc handleUnknownPopupAction(id: EditorId, action: string, args: JsonNode): bool
      addCallable(myImpl):
        proc handleCallback(id: int, args: JsonNode): bool
      addCallable(myImpl):
        proc handleScriptAction(name: string, args: JsonNode): JsonNode

      return implNimScriptModule(myImpl)

    const addins = createAddins()

    static:
      generateScriptingApi(addins)

    createScriptContextConstructor(addins)

    proc createScriptContextImpl(filepath: string, searchPaths: seq[string]): Future[Option[ScriptContext]] = createScriptContextNim(filepath, searchPaths)
    createScriptContext = createScriptContextImpl

  createEditorWasmImportConstructor()
