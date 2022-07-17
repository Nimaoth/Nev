import std/[strformat, bitops, strutils, tables, algorithm, math, logging]
import boxy, times, windy
import sugar
import input, rect_utils

var glogger = newConsoleLogger()

var commands: seq[(string, string)] = @[]
commands.add ("<C-x><C-x>", "quit")
commands.add ("<BACKSPACE>", "backspace")
commands.add ("<DELETE>", "delete")
commands.add ("<ESCAPE>", "escape")
commands.add ("<SPACE>", "insert  ")
commands.add ("<ENTER>", "insert \n")
commands.add ("<C-h>", "change-font-size -1")
commands.add ("<C-f>", "change-font-size 1")
commands.add ("<C-g>", "toggle-status-bar-location")
commands.add ("<C-l><C-n>", "set-layout horizontal")
commands.add ("<C-l><C-r>", "set-layout vertical")
commands.add ("<C-l><C-t>", "set-layout fibonacci")
commands.add ("<CA-n>", "create-view")
commands.add ("<CA-x>", "close-view")
commands.add ("<C-n>", "prev-view")
commands.add ("<C-t>", "next-view")
commands.add ("<CS-n>", "move-view-prev")
commands.add ("<CS-t>", "move-view-next")
commands.add ("<C-r>", "move-current-view-to-top")

var dfa* = buildDFA(commands)
dfa.dump(0, 0, {})
var state* = 0

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
  of KeyA..KeyZ: ord(button) - ord(KeyA) + ord('a')
  of Key0..Key9: ord(button) - ord(Key0) + ord('0')
  of Numpad0..Numpad9: ord(button) - ord(Numpad0) + ord('0')
  of NumpadAdd: ord '+'
  of NumpadSubtract: ord '-'
  of NumpadMultiply: ord '*'
  of NumpadDivide: ord '/'
  else: 0

type View* = ref object
  document*: string

type
  Layout* = ref object of RootObj
    discard
  HorizontalLayout* = ref object of Layout
    discard
  VerticalLayout* = ref object of Layout
    discard
  FibonacciLayout* = ref object of Layout
    discard

method layoutViews*(layout: Layout, bounds: Rect, views: openArray[View]): seq[Rect] =
  return @[bounds]

method layoutViews*(layout: HorizontalLayout, bounds: Rect, views: openArray[View]): seq[Rect] =
  result = @[]
  var rect = bounds
  for i, view in views:
    let ratio = 1.0 / (views.len - i).float32
    let (view_rect, remaining) = rect.splitV(ratio.relative)
    rect = remaining
    result.add view_rect

method layoutViews*(layout: VerticalLayout, bounds: Rect, views: openArray[View]): seq[Rect] =
  result = @[]
  var rect = bounds
  for i, view in views:
    let ratio = 1.0 / (views.len - i).float32
    let (view_rect, remaining) = rect.splitH(ratio.relative)
    rect = remaining
    result.add view_rect

method layoutViews*(layout: FibonacciLayout, bounds: Rect, views: openArray[View]): seq[Rect] =
  result = @[]
  var rect = bounds
  for i, view in views:
    let ratio = if i == views.len - 1: 1.0 else: 0.5
    let (view_rect, remaining) = if i mod 2 == 0: rect.splitV(ratio.relative) else: rect.splitH(ratio.relative)
    rect = remaining
    result.add view_rect

type Editor* = ref object
  window*: Window
  boxy*: Boxy
  inputBuffer*: string
  logger: Logger
  statusBarOnTop*: bool
  ctx*: Context

  currentView*: int
  views*: seq[View]
  layout*: Layout

proc createView(ed: Editor, document: string) =
  ed.views.add View(document: document)
  ed.currentView = ed.views.len - 1

proc newEditor*(window: Window, boxy: Boxy): Editor =
  result = Editor()
  result.window = window
  result.boxy = boxy
  result.inputBuffer = ""
  result.statusBarOnTop = false
  result.logger = newConsoleLogger()

  # result.views = @[View(document: "1"), View(document: "2"), View(document: "3")]
  result.layout = HorizontalLayout()

  let image = newImage(window.size.x, window.size.y)
  result.ctx = newContext(1, 1)
  result.ctx.fillStyle = rgb(255, 255, 255)
  result.ctx.strokeStyle = rgb(255, 255, 255)
  result.ctx.font = "fonts/FiraCode-Regular.ttf"
  result.ctx.fontSize = 20
  result.ctx.textBaseline = TopBaseline
  
  result.createView("a")
  result.createView("b")
  result.createView("c")

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
  ed.inputBuffer.add text

proc handleAction(ed: Editor, action: string, arg: string) =
  ed.logger.log(lvlInfo, "[ed] Action '$1 $2'" % [action, arg])
  case action
  of "quit":
    ed.window.closeRequested = true
  of "backspace":
    if ed.inputBuffer.len > 0:
      ed.inputBuffer = ed.inputBuffer[0..<ed.inputBuffer.len-1]
  of "insert":
    ed.handleTextInput arg
  of "change-font-size":
    ed.ctx.fontSize = ed.ctx.fontSize + arg.parseFloat()
  of "toggle-status-bar-location":
    ed.statusBarOnTop = not ed.statusBarOnTop
  of "create-view":
    ed.createView($ed.views.len)
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
  else:
    echo "Action: '", action, "' with parameter '", arg, "'"

proc handleTerminalState(ed: Editor, state: int) =
  let action = dfa.getAction(state)
  let spaceIndex = action.find(' ')
  if spaceIndex == -1:
    ed.handleAction(action, "")
  else:
    ed.handleAction(action[0..<spaceIndex], action[spaceIndex + 1..^1])

proc handleKeyPress*(ed: Editor, button: Button, modifiers: Modifiers) =
  let input = button.toInput()
  if input != 0:
    state = dfa.step(state, input, modifiers)
    if state == 0:
      echo "Invalid input: ", inputToString(input, modifiers)


    if dfa.isTerminal(state):
      ed.handleTerminalState(state)
      state = 0
  else:
    echo "Unknown button: ", button

proc handleKeyRelease*(ed: Editor, button: Button, modifiers: Modifiers) =
  discard

proc handleRune*(ed: Editor, rune: Rune, modifiers: Modifiers) =
  let input = rune.toInput()
  if input != 0:
    let modifiers = if rune.int64.isAscii and rune.char.isAlphaNumeric: modifiers else: {}

    let prevState = state
    state = dfa.step(state, input, modifiers)
    if state == 0:
      if prevState == 0:
        ed.handleTextInput($rune)
      else:
        echo "Invalid input: ", inputToString(input, modifiers)

    if dfa.isTerminal(state):
      ed.handleTerminalState(state)
      state = 0