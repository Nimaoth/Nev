import std/[strformat, bitops, strutils, tables, algorithm, math, logging]
import boxy, times, windy
import sugar
import input

var glogger = newConsoleLogger()

var commands: seq[(string, string)] = @[]
commands.add ("<C-x>", "quit")
commands.add ("<BACKSPACE>", "backspace")
commands.add ("<DELETE>", "delete")
commands.add ("<ESCAPE>", "escape")
commands.add ("<SPACE>", "insert  ")
commands.add ("<ENTER>", "insert \n")
commands.add ("<C-n>ä", "insert äöüÄÖÜ")
commands.add ("<C-h>", "change-font-size -1")
commands.add ("<C-f>", "change-font-size 1")
commands.add ("<C-r>a", "insert a")
commands.add ("<C-r>b", "insert b")
commands.add ("<C-r>ca", "insert ca")
commands.add ("<C-r>cb", "insert cb")
commands.add ("<C-r>cca", "insert cca")
commands.add ("<C-r>ccb", "insert ccb")
commands.add ("<C-r>ccc", "insert ccc")
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

type Editor* = ref object
  window*: Window
  boxy*: Boxy
  inputBuffer*: string
  fontSize*: float32
  logger: Logger

proc newEditor*(window: Window, boxy: Boxy): Editor =
  result = Editor()
  result.window = window
  result.boxy = boxy
  result.inputBuffer = ""
  result.fontSize = 20
  result.logger = newConsoleLogger()

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
    ed.fontSize = ed.fontSize + arg.parseFloat()
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