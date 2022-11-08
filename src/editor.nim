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

proc parseAction(action: string): tuple[action: string, arg: string] =
  let spaceIndex = action.find(' ')
  if spaceIndex == -1:
    return (action, "")
  else:
    return (action[0..<spaceIndex], action[spaceIndex + 1..^1])

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

  editor_defaults: seq[DocumentEditor]

var gEditor*: Editor = nil

proc registerEditor*(self: Editor, editor: DocumentEditor) =
  self.editors[editor.id] = editor

proc unregisterEditor*(self: Editor, editor: DocumentEditor) =
  self.editors.del(editor.id)

method injectDependencies*(self: DocumentEditor, ed: Editor) {.base.} =
  discard

proc reset*(handler: var EventHandler) =
  handler.state = 0

proc handleEvent*(handler: var EventHandler, input: int64, modifiers: Modifiers, handleUnknownAsInput: bool): EventResponse =
  if input != 0:
    let prevState = handler.state
    handler.state = handler.dfa.step(handler.state, input, modifiers)
    # echo prevState, " -> ", handler.state
    if handler.state == 0:
      if prevState == 0:
        # undefined input in state 0
        if handleUnknownAsInput and input > 0 and modifiers + {Shift} == {Shift} and handler.handleInput != nil:
          return handler.handleInput(inputToString(input, {}))
        return Ignored
      else:
        # undefined input in state n
        return Canceled

    elif handler.dfa.isTerminal(handler.state):
      let (action, arg) = handler.dfa.getAction(handler.state).parseAction
      handler.state = 0
      return handler.handleAction(action, arg)
    else:
      return Progress
  else:
    return Failed

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

proc handleUnknownPopupAction*(ed: Editor, popup: Popup, action: string, arg: string): EventResponse =
  try:
    if ed.scriptContext.inter.invoke(handleUnknownPopupAction, popup.id, action, arg, returnType = bool):
      return Handled
  except:
    ed.logger.log(lvlError, fmt"[ed] Failed to run script handleUnknownPopupAction '{action} {arg}': {getCurrentExceptionMsg()}")
    echo getCurrentException().getStackTrace()

  return Failed

proc handleUnknownDocumentEditorAction*(ed: Editor, editor: DocumentEditor, action: string, arg: string): EventResponse =
  try:
    if ed.scriptContext.inter.invoke(handleEditorAction, editor.id, action, arg, returnType = bool):
      return Handled
  except:
    ed.logger.log(lvlError, fmt"[ed] Failed to run script handleUnknownDocumentEditorAction '{action} {arg}': {getCurrentExceptionMsg()}")
    echo getCurrentException().getStackTrace()

  return Failed

proc handleAction(ed: Editor, action: string, arg: string)

proc createEditorForDocument(ed: Editor, document: Document): DocumentEditor =
  for editor in ed.editor_defaults:
    if editor.canEdit document:
      return editor.createWithDocument document

  echo "No editor found which can edit " & $document
  return nil

proc getOption*[T](editor: Editor, path: string, default: T = T.default): T =
  template createScriptGetOption(editor, path, default, accessor: untyped): untyped =
    block:
      if editor.isNil:
        return default
      let node = editor.options{path.split(".")}
      if node.isNil:
        return default
      accessor(node, default)

  when T is bool:
    return editor.createScriptGetOption(path, default, getBool)
  elif T is Ordinal:
    return editor.createScriptGetOption(path, default, getInt)
  elif T is float32 | float64:
    return editor.createScriptGetOption(path, default, getFloat)
  elif T is string:
    return editor.createScriptGetOption(path, default, getStr)
  else:
    {.fatal: ("Can't get option with type " & $T).}

proc setOption*(editor: Editor, path: string, value: JsonNode) =
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
  node[pathItems[^1]] = value

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

proc getFlag*(editor: Editor, flag: string, default: bool = false): bool =
  return getOption[bool](editor, flag, default)

proc createView(ed: Editor, editor: DocumentEditor) =
  var view = View(document: nil, editor: editor)

  ed.views.add view
  ed.currentView = ed.views.len - 1

proc createView(ed: Editor, document: Document) =
  var editor = ed.createEditorForDocument document
  editor.injectDependencies ed
  var view = View(document: document, editor: editor)

  ed.views.add view
  ed.currentView = ed.views.len - 1

proc pushPopup*(ed: Editor, popup: Popup) =
  popup.init()
  ed.popups.add popup

proc popPopup*(ed: Editor, popup: Popup) =
  if ed.popups.len > 0 and ed.popups[ed.popups.high] == popup:
    discard ed.popups.pop

proc getEventHandlerConfig*(ed: Editor, context: string): EventHandlerConfig =
  if not ed.eventHandlerConfigs.contains(context):
    ed.eventHandlerConfigs[context] = EventHandlerConfig()
  return ed.eventHandlerConfigs[context]

proc getEditorForId*(ed: Editor, id: EditorId): Option[DocumentEditor] =
  if ed.editors.contains(id):
    return ed.editors[id].some

  return DocumentEditor.none

proc getPopupForId*(ed: Editor, id: PopupId): Option[Popup] =
  for popup in ed.popups:
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

proc setTheme*(ed: Editor, path: string) =
  if loadFromFile(path).getSome(theme):
    ed.theme = theme

proc createAddins(): VmAddins

proc getCommandLineTextEditor*(ed: Editor): TextDocumentEditor = ed.commandLineTextEditor.TextDocumentEditor

proc newEditor*(window: Window, boxy: Boxy): Editor =
  var ed = Editor()
  ed.window = window
  ed.boxy = boxy
  ed.boxy2 = newBoxy()
  ed.statusBarOnTop = false
  ed.logger = newConsoleLogger()

  ed.timer = startTimer()
  ed.frameTimer = startTimer()

  ed.layout = HorizontalLayout()
  ed.layout_props = LayoutProperties(props: {"main-split": 0.5.float32}.toTable)

  ed.ctx = newContext(1, 1)
  ed.ctx.fillStyle = rgb(255, 255, 255)
  ed.ctx.strokeStyle = rgb(255, 255, 255)
  ed.ctx.font = "fonts/DejaVuSansMono.ttf"
  ed.ctx.fontSize = 20
  ed.ctx.textBaseline = TopBaseline

  ed.renderCtx = RenderContext(boxy: boxy, ctx: ed.ctx)

  ed.fontRegular = "./fonts/DejaVuSansMono.ttf"
  ed.fontBold = "./fonts/DejaVuSansMono-Bold.ttf"
  ed.fontItalic = "./fonts/DejaVuSansMono-Oblique.ttf"
  ed.fontBoldItalic = "./fonts/DejaVuSansMono-BoldOblique.ttf"

  ed.editor_defaults = @[TextDocumentEditor(), AstDocumentEditor()]

  ed.theme = defaultTheme()
  ed.setTheme("./themes/tokyo-night-color-theme.json")

  ed.createView(newAstDocument("a.ast"))
  # ed.createView(newKeybindAutocompletion())
  ed.currentView = 0

  ed.getEventHandlerConfig("editor").addCommand "<C-x><C-x>", "quit"
  ed.getEventHandlerConfig("editor").addCommand "<CAS-r>", "reload-config"

  ed.options = newJObject()

  ed.eventHandler = eventHandler(ed.getEventHandlerConfig("editor")):
    onAction:
      ed.handleAction(action, arg)
      Handled
    onInput:
      Ignored
  ed.commandLineEventHandler = eventHandler(ed.getEventHandlerConfig("commandLine")):
    onAction:
      ed.handleAction(action, arg)
      Handled
    onInput:
      Ignored
  ed.commandLineMode = false

  try:
    let state = readFile("config.json").parseJson.jsonTo EditorState
    ed.setTheme(state.theme)
    ed.ctx.fontSize = state.fontSize
    ed.ctx.font = state.fontRegular
    if state.fontRegular.len > 0: ed.fontRegular = state.fontRegular
    if state.fontBold.len > 0: ed.fontBold = state.fontBold
    if state.fontItalic.len > 0: ed.fontItalic = state.fontItalic
    if state.fontBoldItalic.len > 0: ed.fontBoldItalic = state.fontBoldItalic

    ed.options = readFile("options.json").parseJson
    echo "Restoring options: ", ed.options.pretty

  except:
    echo "Failed to load previous state from config file"

  gEditor = ed

  ed.commandLineTextEditor = newTextEditor(newTextDocument(), ed)
  ed.commandLineTextEditor.renderHeader = false
  ed.getCommandLineTextEditor.hideCursorWhenInactive = true

  let addins = createAddins()
  try:
    ed.scriptContext = newScriptContext("./absytree_config.nims", addins)
    ed.scriptContext.inter.invoke(postInitialize)
    ed.initializeCalled = true
  except:
    ed.logger.log(lvlError, fmt"Failed to load config")

  return ed

proc shutdown*(ed: Editor) =
  # Save some state
  var state = EditorState()
  state.theme = ed.theme.path
  state.fontSize = ed.ctx.fontSize
  state.fontRegular = ed.fontRegular
  state.fontBold = ed.fontBold
  state.fontItalic = ed.fontItalic
  state.fontBoldItalic = ed.fontBoldItalic

  let serialized = state.toJson
  writeFile("config.json", serialized.pretty)
  writeFile("options.json", ed.options.pretty)

proc getEditor(): Option[Editor] =
  if gEditor.isNil: return Editor.none
  return gEditor.some

static:
  addInjector(Editor, getEditor)

proc getFlagImpl*(editor: Editor, flag: string, default: bool = false): bool {.expose("editor").} =
  return getOption[bool](editor, flag, default)

proc setFlagImpl*(editor: Editor, flag: string, value: bool) {.expose("editor").} =
  setOption[bool](editor, flag, value)

proc toggleFlagImpl*(editor: Editor, flag: string) {.expose("editor").} =
  editor.setFlagImpl(flag, not editor.getFlagImpl(flag))

proc setOptionImpl*(editor: Editor, option: string, value: JsonNode) {.expose("editor").} =
  setOption(editor, option, value)

proc quitImpl*(self: Editor) {.expose("editor").} =
  self.window.closeRequested = true

proc changeFontSizeImpl*(self: Editor, amount: float32) {.expose("editor").} =
  self.ctx.fontSize += amount

proc changeLayoutPropImpl*(self: Editor, prop: string, change: float32) {.expose("editor").} =
  self.layout_props.props.mgetOrPut(prop, 0) += change

proc toggleStatusBarLocationImpl*(self: Editor) {.expose("editor").} =
  self.statusBarOnTop = not self.statusBarOnTop

proc createViewImpl*(self: Editor) {.expose("editor").} =
  self.createView(newTextDocument())

proc createKeybindAutocompleteViewImpl*(self: Editor) {.expose("editor").} =
  self.createView(newKeybindAutocompletion())

proc closeCurrentViewImpl*(ed: Editor) {.expose("editor").} =
  ed.views[ed.currentView].editor.unregister()
  ed.views.delete ed.currentView
  ed.currentView = ed.currentView.clamp(0, ed.views.len - 1)

proc moveCurrentViewToTopImpl*(self: Editor) {.expose("editor").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    self.views.delete(self.currentView)
    self.views.insert(view, 0)
  self.currentView = 0

proc nextViewImpl*(ed: Editor) {.expose("editor").} =
  ed.currentView = if ed.views.len == 0: 0 else: (ed.currentView + 1) mod ed.views.len

proc prevViewImpl*(ed: Editor) {.expose("editor").} =
  ed.currentView = if ed.views.len == 0: 0 else: (ed.currentView + ed.views.len - 1) mod ed.views.len

proc moveCurrentViewPrevImpl*(ed: Editor) {.expose("editor").} =
  if ed.views.len > 0:
    let view = ed.views[ed.currentView]
    let index = (ed.currentView + ed.views.len - 1) mod ed.views.len
    ed.views.delete(ed.currentView)
    ed.views.insert(view, index)
    ed.currentView = index

proc moveCurrentViewNextImpl*(ed: Editor) {.expose("editor").} =
  if ed.views.len > 0:
    let view = ed.views[ed.currentView]
    let index = (ed.currentView + 1) mod ed.views.len
    ed.views.delete(ed.currentView)
    ed.views.insert(view, index)
    ed.currentView = index

proc setLayoutImpl*(ed: Editor, layout: string) {.expose("editor").} =
  ed.layout = case layout
    of "horizontal": HorizontalLayout()
    of "vertical": VerticalLayout()
    of "fibonacci": FibonacciLayout()
    else: HorizontalLayout()

proc commandLineImpl*(ed: Editor, initialValue: string = "") {.expose("editor").} =
  ed.getCommandLineTextEditor.document.content = @[initialValue]
  ed.commandLineMode = true

proc exitCommandLineImpl*(ed: Editor) {.expose("editor").} =
  ed.getCommandLineTextEditor.document.content = @[""]
  ed.commandLineMode = false

proc executeCommandLineImpl*(ed: Editor) {.expose("editor").} =
  ed.commandLineMode = false
  let (action, arg) = ed.getCommandLineTextEditor.document.content.join("").parseAction
  ed.getCommandLineTextEditor.document.content = @[""]
  ed.handleAction(action, arg)

proc openFileImpl*(ed: Editor, path: string) {.expose("editor").} =
  try:
    if path.endsWith(".ast"):
      ed.createView(newAstDocument(path))
    else:
      let file = readFile(path)
      ed.createView(newTextDocument(path, file.splitLines))
  except:
    ed.logger.log(lvlError, fmt"[ed] Failed to load file '{path}': {getCurrentExceptionMsg()}")
    echo getCurrentException().getStackTrace()

proc writeFileImpl*(ed: Editor, path: string = "") {.expose("editor").} =
  if ed.currentView >= 0 and ed.currentView < ed.views.len and ed.views[ed.currentView].document != nil:
    try:
      ed.views[ed.currentView].document.save(path)
    except:
      ed.logger.log(lvlError, fmt"[ed] Failed to write file '{path}': {getCurrentExceptionMsg()}")
      echo getCurrentException().getStackTrace()

proc loadFileImpl*(ed: Editor, path: string = "") {.expose("editor").} =
  if ed.currentView >= 0 and ed.currentView < ed.views.len and ed.views[ed.currentView].document != nil:
    try:
      ed.views[ed.currentView].document.load(path)
      ed.views[ed.currentView].editor.handleDocumentChanged()
    except:
      ed.logger.log(lvlError, fmt"[ed] Failed to load file '{path}': {getCurrentExceptionMsg()}")
      echo getCurrentException().getStackTrace()

proc loadThemeImpl*(ed: Editor, name: string) {.expose("editor").} =
  if theme.loadFromFile(fmt"./themes/{name}.json").getSome(theme):
    ed.theme = theme
  else:
    ed.logger.log(lvlError, fmt"[ed] Failed to load theme {name}")

proc chooseThemeImpl*(ed: Editor) {.expose("editor").} =
  let originalTheme = ed.theme.path
  var popup = ed.newSelectorPopup proc(popup: SelectorPopup, text: string): seq[SelectorItem] =
    for file in walkDirRec("./themes", relative=true):
      if file.endsWith ".json":
        let name = file.splitFile[1]
        let score = fuzzyMatchSmart(text, name)
        result.add ThemeSelectorItem(name: name, path: fmt"./themes/{file}", score: score)

    result.sort((a, b) => cmp(a.ThemeSelectorItem.score, b.ThemeSelectorItem.score), Descending)

  popup.handleItemSelected = proc(item: SelectorItem) =
    if theme.loadFromFile(item.ThemeSelectorItem.path).getSome(theme):
      ed.theme = theme

  popup.handleItemConfirmed = proc(item: SelectorItem) =
    if theme.loadFromFile(item.ThemeSelectorItem.path).getSome(theme):
      ed.theme = theme

  popup.handleCanceled = proc() =
    if theme.loadFromFile(originalTheme).getSome(theme):
      ed.theme = theme

  ed.pushPopup popup

proc chooseFileImpl*(ed: Editor, view: string = "new") {.expose("editor").} =
  var popup = ed.newSelectorPopup proc(popup: SelectorPopup, text: string): seq[SelectorItem] =
    for file in walkDirRec(".", relative=true):
      let name = file.splitFile[1]
      let score = fuzzyMatchSmart(text, name)
      result.add FileSelectorItem(path: fmt"./{file}", score: score)

    result.sort((a, b) => cmp(a.FileSelectorItem.score, b.FileSelectorItem.score), Descending)

  popup.handleItemConfirmed = proc(item: SelectorItem) =
    case view
    of "current":
      ed.loadFileImpl(item.FileSelectorItem.path)
    of "new":
      ed.openFileImpl(item.FileSelectorItem.path)
    else:
      ed.logger.log(lvlError, fmt"Unknown argument {view}")

  ed.pushPopup popup

proc reloadConfigImpl*(ed: Editor) {.expose("editor").} =
  if ed.scriptContext.isNil.not:
    try:
      ed.scriptContext.reloadScript()
      if not ed.initializeCalled:
        ed.scriptContext.inter.invoke(postInitialize)
        ed.initializeCalled = true
    except:
      ed.logger.log(lvlError, fmt"Failed to reload config")

proc logOptionsImpl*(ed: Editor) {.expose("editor").} =
  ed.logger.log(lvlInfo, ed.options.pretty)

genDispatcher("editor")

proc handleAction(ed: Editor, action: string, arg: string) =
  ed.logger.log(lvlInfo, "[ed] Action '$1 $2'" % [action, arg])
  try:
    if ed.scriptContext.inter.invoke(handleGlobalAction, action, arg, returnType = bool):
      return
  except:
    ed.logger.log(lvlError, fmt"[ed] Failed to run script handleGlobalAction '{action} {arg}': {getCurrentExceptionMsg()}")
    echo getCurrentException().getStackTrace()

  var args = newJArray()
  for a in newStringStream(arg).parseJsonFragments():
    args.add a
  discard dispatch(action, args)

proc anyInProgress*(handlers: openArray[EventHandler]): bool =
  for h in handlers:
    if h.state != 0:
      return true
  return false

proc handleEvent*(handlers: seq[EventHandler], input: int64, modifiers: Modifiers) =
  let anyInProgress = handlers.anyInProgress

  var allowHandlingUnknownAsInput = true
  for i in 0..<handlers.len:
    var handler = handlers[handlers.len - i - 1]
    let response = if (anyInProgress and handler.state != 0) or (not anyInProgress and handler.state == 0):
      handler.handleEvent(input, modifiers, allowHandlingUnknownAsInput)
    else:
      Ignored

    # echo i, ": ", response

    case response
    of Handled:
      allowHandlingUnknownAsInput = false
      for h in handlers:
        var h = h
        h.reset()
      break
    of Progress:
      allowHandlingUnknownAsInput = false
    else:
      discard

proc currentEventHandlers*(ed: Editor): seq[EventHandler] =
  result = @[ed.eventHandler]
  if ed.commandLineMode:
    result.add ed.getCommandLineTextEditor.getEventHandlers()
    result.add ed.commandLineEventHandler
  elif ed.popups.len > 0:
    result.add ed.popups[ed.popups.high].getEventHandlers()
  elif ed.currentView >= 0 and ed.currentView < ed.views.len:
    result.add ed.views[ed.currentView].editor.getEventHandlers()

proc handleMousePress*(ed: Editor, button: Button, modifiers: Modifiers, mousePosWindow: Vec2) =
  # Check popups
  for i in 0..ed.popups.high:
    let popup = ed.popups[ed.popups.high - i]
    if popup.lastBounds.contains(mousePosWindow):
      popup.handleMousePress(button, mousePosWindow)
      return

  # Check views
  let rects = ed.layout.layoutViews(ed.layout_props, ed.lastBounds, ed.views)
  for i, view in ed.views:
    if i >= rects.len:
      return
    if rects[i].contains(mousePosWindow):
      view.editor.handleMousePress(button, mousePosWindow)
      return

proc handleMouseRelease*(ed: Editor, button: Button, modifiers: Modifiers, mousePosWindow: Vec2) =
  # Check popups
  for i in 0..ed.popups.high:
    let popup = ed.popups[ed.popups.high - i]
    if popup.lastBounds.contains(mousePosWindow):
      popup.handleMouseRelease(button, mousePosWindow)
      return

  # Check views
  let rects = ed.layout.layoutViews(ed.layout_props, ed.lastBounds, ed.views)
  for i, view in ed.views:
    if i >= rects.len:
      return
    if rects[i].contains(mousePosWindow):
      view.editor.handleMouseRelease(button, mousePosWindow)
      return

proc handleMouseMove*(ed: Editor, mousePosWindow: Vec2, mousePosDelta: Vec2) =
  # Check popups
  for i in 0..ed.popups.high:
    let popup = ed.popups[ed.popups.high - i]
    if popup.lastBounds.contains(mousePosWindow):
      popup.handleMouseMove(mousePosWindow, mousePosDelta)
      return

  # Check views
  let rects = ed.layout.layoutViews(ed.layout_props, ed.lastBounds, ed.views)
  for i, view in ed.views:
    if i >= rects.len:
      return
    if rects[i].contains(mousePosWindow):
      view.editor.handleMouseMove(mousePosWindow, mousePosDelta)
      return

proc handleScroll*(ed: Editor, scroll: Vec2, mousePosWindow: Vec2) =
  # Check popups
  for i in 0..ed.popups.high:
    let popup = ed.popups[ed.popups.high - i]
    if popup.lastBounds.contains(mousePosWindow):
      popup.handleScroll(scroll, mousePosWindow)
      return

  # Check views
  let rects = ed.layout.layoutViews(ed.layout_props, ed.lastBounds, ed.views)
  for i, view in ed.views:
    if i >= rects.len:
      return
    if rects[i].contains(mousePosWindow):
      view.editor.handleScroll(scroll, mousePosWindow)
      return

proc handleKeyPress*(ed: Editor, button: Button, modifiers: Modifiers) =
  let input = button.toInput()
  ed.currentEventHandlers.handleEvent(input, modifiers)

proc handleKeyRelease*(ed: Editor, button: Button, modifiers: Modifiers) =
  discard

proc handleRune*(ed: Editor, rune: Rune, modifiers: Modifiers) =
  let modifiers = if rune.int64.isAscii and rune.char.isAlphaNumeric: modifiers else: {}
  let input = rune.toInput()
  ed.currentEventHandlers.handleEvent(input, modifiers)

proc scriptRunAction*(action: string, arg: string) =
  if gEditor.isNil:
    return
  gEditor.handleAction(action, arg)

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