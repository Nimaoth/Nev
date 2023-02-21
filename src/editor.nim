import std/[strformat, strutils, tables, logging, unicode, options, os, algorithm, json, jsonutils, macros, macrocache, sugar, streams]
import fuzzy
import input, events, rect_utils, document, document_editor, keybind_autocomplete, popup, timer, event, platform/platform
import theme, util, custom_logger
import scripting/[expose, scripting_base]
import platform/[widgets, filesystem]

when not defined(js):
  import scripting/scripting_nim
else:
  import scripting/scripting_js

import scripting_api as api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, Popup, SelectorPopup
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

type EditorState = object
  theme: string
  fontSize: float32
  fontRegular: string
  fontBold: string
  fontItalic: string
  fontBoldItalic: string
  openEditors: seq[OpenEditor]

type Editor* = ref object
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

  eventHandlerConfigs: Table[string, EventHandlerConfig]

  options: JsonNode
  callbacks: Table[string, int]

  logger: Logger

  scriptContext*: ScriptContext
  initializeCalled: bool

  statusBarOnTop*: bool

  currentView*: int
  views*: seq[View]
  layout*: Layout
  layout_props*: LayoutProperties

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

var gEditor* {.exportc.}: Editor = nil

proc registerEditor*(self: Editor, editor: DocumentEditor) =
  self.editors[editor.id] = editor
  self.onEditorRegistered.invoke editor

proc unregisterEditor*(self: Editor, editor: DocumentEditor) =
  self.editors.del(editor.id)
  self.onEditorDeregistered.invoke editor

method injectDependencies*(self: DocumentEditor, ed: Editor) {.base.} =
  discard

proc invokeCallback*(self: Editor, context: string, args: JsonNode): bool =
  if not self.callbacks.contains(context):
    return false
  let id = self.callbacks[context]
  try:
    return self.scriptContext.invoke(handleCallback, id, args, returnType = bool)
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

proc handleUnknownPopupAction*(self: Editor, popup: Popup, action: string, arg: string): EventResponse =
  try:
    if self.scriptContext.invoke(handleUnknownPopupAction, popup.id, action, arg, returnType = bool):
      return Handled
  except CatchableError:
    logger.log(lvlError, fmt"[ed] Failed to run script handleUnknownPopupAction '{action} {arg}': {getCurrentExceptionMsg()}")
    logger.log(lvlError, getCurrentException().getStackTrace())

  return Failed

proc handleUnknownDocumentEditorAction*(self: Editor, editor: DocumentEditor, action: string, args: JsonNode): EventResponse =
  try:
    if self.scriptContext.invoke(handleEditorAction, editor.id, action, args, returnType = bool):
      return Handled
  except CatchableError:
    logger.log(lvlError, fmt"[ed] Failed to run script handleUnknownDocumentEditorAction '{action} {args}': {getCurrentExceptionMsg()}")
    logger.log(lvlError, getCurrentException().getStackTrace())

  return Failed

proc handleAction(self: Editor, action: string, arg: string): bool
proc getFlag*(self: Editor, flag: string, default: bool = false): bool

proc createEditorForDocument(self: Editor, document: Document): DocumentEditor =
  for editor in self.editor_defaults:
    if editor.canEdit document:
      return editor.createWithDocument document

  logger.log(lvlError, "No editor found which can edit " & $document)
  return nil

proc getOption*[T](editor: Editor, path: string, default: T = T.default): T =
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

proc setOption*[T](editor: Editor, path: string, value: T) =
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

proc setFlag*(self: Editor, flag: string, value: bool)
proc toggleFlag*(self: Editor, flag: string)

proc createView*(self: Editor, document: Document) =
  var editor = self.createEditorForDocument document
  editor.injectDependencies self
  discard editor.onMarkedDirty.subscribe () => self.platform.requestRender()
  var view = View(document: document, editor: editor)

  self.views.add view
  self.currentView = self.views.len - 1
  self.platform.requestRender()

proc pushPopup*(self: Editor, popup: Popup) =
  popup.init()
  self.popups.add popup
  self.platform.requestRender()

proc popPopup*(self: Editor, popup: Popup) =
  if self.popups.len > 0 and self.popups[self.popups.high] == popup:
    discard self.popups.pop
  self.platform.requestRender()

proc getEventHandlerConfig*(self: Editor, context: string): EventHandlerConfig =
  if not self.eventHandlerConfigs.contains(context):
    self.eventHandlerConfigs[context] = newEventHandlerConfig(context)
  return self.eventHandlerConfigs[context]

proc getEditorForId*(self: Editor, id: EditorId): Option[DocumentEditor] =
  if self.editors.contains(id):
    return self.editors[id].some

  if self.commandLineTextEditor.id == id:
    return self.commandLineTextEditor.some

  return DocumentEditor.none

proc getPopupForId*(self: Editor, id: EditorId): Option[Popup] =
  for popup in self.popups:
    if popup.id == id:
      return popup.some

  return Popup.none

import text_document, ast_document
import selector_popup

type ThemeSelectorItem* = ref object of SelectorItem
  name*: string
  path*: string

type FileSelectorItem* = ref object of SelectorItem
  path*: string

proc setTheme*(self: Editor, path: string) =
  if loadFromFile(path).getSome(theme):
    self.theme = theme
  self.platform.requestRender()

when not defined(js):
  proc createScriptContext(filepath: string, searchPaths: seq[string]): ScriptContext

proc getCommandLineTextEditor*(self: Editor): TextDocumentEditor = self.commandLineTextEditor.TextDocumentEditor

proc handleKeyPress*(self: Editor, input: int64, modifiers: Modifiers)
proc handleKeyRelease*(self: Editor, input: int64, modifiers: Modifiers)
proc handleRune*(self: Editor, input: int64, modifiers: Modifiers)
proc handleMousePress*(self: Editor, button: MouseButton, modifiers: Modifiers, mousePosWindow: Vec2)
proc handleMouseRelease*(self: Editor, button: MouseButton, modifiers: Modifiers, mousePosWindow: Vec2)
proc handleMouseMove*(self: Editor, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton])
proc handleScroll*(self: Editor, scroll: Vec2, mousePosWindow: Vec2, modifiers: Modifiers)

proc newEditor*(backend: api.Backend, platform: Platform): Editor =
  var self = Editor()

  # Emit this to set the editor prototype to editor_prototype, which needs to be set up before calling this
  when defined(js):
    {.emit: [self, " = createWithPrototype(editor_prototype, ", self, ");"].}
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
  discard platform.onCloseRequested.subscribe proc(_: auto) = self.closeRequested = true

  self.timer = startTimer()
  self.frameTimer = startTimer()

  self.layout = HorizontalLayout()
  self.layout_props = LayoutProperties(props: {"main-split": 0.5.float32}.toTable)

  self.platform.fontSize = 20

  self.fontRegular = "./fonts/DejaVuSansMono.ttf"
  self.fontBold = "./fonts/DejaVuSansMono-Bold.ttf"
  self.fontItalic = "./fonts/DejaVuSansMono-Oblique.ttf"
  self.fontBoldItalic = "./fonts/DejaVuSansMono-BoldOblique.ttf"

  self.editor_defaults = @[TextDocumentEditor(), AstDocumentEditor()]

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

  self.commandLineTextEditor = newTextEditor(newTextDocument(), self)
  self.commandLineTextEditor.renderHeader = false
  self.commandLineTextEditor.TextDocumentEditor.lineNumbers = api.LineNumbers.None.some
  self.getCommandLineTextEditor.hideCursorWhenInactive = true

  var state = EditorState()
  try:
    state = fs.loadApplicationFile("config.json").parseJson.jsonTo EditorState
    self.setTheme(state.theme)
    self.loadedFontSize = state.fontSize.float
    self.platform.fontSize = state.fontSize.float
    if state.fontRegular.len > 0: self.fontRegular = state.fontRegular
    if state.fontBold.len > 0: self.fontBold = state.fontBold
    if state.fontItalic.len > 0: self.fontItalic = state.fontItalic
    if state.fontBoldItalic.len > 0: self.fontBoldItalic = state.fontBoldItalic

    self.options = fs.loadApplicationFile("options.json").parseJson
    logger.log(lvlInfo, fmt"Restoring options: {self.options.pretty}")

  except:
    logger.log(lvlError, fmt"Failed to load previous state from config file: {getCurrentExceptionMsg()}")

  try:
    var searchPaths = @["src", "scripting"]
    let searchPathsJson = self.options{@["scripting", "search-paths"]}
    if not searchPathsJson.isNil:
      for sp in searchPathsJson:
        searchPaths.add sp.getStr

    when defined(js):
      self.scriptContext = new ScriptContextJs
    else:
      self.scriptContext = createScriptContext("./absytree_config.nims", searchPaths)

    discard self.scriptContext.invoke(postInitialize, returnType = bool)

    self.initializeCalled = true
  except:
    logger.log(lvlError, fmt"Failed to load config")

  # Restore open editors
  if self.getFlag("editor.restore-open-editors"):
    for editorState in state.openEditors:
        let document = if editorState.ast:
          newAstDocument(editorState.filename)
        else:
          try:
            let fileContent = fs.loadFile(editorState.filename)
            newTextDocument(editorState.filename, fileContent)
          except:
            logger.log(lvlError, fmt"Failed to restore file {editorState.filename} from previous session: {getCurrentExceptionMsg()}")
            continue

        self.createView(document)

  return self

proc shutdown*(self: Editor) =
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

  # Save open editors
  for view in self.views:
    if view.document of TextDocument:
      let textDocument = TextDocument(view.document)
      state.openEditors.add OpenEditor(filename: textDocument.filename, ast: false, languageId: textDocument.languageId)
    elif view.document of AstDocument:
      let astDocument = AstDocument(view.document)
      state.openEditors.add OpenEditor(filename: astDocument.filename, ast: true, languageId: "ast")

  let serialized = state.toJson
  fs.saveApplicationFile("config.json", serialized.pretty)
  fs.saveApplicationFile("options.json", self.options.pretty)

  for editor in self.editors.values:
    editor.shutdown()

proc getEditor(): Option[Editor] =
  if gEditor.isNil: return Editor.none
  return gEditor.some

static:
  addInjector(Editor, getEditor)

proc getBackend*(self: Editor): Backend {.expose("editor").} =
  return self.backend

proc requestRender*(self: Editor) {.expose("editor").} =
  self.platform.requestRender()

proc setHandleInputs*(self: Editor, context: string, value: bool) {.expose("editor").} =
  self.getEventHandlerConfig(context).setHandleInputs(value)

proc setHandleActions*(self: Editor, context: string, value: bool) {.expose("editor").} =
  self.getEventHandlerConfig(context).setHandleActions(value)

proc setConsumeAllActions*(self: Editor, context: string, value: bool) {.expose("editor").} =
  self.getEventHandlerConfig(context).setConsumeAllActions(value)

proc setConsumeAllInput*(self: Editor, context: string, value: bool) {.expose("editor").} =
  self.getEventHandlerConfig(context).setConsumeAllInput(value)

proc getFlag*(self: Editor, flag: string, default: bool = false): bool {.expose("editor").} =
  return getOption[bool](self, flag, default)

proc setFlag*(self: Editor, flag: string, value: bool) {.expose("editor").} =
  setOption[bool](self, flag, value)

proc toggleFlag*(self: Editor, flag: string) {.expose("editor").} =
  self.setFlag(flag, not self.getFlag(flag))

proc setOption*(self: Editor, option: string, value: JsonNode) {.expose("editor").} =
  if self.isNil:
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
  node[pathItems[^1]] = value

proc quit*(self: Editor) {.expose("editor").} =
  self.closeRequested = true

proc changeFontSize*(self: Editor, amount: float32) {.expose("editor").} =
  self.platform.fontSize = self.platform.fontSize + amount.float

proc changeLayoutProp*(self: Editor, prop: string, change: float32) {.expose("editor").} =
  self.layout_props.props.mgetOrPut(prop, 0) += change

proc toggleStatusBarLocation*(self: Editor) {.expose("editor").} =
  self.statusBarOnTop = not self.statusBarOnTop

proc createView*(self: Editor) {.expose("editor").} =
  self.createView(newTextDocument())

# proc createKeybindAutocompleteView*(self: Editor) {.expose("editor").} =
#   self.createView(newKeybindAutocompletion())

proc closeCurrentView*(self: Editor) {.expose("editor").} =
  self.views[self.currentView].editor.unregister()
  self.views.delete self.currentView
  self.currentView = self.currentView.clamp(0, self.views.len - 1)
  self.platform.requestRender()

proc moveCurrentViewToTop*(self: Editor) {.expose("editor").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    self.views.delete(self.currentView)
    self.views.insert(view, 0)
  self.currentView = 0
  self.platform.requestRender()

proc nextView*(self: Editor) {.expose("editor").} =
  self.currentView = if self.views.len == 0: 0 else: (self.currentView + 1) mod self.views.len
  self.platform.requestRender()

proc prevView*(self: Editor) {.expose("editor").} =
  self.currentView = if self.views.len == 0: 0 else: (self.currentView + self.views.len - 1) mod self.views.len
  self.platform.requestRender()

proc moveCurrentViewPrev*(self: Editor) {.expose("editor").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    let index = (self.currentView + self.views.len - 1) mod self.views.len
    self.views.delete(self.currentView)
    self.views.insert(view, index)
    self.currentView = index
  self.platform.requestRender()

proc moveCurrentViewNext*(self: Editor) {.expose("editor").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    let index = (self.currentView + 1) mod self.views.len
    self.views.delete(self.currentView)
    self.views.insert(view, index)
    self.currentView = index
  self.platform.requestRender()

proc setLayout*(self: Editor, layout: string) {.expose("editor").} =
  self.layout = case layout
    of "horizontal": HorizontalLayout()
    of "vertical": VerticalLayout()
    of "fibonacci": FibonacciLayout()
    else: HorizontalLayout()
  self.platform.requestRender()

proc commandLine*(self: Editor, initialValue: string = "") {.expose("editor").} =
  self.getCommandLineTextEditor.document.content = @[initialValue]
  self.commandLineMode = true
  self.platform.requestRender()

proc exitCommandLine*(self: Editor) {.expose("editor").} =
  self.getCommandLineTextEditor.document.content = @[""]
  self.commandLineMode = false
  self.platform.requestRender()

proc executeCommandLine*(self: Editor): bool {.expose("editor").} =
  defer:
    self.platform.requestRender()
  self.commandLineMode = false
  let (action, arg) = self.getCommandLineTextEditor.document.content.join("").parseAction
  self.getCommandLineTextEditor.document.content = @[""]
  return self.handleAction(action, arg)

proc openFile*(self: Editor, path: string) {.expose("editor").} =
  defer:
    self.platform.requestRender()
  try:
    if path.endsWith(".ast"):
      self.createView(newAstDocument(path))
    else:
      let file = fs.loadFile(path)
      self.createView(newTextDocument(path, file.splitLines))
  except CatchableError:
    logger.log(lvlError, fmt"[ed] Failed to load file '{path}': {getCurrentExceptionMsg()}")
    logger.log(lvlError, getCurrentException().getStackTrace())

proc writeFile*(self: Editor, path: string = "") {.expose("editor").} =
  defer:
    self.platform.requestRender()
  if self.currentView >= 0 and self.currentView < self.views.len and self.views[self.currentView].document != nil:
    try:
      self.views[self.currentView].document.save(path)
    except CatchableError:
      logger.log(lvlError, fmt"[ed] Failed to write file '{path}': {getCurrentExceptionMsg()}")
      logger.log(lvlError, getCurrentException().getStackTrace())

proc loadFile*(self: Editor, path: string = "") {.expose("editor").} =
  defer:
    self.platform.requestRender()
  if self.currentView >= 0 and self.currentView < self.views.len and self.views[self.currentView].document != nil:
    try:
      self.views[self.currentView].document.load(path)
      self.views[self.currentView].editor.handleDocumentChanged()
    except CatchableError:
      logger.log(lvlError, fmt"[ed] Failed to load file '{path}': {getCurrentExceptionMsg()}")
      logger.log(lvlError, getCurrentException().getStackTrace())

proc loadTheme*(self: Editor, name: string) {.expose("editor").} =
  defer:
    self.platform.requestRender()
  if theme.loadFromFile(fmt"./themes/{name}.json").getSome(theme):
    self.theme = theme
  else:
    logger.log(lvlError, fmt"[ed] Failed to load theme {name}")

proc chooseTheme*(self: Editor) {.expose("editor").} =
  defer:
    self.platform.requestRender()
  let originalTheme = self.theme.path
  var popup = self.newSelectorPopup proc(popup: SelectorPopup, text: string): seq[SelectorItem] =
    for file in walkDirRec("./themes", relative=true):
      if file.endsWith ".json":
        let name = file.splitFile.name
        let score = fuzzyMatchSmart(text, name)
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

  self.pushPopup popup

proc chooseFile*(self: Editor, view: string = "new") {.expose("editor").} =
  defer:
    self.platform.requestRender()
  var popup = self.newSelectorPopup proc(popup: SelectorPopup, text: string): seq[SelectorItem] =
    for file in walkDirRec(".", relative=true):
      let name = file.splitFile.name
      let score = fuzzyMatchSmart(text, name)
      result.add FileSelectorItem(path: fmt"./{file}", score: score)

    result.sort((a, b) => cmp(a.FileSelectorItem.score, b.FileSelectorItem.score), Descending)

  popup.handleItemConfirmed = proc(item: SelectorItem) =
    case view
    of "current":
      self.loadFile(item.FileSelectorItem.path)
    of "new":
      self.openFile(item.FileSelectorItem.path)
    else:
      logger.log(lvlError, fmt"Unknown argument {view}")

  self.pushPopup popup

proc reloadConfig*(self: Editor) {.expose("editor").} =
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

proc logOptions*(self: Editor) {.expose("editor").} =
  logger.log(lvlInfo, self.options.pretty)

proc clearCommands*(self: Editor, context: string) {.expose("editor").} =
  self.getEventHandlerConfig(context).clearCommands()

proc getAllEditors*(self: Editor): seq[EditorId] {.expose("editor").} =
  for id in self.editors.keys:
    result.add id

proc getModeConfig(self: Editor, mode: string): EventHandlerConfig =
  return self.getEventHandlerConfig("editor." & mode)

proc setMode*(self: Editor, mode: string) {.expose("editor").} =
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

proc mode*(self: Editor): string {.expose("editor").} =
  return self.currentMode

proc getContextWithMode(self: Editor, context: string): string {.expose("editor").} =
  return context & "." & $self.currentMode

genDispatcher("editor")

proc handleAction(self: Editor, action: string, arg: string): bool =
  logger.log(lvlInfo, "[ed] Action '$1 $2'" % [action, arg])
  try:
    if self.scriptContext.invoke(handleGlobalAction, action, arg, returnType = bool):
      return true
  except CatchableError:
    logger.log(lvlError, fmt"[ed] Failed to run script handleGlobalAction '{action} {arg}': {getCurrentExceptionMsg()}")
    logger.log(lvlError, getCurrentException().getStackTrace())
    return false

  var args = newJArray()
  for a in newStringStream(arg).parseJsonFragments():
    args.add a
  return dispatch(action, args).isSome

proc currentEventHandlers*(self: Editor): seq[EventHandler] =
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

proc handleMousePress*(self: Editor, button: MouseButton, modifiers: Modifiers, mousePosWindow: Vec2) =
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
      view.editor.handleMousePress(button, mousePosWindow)
      return

proc handleMouseRelease*(self: Editor, button: MouseButton, modifiers: Modifiers, mousePosWindow: Vec2) =
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

proc handleMouseMove*(self: Editor, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
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

proc handleScroll*(self: Editor, scroll: Vec2, mousePosWindow: Vec2, modifiers: Modifiers) =
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

proc handleKeyPress*(self: Editor, input: int64, modifiers: Modifiers) =
  self.currentEventHandlers.handleEvent(input, modifiers)

proc handleKeyRelease*(self: Editor, input: int64, modifiers: Modifiers) =
  discard

proc handleRune*(self: Editor, input: int64, modifiers: Modifiers) =
  let modifiers = if input.isAscii and input.char.isAlphaNumeric: modifiers else: {}
  self.currentEventHandlers.handleEvent(input, modifiers)

proc scriptRunAction*(action: string, arg: string) {.expose("editor").} =
  if gEditor.isNil:
    return
  discard gEditor.handleAction(action, arg)

proc scriptLog*(message: string) {.expose("editor").} =
  logger.log(lvlInfo, fmt"[script] {message}")

proc scriptAddCommand*(context: string, keys: string, action: string, arg: string = "") {.expose("editor").} =
  if gEditor.isNil:
    return

  let command = if arg.len == 0: action else: action & " " & arg
  # logger.log(lvlInfo, fmt"Adding command to '{context}': ('{keys}', '{command}')")
  gEditor.getEventHandlerConfig(context).addCommand(keys, command)

proc removeCommand*(context: string, keys: string) {.expose("editor").} =
  if gEditor.isNil:
    return

  # logger.log(lvlInfo, fmt"Removing command from '{context}': '{keys}'")
  gEditor.getEventHandlerConfig(context).removeCommand(keys)

proc getActivePopup*(): EditorId {.expose("editor").} =
  if gEditor.isNil:
    return EditorId(-1)
  if gEditor.popups.len > 0:
    return gEditor.popups[gEditor.popups.high].id

  return EditorId(-1)

when defined(js):
  proc getActiveEditor2*(): DocumentEditor {.expose("editor"), nodispatch.} =
    if gEditor.isNil:
      return nil
    if gEditor.commandLineMode:
      return gEditor.commandLineTextEditor
    if gEditor.currentView >= 0 and gEditor.currentView < gEditor.views.len:
      return gEditor.views[gEditor.currentView].editor

    return nil

proc getActiveEditor*(): EditorId {.expose("editor").} =
  if gEditor.isNil:
    return EditorId(-1)
  if gEditor.commandLineMode:
    return gEditor.commandLineTextEditor.id
  if gEditor.currentView >= 0 and gEditor.currentView < gEditor.views.len:
    return gEditor.views[gEditor.currentView].editor.id

  return EditorId(-1)

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

when not defined(js):
  proc createAddins(): VmAddins =
    addCallable(myImpl):
      proc postInitialize(): bool
      proc handleGlobalAction(action: string, arg: string): bool
      proc handleEditorAction(id: EditorId, action: string, args: JsonNode): bool
      proc handleUnknownPopupAction(id: EditorId, action: string, arg: string): bool
      proc handleCallback(id: int, args: JsonNode): bool

    return implNimScriptModule(myImpl)

  const addins = createAddins()

  static:
    generateScriptingApi(addins)

  createScriptContextConstructor(addins)

  proc createScriptContext(filepath: string, searchPaths: seq[string]): ScriptContext = createScriptContextNim(filepath, searchPaths)