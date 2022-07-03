import std/[json, jsonutils, strformat, bitops, strutils, tables, algorithm, math]
import os, osproc

const
  INPUT_COUNT* = 256 + 10
  INPUT_ENTER* = 13
  INPUT_ESCAPE* = 27
  INPUT_BACKSPACE* = 8
  INPUT_SPACE* = 32
  INPUT_DELETE* = 127

type
  Modifier* = enum
    Control
    Shift
    Alt
  Modifiers* = set[Modifier]
  DFAInput = object
    # length 8 because there are 3 modifiers and so 2^3 = 8 possible combinations
    next: array[8, int]
  DFAState = object
    isTerminal: bool
    function: string
    inputs: array[INPUT_COUNT, DFAInput]
  CommandDFA = ref object
    states: seq[DFAState]

proc step*(dfa: CommandDFA, currentState: int, currentInput: int, mods: Modifiers): int =
  if currentState < 0 or currentState >= dfa.states.len:
    echo fmt"State {currentState} is out of range 0..{dfa.states.len}"
    return 0

  if currentInput < 0 or currentInput >= INPUT_COUNT:
    echo fmt"Input {currentInput} is out of range 0..{INPUT_COUNT}"
    return 0

  return dfa.states[currentState].inputs[currentInput].next[cast[int](mods)]

proc isTerminal*(dfa: CommandDFA, state: int): bool =
  return dfa.states[state].isTerminal

proc getAction*(dfa: CommandDFA, state: int): string =
  return dfa.states[state].function

proc getInputCodeFromSpecialKey(specialKey: string): int =
  if specialKey.len == 1:
    result = ord(specialKey[0])
  else:
    result = case specialKey:
      of "ENTER": INPUT_ENTER
      of "ESCAPE": INPUT_ESCAPE
      of "BACKSPACE": INPUT_BACKSPACE
      of "SPACE": INPUT_SPACE
      of "DELETE": INPUT_DELETE
      else:
        echo "Invalid key '", specialKey, "'"
        0

proc linkState(dfa: var CommandDFA, currentState: int, nextState: int, inputCode: int, mods: Modifiers) =
  let modsInt = cast[int](mods)
  dfa.states[currentState].inputs[inputCode].next[modsInt] = nextState

proc createOrUpdateState(dfa: var CommandDFA, currentState: int, inputCode: int, mods: Modifiers): int =
  let modsInt = cast[int](mods)
  let nextState = if dfa.states[currentState].inputs[inputCode].next[modsInt] != 0:
    dfa.states[currentState].inputs[inputCode].next[modsInt]
  else:
    dfa.states.add DFAState()
    dfa.states.len - 1
  linkState(dfa, currentState, nextState, inputCode, mods)
  return nextState

proc handleNextInput(dfa: var CommandDFA, input: string, function: string, index: int, currentState: int) =
  type State = enum
    Normal
    Special

  var state = State.Normal
  var mods: Modifiers = {}
  var specialKey = ""

  var next: seq[tuple[index: int, state: int]] = @[]
  var lastIndex = 0
  
  if index >= input.len:
    # Mark last state as terminal state.
    dfa.states[currentState].isTerminal = true
    dfa.states[currentState].function = function
    return

  for i in index..<input.len:
    lastIndex = i
    # echo i, ": ", input[i]

    let inputCode = case input[i]:
      of '<':
        state = State.Special
        0
      of '>':
        if state != State.Special:
          echo "Error: > without <"
          return
        let inputCode = getInputCodeFromSpecialKey(specialKey)
        state = State.Normal
        specialKey = ""
        inputCode

      else:
        if state == State.Special:
          if input[i] == '-':
            # Parse stuff so far as mods
            mods = {}
            for m in specialKey:
              case m:
                of 'C': mods = mods + {Modifier.Control}
                of 'S': mods = mods + {Modifier.Shift}
                of 'A': mods = mods + {Modifier.Alt}
                else: echo "Invalid modifier '", m, "'"
            specialKey = ""
          else:
            specialKey.add $input[i]
          0
        else:
          mods = {}
          ord(input[i])

    # echo inputCode, ", ", mods
    if inputCode != 0:
      let nextState = createOrUpdateState(dfa, currentState, inputCode, mods)
      next.add((index: i + 1, state: nextState))

      if isUpperAscii(char(inputCode)):
        linkState(dfa, currentState, nextState, ord toLowerAscii(char(inputCode)), mods + {Modifier.Shift})

      if isLowerAscii(char(inputCode)) and Modifier.Shift in mods:
        linkState(dfa, currentState, nextState, ord toUpperAscii(char(inputCode)), mods - {Modifier.Shift})
      break

  for n in next:
    handleNextInput(dfa, input, function, n.index, n.state)

proc buildDFA*(commands: seq[(string, string)]): CommandDFA =
  new(result)

  result.states.add DFAState()
  var currentState = 0

  for command in commands:
    # echo "Compiling '", command, "'"

    currentState = 0

    let input = command[0]
    let function = command[1]

    if input.len > 0:
      handleNextInput(result, input, function, 0, 0)

proc inputAsString(input: int): string =
  result = case input:
    of INPUT_ENTER: "ENTER"
    of INPUT_ESCAPE: "ESCAPE"
    of INPUT_BACKSPACE: "BACKSPACE"
    of INPUT_SPACE: "SPACE"
    of INPUT_DELETE: "DELETE"
    else: "<UNKNOWN>"

proc dump*(dfa: CommandDFA, currentState: int, currentInput: int, currentMods: Modifiers): void =
  stdout.write "        "
  for state in 0..<dfa.states.len:
    var stateStr = $state
    if state == currentState:
      stateStr = fmt"({stateStr})"
    stdout.write fmt"{stateStr:^7.7}|"
  echo ""

  stdout.write "        "
  for state in dfa.states:
    if state.isTerminal:
      stdout.write fmt"{state.function:^7.7}|"
    else:
      stdout.write fmt"       |"

  echo ""

  for input in 0..<INPUT_COUNT:
    for modifiersNum in 0..0b111:
      let modifiers = cast[Modifiers](modifiersNum)

      var line = ""

      # Input
      var chStr = ""
      if Control in modifiers:
        chStr.add "C"
      if Shift in modifiers:
        chStr.add "S"
      if Alt in modifiers:
        chStr.add "A"
      if chStr.len > 0:
        chStr.add "-"

      if input < 256:
        let ch = chr(input)
        case ch:
          of 'a'..'z', 'A'..'Z':
            chStr.add $ch
          else:
            chStr.add inputAsString(input)
      else:
        chStr.add inputAsString(input)

      if currentInput != 0 and input == currentInput and modifiersNum == cast[int](currentMods):
        chStr = fmt"({chStr})"
      line.add fmt"{chStr:^7.7}|"

      # Next state
      var notEmpty = false
      for state in 0..<dfa.states.len:
        let nextState = dfa.states[state].inputs[input].next[modifiersNum]
        if nextState == 0 and (state != currentState or input != currentInput or modifiersNum != cast[int](currentMods)):
          line.add "       |"
        else:
          var nextStateStr = $nextState
          if state == currentState and currentInput != 0 and input == currentInput and modifiersNum == cast[int](currentMods):
            nextStateStr = fmt"({nextStateStr})"
          line.add fmt"{nextStateStr:^7.7}|"
          notEmpty = true

      if notEmpty:
        echo line