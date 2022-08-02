import std/[strformat, bitops, strutils, tables, algorithm, math, logging, unicode]
import boxy, times, windy, print
import sugar
import input, events, rect_utils, document, document_editor, text_document, ast_document, keybind_autocomplete

var glogger = newConsoleLogger()

var commands: seq[(string, string)] = @[]
commands.add ("<C-x><C-x>", "quit")
commands.add ("<BACKSPACE>", "backspace")
commands.add ("<DELETE>", "delete")
commands.add ("<ESCAPE>", "escape")
commands.add ("<SPACE>", "insert  ")
commands.add ("<ENTER>", "insert \n")
commands.add ("<C-l><C-h>", "change-font-size -1")
commands.add ("<C-l><C-f>", "change-font-size 1")
commands.add ("<C-g>", "toggle-status-bar-location")
commands.add ("<C-l><C-n>", "set-layout horizontal")
commands.add ("<C-l><C-r>", "set-layout vertical")
commands.add ("<C-l><C-t>", "set-layout fibonacci")
commands.add ("<C-h>", "change-layout-prop main-split -0.05")
commands.add ("<C-f>", "change-layout-prop main-split +0.05")
commands.add ("<CA-n>", "create-view")
commands.add ("<CA-a>", "create-keybind-autocomplete-view")
commands.add ("<CA-x>", "close-view")
commands.add ("<C-n>", "prev-view")
commands.add ("<C-t>", "next-view")
commands.add ("<CS-n>", "move-view-prev")
commands.add ("<CS-t>", "move-view-next")
commands.add ("<C-r>", "move-current-view-to-top")
commands.add ("<C-s>", "write-file")
commands.add ("<C-r>", "load-file")
commands.add ("<C-m>", "command-line")

var commandLineCommands: seq[(string, string)] = @[]
commandLineCommands.add ("<ESCAPE>", "exit-command-line")
commandLineCommands.add ("<ENTER>", "execute-command-line")

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

type Editor* = ref object
  window*: Window
  boxy*: Boxy
  ctx*: Context

  logger: Logger

  statusBarOnTop*: bool
  inputBuffer*: string

  currentView*: int
  views*: seq[View]
  layout*: Layout
  layout_props*: LayoutProperties

  eventHandler*: EventHandler
  commandLineEventHandler*: EventHandler
  commandLineMode*: bool

  editor_defaults: seq[DocumentEditor]

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

proc handleTextInput(ed: Editor, text: string)
proc handleAction(ed: Editor, action: string, arg: string)

proc createEditorForDocument(ed: Editor, document: Document): DocumentEditor =
  for editor in ed.editor_defaults:
    if editor.canEdit document:
      return editor.createWithDocument document

  echo "No editor found which can edit " & $document
  return nil

proc createView(ed: Editor, editor: DocumentEditor) =
  var view = View(document: nil, editor: editor)

  ed.views.add view
  ed.currentView = ed.views.len - 1

proc createView(ed: Editor, document: Document) =
  var editor = ed.createEditorForDocument document
  var view = View(document: document, editor: editor)

  ed.views.add view
  ed.currentView = ed.views.len - 1

proc newEditor*(window: Window, boxy: Boxy): Editor =
  var ed = Editor()
  ed.window = window
  ed.boxy = boxy
  ed.inputBuffer = ""
  ed.statusBarOnTop = false
  ed.logger = newConsoleLogger()

  # ed.views = @[View(document: "1"), View(document: "2"), View(document: "3")]
  ed.layout = HorizontalLayout()
  ed.layout_props = LayoutProperties(props: {"main-split": 0.5.float32}.toTable)

  let image = newImage(window.size.x, window.size.y)
  ed.ctx = newContext(1, 1)
  ed.ctx.fillStyle = rgb(255, 255, 255)
  ed.ctx.strokeStyle = rgb(255, 255, 255)
  ed.ctx.font = "fonts/FiraCode-Regular.ttf"
  ed.ctx.fontSize = 20
  ed.ctx.textBaseline = TopBaseline

  ed.editor_defaults = @[TextDocumentEditor(), AstDocumentEditor()]

  ed.createView(newAstDocument("b.txt"))
  # ed.createView(TextDocument(filename: "a.txt", content: @[""]))
  # ed.createView(newKeybindAutocompletion())
  ed.currentView = 0

  ed.eventHandler = eventHandler(buildDFA(commands)):
    onAction:
      ed.handleAction(action, arg)
      Handled
    onInput:
      ed.handleTextInput(input)
      Handled
  ed.commandLineEventHandler = eventHandler(buildDFA(commandLineCommands)):
    onAction:
      ed.handleAction(action, arg)
      Handled
    onInput:
      ed.handleTextInput(input)
      Handled
  ed.commandLineMode = false

  return ed

proc closeCurrentView(ed: Editor) =
  ed.views.delete ed.currentView
  ed.currentView = ed.currentView.clamp(0, ed.views.len - 1)

proc moveCurrentViewToTop(ed: Editor) =
  if ed.views.len > 0:
    let view = ed.views[ed.currentView]
    ed.views.delete(ed.currentView)
    ed.views.insert(view, 0)
  ed.currentView = 0

proc moveCurrentViewPrev(ed: Editor) =
  if ed.views.len > 0:
    let view = ed.views[ed.currentView]
    let index = (ed.currentView + ed.views.len - 1) mod ed.views.len
    ed.views.delete(ed.currentView)
    ed.views.insert(view, index)
    ed.currentView = index

proc moveCurrentViewNext(ed: Editor) =
  if ed.views.len > 0:
    let view = ed.views[ed.currentView]
    let index = (ed.currentView + 1) mod ed.views.len
    ed.views.delete(ed.currentView)
    ed.views.insert(view, index)
    ed.currentView = index

proc handleTextInput(ed: Editor, text: string) =
  echo "handleTextInput '" & text & "'"
  ed.inputBuffer.add text

proc handleAction(ed: Editor, action: string, arg: string) =
  ed.logger.log(lvlInfo, "[ed] Action '$1 $2'" % [action, arg])
  case action
  of "quit":
    ed.window.closeRequested = true
  of "backspace":
    if ed.inputBuffer.len > 0:
      let (rune, l) = ed.inputBuffer.lastRune(ed.inputBuffer.len - 1)
      ed.inputBuffer = ed.inputBuffer[0..<ed.inputBuffer.len-l]
  of "insert":
    ed.handleTextInput arg
  of "change-font-size":
    ed.ctx.fontSize = ed.ctx.fontSize + arg.parseFloat()
  of "toggle-status-bar-location":
    ed.statusBarOnTop = not ed.statusBarOnTop
  of "create-view":
    ed.createView(TextDocument(filename: "", content: @[]))
  of "create-keybind-autocomplete-view":
    ed.createView(newKeybindAutocompletion())
  of "close-view":
    ed.closeCurrentView()
  of "move-current-view-to-top":
    ed.moveCurrentViewToTop()
  of "next-view":
    ed.currentView = if ed.views.len == 0: 0 else: (ed.currentView + 1) mod ed.views.len
  of "prev-view":
    ed.currentView = if ed.views.len == 0: 0 else: (ed.currentView + ed.views.len - 1) mod ed.views.len
  of "move-view-prev":
    ed.moveCurrentViewPrev()
  of "move-view-next":
    ed.moveCurrentViewNext()
  of "set-layout":
    ed.layout = case arg
      of "horizontal": HorizontalLayout()
      of "vertical": VerticalLayout()
      of "fibonacci": FibonacciLayout()
      else: HorizontalLayout()
  of "change-layout-prop":
    let args = arg.split(' ')
    if args.len == 2:
      let prop = args[0]
      let change = try: args[1].parseFloat
      except: 0.float32
      ed.layout_props.props.mgetOrPut(prop, 0) += change
  of "command-line":
    ed.inputBuffer = arg
    ed.commandLineMode = true
  of "exit-command-line":
    ed.inputBuffer = ""
    ed.commandLineMode = false
  of "execute-command-line":
    ed.commandLineMode = false
    let (action, arg) = ed.inputBuffer.parseAction
    ed.inputBuffer = ""
    ed.handleAction(action, arg)
  of "open-file":
    try:
      let file = readFile(arg)
      ed.createView(TextDocument(filename: arg, content: collect file.splitLines))
    except:
      ed.logger.log(lvlError, "[ed] Failed to load file '$1'" % [arg])
  of "write-file":
    if ed.currentView >= 0 and ed.currentView < ed.views.len and ed.views[ed.currentView].document != nil:
      try:
        ed.views[ed.currentView].document.save(arg)
      except:
        ed.logger.log(lvlError, "[ed] Failed to write file '$1'" % [arg])
  of "load-file":
    if ed.currentView >= 0 and ed.currentView < ed.views.len and ed.views[ed.currentView].document != nil:
      try:
        ed.views[ed.currentView].document.load(arg)
        ed.views[ed.currentView].editor.handleDocumentChanged()
      except:
        ed.logger.log(lvlError, "[ed] Failed to load file '$1'" % [arg])
  else:
    ed.logger.log(lvlError, "[ed] Unknown Action '$1 $2'" % [action, arg])

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
    echo i, ": ", response
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
    result.add ed.commandLineEventHandler
  elif ed.currentView >= 0 and ed.currentView < ed.views.len:
    result.add ed.views[ed.currentView].editor.getEventHandlers()

proc handleKeyPress*(ed: Editor, button: Button, modifiers: Modifiers) =
  let input = button.toInput()
  ed.currentEventHandlers.handleEvent(input, modifiers)

proc handleKeyRelease*(ed: Editor, button: Button, modifiers: Modifiers) =
  discard

proc handleRune*(ed: Editor, rune: Rune, modifiers: Modifiers) =
  let modifiers = if rune.int64.isAscii and rune.char.isAlphaNumeric: modifiers else: {}
  let input = rune.toInput()
  ed.currentEventHandlers.handleEvent(input, modifiers)