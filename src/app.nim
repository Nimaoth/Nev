import std/[algorithm, sequtils, strformat, strutils, tables, options, os, json, macros, sugar, streams, deques]
import misc/[id, util, timer, event, myjsonutils, traits, rect_utils, custom_logger, custom_async,
  array_set, delayed_task, disposable_ref, regex, custom_unicode]
import ui/node
import scripting/[expose, scripting_base]
import platform/[platform]
import workspaces/[workspace]
import config_provider, app_interface
import text/language/language_server_base, language_server_command_line
import input, events, document, document_editor, popup, dispatch_tables, theme, app_options, view, register
import text/[custom_treesitter]
import finder/[finder, previewer, data_previewer]
import compilation_config, vfs, vfs_service
import service, layout, session, command_service

import nimsumtree/[rope]

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
const appConfigDir = "app://config"
const homeConfigDir = "home://" & configDirName
const workspaceConfigDir = "ws0://" & configDirName

let platformName = when defined(windows):
  "windows"
elif defined(linux):
  "linux"
elif defined(wasm):
  "wasm"
else:
  "other"

type OpenEditor = object
  filename: string
  languageID: string
  appFile: bool
  customOptions: JsonNode

type
  # todo: this isn't necessary anymore
  OpenWorkspace = object
    id*: string
    name*: string
    settings*: JsonNode

type EditorState = object
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

    services: Services
    config*: ConfigService
    session*: SessionService
    events*: EventHandlerService
    plugins*: PluginService
    registers: Registers
    vfsService*: VFSService
    commands*: CommandService

    workspace*: Workspace
    vfs*: VFS

    logNextFrameTime*: bool = false
    disableLogFrameTime*: bool = true
    logBuffer = ""

    wasmScriptContext*: ScriptContextWasm
    initializeCalled: bool

    statusBarOnTop*: bool
    inputHistory*: string
    clearInputHistoryTask: DelayedTask

    layout*: LayoutService

    theme*: Theme
    loadedFontSize: float
    loadedLineDistance: float

    editors*: DocumentEditorService

    logDocument: Document

    eventHandler*: EventHandler
    modeEventHandler: EventHandler
    currentMode*: string

    sessionFile*: string

    currentLocationListIndex: int
    finderItems: seq[FinderItem]
    previewer: Option[DisposableRef[Previewer]]

    closeUnusedDocumentsTask: DelayedTask

    showNextPossibleInputsTask: DelayedTask
    nextPossibleInputs*: seq[tuple[input: string, description: string, continues: bool]]
    showNextPossibleInputs*: bool

var gEditor* {.exportc.}: App = nil

proc handleLog(self: App, level: Level, args: openArray[string])
proc getActiveEditor*(self: App): Option[DocumentEditor]
proc help*(self: App, about: string = "")
proc setHandleInputs*(self: App, context: string, value: bool)
proc setLocationList*(self: App, list: seq[FinderItem], previewer: Option[Previewer] = Previewer.none)
proc closeUnusedDocuments*(self: App)
proc addCommandScript*(self: App, context: string, subContext: string, keys: string, action: string, arg: string = "", description: string = "", source: tuple[filename: string, line: int, column: int] = ("", 0, 0))
proc currentEventHandlers*(self: App): seq[EventHandler]
proc defaultHandleCommand*(self: App, command: string): Option[string]

implTrait AppInterface, App:
  getActiveEditor(Option[DocumentEditor], App)
  setLocationList(void, App, seq[FinderItem], Option[Previewer])

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

proc handleAction(self: App, action: string, arg: string, record: bool): Option[JsonNode]

import text/[text_editor, text_document]
import text/language/debugger
when enableAst:
  import ast/[model_document]
import selector_popup
import finder/[file_previewer, open_editor_previewer]

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

proc setTheme*(self: App, path: string, force: bool = false) {.async: (raises: []).} =
  if not force and self.theme.isNotNil and self.theme.path == path:
    return
  if theme.loadFromFile(self.vfs, path).await.getSome(theme):
    log(lvlInfo, fmt"Loaded theme {path}")
    self.theme = theme
    {.gcsafe.}:
      gTheme = theme
  else:
    log(lvlError, fmt"Failed to load theme {path}")
  self.platform.requestRender(redrawEverything=true)

proc runConfigCommands(self: App, key: string) =
  let startupCommands = self.config.getOption(key, newJArray())
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
      self.plugins.scriptContexts.add self.wasmScriptContext
      self.wasmScriptContext.moduleVfs = VFS()
      self.wasmScriptContext.vfs = self.vfs
      self.vfs.mount("plugs://", self.wasmScriptContext.moduleVfs)

      withScriptContext self.plugins, self.wasmScriptContext:
        let t1 = startTimer()
        await self.wasmScriptContext.init("app://config", self.vfs)
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

  let editorConfig = self.events.getEventHandlerConfig("editor")
  let textConfig = self.events.getEventHandlerConfig("editor.text")
  let textCompletionConfig = self.events.getEventHandlerConfig("editor.text.completion")
  let commandLineConfig = self.events.getEventHandlerConfig("command-line-high")
  let selectorPopupConfig = self.events.getEventHandlerConfig("popup.selector")

  self.setHandleInputs("editor.text", true)
  self.config.setOption[:string]("editor.text.cursor.movement.", "both")
  self.config.setOption[:bool]("editor.text.cursor.wide.", false)

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

proc restoreStateFromConfig*(self: App, state: ptr EditorState) {.async: (raises: []).} =
  try:
    let stateJson = self.vfs.read(self.sessionFile).await.parseJson

    state[] = stateJson.jsonTo(EditorState, JOptions(allowMissingKeys: true, allowExtraKeys: true))
    log(lvlInfo, fmt"Restoring session {self.sessionFile}")

    if not state[].layout.isEmptyOrWhitespace:
      self.layout.setLayout(state[].layout)

    let fontSize = max(state[].fontSize.float, 10.0)
    self.loadedFontSize = fontSize
    self.platform.fontSize = fontSize
    self.loadedLineDistance = state[].lineDistance.float
    self.platform.lineDistance = state[].lineDistance.float
    if state[].fontRegular.len > 0: self.fontRegular = state[].fontRegular
    if state[].fontBold.len > 0: self.fontBold = state[].fontBold
    if state[].fontItalic.len > 0: self.fontItalic = state[].fontItalic
    if state[].fontBoldItalic.len > 0: self.fontBoldItalic = state[].fontBoldItalic
    if state[].fallbackFonts.len > 0: self.fallbackFonts = state[].fallbackFonts

    self.platform.setFont(self.fontRegular, self.fontBold, self.fontItalic, self.fontBoldItalic, self.fallbackFonts)

    self.session.restoreSession(state[].sessionData)
  except CatchableError:
    log(lvlError, fmt"Failed to load previous state from config file: {getCurrentExceptionMsg()}")

proc loadKeybindingsFromJson*(self: App, json: JsonNode, filename: string) =
  try:
    let oldScriptContext = self.plugins.currentScriptContext
    self.plugins.currentScriptContext = ScriptContext.none
    defer:
      self.plugins.currentScriptContext = oldScriptContext

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
        self.config.setOption("", json, override=false)

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

proc loadConfigFileFrom(self: App, context: string, path: string):
    Future[Option[string]] {.async.} =
  try:
    let content = await self.vfs.read(path)
    log lvlInfo, &"Loaded {context} from '{path}'"
    return content.some
  except FileNotFoundError:
    return string.none
  except CatchableError:
    log(lvlError, fmt"Failed to load {context} from '{path}': {getCurrentExceptionMsg()}")

  return string.none

proc loadConfigFrom*(self: App, root: string) {.async.} =
  await allFutures(
    self.loadSettingsFrom(root, loadConfigFileFrom),
    self.loadKeybindings(root, loadConfigFileFrom)
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
#       self.vfs.write(fileName, $actualPort.int)
#   except:
#     log lvlError, &"Failed to create server on port {port.int}: {getCurrentExceptionMsg()}"
#     return

#   while true:
#     let client = await server.accept()

#     asyncSpawn processClient(client)

# proc listenForConnection*(self: App, port: Port) {.async.} =
#   await serve(port, self.config.getFlag("command-server.save-file", false))

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
#             self.config.setOption(path, value)
#           else:
#             discard self.layout.openFile(message)

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
    self.config.setOption(path, value)

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

proc newApp*(backend: api.Backend, platform: Platform, services: Services, options = AppOptions()): Future[App] {.async.} =
  var self = App()

  {.gcsafe.}:
    gEditor = self
    gAppInterface = self.asAppInterface
    self.platform = platform

    logger.addLogger AppLogger(app: self, fmtStr: "")

  log lvlInfo, fmt"Creating App with backend {backend} and options {options}"

  self.backend = backend
  self.statusBarOnTop = false
  self.appOptions = options
  self.services = services

  discard platform.onKeyPress.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleKeyPress(event.input, event.modifiers)
  discard platform.onKeyRelease.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleKeyRelease(event.input, event.modifiers)
  discard platform.onRune.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleRune(event.input, event.modifiers)
  discard platform.onDropFile.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleDropFile(event.path, event.content)
  discard platform.onCloseRequested.subscribe proc() {.gcsafe, raises: [].} = self.closeRequested = true

  self.timer = startTimer()
  self.frameTimer = startTimer()

  self.layout = services.getService(LayoutService).get
  self.config = services.getService(ConfigService).get
  self.editors = services.getService(DocumentEditorService).get
  self.session = services.getService(SessionService).get
  self.events = services.getService(EventHandlerService).get
  self.plugins = services.getService(PluginService).get
  self.registers = services.getService(Registers).get
  self.vfsService = services.getService(VFSService).get
  self.workspace = services.getService(Workspace).get
  self.commands = services.getService(CommandService).get
  self.vfs = self.vfsService.vfs

  self.platform.fontSize = 16
  self.platform.lineDistance = 4

  self.fontRegular = "app://fonts/DejaVuSansMono.ttf"
  self.fontBold = "app://fonts/DejaVuSansMono-Bold.ttf"
  self.fontItalic = "app://fonts/DejaVuSansMono-Oblique.ttf"
  self.fontBoldItalic = "app://fonts/DejaVuSansMono-BoldOblique.ttf"
  self.fallbackFonts.add "app://fonts/Noto_Sans_Symbols_2/NotoSansSymbols2-Regular.ttf"
  self.fallbackFonts.add "app://fonts/NotoEmoji/NotoEmoji.otf"

  # todo: refactor this
  self.editors.editorDefaults.add TextDocumentEditor()
  when enableAst:
    self.editors.editorDefaults.add ModelDocumentEditor()

  self.setupDefaultKeybindings()

  await self.loadConfigFrom(appConfigDir)
  await self.loadConfigFrom(homeConfigDir)
  log lvlInfo, &"Finished loading app and user settings"

  self.applySettingsFromAppOptions()

  self.theme = defaultTheme()
  {.gcsafe.}:
    gTheme = self.theme

  self.logDocument = newTextDocument(self.services, "log", load=false, createLanguageServer=false, language="log".some)
  self.editors.documents.add self.logDocument
  self.layout.pinnedDocuments.incl(self.logDocument)

  self.commands.languageServerCommandLine = newLanguageServerCommandLine(self.services)
  let commandLineTextDocument = newTextDocument(self.services, language="command-line".some, languageServer=self.commands.languageServerCommandLine.some)
  self.editors.documents.add commandLineTextDocument
  self.commands.commandLineEditor = newTextEditor(commandLineTextDocument, self.services)
  self.commands.commandLineEditor.renderHeader = false
  self.commands.commandLineEditor.TextDocumentEditor.usage = "command-line"
  self.commands.commandLineEditor.TextDocumentEditor.disableScrolling = true
  self.commands.commandLineEditor.TextDocumentEditor.lineNumbers = api.LineNumbers.None.some
  self.commands.commandLineEditor.TextDocumentEditor.hideCursorWhenInactive = true
  self.commands.commandLineEditor.TextDocumentEditor.cursorMargin = 0.0.some
  self.commands.commandLineEditor.TextDocumentEditor.defaultScrollBehaviour = ScrollBehaviour.ScrollToMargin
  discard self.commands.commandLineEditor.onMarkedDirty.subscribe () => self.platform.requestRender()
  self.editors.commandLineEditor = self.commands.commandLineEditor
  self.commands.defaultCommandHandler = proc(command: Option[string]): Option[string] =
    if command.isSome:
      self.defaultHandleCommand(command.get)
    else:
      string.none

  assignEventHandler(self.eventHandler, self.events.getEventHandlerConfig("editor")):
    onAction:
      if self.handleAction(action, arg, record=true).isSome:
        Handled
      else:
        Ignored
    onInput:
      Ignored

  assignEventHandler(self.commands.commandLineEventHandlerHigh, self.events.getEventHandlerConfig("command-line-high")):
    onAction:
      if self.handleAction(action, arg, record=true).isSome:
        Handled
      else:
        Ignored
    onInput:
      Ignored

  assignEventHandler(self.commands.commandLineEventHandlerLow, self.events.getEventHandlerConfig("command-line-low")):
    onAction:
      if self.handleAction(action, arg, record=true).isSome:
        Handled
      else:
        Ignored
    onInput:
      Ignored

  assignEventHandler(self.commands.commandLineResultEventHandlerHigh, self.events.getEventHandlerConfig("command-line-result-high")):
    onAction:
      if self.handleAction(action, arg, record=true).isSome:
        Handled
      else:
        Ignored
    onInput:
      Ignored

  assignEventHandler(self.commands.commandLineResultEventHandlerLow, self.events.getEventHandlerConfig("command-line-result-low")):
    onAction:
      if self.handleAction(action, arg, record=true).isSome:
        Handled
      else:
        Ignored
    onInput:
      Ignored

  var state = EditorState()
  if not options.dontRestoreConfig:
    if options.sessionOverride.getSome(session):
      self.sessionFile = os.absolutePath(session).normalizePathUnix
    elif options.fileToOpen.getSome(file):
      let path = os.absolutePath(file).normalizePathUnix
      if self.vfs.getFileKind(path).await.getSome(kind):
        case kind
        of FileKind.File:
          # Don't restore a session when opening a specific file.
          discard
        of FileKind.Directory:
          log lvlInfo, &"Set current dir: '{path}'"
          setCurrentDir(path)
          if fileExists(path // defaultSessionName):
            self.sessionFile = path // defaultSessionName

    elif fileExists(defaultSessionName):
      self.sessionFile = os.absolutePath(defaultSessionName).normalizePathUnix

    if self.sessionFile != "":
      await self.restoreStateFromConfig(state.addr)
    else:
      log lvlInfo, &"Don't restore session file."

  self.commands.languageServerCommandLine.LanguageServerCommandLine.commandHistory = state.commandHistory

  let closeUnusedDocumentsTimerS = self.config.getOption("editor.close-unused-documents-timer", 10)
  self.closeUnusedDocumentsTask = startDelayed(closeUnusedDocumentsTimerS * 1000, repeat=true):
    self.closeUnusedDocuments()

  let showNextPossibleInputsDelay = self.config.getOption("ui.which-key-delay", 500)
  self.showNextPossibleInputsTask = startDelayedPaused(showNextPossibleInputsDelay, repeat=false):
    self.showNextPossibleInputs = self.nextPossibleInputs.len > 0
    self.platform.requestRender()

  self.runEarlyCommandsFromAppOptions()
  self.runConfigCommands("startup-commands")

  # if self.getOption("command-server.port", Port.none).getSome(port):
  #   asyncSpawn self.listenForConnection(port)

  if self.config.getFlag("editor.restore-open-workspaces", true):
    for wf in state.workspaceFolders:
      log(lvlInfo, fmt"Restoring workspace")
      self.workspace.restore(wf.settings)
      await self.loadConfigFrom(workspaceConfigDir)

  # Open current working dir as local workspace if no workspace exists yet
  if self.workspace.path == "":
    log lvlInfo, "No workspace open yet, opening current working directory as local workspace"
    self.workspace.addWorkspaceFolder(getCurrentDir().normalizePathUnix)
    await self.loadConfigFrom(workspaceConfigDir)

  let themeName = self.config.getOption("ui.theme", "app://themes/tokyo-night-color-theme.json")
  await self.setTheme(themeName)

  self.vfs.watch "app://themes", proc(events: seq[PathEvent]) =
    for e in events:
      case e.action
      of Modify:
        if "app://themes" // e.name == self.theme.path:
          asyncSpawn self.setTheme(self.theme.path, force = true)

      else:
        discard

  asyncSpawn self.finishInitialization(state)

  log lvlInfo, &"Finished creating app"

  return self

proc finishInitialization*(self: App, state: EditorState) {.async.} =
  await sleepAsync(1.milliseconds)

  # Restore open editors
  if self.appOptions.fileToOpen.getSome(filePath):
    try:
      discard self.layout.openFile(os.absolutePath(filePath).normalizePathUnix)
    except CatchableError as e:
      log lvlError, &"Failed to open file '{filePath}': {e.msg}"

  elif self.config.getFlag("editor.restore-open-editors", true):
    for editorState in state.openEditors:
      let view = self.layout.createView(editorState.filename)
      if view.isNil:
        continue

      self.layout.addView(view, append=true)
      if editorState.customOptions.isNotNil and view of EditorView:
        view.EditorView.editor.restoreStateJson(editorState.customOptions)

    for editorState in state.hiddenEditors:
      let view = self.layout.createView(editorState.filename)
      if view.isNil:
        continue

      self.layout.hiddenViews.add view
      if editorState.customOptions.isNotNil and view of EditorView:
        view.EditorView.editor.restoreStateJson(editorState.customOptions)

  if self.layout.views.len == 0:
    if self.layout.hiddenViews.len > 0:
      self.layout.addView self.layout.hiddenViews.pop
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
  if self.config.getOption("editor.print-statistics-on-shutdown", false):
    self.printStatistics()

  self.saveAppState()

  # Clear log document so we don't log to it as it will be destroyed.
  self.logDocument = nil

  for popup in self.layout.popups:
    popup.deinit()

  let editors = collect(for e in self.editors.editors.values: e)
  for editor in editors:
    editor.deinit()

  for document in self.editors.documents:
    document.deinit()

  if self.wasmScriptContext.isNotNil:
    self.wasmScriptContext.deinit()

  self.commands.languageServerCommandLine.stop()

  {.gcsafe.}:
    gAppInterface = nil
  self[] = AppObject()

  {.gcsafe.}:
    custom_treesitter.freeDynamicLibraries()

proc handleLog(self: App, level: Level, args: openArray[string]) =
  let str = substituteLog(defaultFmtStr, level, args) & "\n"
  if self.logDocument.isNotNil:
    for view in self.layout.views:
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
    await self.loadKeybindings(appConfigDir, loadConfigFileFrom)
  if home:
    await self.loadKeybindings(homeConfigDir, loadConfigFileFrom)
  if workspace:
    await self.loadKeybindings(workspaceConfigDir, loadConfigFileFrom)

proc reapplyConfigKeybindings*(self: App, app: bool = false, home: bool = false, workspace: bool = false)
    {.expose("editor").} =
  asyncSpawn self.reapplyConfigKeybindingsAsync(app, home, workspace)

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
  for view in self.layout.views:
    if view of DebuggerView:
      return

  for i, view in self.layout.hiddenViews:
    if view of DebuggerView:
      self.layout.hiddenViews.delete i
      self.layout.addView(view, false)
      return

  self.layout.addView(DebuggerView(), false)

proc setLocationListFromCurrentPopup*(self: App) {.expose("editor").} =
  if self.layout.popups.len == 0:
    return

  let popup = self.layout.popups[self.layout.popups.high]
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

proc toggleShowDrawnNodes*(self: App) {.expose("editor").} =
  self.platform.showDrawnNodes = not self.platform.showDrawnNodes

proc saveAppState*(self: App) {.expose("editor").} =
  # Save some state
  var state = EditorState()

  # todo: save ast project state

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

  state.commandHistory = self.commands.languageServerCommandLine.LanguageServerCommandLine.commandHistory
  state.sessionData = self.session.sessionData

  if getDebugger().getSome(debugger):
    state.debuggerState = debugger.getStateJson().some

  # todo
  # if self.layout of HorizontalLayout:
  #   state.layout = "horizontal"
  # elif self.layout of VerticalLayout:
  #   state.layout = "vertical"
  # else:
  #   state.layout = "fibonacci"

  # Save open workspace folders
  state.workspaceFolders.add OpenWorkspace(
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
          customOptions: customOptions ?? newJObject()
          ).some
      else:
        when enableAst:
          if view.document of ModelDocument:
            let document = ModelDocument(view.document)
            return OpenEditor(
              filename: document.filename, languageId: "am", appFile: document.appFile,
              customOptions: customOptions ?? newJObject()
              ).some
    except CatchableError:
      log lvlError, fmt"Failed to get editor state for {view.document.filename}: {getCurrentExceptionMsg()}"
      return OpenEditor.none

  for view in self.layout.views:
    if view of EditorView and view.EditorView.getEditorState().getSome(editorState):
      state.openEditors.add editorState

  for view in self.layout.hiddenViews:
    if view of EditorView and view.EditorView.getEditorState().getSome(editorState):
      state.hiddenEditors.add editorState

  if self.sessionFile != "":
    try:
      let serialized = state.toJson
      waitFor self.vfs.write(self.sessionFile, serialized.pretty)
    except IOError as e:
      log lvlError, &"Failed to save app state: {e.msg}\n{e.getStackTrace()}"

proc requestRender*(self: App, redrawEverything: bool = false) {.expose("editor").} =
  self.platform.requestRender(redrawEverything)

proc setHandleInputs*(self: App, context: string, value: bool) {.expose("editor").} =
  self.events.getEventHandlerConfig(context).setHandleInputs(value)

proc setHandleActions*(self: App, context: string, value: bool) {.expose("editor").} =
  self.events.getEventHandlerConfig(context).setHandleActions(value)

proc setConsumeAllActions*(self: App, context: string, value: bool) {.expose("editor").} =
  self.events.getEventHandlerConfig(context).setConsumeAllActions(value)

proc setConsumeAllInput*(self: App, context: string, value: bool) {.expose("editor").} =
  self.events.getEventHandlerConfig(context).setConsumeAllInput(value)

proc clearWorkspaceCaches*(self: App) {.expose("editor").} =
  self.workspace.clearDirectoryCache()

proc quit*(self: App) {.expose("editor").} =
  self.closeRequested = true

proc quitImmediately*(self: App, exitCode: int = 0) {.expose("editor").} =
  quit(exitCode)

proc help*(self: App, about: string = "") {.expose("editor").} =
  const introductionMd = staticRead"../docs/getting_started.md"
  let docsPath = "app://docs/getting_started.md"
  let textDocument = newTextDocument(self.services, docsPath, introductionMd, load=true)
  self.editors.documents.add textDocument
  textDocument.load()
  discard self.layout.createAndAddView(textDocument)

proc loadWorkspaceFileImpl(self: App, path: string, callback: string) {.async: (raises: []).} =
  let path = self.workspace.getAbsolutePath(path)
  try:
    let content = await self.vfs.read(path)
    discard self.plugins.callScriptAction(callback, content.some.toJson)
  except FileNotFoundError:
    discard self.plugins.callScriptAction(callback, string.none.toJson)
  except IOError as e:
    log lvlError, &"Failed to load workspace file: {e.msg}"
    discard self.plugins.callScriptAction(callback, string.none.toJson)

proc loadWorkspaceFile*(self: App, path: string, callback: string) {.expose("editor").} =
  asyncSpawn self.loadWorkspaceFileImpl(path, callback)

proc writeWorkspaceFileImpl(self: App, path: string, content: string) {.async: (raises: []).} =
  let path = self.workspace.getAbsolutePath(path)
  log lvlInfo, &"[writeWorkspaceFile] {path}"
  try:
    await self.vfs.write(path, content)
  except IOError as e:
    log lvlError, &"Failed to load workspace file: {e.msg}"

proc writeWorkspaceFile*(self: App, path: string, content: string) {.expose("editor").} =
  asyncSpawn self.writeWorkspaceFileImpl(path, content)

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

proc toggleStatusBarLocation*(self: App) {.expose("editor").} =
  self.statusBarOnTop = not self.statusBarOnTop
  self.platform.requestRender(true)

proc logs*(self: App, scrollToBottom: bool = false) {.expose("editor").} =
  let editors = self.editors.getEditorsForDocument(self.logDocument)
  let editor = if editors.len > 0:
    self.layout.showEditor(editors[0].id)
    editors[0]
  else:
    self.layout.createAndAddView(self.logDocument).get

  if scrollToBottom and editor of TextDocumentEditor:
    let editor = editor.TextDocumentEditor
    editor.moveLast("file")
    editor.selection = editor.selection.last.toSelection

proc toggleConsoleLogger*(self: App) {.expose("editor").} =
  {.gcsafe.}:
    logger.toggleConsoleLogger()

proc closeUnusedDocuments*(self: App) =
  let documents = self.editors.documents
  for document in documents:
    if document == self.logDocument:
      continue

    let editors = self.editors.getEditorsForDocument(document)
    if editors.len > 0:
      continue

    discard self.layout.tryCloseDocument(document, true)

    # Only close one document on each iteration so we don't create spikes
    break

proc defaultHandleCommand*(self: App, command: string): Option[string] =
  var (action, arg) = command.parseAction

  if arg.startsWith("\\"):
    arg = $newJString(arg[1..^1])

  let res = self.handleAction(action, arg, record=true)
  if res.getSome(res) and res.kind != JNull:
    return res.pretty.some
  return string.none

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
  if self.layout.tryGetCurrentEditorView().getSome(view) and view.document.isNotNil:
    defer:
      self.platform.requestRender()
    try:
      view.document.load(path)
      view.editor.handleDocumentChanged()
    except CatchableError:
      log(lvlError, fmt"Failed to load file '{path}': {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())

proc loadTheme*(self: App, name: string, force: bool = false) {.expose("editor").} =
  asyncSpawn self.setTheme(fmt"app://themes/{name}.json", force)

proc vsync*(self: App, enabled: bool) {.expose("editor").} =
  self.platform.setVsync(enabled)

proc chooseTheme*(self: App) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  let originalTheme = self.theme.path

  proc getItems(): Future[ItemList] {.gcsafe, async: (raises: []).} =
    var items = newSeq[FinderItem]()
    let themesDir = "app://themes"
    try:
      let files = self.vfs.getDirectoryListingRec(Globs(), themesDir).await
      for file in files:
        if file.endsWith(".json"):
          let (relativeDirectory, name, _) = file.splitFile
          items.add FinderItem(
            displayName: name,
            data: file,
            detail: relativeDirectory,
          )
    except:
      discard

    return newItemList(items)

  let source = newAsyncCallbackDataSource(getItems)
  var finder = newFinder(source, filterAndSort=true)
  finder.filterThreshold = float.low

  var popup = newSelectorPopup(self.services, "theme".some, finder.some)
  popup.scale.x = 0.35

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    if theme.loadFromFile(self.vfs, item.data).waitFor.getSome(theme):
      self.theme = theme
      {.gcsafe.}:
        gTheme = theme
      self.platform.requestRender(true)

      return true

  popup.handleItemSelected = proc(item: FinderItem) =
    if theme.loadFromFile(self.vfs, item.data).waitFor.getSome(theme):
      self.theme = theme
      {.gcsafe.}:
        gTheme = theme
      self.platform.requestRender(true)

  popup.handleCanceled = proc() =
    if theme.loadFromFile(self.vfs, originalTheme).waitFor.getSome(theme):
      self.theme = theme
      {.gcsafe.}:
        gTheme = theme
      self.platform.requestRender(true)

  self.layout.pushPopup popup

proc createFile*(self: App, path: string) {.expose("editor").} =
  let fullPath = if path.isVfsPath:
    path
  elif path.isAbsolute:
    path.normalizeNativePath
  else:
    path.absolutePath.catch().valueOr(path).normalizePathUnix

  log lvlInfo, fmt"createFile: '{fullPath}'"

  let document = self.editors.openDocument(fullPath, load=false).getOr:
    log(lvlError, fmt"Failed to create file {path}")
    return

  discard self.layout.createAndAddView(document)

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

proc browseKeybinds*(self: App, preview: bool = true, scaleX: float = 0.9, scaleY: float = 0.8, previewScale: float = 0.4) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  proc getItems(): seq[FinderItem] {.gcsafe, raises: [].} =
    var items = newSeq[FinderItem]()
    for (context, c) in self.events.eventHandlerConfigs.pairs:
      if not c.commands.contains(""):
        continue
      for (keys, commandInfo) in c.commands[""].pairs:
        var name = commandInfo.command

        let key = context & keys
        self.events.commandDescriptions.withValue(key, val):
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
    newFilePreviewer(self.vfs, self.services, reuseExistingDocuments = false).Previewer.toDisposableRef.some
  else:
    DisposableRef[Previewer].none

  let source = newSyncDataSource(getItems)
  let finder = newFinder(source, filterAndSort=true)
  var popup = newSelectorPopup(self.services, "file".some, finder.some, previewer)
  popup.scale.x = scaleX
  popup.scale.y = scaleY
  popup.previewScale = previewScale

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let (path, location, _, _) = item.parsePathAndLocationFromItemData().getOr:
      log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
        fmt"Expected path or json object with path property {item}"
      return

    var targetSelection = location.mapIt(it.toSelection)
    if popup.getPreviewSelection().getSome(selection):
      targetSelection = selection.some

    let editor = self.layout.openFile(path)
    if editor.getSome(editor) and editor of TextDocumentEditor and targetSelection.isSome:
      editor.TextDocumentEditor.targetSelection = targetSelection.get
      editor.TextDocumentEditor.centerCursor()
    return true

  self.layout.pushPopup popup

proc browseSettings*(self: App, scaleX: float = 0.8, scaleY: float = 0.8, previewScale: float = 0.5) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  let dataPreviewer = newDataPreviewer(self.services, language="javascript".some)
  let previewer = dataPreviewer.Previewer.toDisposableRef.some

  proc getItems(): seq[FinderItem] {.gcsafe, raises: [].} =
    var items = newSeq[FinderItem]()
    for (key, value) in self.config.getAllConfigKeys():
      let valueStr = $value
      items.add FinderItem(
        displayName: key,
        data: value.pretty,
        detail: valueStr[0..min(valueStr.high, 50)],
      )

    return items

  let source = newSyncDataSource(getItems)
  let finder = newFinder(source, filterAndSort=true)
  var popup = newSelectorPopup(self.services, "settings".some, finder.some, previewer)
  popup.scale.x = scaleX
  popup.scale.y = scaleY
  popup.previewScale = previewScale

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    return true

  popup.handleItemSelected = proc(item: FinderItem) =
    let path = "settings://" & item.displayName.replace('.', '/')
    dataPreviewer.setPath(path)

  popup.addCustomCommand "toggle-flag", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    let item = popup.getSelectedItem().getOr:
      return true

    let key = item.displayName
    self.config.toggleFlag(key)
    source.retrigger()
    return true

  popup.addCustomCommand "update-setting", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    let item = popup.getSelectedItem().getOr:
      return true

    let key = item.displayName
    let value = popup.previewEditor.document.contentString
    try:
      let valueJson = value.parseJson
      self.config.asConfigProvider.setValue(key, valueJson)
      source.retrigger()
      return true
    except Exception as e:
      log lvlError, &"Failed to update setting '{key}' to '{value}': {e.msg}"

  self.layout.pushPopup popup

proc chooseFile*(self: App, preview: bool = true, scaleX: float = 0.8, scaleY: float = 0.8, previewScale: float = 0.5) {.expose("editor").} =
  ## Opens a file dialog which shows all files in the currently open workspaces
  ## Press <ENTER> to select a file
  ## Press <ESCAPE> to close the dialogue

  defer:
    self.platform.requestRender()

  let previewer = if preview:
    newFilePreviewer(self.vfs, self.services).Previewer.toDisposableRef.some
  else:
    DisposableRef[Previewer].none

  let finder = newFinder(newWorkspaceFilesDataSource(self.workspace), filterAndSort=true)
  var popup = newSelectorPopup(self.services, "file".some, finder.some, previewer)
  popup.scale.x = scaleX
  popup.scale.y = scaleY
  popup.previewScale = previewScale

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    discard self.layout.openFile(item.data)
    return true

  self.layout.pushPopup popup

proc openLastEditor*(self: App) {.expose("editor").} =
  if self.layout.hiddenViews.len > 0:
    let view = self.layout.hiddenViews.pop()
    self.layout.addView(view, addToHistory=false, append=false)

proc chooseOpen*(self: App, preview: bool = true, scaleX: float = 0.8, scaleY: float = 0.8, previewScale: float = 0.6) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  proc getItems(): seq[FinderItem] {.gcsafe, raises: [].} =
    var items = newSeq[FinderItem]()
    let allViews = self.layout.views & self.layout.hiddenViews
    for i in countdown(allViews.high, 0):
      if not (allViews[i] of EditorView):
        continue

      let view = allViews[i].EditorView
      let document = view.editor.getDocument
      let path = document.filename
      let isDirty = not document.requiresLoad and document.lastSavedRevision != document.revision
      let dirtyMarker = if isDirty: "*" else: " "
      let activeMarker = if i == self.layout.currentView:
        "#"
      elif i < self.layout.views.len:
        "👁"
      else:
        " "

      let (directory, name) = path.splitPath
      let relativeDirectory = self.workspace.getRelativePathSync(directory).get(directory)

      items.add FinderItem(
        displayName: activeMarker & dirtyMarker & name,
        filterText: name,
        data: $view.editor.id,
        detail: relativeDirectory,
      )

    return items

  let source = newSyncDataSource(getItems)
  var finder = newFinder(source, filterAndSort=true)
  finder.filterThreshold = float.low

  let previewer = if preview:
    newOpenEditorPreviewer(self.services).Previewer.toDisposableRef.some
  else:
    DisposableRef[Previewer].none

  var popup = newSelectorPopup(self.services, "open".some, finder.some, previewer)
  popup.scale.x = scaleX
  popup.scale.y = scaleY
  popup.previewScale = previewScale

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let editorId = item.data.parseInt.EditorId.catch:
      log lvlError, fmt"Failed to parse editor id from data '{item}'"
      return true

    discard self.layout.tryOpenExisting(editorId)
    return true

  popup.addCustomCommand "close-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    let item = popup.getSelectedItem().getOr:
      return true

    let editorId = item.data.parseInt.EditorId.catch:
      log lvlError, fmt"Failed to parse editor id from data '{item}'"
      return true

    if self.editors.getEditorForId(editorId).getSome(editor):
      if self.layout.getViewForEditor(editor).getSome(view):
        self.layout.closeView(view)
      else:
        self.editors.closeEditor(editor)

    source.retrigger()
    return true

  self.layout.pushPopup popup

proc chooseOpenDocument*(self: App) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  proc getItems(): seq[FinderItem] {.gcsafe, raises: [].} =
    var items = newSeq[FinderItem]()
    for document in self.editors.documents:
      if document == self.logDocument or document == self.commands.commandLineEditor.getDocument():
        continue

      let path = document.filename
      let isDirty = not document.requiresLoad and document.lastSavedRevision != document.revision
      let dirtyMarker = if isDirty: "*" else: " "
      let (directory, name) = path.splitPath
      let relativeDirectory = self.workspace.getRelativePathSync(directory).get(directory)

      items.add FinderItem(
        displayName: dirtyMarker & name,
        filterText: name,
        data: path,
        detail: relativeDirectory,
      )

    return items

  let source = newSyncDataSource(getItems)
  var finder = newFinder(source, filterAndSort=true)
  finder.filterThreshold = float.low

  var popup = newSelectorPopup(self.services, "open".some, finder.some)
  popup.scale.x = 0.35

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    if self.editors.getDocument(item.data).getSome(document):
      discard self.layout.createAndAddView(document)
    else:
      log lvlError, fmt"Failed to open location {item}"

    return true

  popup.addCustomCommand "close-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    if popup.getSelectedItem().getSome(item):
      if self.editors.getDocument(item.data).getSome(document):
        discard self.layout.tryCloseDocument(document, force=true)
        source.retrigger()

    return true

  self.layout.pushPopup popup

proc gotoNextLocation*(self: App) {.expose("editor").} =
  if self.finderItems.len == 0:
    return

  self.currentLocationListIndex = (self.currentLocationListIndex + 1) mod self.finderItems.len
  let item = self.finderItems[self.currentLocationListIndex]

  let (path, location, _, _) = item.parsePathAndLocationFromItemData().getOr:
    log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
      fmt"Expected path or json object with path property {item}"
    return

  log lvlInfo, &"[gotoNextLocation] Found {path}:{location}"

  let editor = self.layout.openFile(path)
  if editor.getSome(editor) and editor of TextDocumentEditor and location.isSome:
    editor.TextDocumentEditor.targetSelection = location.get.toSelection
    editor.TextDocumentEditor.centerCursor()

proc gotoPrevLocation*(self: App) {.expose("editor").} =
  if self.finderItems.len == 0:
    return

  self.currentLocationListIndex = (self.currentLocationListIndex - 1 + self.finderItems.len) mod self.finderItems.len
  let item = self.finderItems[self.currentLocationListIndex]

  let (path, location, _, _) = item.parsePathAndLocationFromItemData().getOr:
    log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
      fmt"Expected path or json object with path property {item}"
    return

  log lvlInfo, &"[gotoPrevLocation] Found {path}:{location}"

  let editor = self.layout.openFile(path)
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

  var popup = newSelectorPopup(self.services, "open".some, finder.some, self.previewer.clone())

  popup.scale.x = if self.previewer.isSome: 0.8 else: 0.4

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let (path, location, _, _) = item.parsePathAndLocationFromItemData().getOr:
      log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
        fmt"Expected path or json object with path property {item}"
      return

    var targetSelection = location.mapIt(it.toSelection)
    if popup.getPreviewSelection().getSome(selection):
      targetSelection = selection.some

    let editor = self.layout.openFile(path)
    if editor.getSome(editor) and editor of TextDocumentEditor and targetSelection.isSome:
      editor.TextDocumentEditor.targetSelection = targetSelection.get
      editor.TextDocumentEditor.centerCursor()

    return true

  self.layout.pushPopup popup

proc searchWorkspaceItemList(workspace: Workspace, query: string, maxResults: int, maxLen: int): Future[ItemList] {.async: (raises: []).} =
  let searchResults = workspace.searchWorkspace(query, maxResults).await
  log lvlInfo, fmt"Found {searchResults.len} results"

  var list = newItemList(searchResults.len)
  for i, info in searchResults:
    var relativePath = workspace.getRelativePathSync(info.path).get(info.path)
    if relativePath == ".":
      relativePath = ""

    list[i] = FinderItem(
      displayName: info.text[0..<min(info.text.len, maxLen)],
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
    maxLen: int = 1000

proc getWorkspaceSearchResults(self: WorkspaceSearchDataSource): Future[void] {.async.} =
  if self.query.len < self.minQueryLen:
    return

  let t = startTimer()
  let list = self.workspace.searchWorkspaceItemList(self.query, self.maxResults, self.maxLen).await
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

  let maxResults = self.config.getOption[:int]("editor.max-search-results", 1000)
  let source = newWorkspaceSearchDataSource(workspace, maxResults)
  var finder = newFinder(source, filterAndSort=true)

  var popup = newSelectorPopup(self.services, "search".some, finder.some,
    newFilePreviewer(self.vfs, self.services).Previewer.toDisposableRef.some)
  popup.scale.x = 0.85
  popup.scale.y = 0.85

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let (path, location, _, _) = item.parsePathAndLocationFromItemData().getOr:
      log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
        fmt"Expected path or json object with path property {item}"
      return

    var targetSelection = location.mapIt(it.toSelection)
    if popup.getPreviewSelection().getSome(selection):
      targetSelection = selection.some

    let editor = self.layout.openFile(path)
    if editor.getSome(editor) and editor of TextDocumentEditor and targetSelection.isSome:
      editor.TextDocumentEditor.targetSelection = targetSelection.get
      editor.TextDocumentEditor.centerCursor()
    return true

  self.layout.pushPopup popup

proc searchGlobal*(self: App, query: string) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  proc getItems(): Future[ItemList] {.gcsafe, async: (raises: []).} =
    let maxResults = self.config.getOption[:int]("editor.max-search-results", 1000)
    let maxLen = self.config.getOption[:int]("editor.max-search-result-display-len", 1000)
    return self.workspace.searchWorkspaceItemList(query, maxResults, maxLen).await

  let source = newAsyncCallbackDataSource(getItems)
  var finder = newFinder(source, filterAndSort=true)

  var popup = newSelectorPopup(self.services, "search".some, finder.some,
    newFilePreviewer(self.vfs, self.services).Previewer.toDisposableRef.some)
  popup.scale.x = 0.85
  popup.scale.y = 0.85

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let (path, location, _, _) = item.parsePathAndLocationFromItemData().getOr:
      log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
        fmt"Expected path or json object with path property {item}"
      return

    var targetSelection = location.mapIt(it.toSelection)
    if popup.getPreviewSelection().getSome(selection):
      targetSelection = selection.some

    let editor = self.layout.openFile(path)
    if editor.getSome(editor) and editor of TextDocumentEditor and targetSelection.isSome:
      editor.TextDocumentEditor.targetSelection = targetSelection.get
      editor.TextDocumentEditor.centerCursor()
    return true

  self.layout.pushPopup popup

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
      (language, self.config.getOption(&"languages.{language}.treesitter", ""))

    let queriesSubDir = self.config.getOption(&"languages.{language}.treesitter-queries", "").catch("")

    log lvlInfo, &"Install treesitter parser for {language} from {repo}"
    let parts = repo.split("/")
    if parts.len < 2:
      log lvlError, &"Invalid value for languages.{language}.treesitter: '{repo}'. Expected 'user/repo'"
      return

    let languagesRoot = self.vfs.localize("app://languages")
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
        let highlightQueries = await self.vfs.findFiles(repoPath, r"highlights.scm$")
        highlightQueries.mapIt(repoPath // it.splitPath.head)

      for path in queryDirs:
        let list = await self.vfs.getDirectoryListing(path)
        for f in list.files:
          if f.endsWith(".scm"):
            let fileName = f.splitPath.tail
            log lvlInfo, &"Copy '{f}' to '{queryDir}'"
            await self.vfs.copyFile(path // f, queryDir // fileName)

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

proc getItemsFromDirectory(vfs: VFS, workspace: Workspace, directory: string, showVFS: bool = false): Future[ItemList] {.async: (raises: []).} =

  let listing = await vfs.getDirectoryListing(directory)

  var list = newItemList(listing.files.len + listing.folders.len)

  # todo: use unicode icons on all targets once rendering is fixed
  const fileIcon = "🗎 "
  const folderIcon = "🗀"

  var i = 0
  proc addItem(name: string, isFile: bool) =
    var relativeDirectory = workspace.getRelativePathSync(directory).get(directory)

    if relativeDirectory == ".":
      relativeDirectory = ""

    var detail = directory
    if showVFS:
      let (vfs, _) = vfs.getVFS(directory // name, 1)
      detail.add "\t"
      detail.add vfs.name

    let icon = if isFile: fileIcon else: folderIcon
    list[i] = FinderItem(
      displayName: icon & " " & name,
      filterText: name,
      data: $ %*{
        "path": directory // name,
        "isFile": isFile,
      },
      detail: detail,
    )
    inc i

  for file in listing.files:
    addItem(file, true)

  for dir in listing.folders:
    addItem(dir, false)

  return list

proc exploreFiles*(self: App, root: string = "", showVFS: bool = false, normalize: bool = true) {.expose("editor").} =
  defer:
    self.platform.requestRender()

  log lvlInfo, &"exploreFiles '{root}'"

  let currentDirectory = new string
  currentDirectory[] = root

  proc getItems(): Future[ItemList] {.gcsafe, async: (raises: []).} =
    return getItemsFromDirectory(self.vfs, self.workspace, currentDirectory[], showVFS).await

  let source = newAsyncCallbackDataSource(getItems)
  var finder = newFinder(source, filterAndSort=true)
  finder.filterThreshold = float.low

  var popup = newSelectorPopup(self.services, "file-explorer".some, finder.some,
    newFilePreviewer(self.vfs, self.services).Previewer.toDisposableRef.some)
  popup.scale.x = 0.85
  popup.scale.y = 0.85

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let fileInfo = item.data.parseJson.jsonTo(tuple[path: string, isFile: bool]).catch:
      log lvlError, fmt"Failed to parse file info from item: {item}"
      return true

    var path = fileInfo.path
    if normalize:
      path = self.vfs.normalize(path)

    if fileInfo.isFile:
      if self.layout.openFile(path).getSome(editor):
        if editor of TextDocumentEditor and popup.getPreviewSelection().getSome(selection):
          editor.TextDocumentEditor.selection = selection
          editor.TextDocumentEditor.centerCursor()
      return true
    else:
      currentDirectory[] = fileInfo.path
      popup.textEditor.document.content = ""
      source.retrigger()
      return false

  popup.addCustomCommand "refresh", proc(popup: SelectorPopup, args: JsonNode): bool =
    source.retrigger()
    return false

  popup.addCustomCommand "enter-normalized", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.getSelectedItem().getSome(item):
      let fileInfo = item.data.parseJson.jsonTo(tuple[path: string, isFile: bool]).catch:
        log lvlError, fmt"Failed to parse file info from item: {item}"
        return true

      let path = self.vfs.normalize(fileInfo.path)

      if fileInfo.isFile:
        if self.layout.openFile(path).getSome(editor):
          if editor of TextDocumentEditor and popup.getPreviewSelection().getSome(selection):
            editor.TextDocumentEditor.selection = selection
            editor.TextDocumentEditor.centerCursor()
        return true
      else:
        currentDirectory[] = path
      popup.textEditor.document.content = ""
      source.retrigger()
      return false

  popup.addCustomCommand "go-up", proc(popup: SelectorPopup, args: JsonNode): bool =
    let parent = currentDirectory[].parentDirectory
    log lvlInfo, fmt"go up: {currentDirectory[]} -> {parent}"
    currentDirectory[] = parent

    popup.textEditor.document.content = ""
    source.retrigger()
    return true

  popup.addCustomCommand "add-workspace-folder", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.getSelectedItem().getSome(item):
      let fileInfo = item.data.parseJson.jsonTo(tuple[path: string, isFile: bool]).catch:
        log lvlError, fmt"Failed to parse file info from item: {item}"
        return true

      let path = self.vfs.localize(fileInfo.path)

      log lvlInfo, fmt"Add workspace folder: {currentDirectory[]} -> {path}"
      self.workspace.addWorkspaceFolder(path)
      source.retrigger()

  popup.addCustomCommand "remove-workspace-folder", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.getSelectedItem().getSome(item):
      let fileInfo = item.data.parseJson.jsonTo(tuple[path: string, isFile: bool]).catch:
        log lvlError, fmt"Failed to parse file info from item: {item}"
        return true

      let path = self.vfs.localize(fileInfo.path)

      log lvlInfo, fmt"Remove workspace folder: {currentDirectory[]} -> {path}"
      self.workspace.removeWorkspaceFolder(path)
      source.retrigger()

    return true

  popup.addCustomCommand "create-file", proc(popup: SelectorPopup, args: JsonNode): bool =
    let dir = currentDirectory[]
    self.commands.openCommandLine "", proc(command: Option[string]): Option[string] =
      if command.getSome(path):
        if path.isAbsolute:
          self.createFile(path)
        else:
          self.createFile(dir // path)

  self.layout.pushPopup popup

proc exploreWorkspacePrimary*(self: App) {.expose("editor").} =
  self.exploreFiles(self.workspace.getWorkspacePath())

proc exploreCurrentFileDirectory*(self: App) {.expose("editor").} =
  if self.layout.tryGetCurrentEditorView().getSome(view) and view.document.isNotNil:
    self.exploreFiles(view.document.filename.splitPath.head)

proc openPreviousEditor*(self: App) {.expose("editor").} =
  if self.layout.editorHistory.len == 0:
    return

  let editor = self.layout.editorHistory.popLast

  if self.layout.tryGetCurrentEditorView().getSome(view):
    self.layout.editorHistory.addFirst view.editor.id

  discard self.layout.tryOpenExisting(editor, addToHistory=false)
  self.platform.requestRender()

proc openNextEditor*(self: App) {.expose("editor").} =
  if self.layout.editorHistory.len == 0:
    return

  let editor = self.layout.editorHistory.popFirst

  if self.layout.tryGetCurrentEditorView().getSome(view):
    self.layout.editorHistory.addLast view.editor.id

  discard self.layout.tryOpenExisting(editor, addToHistory=false)
  self.platform.requestRender()

# todo: move to scripting_base
proc reloadPluginAsync*(self: App) {.async.} =
  if self.wasmScriptContext.isNotNil:
    log lvlInfo, "Reload wasm plugins"
    try:
      self.plugins.clearScriptActionsFor(self.wasmScriptContext)

      let t1 = startTimer()
      withScriptContext self.plugins, self.wasmScriptContext:
        await self.wasmScriptContext.reload()
      log(lvlInfo, fmt"Reload wasm plugins ({t1.elapsed.ms}ms)")

      withScriptContext self.plugins, self.wasmScriptContext:
        let t2 = startTimer()
        discard self.wasmScriptContext.postInitialize()
        log(lvlInfo, fmt"Post init wasm plugins ({t2.elapsed.ms}ms)")

      log lvlInfo, &"Successfully reloaded wasm plugins"
    except CatchableError:
      log lvlError, &"Failed to reload wasm plugins: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

    self.runConfigCommands("wasm-plugin-post-reload-commands")
    self.runConfigCommands("plugin-post-reload-commands")

proc reloadConfigAsync*(self: App) {.async.} =
  await self.loadConfigFrom(appConfigDir)
  await self.loadConfigFrom(homeConfigDir)
  await self.loadConfigFrom(workspaceConfigDir)

proc reloadConfig*(self: App, clearOptions: bool = false) {.expose("editor").} =
  ## Reloads settings.json and keybindings.json from the app directory, home directory and workspace
  log lvlInfo, &"Reload config"
  if clearOptions:
    self.config.settings = newJObject()
  asyncSpawn self.reloadConfigAsync()

proc reloadPlugin*(self: App) {.expose("editor").} =
  log lvlInfo, &"Reload current plugin"
  asyncSpawn self.reloadPluginAsync()

proc reloadTheme*(self: App) {.expose("editor").} =
  log lvlInfo, &"Reload theme"
  asyncSpawn self.setTheme(self.theme.path, force = true)

proc reloadState*(self: App) {.expose("editor").} =
  ## Reloads some of the state stored in the session file (default: config/config.json)
  var state = EditorState()
  if self.sessionFile != "":
    try:
      waitFor self.restoreStateFromConfig(state.addr)
    except CatchableError as e:
      log lvlError, &"Failed to reload state: {e.msg}\n{e.getStackTrace()}"

  self.requestRender()

proc saveSession*(self: App, sessionFile: string = "") {.expose("editor").} =
  ## Reloads some of the state stored in the session file (default: config/config.json)
  let sessionFile = if sessionFile == "": defaultSessionName else: sessionFile
  try:
    self.sessionFile = os.absolutePath(sessionFile).normalizePathUnix
    self.saveAppState()
    self.requestRender()
  except Exception as e:
    log lvlError, &"Failed to save session: {e.msg}\n{e.getStackTrace()}"

proc dumpKeymapGraphViz*(self: App, context: string = "") {.expose("editor").} =
  for handler in self.currentEventHandlers():
    if context == "" or handler.config.context == context:
      try:
        waitFor self.vfs.write("app://input_dots" // handler.config.context & ".dot", handler.dfa.dumpGraphViz)
      except IOError as e:
        log lvlError, &"Failed to dump keymap graph: {e.msg}\n{e.getStackTrace()}"

proc getModeConfig(self: App, mode: string): EventHandlerConfig =
  return self.events.getEventHandlerConfig("editor." & mode)

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

  let modeOnTop = self.config.getOption[:bool](self.getContextWithMode("editor.custom-mode-on-top"), true)
  if not self.modeEventHandler.isNil and not modeOnTop:
    result.add self.modeEventHandler

  if self.commands.commandLineInputMode:
    result.add self.commands.commandLineEditor.getEventHandlers({"above-mode": self.commands.commandLineEventHandlerLow}.toTable)
    result.add self.commands.commandLineEventHandlerHigh
  elif self.commands.commandLineResultMode:
    result.add self.commands.commandLineEditor.getEventHandlers({"above-mode": self.commands.commandLineResultEventHandlerLow}.toTable)
    result.add self.commands.commandLineResultEventHandlerHigh
  elif self.layout.popups.len > 0:
    result.add self.layout.popups[self.layout.popups.high].getEventHandlers()
  elif self.layout.tryGetCurrentView().getSome(view):
      result.add view.getEventHandlers(initTable[string, EventHandler]())

  if not self.modeEventHandler.isNil and modeOnTop:
    result.add self.modeEventHandler

proc clearInputHistoryDelayed*(self: App) =
  let clearInputHistoryDelay = self.config.getOption[:int]("editor.clear-input-history-delay", 3000)
  if self.clearInputHistoryTask.isNil:
    self.clearInputHistoryTask = startDelayed(clearInputHistoryDelay, repeat=false):
      self.inputHistory.setLen 0
      self.platform.requestRender()
  else:
    self.clearInputHistoryTask.interval = clearInputHistoryDelay
    self.clearInputHistoryTask.reschedule()

proc recordInputToHistory*(self: App, input: string) =
  let recordInput = self.config.getOption[:bool]("editor.record-input-history", false)
  if not recordInput:
    return

  self.inputHistory.add input
  const maxLen = 50
  if self.inputHistory.len > maxLen:
    self.inputHistory = self.inputHistory[(self.inputHistory.len - maxLen)..^1]

proc getNextPossibleInputs*(self: App, inProgressOnly: bool, filter: proc(handler: EventHandler): bool {.gcsafe, raises: [].} = nil): seq[tuple[input: string, description: string, continues: bool]] =
  result.setLen(0)
  let handlers = self.currentEventHandlers
  let anyInProgress = handlers.anyInProgress

  for handler in handlers:
    if (anyInProgress or inProgressOnly) and not handler.inProgress:
      continue

    if filter != nil and not filter(handler):
      continue

    let nextPossibleInputs = handler.getNextPossibleInputs()
    for x in nextPossibleInputs:
      let key = inputToString(x[0], x[1])

      for i in 0..result.high:
        if result[i].input == key:
          result.removeSwap(i)
          break

      for next in x[2]:
        if x[1] == {Shift} and x[0] in 0..Rune.high.int and x[0].Rune.isAlpha:
          continue

        let actions = handler.dfa.getActions(next)
        if actions.len > 1:
          var desc = &"... ({handler.config.context})"
          handler.config.stateToDescription.withValue(next.current, val):
            desc = val[] & "..."
          result.add (key, desc, true)
        elif actions.len > 0:
          var desc = &"{actions[0][0]} {actions[0][1]}"
          handler.config.stateToDescription.withValue(next.current, val):
            desc = val[]
          result.add (key, desc, false)

    result.sort proc(a, b: tuple[input: string, description: string, continues: bool]): int =
      cmp(a.input, b.input)

proc updateNextPossibleInputs*(self: App) =
  let whichKeyInProgressOnly = not self.config.asConfigProvider.getValue("ui.which-key-no-progress", false)
  self.nextPossibleInputs = self.getNextPossibleInputs(whichKeyInProgressOnly)

  if self.nextPossibleInputs.len > 0 and not self.showNextPossibleInputs:
    self.showNextPossibleInputsTask.interval = self.config.getOption("ui.which-key-delay", 500)
    self.showNextPossibleInputsTask.reschedule()

  elif self.nextPossibleInputs.len == 0:
    self.showNextPossibleInputs = false

  if self.showNextPossibleInputs:
    self.platform.requestRender()

proc handleKeyPress*(self: App, input: int64, modifiers: Modifiers) =
  # logScope lvlDebug, &"handleKeyPress {inputToString(input, modifiers)}"
  self.logNextFrameTime = true

  for register in self.registers.recordingKeys:
    if not self.registers.registers.contains(register) or self.registers.registers[register].kind != RegisterKind.Text:
      self.registers.registers[register] = Register(kind: RegisterKind.Text, text: "")
    self.registers.registers[register].text.add inputToString(input, modifiers)

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

  self.updateNextPossibleInputs()

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

  self.updateNextPossibleInputs()

proc handleDropFile*(self: App, path, content: string) =
  let document = newTextDocument(self.services, path, content)
  self.editors.documents.add document
  discard self.layout.createAndAddView(document)

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

proc registerPluginSourceCode*(self: App, path: string, content: string) {.expose("editor").} =
  if self.plugins.currentScriptContext.getSome(scriptContext):
    asyncSpawn self.vfs.write(scriptContext.getCurrentContext() & path, content)

proc addCommandScript*(self: App, context: string, subContext: string, keys: string, action: string, arg: string = "", description: string = "", source: tuple[filename: string, line: int, column: int] = ("", 0, 0)) {.expose("editor").} =
  let command = if arg.len == 0: action else: action & " " & arg

  let context = if context.endsWith("."):
    context[0..^2]
  else:
    context

  # log(lvlInfo, fmt"Adding command to '{context}': ('{subContext}', '{keys}', '{command}')")

  let (baseContext, subContext) = if (let i = context.find('#'); i != -1):
    (context[0..<i], context[i+1..^1] & subContext)
  else:
    (context, subContext)

  if description.len > 0:
    self.events.commandDescriptions[baseContext & subContext & keys] = description
    self.events.getEventHandlerConfig(baseContext).addCommandDescription(keys, description)

  var source = source
  if self.plugins.currentScriptContext.getSome(scriptContext):
    source.filename = scriptContext.getCurrentContext() & source.filename

  self.events.getEventHandlerConfig(baseContext).addCommand(subContext, keys, command, source)
  self.events.invalidateCommandToKeysMap()

proc getActivePopup*(): EditorId {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return EditorId(-1)
    if gEditor.layout.popups.len > 0:
      return gEditor.layout.popups[gEditor.layout.popups.high].id

  return EditorId(-1)

# todo: move to layout
proc getActiveEditor*(): EditorId {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return EditorId(-1)
    if gEditor.commands.commandLineMode:
      return gEditor.commands.commandLineEditor.id

    if gEditor.layout.popups.len > 0 and gEditor.layout.popups[gEditor.layout.popups.high].getActiveEditor().getSome(editor):
      return editor.id

    if gEditor.layout.tryGetCurrentView().getSome(view) and view.getActiveEditor().getSome(editor):
      return editor.id

  return EditorId(-1)

proc getActiveEditor*(self: App): Option[DocumentEditor] =
  if self.commands.commandLineMode:
    return self.commands.commandLineEditor.some

  if self.layout.popups.len > 0 and self.layout.popups[self.layout.popups.high].getActiveEditor().getSome(editor):
    return editor.some

  if self.layout.tryGetCurrentEditorView().getSome(view):
    return view.editor.some

  return DocumentEditor.none

# todo move to layout
proc logRootNode*(self: App) {.expose("editor").} =
  let str = self.platform.builder.root.dump(true)
  debug "logRootNode: ", str

proc scriptIsSelectorPopup*(editorId: EditorId): bool {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return false
    if gEditor.layout.getPopupForId(editorId).getSome(popup):
      return popup of SelectorPopup
  return false

proc scriptIsTextEditor*(editorId: EditorId): bool {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return false
    if gEditor.editors.getEditorForId(editorId).getSome(editor):
      return editor of TextDocumentEditor
  return false

proc scriptIsModelEditor*(editorId: EditorId): bool {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return false
    when enableAst:
      if gEditor.editors.getEditorForId(editorId).getSome(editor):
        return editor of ModelDocumentEditor
  return false

proc scriptRunActionFor*(editorId: EditorId, action: string, arg: string) {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return
    defer:
      gEditor.platform.requestRender()
    if gEditor.editors.getEditorForId(editorId).getSome(editor):
      discard editor.handleAction(action, arg, record=false)
    elif gEditor.layout.getPopupForId(editorId).getSome(popup):
      discard popup.eventHandler.handleAction(action, arg)

proc scriptSetCallback*(path: string, id: int) {.expose("editor").} =
  {.gcsafe.}:
    if gEditor.isNil:
      return
    gEditor.plugins.callbacks[path] = id

proc replayCommands*(self: App, register: string) {.expose("editor").} =
  if not self.registers.registers.contains(register) or self.registers.registers[register].kind != RegisterKind.Text:
    log lvlError, fmt"No commands recorded in register '{register}'"
    return

  if self.registers.bIsReplayingCommands:
    log lvlError, fmt"replayCommands '{register}': Already replaying commands"
    return

  log lvlInfo, &"replayCommands '{register}':\n{self.registers.registers[register].text}"
  self.registers.bIsReplayingCommands = true
  defer:
    self.registers.bIsReplayingCommands = false

  for command in self.registers.registers[register].text.splitLines:
    let (action, arg) = parseAction(command)
    discard self.handleAction(action, arg, record=false)

proc replayKeys*(self: App, register: string) {.expose("editor").} =
  if not self.registers.registers.contains(register) or self.registers.registers[register].kind != RegisterKind.Text:
    log lvlError, fmt"No commands recorded in register '{register}'"
    return

  if self.registers.bIsReplayingKeys:
    log lvlError, fmt"replayKeys '{register}': Already replaying keys"
    return

  log lvlInfo, &"replayKeys '{register}': {self.registers.registers[register].text}"
  self.registers.bIsReplayingKeys = true
  defer:
    self.registers.bIsReplayingKeys = false

  for (inputCode, mods, _) in parseInputs(self.registers.registers[register].text):
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
      for (key, value) in self.registers.registers.mpairs:
        case value.kind
        of RegisterKind.Text:
          result.add &"    {key}: {value.text[0..<min(value.text.len, 150)]}\n"
        of RegisterKind.Rope:
          result.add &"    {key}: {value.rope[0...min(value.rope.len, 150)]}\n"

      result.add &"RecordingKeys:\n"
      for key in self.registers.recordingKeys:
        result.add &"    {key}"

      result.add &"RecordingCommands:\n"
      for key in self.registers.recordingKeys:
        result.add &"    {key}"

      result.add &"Event Handlers: {self.events.eventHandlerConfigs.len}\n"
        # events.eventHandlerConfigs: Table[string, EventHandlerConfig]

      result.add &"Options: {self.config.settings.pretty.len}\n"
      result.add &"Callbacks: {self.plugins.callbacks.len}\n"
      result.add &"Script Actions: {self.plugins.scriptActions.len}\n"

      result.add &"Input History: {self.inputHistory}\n"
      result.add &"Editor History: {self.layout.editorHistory}\n"

      result.add &"Command History: {self.commands.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len}\n"
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

proc handleAction(self: App, action: string, arg: string, record: bool): Option[JsonNode] =
  let t = startTimer()
  if not self.registers.bIsReplayingCommands:
    log lvlInfo, &"[handleAction] '{action} {arg}'"
  defer:
    if not self.registers.bIsReplayingCommands:
      let elapsed = t.elapsed
      log lvlInfo, &"[handleAction] '{action} {arg}' took {elapsed.ms} ms"

  try:
    if record:
      self.registers.recordCommand(action, arg)

    var args = newJArray()
    try:
      for a in newStringStream(arg).parseJsonFragments():
        args.add a
    except CatchableError:
      log(lvlError, fmt"Failed to parse arguments '{arg}': {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())

    if action.startsWith("."): # active action
      if self.getActiveEditor().getSome(editor):
        return editor.handleAction(action[1..^1], arg, record=false)

      log lvlError, fmt"No current view"
      return JsonNode.none

    {.gcsafe.}:
      for t in globalDispatchTables.mitems:
        t.functions.withValue(action, f):
          try:
            let res = f[].dispatch(args)
            if res.isNil:
              continue

            return res.some
          except JsonCallError as e:
            log lvlError, &"Failed to dispatch '{action} {args}': {e.msg}"

    try:
      for sc in self.plugins.scriptContexts:
        withScriptContext self.plugins, sc:
          let res = sc.handleScriptAction(action, args)
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
