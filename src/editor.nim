import std/[strformat, strutils, tables, logging, unicode, options, os, algorithm, json, jsonutils, macros, macrocache, sugar, streams]
import boxy, windy, fuzzy
import input, events, rect_utils, document, document_editor, keybind_autocomplete, popup, render_context, timer
import theme, util
import scripting
import nimscripter, nimscripter/[vmconversion, vmaddins]

import scripting_api as api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, Popup, SelectorPopup

var logger = newConsoleLogger()

proc toInput(rune: Rune): int64 =
  return rune.int64

proc toInput(button: Button): int64 =
  return case button
  of KeyEnter: INPUT_ENTER
  of KeyEscape: INPUT_ESCAPE
  of KeyBackspace: INPUT_BACKSPACE
  of KeySpace: INPUT_SPACE
  of KeyDelete: INPUT_DELETE
  of KeyTab: INPUT_TAB
  of KeyLeft: INPUT_LEFT
  of KeyRight: INPUT_RIGHT
  of KeyUp: INPUT_UP
  of KeyDown: INPUT_DOWN
  of KeyHome: INPUT_HOME
  of KeyEnd: INPUT_END
  of KeyPageUp: INPUT_PAGE_UP
  of KeyPageDown: INPUT_PAGE_DOWN
  of KeyA..KeyZ: ord(button) - ord(KeyA) + ord('a')
  of Key0..Key9: ord(button) - ord(Key0) + ord('0')
  of Numpad0..Numpad9: ord(button) - ord(Numpad0) + ord('0')
  of KeyF1..KeyF12: INPUT_F1 - (ord(button) - ord(KeyF1))
  of NumpadAdd: ord '+'
  of NumpadSubtract: ord '-'
  of NumpadMultiply: ord '*'
  of NumpadDivide: ord '/'
  else: 0

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

type EditorState = object
  theme: string
  fontSize: float32
  fontRegular: string
  fontBold: string
  fontItalic: string
  fontBoldItalic: string

type Editor* = ref object
  window*: Window
  boxy*: Boxy
  boxy2*: Boxy
  ctx*: Context
  renderCtx*: RenderContext
  fontRegular*: string
  fontBold*: string
  fontItalic*: string
  fontBoldItalic*: string
  clearAtlasTimer*: Timer
  timer*: Timer
  frameTimer*: Timer
  lastBounds*: Rect

  eventHandlerConfigs: Table[string, EventHandlerConfig]

  options: JsonNode

  logger: Logger

  scriptContext*: ScriptContext
  initializeCalled: bool

  statusBarOnTop*: bool

  currentView*: int
  views*: seq[View]
  layout*: Layout
  layout_props*: LayoutProperties

  theme*: Theme

  editors*: Table[EditorId, DocumentEditor]
  popups*: seq[Popup]

  commandLineTextEditor: DocumentEditor
  eventHandler*: EventHandler
  commandLineEventHandler*: EventHandler
  commandLineMode*: bool

  modeEventHandler: EventHandler
  currentMode*: string

  editor_defaults: seq[DocumentEditor]

var gEditor*: Editor = nil

proc registerEditor*(self: Editor, editor: DocumentEditor) =
  self.editors[editor.id] = editor

proc unregisterEditor*(self: Editor, editor: DocumentEditor) =
  self.editors.del(editor.id)

method injectDependencies*(self: DocumentEditor, ed: Editor) {.base.} =
  discard

proc handleAction(action: string, arg: string): EventResponse =
  echo "event: " & action & " - " & arg
  return Handled

proc handleInput(input: string): EventResponse =
  echo "input: " & input
  return Handled

method layoutViews*(layout: Layout, props: LayoutProperties, bounds: Rect, views: openArray[View]): seq[Rect] {.base.} =
  return @[bounds]

method layoutViews*(layout: HorizontalLayout, props: LayoutProperties, bounds: Rect, views: openArray[View]): seq[Rect] =
  let mainSplit = props.props.getOrDefault("main-split", 0.5)
  result = @[]
  var rect = bounds
  for i, view in views:
    let ratio = if i == 0 and views.len > 1: mainSplit else: 1.0 / (views.len - i).float32
    let (view_rect, remaining) = rect.splitV(ratio.percent)
    rect = remaining
    result.add view_rect

method layoutViews*(layout: VerticalLayout, props: LayoutProperties, bounds: Rect, views: openArray[View]): seq[Rect] =
  let mainSplit = props.props.getOrDefault("main-split", 0.5)
  result = @[]
  var rect = bounds
  for i, view in views:
    let ratio = if i == 0 and views.len > 1: mainSplit else: 1.0 / (views.len - i).float32
    let (view_rect, remaining) = rect.splitH(ratio.percent)
    rect = remaining
    result.add view_rect

method layoutViews*(layout: FibonacciLayout, props: LayoutProperties, bounds: Rect, views: openArray[View]): seq[Rect] =
  let mainSplit = props.props.getOrDefault("main-split", 0.5)
  result = @[]
  var rect = bounds
  for i, view in views:
    let ratio = if i == 0 and views.len > 1: mainSplit elif i == views.len - 1: 1.0 else: 0.5
    let (view_rect, remaining) = if i mod 2 == 0: rect.splitV(ratio.percent) else: rect.splitH(ratio.percent)
    rect = remaining
    result.add view_rect

proc handleUnknownPopupAction*(self: Editor, popup: Popup, action: string, arg: string): EventResponse =
  try:
    if self.scriptContext.inter.invoke(handleUnknownPopupAction, popup.id, action, arg, returnType = bool):
      return Handled
  except:
    self.logger.log(lvlError, fmt"[ed] Failed to run script handleUnknownPopupAction '{action} {arg}': {getCurrentExceptionMsg()}")
    echo getCurrentException().getStackTrace()

  return Failed

proc handleUnknownDocumentEditorAction*(self: Editor, editor: DocumentEditor, action: string, arg: string): EventResponse =
  try:
    if self.scriptContext.inter.invoke(handleEditorAction, editor.id, action, arg, returnType = bool):
      return Handled
  except:
    self.logger.log(lvlError, fmt"[ed] Failed to run script handleUnknownDocumentEditorAction '{action} {arg}': {getCurrentExceptionMsg()}")
    echo getCurrentException().getStackTrace()

  return Failed

proc handleAction(self: Editor, action: string, arg: string): bool
proc getFlag*(self: Editor, flag: string, default: bool = false): bool

proc createEditorForDocument(self: Editor, document: Document): DocumentEditor =
  for editor in self.editor_defaults:
    if editor.canEdit document:
      return editor.createWithDocument document

  echo "No editor found which can edit " & $document
  return nil

proc getOption*[T](editor: Editor, path: string, default: T = T.default): T =
  template createScriptGetOption(editor, path, defaultValue, accessor: untyped): untyped =
    block:
      if editor.isNil:
        return default
      let node = editor.options{path.split(".")}
      if node.isNil:
        return default
      accessor(node, defaultValue)

  when T is bool:
    return editor.createScriptGetOption(path, default, getBool)
  elif T is enum:
    return parseEnum[T](editor.createScriptGetOption(path, "", getStr), default)
  elif T is Ordinal:
    return editor.createScriptGetOption(path, default, getInt)
  elif T is float32 | float64:
    return editor.createScriptGetOption(path, default, getFloat)
  elif T is string:
    return editor.createScriptGetOption(path, default, getStr)
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

proc createView(self: Editor, editor: DocumentEditor) =
  var view = View(document: nil, editor: editor)

  self.views.add view
  self.currentView = self.views.len - 1

proc createView(self: Editor, document: Document) =
  var editor = self.createEditorForDocument document
  editor.injectDependencies self
  var view = View(document: document, editor: editor)

  self.views.add view
  self.currentView = self.views.len - 1

proc pushPopup*(self: Editor, popup: Popup) =
  popup.init()
  self.popups.add popup

proc popPopup*(self: Editor, popup: Popup) =
  if self.popups.len > 0 and self.popups[self.popups.high] == popup:
    discard self.popups.pop

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

proc getPopupForId*(self: Editor, id: PopupId): Option[Popup] =
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

proc createAddins(): VmAddins

proc getCommandLineTextEditor*(self: Editor): TextDocumentEditor = self.commandLineTextEditor.TextDocumentEditor

proc newEditor*(window: Window, boxy: Boxy): Editor =
  var self = Editor()
  self.window = window
  self.boxy = boxy
  self.boxy2 = newBoxy()
  self.statusBarOnTop = false
  self.logger = newConsoleLogger()

  self.timer = startTimer()
  self.frameTimer = startTimer()

  self.layout = HorizontalLayout()
  self.layout_props = LayoutProperties(props: {"main-split": 0.5.float32}.toTable)

  self.ctx = newContext(1, 1)
  self.ctx.fillStyle = rgb(255, 255, 255)
  self.ctx.strokeStyle = rgb(255, 255, 255)
  self.ctx.font = "fonts/DejaVuSansMono.ttf"
  self.ctx.fontSize = 20
  self.ctx.textBaseline = TopBaseline

  self.renderCtx = RenderContext(boxy: boxy, ctx: self.ctx)

  self.fontRegular = "./fonts/DejaVuSansMono.ttf"
  self.fontBold = "./fonts/DejaVuSansMono-Bold.ttf"
  self.fontItalic = "./fonts/DejaVuSansMono-Oblique.ttf"
  self.fontBoldItalic = "./fonts/DejaVuSansMono-BoldOblique.ttf"

  self.editor_defaults = @[TextDocumentEditor(), AstDocumentEditor()]

  self.theme = defaultTheme()
  self.setTheme("./themes/tokyo-night-color-theme.json")

  self.createView(newAstDocument("a.ast"))
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

  try:
    let state = readFile("config.json").parseJson.jsonTo EditorState
    self.setTheme(state.theme)
    self.ctx.fontSize = state.fontSize
    self.ctx.font = state.fontRegular
    if state.fontRegular.len > 0: self.fontRegular = state.fontRegular
    if state.fontBold.len > 0: self.fontBold = state.fontBold
    if state.fontItalic.len > 0: self.fontItalic = state.fontItalic
    if state.fontBoldItalic.len > 0: self.fontBoldItalic = state.fontBoldItalic

    self.options = readFile("options.json").parseJson
    echo "Restoring options: ", self.options.pretty

  except:
    echo "Failed to load previous state from config file"

  gEditor = self

  self.commandLineTextEditor = newTextEditor(newTextDocument(), self)
  self.commandLineTextEditor.renderHeader = false
  self.commandLineTextEditor.TextDocumentEditor.lineNumbers = api.LineNumbers.None.some
  self.getCommandLineTextEditor.hideCursorWhenInactive = true

  let addins = createAddins()
  try:
    self.scriptContext = newScriptContext("./absytree_config.nims", addins)
    self.scriptContext.inter.invoke(postInitialize)
    self.initializeCalled = true
  except:
    self.logger.log(lvlError, fmt"Failed to load config")

  return self

proc shutdown*(self: Editor) =
  # Save some state
  var state = EditorState()
  state.theme = self.theme.path
  state.fontSize = self.ctx.fontSize
  state.fontRegular = self.fontRegular
  state.fontBold = self.fontBold
  state.fontItalic = self.fontItalic
  state.fontBoldItalic = self.fontBoldItalic

  let serialized = state.toJson
  writeFile("config.json", serialized.pretty)
  writeFile("options.json", self.options.pretty)

proc getEditor(): Option[Editor] =
  if gEditor.isNil: return Editor.none
  return gEditor.some

static:
  addInjector(Editor, getEditor)

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
  self.window.closeRequested = true

proc changeFontSize*(self: Editor, amount: float32) {.expose("editor").} =
  self.ctx.fontSize += amount

proc changeLayoutProp*(self: Editor, prop: string, change: float32) {.expose("editor").} =
  self.layout_props.props.mgetOrPut(prop, 0) += change

proc toggleStatusBarLocation*(self: Editor) {.expose("editor").} =
  self.statusBarOnTop = not self.statusBarOnTop

proc createView*(self: Editor) {.expose("editor").} =
  self.createView(newTextDocument())

proc createKeybindAutocompleteView*(self: Editor) {.expose("editor").} =
  self.createView(newKeybindAutocompletion())

proc closeCurrentView*(self: Editor) {.expose("editor").} =
  self.views[self.currentView].editor.unregister()
  self.views.delete self.currentView
  self.currentView = self.currentView.clamp(0, self.views.len - 1)

proc moveCurrentViewToTop*(self: Editor) {.expose("editor").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    self.views.delete(self.currentView)
    self.views.insert(view, 0)
  self.currentView = 0

proc nextView*(self: Editor) {.expose("editor").} =
  self.currentView = if self.views.len == 0: 0 else: (self.currentView + 1) mod self.views.len

proc prevView*(self: Editor) {.expose("editor").} =
  self.currentView = if self.views.len == 0: 0 else: (self.currentView + self.views.len - 1) mod self.views.len

proc moveCurrentViewPrev*(self: Editor) {.expose("editor").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    let index = (self.currentView + self.views.len - 1) mod self.views.len
    self.views.delete(self.currentView)
    self.views.insert(view, index)
    self.currentView = index

proc moveCurrentViewNext*(self: Editor) {.expose("editor").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    let index = (self.currentView + 1) mod self.views.len
    self.views.delete(self.currentView)
    self.views.insert(view, index)
    self.currentView = index

proc setLayout*(self: Editor, layout: string) {.expose("editor").} =
  self.layout = case layout
    of "horizontal": HorizontalLayout()
    of "vertical": VerticalLayout()
    of "fibonacci": FibonacciLayout()
    else: HorizontalLayout()

proc commandLine*(self: Editor, initialValue: string = "") {.expose("editor").} =
  self.getCommandLineTextEditor.document.content = @[initialValue]
  self.commandLineMode = true

proc exitCommandLine*(self: Editor) {.expose("editor").} =
  self.getCommandLineTextEditor.document.content = @[""]
  self.commandLineMode = false

proc executeCommandLine*(self: Editor): bool {.expose("editor").} =
  self.commandLineMode = false
  let (action, arg) = self.getCommandLineTextEditor.document.content.join("").parseAction
  self.getCommandLineTextEditor.document.content = @[""]
  return self.handleAction(action, arg)

proc openFile*(self: Editor, path: string) {.expose("editor").} =
  try:
    if path.endsWith(".ast"):
      self.createView(newAstDocument(path))
    else:
      let file = readFile(path)
      self.createView(newTextDocument(path, file.splitLines))
  except:
    self.logger.log(lvlError, fmt"[ed] Failed to load file '{path}': {getCurrentExceptionMsg()}")
    echo getCurrentException().getStackTrace()

proc writeFile*(self: Editor, path: string = "") {.expose("editor").} =
  if self.currentView >= 0 and self.currentView < self.views.len and self.views[self.currentView].document != nil:
    try:
      self.views[self.currentView].document.save(path)
    except:
      self.logger.log(lvlError, fmt"[ed] Failed to write file '{path}': {getCurrentExceptionMsg()}")
      echo getCurrentException().getStackTrace()

proc loadFile*(self: Editor, path: string = "") {.expose("editor").} =
  if self.currentView >= 0 and self.currentView < self.views.len and self.views[self.currentView].document != nil:
    try:
      self.views[self.currentView].document.load(path)
      self.views[self.currentView].editor.handleDocumentChanged()
    except:
      self.logger.log(lvlError, fmt"[ed] Failed to load file '{path}': {getCurrentExceptionMsg()}")
      echo getCurrentException().getStackTrace()

proc loadTheme*(self: Editor, name: string) {.expose("editor").} =
  if theme.loadFromFile(fmt"./themes/{name}.json").getSome(theme):
    self.theme = theme
  else:
    self.logger.log(lvlError, fmt"[ed] Failed to load theme {name}")

proc chooseTheme*(self: Editor) {.expose("editor").} =
  let originalTheme = self.theme.path
  var popup = self.newSelectorPopup proc(popup: SelectorPopup, text: string): seq[SelectorItem] =
    for file in walkDirRec("./themes", relative=true):
      if file.endsWith ".json":
        let name = file.splitFile[1]
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
  var popup = self.newSelectorPopup proc(popup: SelectorPopup, text: string): seq[SelectorItem] =
    for file in walkDirRec(".", relative=true):
      let name = file.splitFile[1]
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
      self.logger.log(lvlError, fmt"Unknown argument {view}")

  self.pushPopup popup

proc reloadConfig*(self: Editor) {.expose("editor").} =
  if self.scriptContext.isNil.not:
    try:
      self.scriptContext.reloadScript()
      if not self.initializeCalled:
        self.scriptContext.inter.invoke(postInitialize)
        self.initializeCalled = true
    except:
      self.logger.log(lvlError, fmt"Failed to reload config")

proc logOptions*(self: Editor) {.expose("editor").} =
  self.logger.log(lvlInfo, self.options.pretty)

proc clearCommands*(self: Editor, context: string) {.expose("editor").} =
  self.getEventHandlerConfig(context).clearCommands()

proc getAllEditors*(self: Editor): seq[EditorId] {.expose("editor").} =
  for id in self.editors.keys:
    result.add id

proc getModeConfig(self: Editor, mode: string): EventHandlerConfig =
  return self.getEventHandlerConfig("editor." & mode)

proc setMode*(self: Editor, mode: string) {.expose("editor").} =
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
  self.logger.log(lvlInfo, "[ed] Action '$1 $2'" % [action, arg])
  try:
    if self.scriptContext.inter.invoke(handleGlobalAction, action, arg, returnType = bool):
      return true
  except:
    self.logger.log(lvlError, fmt"[ed] Failed to run script handleGlobalAction '{action} {arg}': {getCurrentExceptionMsg()}")
    echo getCurrentException().getStackTrace()
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

proc handleMousePress*(self: Editor, button: Button, modifiers: Modifiers, mousePosWindow: Vec2) =
  # Check popups
  for i in 0..self.popups.high:
    let popup = self.popups[self.popups.high - i]
    if popup.lastBounds.contains(mousePosWindow):
      popup.handleMousePress(button, mousePosWindow)
      return

  # Check views
  let rects = self.layout.layoutViews(self.layout_props, self.lastBounds, self.views)
  for i, view in self.views:
    if i >= rects.len:
      return
    if rects[i].contains(mousePosWindow):
      self.currentView = i
      view.editor.handleMousePress(button, mousePosWindow)
      return

proc handleMouseRelease*(self: Editor, button: Button, modifiers: Modifiers, mousePosWindow: Vec2) =
  # Check popups
  for i in 0..self.popups.high:
    let popup = self.popups[self.popups.high - i]
    if popup.lastBounds.contains(mousePosWindow):
      popup.handleMouseRelease(button, mousePosWindow)
      return

  # Check views
  let rects = self.layout.layoutViews(self.layout_props, self.lastBounds, self.views)
  for i, view in self.views:
    if i >= rects.len:
      return
    if self.currentView == i and rects[i].contains(mousePosWindow):
      view.editor.handleMouseRelease(button, mousePosWindow)
      return

proc handleMouseMove*(self: Editor, mousePosWindow: Vec2, mousePosDelta: Vec2) =
  # Check popups
  for i in 0..self.popups.high:
    let popup = self.popups[self.popups.high - i]
    if popup.lastBounds.contains(mousePosWindow):
      popup.handleMouseMove(mousePosWindow, mousePosDelta)
      return

  # Check views
  let rects = self.layout.layoutViews(self.layout_props, self.lastBounds, self.views)
  for i, view in self.views:
    if i >= rects.len:
      return
    if self.currentView == i and rects[i].contains(mousePosWindow):
      view.editor.handleMouseMove(mousePosWindow, mousePosDelta)
      return

proc handleScroll*(self: Editor, scroll: Vec2, mousePosWindow: Vec2) =
  # Check popups
  for i in 0..self.popups.high:
    let popup = self.popups[self.popups.high - i]
    if popup.lastBounds.contains(mousePosWindow):
      popup.handleScroll(scroll, mousePosWindow)
      return

  # Check views
  let rects = self.layout.layoutViews(self.layout_props, self.lastBounds, self.views)
  for i, view in self.views:
    if i >= rects.len:
      return
    if rects[i].contains(mousePosWindow):
      view.editor.handleScroll(scroll, mousePosWindow)
      return

proc handleKeyPress*(self: Editor, button: Button, modifiers: Modifiers) =
  let input = button.toInput()
  self.currentEventHandlers.handleEvent(input, modifiers)

proc handleKeyRelease*(self: Editor, button: Button, modifiers: Modifiers) =
  discard

proc handleRune*(self: Editor, rune: Rune, modifiers: Modifiers) =
  let modifiers = if rune.int64.isAscii and rune.char.isAlphaNumeric: modifiers else: {}
  let input = rune.toInput()
  self.currentEventHandlers.handleEvent(input, modifiers)

proc scriptRunAction*(action: string, arg: string) =
  if gEditor.isNil:
    return
  discard gEditor.handleAction(action, arg)

proc scriptLog*(message: string) =
  logger.log(lvlInfo, message)

proc scriptAddCommand*(context: string, keys: string, action: string, arg: string) =
  if gEditor.isNil:
    return

  let command = if arg.len == 0: action else: action & " " & arg
  # logger.log(lvlInfo, fmt"Adding command to '{context}': ('{keys}', '{command}')")
  gEditor.getEventHandlerConfig(context).addCommand(keys, command)

proc scriptRemoveCommand*(context: string, keys: string) =
  if gEditor.isNil:
    return

  # logger.log(lvlInfo, fmt"Removing command from '{context}': '{keys}'")
  gEditor.getEventHandlerConfig(context).removeCommand(keys)

proc scriptGetActivePopupHandle*(): PopupId =
  if gEditor.isNil:
    return PopupId(-1)
  if gEditor.popups.len > 0:
    return gEditor.popups[gEditor.popups.high].id

  return PopupId(-1)

proc scriptGetActiveEditorHandle*(): EditorId =
  if gEditor.isNil:
    return EditorId(-1)
  if gEditor.commandLineMode:
    return gEditor.commandLineTextEditor.id
  if gEditor.currentView >= 0 and gEditor.currentView < gEditor.views.len:
    return gEditor.views[gEditor.currentView].editor.id

  return EditorId(-1)

proc scriptGetEditorHandle*(index: int): EditorId =
  if gEditor.isNil:
    return EditorId(-1)
  if index >= 0 and index < gEditor.views.len:
    return gEditor.views[index].editor.id

  return EditorId(-1)

proc scriptIsTextEditor*(editorId: EditorId): bool =
  if gEditor.isNil:
    return false
  if gEditor.getEditorForId(editorId).getSome(editor):
    return editor of TextDocumentEditor
  return false

proc scriptIsAstEditor*(editorId: EditorId): bool =
  if gEditor.isNil:
    return false
  if gEditor.getEditorForId(editorId).getSome(editor):
    return editor of AstDocumentEditor
  return false

proc scriptRunActionFor*(editorId: EditorId, action: string, arg: string) =
  if gEditor.isNil:
    return
  if gEditor.getEditorForId(editorId).getSome(editor):
    discard editor.eventHandler.handleAction(action, arg)

proc scriptRunActionForPopup*(popupId: PopupId, action: string, arg: string) =
  if gEditor.isNil:
    return
  if gEditor.getPopupForId(popupId).getSome(popup):
    discard popup.eventHandler.handleAction(action, arg)

proc scriptInsertTextInto*(editorId: EditorId, text: string) =
  if gEditor.isNil:
    return
  if gEditor.getEditorForId(editorId).getSome(editor):
    discard editor.eventHandler.handleInput(text)

proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  if gEditor.isNil:
    return ((0, 0), (0, 0))
  if gEditor.getEditorForId(editorId).getSome(editor):
    if editor of TextDocumentEditor:
      let editor = TextDocumentEditor(editor)
      return editor.selection
  return ((0, 0), (0, 0))

proc scriptSetTextEditorSelection*(editorId: EditorId, selection: Selection) =
  if gEditor.isNil:
    return
  if gEditor.getEditorForId(editorId).getSome(editor):
    if editor of TextDocumentEditor:
      editor.TextDocumentEditor.selection = selection

proc scriptGetTextEditorLine*(editorId: EditorId, line: int): string =
  if gEditor.isNil:
    return ""
  if gEditor.getEditorForId(editorId).getSome(editor):
    if editor of TextDocumentEditor:
      let editor = TextDocumentEditor(editor)
      if line >= 0 and line < editor.document.content.len:
        return editor.document.content[line]
  return ""

proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
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

proc scriptGetOptionInt*(path: string, default: int): int =
  result = createScriptGetOption(path, default, getInt)

proc scriptGetOptionFloat*(path: string, default: float): float =
  result = createScriptGetOption(path, default, getFloat)

proc scriptGetOptionBool*(path: string, default: bool): bool =
  result = createScriptGetOption(path, default, getBool)

proc scriptGetOptionString*(path: string, default: string): string =
  result = createScriptGetOption(path, default, getStr)

proc scriptSetOptionInt*(path: string, value: int) =
  createScriptSetOption(path, newJInt(value))

proc scriptSetOptionFloat*(path: string, value: float) =
  createScriptSetOption(path, newJFloat(value))

proc scriptSetOptionBool*(path: string, value: bool) =
  createScriptSetOption(path, newJBool(value))

proc scriptSetOptionString*(path: string, value: string) =
  createScriptSetOption(path, newJString(value))

proc createAddins(): VmAddins =
  exportTo(myImpl,
    scriptRunAction,
    scriptLog,
    scriptAddCommand,
    scriptRemoveCommand,
    scriptGetActiveEditorHandle,
    scriptGetActivePopupHandle,
    scriptGetEditorHandle,
    scriptRunActionFor,
    scriptRunActionForPopup,
    scriptInsertTextInto,
    scriptIsTextEditor,
    scriptIsAstEditor,
    scriptTextEditorSelection,
    scriptSetTextEditorSelection,
    scriptGetTextEditorLine,
    scriptGetTextEditorLineCount,
    scriptGetOptionInt,
    scriptGetOptionFloat,
    scriptGetOptionBool,
    scriptGetOptionString,
    scriptSetOptionInt,
    scriptSetOptionFloat,
    scriptSetOptionBool,
    scriptSetOptionString,
    )
  addCallable(myImpl):
    proc handleGlobalAction(action: string, arg: string): bool
    proc postInitialize()
    proc handleEditorAction(id: EditorId, action: string, arg: string): bool
    proc handleUnknownPopupAction(id: PopupId, action: string, arg: string): bool
  return implNimScriptModule(myImpl)