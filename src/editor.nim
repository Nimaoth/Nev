import std/[strformat, strutils, tables, logging, unicode, options, os, algorithm, json, jsonutils, macros, macrocache, sugar, streams, deques]
import input, id, events, rect_utils, document, document_editor, popup, timer, event, cancellation_token
import theme, util, custom_logger, custom_async, fuzzy_matching
import scripting/[expose, scripting_base]
import platform/[platform, widgets, filesystem]
import workspaces/[workspace]
import ast/types
import traits
import config_provider

when not defined(js):
  import scripting/scripting_nim
else:
  import scripting/scripting_js

import scripting/scripting_wasm

import scripting_api as api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, ModelDocumentEditor, Popup, SelectorPopup
from scripting_api import Backend

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
  ast: bool
  languageID: string
  appFile: bool
  workspaceId: string

type
  OpenWorkspaceKind {.pure.} = enum Local, AbsytreeServer, Github
  OpenWorkspace = object
    kind*: OpenWorkspaceKind
    id*: string
    name*: string
    settings*: JsonNode

type EditorState = object
  theme: string
  fontSize: float32
  fontRegular: string
  fontBold: string
  fontItalic: string
  fontBoldItalic: string
  workspaceFolders: seq[OpenWorkspace]
  openEditors: seq[OpenEditor]

type
  RegisterKind* {.pure.} = enum Text, AstNode
  Register* = object
    case kind*: RegisterKind
    of Text:
      text*: string
    of AstNode:
      node*: AstNode

type App* = ref object
  backend: api.Backend
  platform*: Platform
  fontRegular*: string
  fontBold*: string
  fontItalic*: string
  fontBoldItalic*: string
  clearAtlasTimer*: Timer
  timer*: Timer
  frameTimer*: Timer
  lastBounds*: Rect
  closeRequested*: bool

  widget*: WWidget

  registers*: Table[string, Register]

  eventHandlerConfigs: Table[string, EventHandlerConfig]

  options: JsonNode
  callbacks: Table[string, int]

  logger: Logger

  workspace*: Workspace

  scriptContext*: ScriptContext
  wasmScriptContext*: ScriptContextWasm
  initializeCalled: bool

  statusBarOnTop*: bool

  currentViewInternal: int
  views*: seq[View]
  hiddenViews*: seq[View]
  layout*: Layout
  layout_props*: LayoutProperties

  activeEditorInternal: Option[EditorId]
  editorHistory: Deque[EditorId]

  theme*: Theme
  loadedFontSize: float

  editors*: Table[EditorId, DocumentEditor]
  popups*: seq[Popup]

  onEditorRegistered*: Event[DocumentEditor]
  onEditorDeregistered*: Event[DocumentEditor]

  commandLineTextEditor: DocumentEditor
  eventHandler*: EventHandler
  commandLineEventHandler*: EventHandler
  commandLineMode*: bool

  modeEventHandler: EventHandler
  currentMode*: string

  editor_defaults: seq[DocumentEditor]

var gEditor* {.exportc.}: App = nil

proc setRegisterText*(self: App, text: string, register: string = "")
proc getRegisterText*(self: App, text: var string, register: string = "")
proc openWorkspaceFile*(self: App, path: string, folder: WorkspaceFolder): Option[DocumentEditor]
proc openFile*(self: App, path: string, app: bool = false): Option[DocumentEditor]

proc registerEditor*(self: App, editor: DocumentEditor) =
  self.editors[editor.id] = editor
  self.onEditorRegistered.invoke editor

proc unregisterEditor*(self: App, editor: DocumentEditor) =
  self.editors.del(editor.id)
  self.onEditorDeregistered.invoke editor

method injectDependencies*(self: DocumentEditor, ed: App) {.base.} =
  discard

proc invokeCallback*(self: App, context: string, args: JsonNode): bool =
  if not self.callbacks.contains(context):
    return false
  let id = self.callbacks[context]
  try:
    if self.scriptContext.invoke(handleCallback, id, args, returnType = bool):
      return true
    return self.wasmScriptContext.invoke(handleCallback, id, args, returnType = bool)
  except CatchableError:
    logger.log(lvlError, fmt"[ed] Failed to run script handleCallback {id}: {getCurrentExceptionMsg()}")
    logger.log(lvlError, getCurrentException().getStackTrace())
    return false

proc handleAction(action: string, arg: string): EventResponse =
  logger.log(lvlInfo, "event: " & action & " - " & arg)
  return Handled

proc handleInput(input: string): EventResponse =
  logger.log(lvlInfo, "input: " & input)
  return Handled

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

    if self.scriptContext.handleUnknownPopupAction(popup, action, args):
      return Handled
    if self.wasmScriptContext.handleUnknownPopupAction(popup, action, args):
      return Handled
  except CatchableError:
    logger.log(lvlError, fmt"[ed] Failed to run script handleUnknownPopupAction '{action} {arg}': {getCurrentExceptionMsg()}")
    logger.log(lvlError, getCurrentException().getStackTrace())

  return Failed

proc handleUnknownDocumentEditorAction*(self: App, editor: DocumentEditor, action: string, args: JsonNode): EventResponse =
  try:
    if self.scriptContext.handleUnknownDocumentEditorAction(editor, action, args):
      return Handled
    if self.wasmScriptContext.handleUnknownDocumentEditorAction(editor, action, args):
      return Handled
  except CatchableError:
    logger.log(lvlError, fmt"[ed] Failed to run script handleUnknownDocumentEditorAction '{action} {args}': {getCurrentExceptionMsg()}")
    logger.log(lvlError, getCurrentException().getStackTrace())

  return Failed

proc handleAction(self: App, action: string, arg: string): bool
proc getFlag*(self: App, flag: string, default: bool = false): bool

proc createEditorForDocument(self: App, document: Document): DocumentEditor =
  for editor in self.editor_defaults:
    if editor.canEdit document:
      return editor.createWithDocument document

  logger.log(lvlError, "No editor found which can edit " & $document)
  return nil

implTrait(ConfigProvider, App):
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

proc addView*(self: App, view: View, addToHistory = true) =
  self.views.insert(view, self.currentView)

  let maxViews = getOption[int](self, "editor.maxViews", int.high)
  while maxViews > 0 and self.views.len > maxViews:
    self.hiddenViews.add self.views.pop()

  self.updateActiveEditor(addToHistory)
  self.platform.requestRender()

proc createView*(self: App, document: Document): DocumentEditor =
  var editor = self.createEditorForDocument document
  editor.injectDependencies self
  discard editor.onMarkedDirty.subscribe () => self.platform.requestRender()
  var view = View(document: document, editor: editor)
  self.addView(view)
  return editor

proc pushPopup*(self: App, popup: Popup) =
  popup.init()
  self.popups.add popup
  discard popup.onMarkedDirty.subscribe () => self.platform.requestRender()
  self.platform.requestRender()

proc popPopup*(self: App, popup: Popup) =
  if self.popups.len > 0 and self.popups[self.popups.high] == popup:
    discard self.popups.pop
  self.platform.requestRender()

proc getEventHandlerConfig*(self: App, context: string): EventHandlerConfig =
  if not self.eventHandlerConfigs.contains(context):
    self.eventHandlerConfigs[context] = newEventHandlerConfig(context)
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

import text/text_editor, ast_document, model_document
import selector_popup

type ThemeSelectorItem* = ref object of SelectorItem
  name*: string
  path*: string

type FileSelectorItem* = ref object of SelectorItem
  path*: string
  workspaceFolder*: Option[WorkspaceFolder]

method changed*(self: FileSelectorItem, other: SelectorItem): bool =
  let other = other.FileSelectorItem
  return self.path != other.path

method changed*(self: ThemeSelectorItem, other: SelectorItem): bool =
  let other = other.ThemeSelectorItem
  return self.name != other.name or self.path != other.path

proc setTheme*(self: App, path: string) =
  if loadFromFile(path).getSome(theme):
    self.theme = theme
  self.platform.requestRender()

when not defined(js):
  proc createScriptContext(filepath: string, searchPaths: seq[string]): ScriptContext

proc getCommandLineTextEditor*(self: App): TextDocumentEditor = self.commandLineTextEditor.TextDocumentEditor

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

proc newEditor*(backend: api.Backend, platform: Platform): App =
  var self = App()

  # Emit this to set the editor prototype to editor_prototype, which needs to be set up before calling this
  when defined(js):
    {.emit: [self, " = jsCreateWithPrototype(editor_prototype, ", self, ");"].}
    # This " is here to fix syntax highlighting

  gEditor = self
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
  discard platform.onCloseRequested.subscribe proc(_: auto) = self.closeRequested = true

  self.timer = startTimer()
  self.frameTimer = startTimer()

  self.layout = HorizontalLayout()
  self.layout_props = LayoutProperties(props: {"main-split": 0.5.float32}.toTable)

  self.registers = initTable[string, Register]()

  self.platform.fontSize = 20

  self.fontRegular = "./fonts/DejaVuSansMono.ttf"
  self.fontBold = "./fonts/DejaVuSansMono-Bold.ttf"
  self.fontItalic = "./fonts/DejaVuSansMono-Oblique.ttf"
  self.fontBoldItalic = "./fonts/DejaVuSansMono-BoldOblique.ttf"

  self.editor_defaults = @[TextDocumentEditor(), AstDocumentEditor(), ModelDocumentEditor()]

  self.workspace.new()

  self.theme = defaultTheme()
  self.setTheme("./themes/tokyo-night-color-theme.json")

  # self.createView(newAstDocument("a.ast"))
  # self.createView(newKeybindAutocompletion())
  self.currentView = 0

  self.getEventHandlerConfig("editor").addCommand "<C-x><C-x>", "quit"
  self.getEventHandlerConfig("editor").addCommand "<CAS-r>", "reload-config"

  self.options = newJObject()

  self.eventHandler = eventHandler(self.getEventHandlerConfig("editor")):
    onAction:
      if self.handleAction(action, arg):
        Handled
      else:
        Ignored
    onInput:
      Ignored
  self.commandLineEventHandler = eventHandler(self.getEventHandlerConfig("commandLine")):
    onAction:
      if self.handleAction(action, arg):
        Handled
      else:
        Ignored
    onInput:
      Ignored
  self.commandLineMode = false

  self.commandLineTextEditor = newTextEditor(newTextDocument(self.asConfigProvider), self)
  self.commandLineTextEditor.renderHeader = false
  self.commandLineTextEditor.TextDocumentEditor.lineNumbers = api.LineNumbers.None.some
  self.getCommandLineTextEditor.hideCursorWhenInactive = true

  var state = EditorState()
  try:
    state = fs.loadApplicationFile("./config/config.json").parseJson.jsonTo(EditorState, JOptions(allowMissingKeys: true, allowExtraKeys: true))
    self.setTheme(state.theme)
    self.loadedFontSize = state.fontSize.float
    self.platform.fontSize = state.fontSize.float
    if state.fontRegular.len > 0: self.fontRegular = state.fontRegular
    if state.fontBold.len > 0: self.fontBold = state.fontBold
    if state.fontItalic.len > 0: self.fontItalic = state.fontItalic
    if state.fontBoldItalic.len > 0: self.fontBoldItalic = state.fontBoldItalic

    self.options = fs.loadApplicationFile("./config/options.json").parseJson
    # logger.log(lvlInfo, fmt"Restoring options: {self.options.pretty}")

  except CatchableError:
    logger.log(lvlError, fmt"Failed to load previous state from config file: {getCurrentExceptionMsg()}")

  if self.getFlag("editor.restore-open-workspaces"):
    for wf in state.workspaceFolders:
      var folder: WorkspaceFolder = case wf.kind
      of OpenWorkspaceKind.Local: newWorkspaceFolderLocal(wf.settings)
      of OpenWorkspaceKind.AbsytreeServer: newWorkspaceFolderAbsytreeServer(wf.settings)
      of OpenWorkspaceKind.Github: newWorkspaceFolderGithub(wf.settings)

      folder.id = wf.id.parseId
      folder.name = wf.name
      if self.addWorkspaceFolder(folder):
        logger.log(lvlInfo, fmt"Restoring workspace {folder.name} ({folder.id})")

  try:
    var searchPaths = @["src", "scripting"]
    let searchPathsJson = self.options{@["scripting", "search-paths"]}
    if not searchPathsJson.isNil:
      for sp in searchPathsJson:
        searchPaths.add sp.getStr

    when defined(js):
      self.scriptContext = new ScriptContextJs
    else:
      self.scriptContext = createScriptContext("./config/absytree_config_wasm.nim", searchPaths)

    self.wasmScriptContext = new ScriptContextWasm

    logger.log(lvlInfo, fmt"[editor] init wasm configs")
    self.wasmScriptContext.init("./config")
    logger.log(lvlInfo, fmt"[editor] post init wasm configs")
    discard self.wasmScriptContext.invoke(postInitialize, returnType = bool)

    logger.log(lvlInfo, fmt"[editor] init nim script config")
    self.scriptContext.init("./config")
    logger.log(lvlInfo, fmt"[editor] post init nim script config")
    discard self.scriptContext.invoke(postInitialize, returnType = bool)

    logger.log(lvlInfo, fmt"[editor] finished configs")
    self.initializeCalled = true
  except CatchableError:
    logger.log(lvlError, fmt"Failed to load config: {(getCurrentExceptionMsg())}{'\n'}{(getCurrentException().getStackTrace())}")

  # Restore open editors
  if self.getFlag("editor.restore-open-editors"):
    for editorState in state.openEditors:
        let workspaceFolder = self.getWorkspaceFolder(editorState.workspaceId.parseId)
        let document = if editorState.ast:
          newAstDocument(editorState.filename, editorState.appFile, workspaceFolder)
        elif editorState.filename.endsWith ".am":
          try:
            newModelDocument(editorState.filename, editorState.appFile, workspaceFolder)
          except CatchableError:
            logger.log(lvlError, fmt"Failed to restore file {editorState.filename} from previous session: {getCurrentExceptionMsg()}")
            continue
        else:
          try:
            newTextDocument(self.asConfigProvider, editorState.filename, editorState.appFile, workspaceFolder)
          except CatchableError:
            logger.log(lvlError, fmt"Failed to restore file {editorState.filename} from previous session: {getCurrentExceptionMsg()}")
            continue

        discard self.createView(document)

  return self

proc saveAppState*(self: App)

proc shutdown*(self: App) =
  self.saveAppState()

  for editor in self.editors.values:
    editor.shutdown()

proc getEditor(): Option[App] =
  if gEditor.isNil: return App.none
  return gEditor.some

static:
  addInjector(App, getEditor)

proc getBackend*(self: App): Backend {.expose("editor").} =
  return self.backend

proc saveAppState*(self: App) {.expose("editor").} =
  # Save some state
  var state = EditorState()
  state.theme = self.theme.path

  if self.backend == api.Backend.Terminal:
    state.fontSize = self.loadedFontSize
  else:
    state.fontSize = self.platform.fontSize

  state.fontRegular = self.fontRegular
  state.fontBold = self.fontBold
  state.fontItalic = self.fontItalic
  state.fontBoldItalic = self.fontBoldItalic

  # Save open workspace folders
  for workspaceFolder in self.workspace.folders:
    let kind = if workspaceFolder of WorkspaceFolderLocal:
      OpenWorkspaceKind.Local
    elif workspaceFolder of WorkspaceFolderAbsytreeServer:
      OpenWorkspaceKind.AbsytreeServer
    elif workspaceFolder of WorkspaceFolderGithub:
      OpenWorkspaceKind.Github
    else:
      continue

    state.workspaceFolders.add OpenWorkspace(
      kind: kind,
      id: $workspaceFolder.id,
      name: workspaceFolder.name,
      settings: workspaceFolder.settings
    )

  # Save open editors
  for view in self.views:
    if view.document of TextDocument:
      let textDocument = TextDocument(view.document)
      state.openEditors.add OpenEditor(
        filename: textDocument.filename, ast: false, languageId: textDocument.languageId, appFile: textDocument.appFile,
        workspaceId: textDocument.workspace.map(wf => $wf.id).get("")
        )
    elif view.document of AstDocument:
      let astDocument = AstDocument(view.document)
      state.openEditors.add OpenEditor(
        filename: astDocument.filename, ast: true, languageId: "ast", appFile: astDocument.appFile,
        workspaceId: astDocument.workspace.map(wf => $wf.id).get("")
        )
    elif view.document of ModelDocument:
      let astDocument = ModelDocument(view.document)
      state.openEditors.add OpenEditor(
        filename: astDocument.filename, ast: false, languageId: "am", appFile: astDocument.appFile,
        workspaceId: astDocument.workspace.map(wf => $wf.id).get("")
        )

  let serialized = state.toJson
  fs.saveApplicationFile("./config/config.json", serialized.pretty)
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

proc openWorkspaceKind(workspaceFolder: WorkspaceFolder): OpenWorkspaceKind =
  if workspaceFolder of WorkspaceFolderLocal:
    return OpenWorkspaceKind.Local
  if workspaceFolder of WorkspaceFolderAbsytreeServer:
    return OpenWorkspaceKind.AbsytreeServer
  if workspaceFolder of WorkspaceFolderGithub:
    return OpenWorkspaceKind.Github
  assert false

proc addWorkspaceFolder(self: App, workspaceFolder: WorkspaceFolder): bool =
  for wf in self.workspace.folders:
    if wf.openWorkspaceKind == workspaceFolder.openWorkspaceKind and wf.settings == workspaceFolder.settings:
      return false
  if workspaceFolder.id == idNone():
    workspaceFolder.id = newId()
  logger.log(lvlInfo, fmt"Opening workspace {workspaceFolder.name}")
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

when not defined(js):
  proc openLocalWorkspace*(self: App, path: string) {.expose("editor").} =
    let path = if path.isAbsolute: path else: path.absolutePath
    discard self.addWorkspaceFolder newWorkspaceFolderLocal(path)

proc getFlag*(self: App, flag: string, default: bool = false): bool {.expose("editor").} =
  return getOption[bool](self, flag, default)

proc setFlag*(self: App, flag: string, value: bool) {.expose("editor").} =
  setOption[bool](self, flag, value)

proc toggleFlag*(self: App, flag: string) {.expose("editor").} =
  self.setFlag(flag, not self.getFlag(flag))
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

proc changeFontSize*(self: App, amount: float32) {.expose("editor").} =
  self.platform.fontSize = self.platform.fontSize + amount.float
  self.platform.requestRender(true)

proc changeLayoutProp*(self: App, prop: string, change: float32) {.expose("editor").} =
  self.layout_props.props.mgetOrPut(prop, 0) += change
  self.platform.requestRender(true)

proc toggleStatusBarLocation*(self: App) {.expose("editor").} =
  self.statusBarOnTop = not self.statusBarOnTop
  self.platform.requestRender(true)

proc createView*(self: App) {.expose("editor").} =
  discard self.createView(newTextDocument(self.asConfigProvider))

# proc createKeybindAutocompleteView*(self: App) {.expose("editor").} =
#   self.createView(newKeybindAutocompletion())

proc closeCurrentView*(self: App) {.expose("editor").} =
  self.views[self.currentView].editor.unregister()
  self.views.delete self.currentView
  self.currentView = self.currentView.clamp(0, self.views.len - 1)
  self.platform.requestRender()

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
    else: HorizontalLayout()
  self.platform.requestRender()

proc commandLine*(self: App, initialValue: string = "") {.expose("editor").} =
  self.getCommandLineTextEditor.document.content = @[initialValue]
  self.commandLineMode = true
  self.platform.requestRender()

proc exitCommandLine*(self: App) {.expose("editor").} =
  self.getCommandLineTextEditor.document.content = @[""]
  self.commandLineMode = false
  self.platform.requestRender()

proc executeCommandLine*(self: App): bool {.expose("editor").} =
  defer:
    self.platform.requestRender()
  self.commandLineMode = false
  var (action, arg) = self.getCommandLineTextEditor.document.content.join("").parseAction
  self.getCommandLineTextEditor.document.content = @[""]

  if arg.startsWith("\\"):
    arg = $newJString(arg[1..^1])

  return self.handleAction(action, arg)

proc writeFile*(self: App, path: string = "", app: bool = false) {.expose("editor").} =
  defer:
    self.platform.requestRender()
  if self.currentView >= 0 and self.currentView < self.views.len and self.views[self.currentView].document != nil:
    try:
      self.views[self.currentView].document.save(path, app)
    except CatchableError:
      logger.log(lvlError, fmt"[ed] Failed to write file '{path}': {getCurrentExceptionMsg()}")
      logger.log(lvlError, getCurrentException().getStackTrace())

proc loadFile*(self: App, path: string = "") {.expose("editor").} =
  defer:
    self.platform.requestRender()
  if self.currentView >= 0 and self.currentView < self.views.len and self.views[self.currentView].document != nil:
    try:
      self.views[self.currentView].document.load(path)
      self.views[self.currentView].editor.handleDocumentChanged()
    except CatchableError:
      logger.log(lvlError, fmt"[ed] Failed to load file '{path}': {getCurrentExceptionMsg()}")
      logger.log(lvlError, getCurrentException().getStackTrace())

proc loadWorkspaceFile*(self: App, path: string, folder: WorkspaceFolder) =
  defer:
    self.platform.requestRender()
  if self.currentView >= 0 and self.currentView < self.views.len and self.views[self.currentView].document != nil:
    try:
      self.views[self.currentView].document.workspace = folder.some
      self.views[self.currentView].document.load(path)
      self.views[self.currentView].editor.handleDocumentChanged()
    except CatchableError:
      logger.log(lvlError, fmt"[ed] Failed to load file '{path}': {getCurrentExceptionMsg()}")
      logger.log(lvlError, getCurrentException().getStackTrace())

proc tryOpenExisting*(self: App, path: string, folder: Option[WorkspaceFolder]): Option[DocumentEditor] =
  for i, view in self.views:
    if view.document.filename == path and view.document.workspace == folder:
      logger.log(lvlInfo, fmt"Reusing open editor in view {i}")
      self.currentView = i
      return view.editor.some

  for i, view in self.hiddenViews:
    if view.document.filename == path and view.document.workspace == folder:
      logger.log(lvlInfo, fmt"Reusing hidden view")
      self.hiddenViews.delete i
      self.addView(view)
      return view.editor.some

  return DocumentEditor.none

proc tryOpenExisting*(self: App, editor: EditorId, addToHistory = true): Option[DocumentEditor] =
  for i, view in self.views:
    if view.editor.id == editor:
      logger.log(lvlInfo, fmt"Reusing open editor in view {i}")
      `currentView=`(self, i, addToHistory)
      return view.editor.some

  for i, view in self.hiddenViews:
    if view.editor.id == editor:
      logger.log(lvlInfo, fmt"Reusing hidden view")
      self.hiddenViews.delete i
      self.addView(view, addToHistory)
      return view.editor.some

  return DocumentEditor.none

proc openFile*(self: App, path: string, app: bool = false): Option[DocumentEditor] =
  defer:
    self.platform.requestRender()

  if self.tryOpenExisting(path, WorkspaceFolder.none).isSome:
    return

  try:
    if path.endsWith(".ast"):
      return self.createView(newAstDocument(path, app, WorkspaceFolder.none)).some
    elif path.endsWith(".am"):
      return self.createView(newModelDocument(path, app, WorkspaceFolder.none)).some
    else:
      let file = if app: fs.loadApplicationFile(path) else: fs.loadFile(path)
      return self.createView(newTextDocument(self.asConfigProvider, path, file.splitLines, app)).some
  except CatchableError:
    logger.log(lvlError, fmt"[ed] Failed to load file '{path}': {getCurrentExceptionMsg()}")
    logger.log(lvlError, getCurrentException().getStackTrace())
    return DocumentEditor.none

proc openWorkspaceFile*(self: App, path: string, folder: WorkspaceFolder): Option[DocumentEditor] =
  defer:
    self.platform.requestRender()

  if self.tryOpenExisting(path, folder.some).getSome(editor):
    return editor.some

  try:
    if path.endsWith(".ast"):
      return self.createView(newAstDocument(path, false, folder.some)).some
    elif path.endsWith(".am"):
      return self.createView(newModelDocument(path, false, folder.some)).some
    else:
      return self.createView(newTextDocument(self.asConfigProvider, path, false, folder.some)).some

  except CatchableError:
    logger.log(lvlError, fmt"[ed] Failed to load file '{path}': {getCurrentExceptionMsg()}")
    logger.log(lvlError, getCurrentException().getStackTrace())
    return DocumentEditor.none

proc removeFromLocalStorage*(self: App) {.expose("editor").} =
  ## Browser only
  ## Clears the content of the current document in local storage
  when defined(js):
    proc clearStorage(path: cstring) {.importjs: "window.localStorage.removeItem(#);".}
    if self.currentView >= 0 and self.currentView < self.views.len and self.views[self.currentView].document != nil:
      let filename = if self.views[self.currentView].document of TextDocument:
        self.views[self.currentView].document.TextDocument.filename
      else:
        self.views[self.currentView].document.AstDocument.filename
      clearStorage(filename.cstring)

proc loadTheme*(self: App, name: string) {.expose("editor").} =
  defer:
    self.platform.requestRender()
  if theme.loadFromFile(fmt"./themes/{name}.json").getSome(theme):
    self.theme = theme
  else:
    logger.log(lvlError, fmt"[ed] Failed to load theme {name}")

proc chooseTheme*(self: App) {.expose("editor").} =
  defer:
    self.platform.requestRender()
  let originalTheme = self.theme.path

  var popup = self.newSelectorPopup()
  popup.getCompletions = proc(popup: SelectorPopup, text: string): seq[SelectorItem] =
    for file in walkDirRec("./themes", relative=true):
      if file.endsWith ".json":
        let name = file.splitFile.name
        let score = matchPath(file, text)
        result.add ThemeSelectorItem(name: name, path: fmt"./themes/{file}", score: score)

    result.sort((a, b) => cmp(a.ThemeSelectorItem.score, b.ThemeSelectorItem.score), Descending)

  popup.handleItemSelected = proc(item: SelectorItem) =
    if theme.loadFromFile(item.ThemeSelectorItem.path).getSome(theme):
      self.theme = theme

  popup.handleItemConfirmed = proc(item: SelectorItem) =
    if theme.loadFromFile(item.ThemeSelectorItem.path).getSome(theme):
      self.theme = theme

  popup.handleCanceled = proc() =
    if theme.loadFromFile(originalTheme).getSome(theme):
      self.theme = theme

  popup.updateCompletions()

  self.pushPopup popup

proc getDirectoryListingRec(self: App, folder: WorkspaceFolder, path: string): Future[seq[string]] {.async.} =
  var resultItems: seq[string]

  let items = await folder.getDirectoryListing(path)
  for file in items.files:
    resultItems.add(path / file)

  var futs: seq[Future[seq[string]]]

  for dir in items.folders:
    futs.add self.getDirectoryListingRec(folder, path / dir)

  for fut in futs:
    let children = await fut
    resultItems.add children

  return resultItems

proc iterateDirectoryRec(self: App, folder: WorkspaceFolder, path: string, cancellationToken: CancellationToken, callback: proc(files: seq[string]): void): Future[void] {.async.} =
  let path = path
  var resultItems: seq[string]
  var folders: seq[string]

  if cancellationToken.canceled:
    return

  let items = await folder.getDirectoryListing(path)

  if cancellationToken.canceled:
    return

  for file in items.files:
    resultItems.add(path / file)

  for dir in items.folders:
    folders.add(path / dir)

  callback(resultItems)

  if cancellationToken.canceled:
    return

  var futs: seq[Future[void]]

  for dir in folders:
    futs.add self.iterateDirectoryRec(folder, dir, cancellationToken, callback)

  for fut in futs:
    await fut

proc chooseFile*(self: App, view: string = "new") {.expose("editor").} =
  defer:
    self.platform.requestRender()

  var popup = self.newSelectorPopup()
  popup.getCompletionsAsyncIter = proc(popup: SelectorPopup, text: string): Future[void] {.async.} =
    if not popup.cancellationToken.isNil:
      popup.cancellationToken.cancel()

    var cancellationToken = newCancellationToken()
    popup.cancellationToken = cancellationToken

    for folder in self.workspace.folders:
      var folder = folder
      await self.iterateDirectoryRec(folder, "", cancellationToken, proc(files: seq[string]) =
        let folder = folder
        for file in files:
          let score = matchPath(file, text)
          popup.completions.add FileSelectorItem(path: fmt"{file}", score: score, workspaceFolder: folder.some)

        popup.completions.sort((a, b) => cmp(a.FileSelectorItem.score, b.FileSelectorItem.score), Descending)
        popup.markDirty()
      )

  popup.handleItemConfirmed = proc(item: SelectorItem) =
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
      logger.log(lvlError, fmt"Unknown argument {view}")

  popup.updateCompletions()

  self.pushPopup popup

proc chooseOpen*(self: App, view: string = "new") {.expose("editor").} =
  defer:
    self.platform.requestRender()

  var popup = self.newSelectorPopup()
  popup.getCompletions = proc(popup: SelectorPopup, text: string): seq[SelectorItem] =
    let allViews = self.views & self.hiddenViews
    for view in allViews:
      let document = view.editor.getDocument
      let name = view.document.filename
      let score = matchPath(name, text)
      result.add FileSelectorItem(path: name, score: score, workspaceFolder: document.workspace)

    result.sort((a, b) => cmp(a.FileSelectorItem.score, b.FileSelectorItem.score), Descending)

  popup.handleItemConfirmed = proc(item: SelectorItem) =
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
      logger.log(lvlError, fmt"Unknown argument {view}")

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

proc reloadConfig*(self: App) {.expose("editor").} =
  defer:
    self.platform.requestRender()
  if self.scriptContext.isNil.not:
    try:
      self.scriptContext.reload()
      if not self.initializeCalled:
        discard self.scriptContext.invoke(postInitialize, returnType = bool)
        self.initializeCalled = true
    except CatchableError:
      logger.log(lvlError, fmt"Failed to reload config")

proc logOptions*(self: App) {.expose("editor").} =
  logger.log(lvlInfo, self.options.pretty)

proc clearCommands*(self: App, context: string) {.expose("editor").} =
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
        if self.handleAction(action, arg):
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
    result.add self.getCommandLineTextEditor.getEventHandlers()
    result.add self.commandLineEventHandler
  elif self.popups.len > 0:
    result.add self.popups[self.popups.high].getEventHandlers()
  elif self.currentView >= 0 and self.currentView < self.views.len:
    result.add self.views[self.currentView].editor.getEventHandlers()

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

proc handleKeyPress*(self: App, input: int64, modifiers: Modifiers) =
  # debugf"key press: {(inputToString(input, modifiers))}"
  if self.currentEventHandlers.handleEvent(input, modifiers):
    self.platform.preventDefault()

proc handleKeyRelease*(self: App, input: int64, modifiers: Modifiers) =
  discard

proc handleRune*(self: App, input: int64, modifiers: Modifiers) =
  let modifiers = if input.isAscii and input.char.isAlphaNumeric: modifiers else: {}
  if self.currentEventHandlers.handleEvent(input, modifiers):
    self.platform.preventDefault()

proc handleDropFile*(self: App, path, content: string) =
  discard self.createView(newTextDocument(self.asConfigProvider, path, content))

proc scriptRunAction*(action: string, arg: string) {.expose("editor").} =
  if gEditor.isNil:
    return
  discard gEditor.handleAction(action, arg)

proc scriptLog*(message: string) {.expose("editor").} =
  logger.log(lvlInfo, fmt"[script] {message}")

proc addCommandScript*(self: App, context: string, keys: string, action: string, arg: string = "") {.expose("editor").} =
  let command = if arg.len == 0: action else: action & " " & arg
  # logger.log(lvlInfo, fmt"Adding command to '{context}': ('{keys}', '{command}')")
  self.getEventHandlerConfig(context).addCommand(keys, command)

proc removeCommand*(self: App, context: string, keys: string) {.expose("editor").} =
  # logger.log(lvlInfo, fmt"Removing command from '{context}': '{keys}'")
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
  ## Javascript backend only!
  ## Opens the config file in a new view.
  when defined(js):
    discard self.createView(newTextDocument(self.asConfigProvider, "./config/absytree_config.js", fs.loadApplicationFile("./config/absytree_config.js"), true))

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
      echo contentStrict

      if confirmJs((fmt"You are about to eval() some javascript ({document.filename}). Look in the console to see what's in there.").cstring):
        evalJs(contentStrict.cstring)
      else:
        logger.log(lvlWarn, fmt"Did not load config file because user declined.")

proc getEditor*(index: int): EditorId {.expose("editor").} =
  if gEditor.isNil:
    return EditorId(-1)
  if index >= 0 and index < gEditor.views.len:
    return gEditor.views[index].editor.id

  return EditorId(-1)

proc scriptIsTextEditor*(editorId: EditorId): bool {.expose("editor").} =
  if gEditor.isNil:
    return false
  if gEditor.getEditorForId(editorId).getSome(editor):
    return editor of TextDocumentEditor
  return false

proc scriptIsAstEditor*(editorId: EditorId): bool {.expose("editor").} =
  if gEditor.isNil:
    return false
  if gEditor.getEditorForId(editorId).getSome(editor):
    return editor of AstDocumentEditor
  return false

proc scriptIsModelEditor*(editorId: EditorId): bool {.expose("editor").} =
  if gEditor.isNil:
    return false
  if gEditor.getEditorForId(editorId).getSome(editor):
    return editor of ModelDocumentEditor
  return false

proc scriptRunActionFor*(editorId: EditorId, action: string, arg: string) {.expose("editor").} =
  if gEditor.isNil:
    return
  defer:
    gEditor.platform.requestRender()
  if gEditor.getEditorForId(editorId).getSome(editor):
    discard editor.eventHandler.handleAction(action, arg)
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

proc setRegisterText*(self: App, text: string, register: string = "") {.expose("editor").} =
  self.registers[register] = Register(kind: Text, text: text)

proc getRegisterText*(self: App, text: var string, register: string = "") =
  # For some reason returning string causes a crash, the returned pointer is just different at the call site for some reason.
  # var string parameter seems to fix it
  text = ""
  if self.registers.contains(register):
    text = self.registers[register].getText()

genDispatcher("editor")

proc handleAction(self: App, action: string, arg: string): bool =
  logger.log(lvlInfo, "[ed] Action '$1 $2'" % [action, arg])

  var args = newJArray()
  for a in newStringStream(arg).parseJsonFragments():
    args.add a

  try:
    if self.scriptContext.handleGlobalAction(action, args):
      return true
  except CatchableError:
    logger.log(lvlError, fmt"[ed] Failed to run script handleGlobalAction '{action} {arg}': {getCurrentExceptionMsg()}")
    logger.log(lvlError, getCurrentException().getStackTrace())

  try:
    if self.wasmScriptContext.handleGlobalAction(action, args):
      return true
  except CatchableError:
    logger.log(lvlError, fmt"[ed] Failed to run script handleGlobalAction '{action} {arg}': {getCurrentExceptionMsg()}")
    logger.log(lvlError, getCurrentException().getStackTrace())

  return dispatch(action, args).isSome

when not defined(js):
  proc createAddins(): VmAddins =
    addCallable(myImpl):
      proc postInitialize(): bool
      proc handleGlobalAction(action: string, args: JsonNode): bool
      proc handleEditorAction(id: EditorId, action: string, args: JsonNode): bool
      proc handleUnknownPopupAction(id: EditorId, action: string, args: JsonNode): bool
      proc handleCallback(id: int, args: JsonNode): bool

    return implNimScriptModule(myImpl)

  const addins = createAddins()

  static:
    generateScriptingApi(addins)

  createScriptContextConstructor(addins)

  proc createScriptContext(filepath: string, searchPaths: seq[string]): ScriptContext = createScriptContextNim(filepath, searchPaths)

when not defined(js):
  import wasm3, wasm3/[wasm3c, wasmconversions]

createEditorWasmImportConstructor()