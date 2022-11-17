import std/[strformat, strutils, tables, algorithm, unicode, sequtils]

const
  INPUT_ENTER* = -1
  INPUT_ESCAPE* = -2
  INPUT_BACKSPACE* = -3
  INPUT_SPACE* = -4
  INPUT_DELETE* = -5
  INPUT_TAB* = -6
  INPUT_LEFT* = -7
  INPUT_RIGHT* = -8
  INPUT_UP* = -9
  INPUT_DOWN* = -10
  INPUT_HOME* = -11
  INPUT_END* = -12
  INPUT_PAGE_UP* = -13
  INPUT_PAGE_DOWN* = -14
  INPUT_F1* = -20
  INPUT_F2* = -21
  INPUT_F3* = -22
  INPUT_F4* = -23
  INPUT_F5* = -24
  INPUT_F6* = -25
  INPUT_F7* = -26
  INPUT_F8* = -27
  INPUT_F9* = -28
  INPUT_F10* = -29
  INPUT_F11* = -30
  INPUT_F12* = -31

type
  Modifier* = enum
    Control
    Shift
    Alt
    Super
  Modifiers* = set[Modifier]
  DFAInput = object
    # length 16 because there are 4 modifiers and so 2^4 = 16 possible combinations
    next: Table[Modifiers, int]
  InputKey = int64
  DFAState = object
    isTerminal: bool
    function: string
    inputs: Table[InputKey, DFAInput]
  CommandDFA* = ref object
    states: seq[DFAState]

proc isAscii*(input: int64): bool =
  if input >= char.low.ord and input <= char.high.ord:
    return true
  return false

proc step*(dfa: CommandDFA, currentState: int, currentInput: int64, mods: Modifiers): int =
  if currentInput == 0:
    echo "Input 0 is invalid"
    return

  if not (currentInput in dfa.states[currentState].inputs):
    return 0

  if not (mods in dfa.states[currentState].inputs[currentInput].next):
    return 0

  return dfa.states[currentState].inputs[currentInput].next[mods]

proc isTerminal*(dfa: CommandDFA, state: int): bool =
  return dfa.states[state].isTerminal

proc getAction*(dfa: CommandDFA, state: int): string =
  return dfa.states[state].function

proc inputAsString(input: int64): string =
  result = case input:
    of INPUT_ENTER: "ENTER"
    of INPUT_ESCAPE: "ESCAPE"
    of INPUT_BACKSPACE: "BACKSPACE"
    of INPUT_SPACE: "SPACE"
    of INPUT_DELETE: "DELETE"
    of INPUT_TAB: "TAB"
    of INPUT_LEFT: "LEFT"
    of INPUT_RIGHT: "RIGHT"
    of INPUT_UP: "UP"
    of INPUT_DOWN: "DOWN"
    of INPUT_HOME: "HOME"
    of INPUT_END: "END"
    of INPUT_PAGE_UP: "PAGE_UP"
    of INPUT_PAGE_DOWN: "PAGE_DOWN"
    of INPUT_F1: "F1"
    of INPUT_F2: "F2"
    of INPUT_F3: "F3"
    of INPUT_F4: "F4"
    of INPUT_F5: "F5"
    of INPUT_F6: "F6"
    of INPUT_F7: "F7"
    of INPUT_F8: "F8"
    of INPUT_F9: "F9"
    of INPUT_F10: "F10"
    of INPUT_F11: "F11"
    of INPUT_F12: "F12"
    else: "<" & $input & ">"

proc inputToString*(input: int64, modifiers: Modifiers = {}): string =
  if modifiers != {} or input < 0: result.add "<"
  if Control in modifiers: result.add "C"
  if Shift in modifiers: result.add "S"
  if Alt in modifiers: result.add "A"
  if Super in modifiers: result.add "M"
  if modifiers != {}: result.add "-"

  if input > 0 and input <= int32.high:
    let ch = Rune(input)
    result.add $ch
  else:
    result.add inputAsString(input)
  if modifiers != {} or input < 0: result.add ">"

proc getInputCodeFromSpecialKey(specialKey: string): int64 =
  let runes = specialKey.toRunes
  if runes.len == 1:
    result = runes[0].int32
  else:
    result = case specialKey:
      of "ENTER": INPUT_ENTER
      of "ESCAPE": INPUT_ESCAPE
      of "BACKSPACE": INPUT_BACKSPACE
      of "SPACE": INPUT_SPACE
      of "DELETE": INPUT_DELETE
      of "TAB": INPUT_TAB
      of "LEFT": INPUT_LEFT
      of "RIGHT": INPUT_RIGHT
      of "UP": INPUT_UP
      of "DOWN": INPUT_DOWN
      of "HOME": INPUT_HOME
      of "END": INPUT_END
      of "PAGE_UP": INPUT_PAGE_UP
      of "PAGE_DOWN": INPUT_PAGE_DOWN
      of "F1": INPUT_F1
      of "F2": INPUT_F2
      of "F3": INPUT_F3
      of "F4": INPUT_F4
      of "F5": INPUT_F5
      of "F6": INPUT_F6
      of "F7": INPUT_F7
      of "F8": INPUT_F8
      of "F9": INPUT_F9
      of "F10": INPUT_F10
      of "F11": INPUT_F11
      of "F12": INPUT_F12
      else:
        echo "Invalid key '", specialKey, "'"
        0

proc linkState(dfa: var CommandDFA, currentState: int, nextState: int, inputCode: int64, mods: Modifiers) =
  if not (inputCode in dfa.states[currentState].inputs):
    dfa.states[currentState].inputs[inputCode] = DFAInput()
  dfa.states[currentState].inputs[inputCode].next[mods] = nextState

proc createOrUpdateState(dfa: var CommandDFA, currentState: int, inputCode: int64, mods: Modifiers): int =
  let nextState = if inputCode in dfa.states[currentState].inputs:
    if mods in dfa.states[currentState].inputs[inputCode].next:
      dfa.states[currentState].inputs[inputCode].next[mods]
    else:
      dfa.states.add DFAState()
      dfa.states[currentState].inputs[inputCode].next[mods] = dfa.states.len - 1
      dfa.states.len - 1
  else:
    dfa.states.add DFAState()
    dfa.states.len - 1
  linkState(dfa, currentState, nextState, inputCode, mods)
  return nextState

proc handleNextInput(dfa: var CommandDFA, input: seq[Rune], function: string, index: int, currentState: int) =
  type State = enum
    Normal
    Special

  var state = State.Normal
  var mods: Modifiers = {}
  var specialKey = ""

  var next: seq[tuple[index: int, state: int]] = @[]

  if index >= input.len:
    # Mark last state as terminal state.
    dfa.states[currentState].isTerminal = true
    dfa.states[currentState].function = function
    return

  for i in index..<input.len:
    var rune = input[i]
    var ascii = if rune.int64.isAscii: rune.char else: '\0'

    let isEscaped = i > 0 and input[i - 1].int64.isAscii and input[i - 1].char == '\\'
    if not isEscaped and ascii == '\\':
      continue

    let inputCode: int64 = if not isEscaped and ascii == '<':
      state = State.Special
      0.int64
    elif not isEscaped and ascii == '>':
      if state != State.Special:
        echo "Error: > without <"
        return
      let inputCode = getInputCodeFromSpecialKey(specialKey)
      state = State.Normal
      specialKey = ""
      inputCode

    else:
      if state == State.Special:
        if not isEscaped and ascii == '-':
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
          specialKey.add rune
        0.int64
      else:
        mods = {}
        rune.int64

    # echo inputCode, ", ", mods
    if inputCode != 0:
      let nextState = createOrUpdateState(dfa, currentState, inputCode, mods)
      next.add((index: i + 1, state: nextState))

      # echo "inputCode: ", inputCode, ", mods: ", mods

      if inputCode > 0 and (mods == {} or mods == {Shift}):
        let rune = Rune(inputCode)
        let bIsLower = rune.isLower
        if not bIsLower:
          # echo rune, " ", rune.toLower, " ", rune.toLower.int64, " ", inputToString(rune.toLower.int64, mods)
          linkState(dfa, currentState, nextState, rune.toLower.int64, mods + {Shift})
          linkState(dfa, currentState, nextState, inputCode, mods + {Shift})

        if bIsLower and Shift in mods:
          # echo rune, " ", rune.toUpper, " ", rune.toUpper.int64, " ", inputToString(rune.toUpper.int64, mods)
          linkState(dfa, currentState, nextState, rune.toUpper.int64, mods - {Shift})
          linkState(dfa, currentState, nextState, rune.toUpper.int64, mods)
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
      handleNextInput(result, input.toRunes, function, 0, 0)

proc autoCompleteRec(dfa: CommandDFA, result: var seq[(string, string)], currentInputs: string, currentState: int) =
  let state = dfa.states[currentState]
  if state.isTerminal:
    result.add (currentInputs, state.function)
  for input in state.inputs.keys:
    for mods in state.inputs[input].next.keys:
      let newInput = currentInputs & inputToString(input, mods)
      dfa.autoCompleteRec(result, newInput, state.inputs[input].next[mods])


proc autoComplete*(dfa: CommandDFA, currentState: int): seq[(string, string)] =
  result = @[]
  dfa.autoCompleteRec(result, "", currentState)

proc dump*(dfa: CommandDFA, currentState: int, currentInput: int64, currentMods: Modifiers): void =
  stdout.write '_'.repeat(dfa.states.len * 8 + 8)
  echo ""
  stdout.write "cmd\\sta|"
  for state in 0..<dfa.states.len:
    var stateStr = $state
    if state == currentState:
      stateStr = fmt"({stateStr})"
    stdout.write fmt"{stateStr:^7.7}|"
  echo ""

  stdout.write "       |"
  for state in dfa.states:
    if state.isTerminal:
      stdout.write fmt"{state.function:^7.7}|"
    else:
      stdout.write fmt"       |"

  echo ""

  var allUsedInputs: seq[int64] = @[]
  for state in 0..<dfa.states.len:
    for key in dfa.states[state].inputs.keys:
      allUsedInputs.add key

  allUsedInputs.sort
  allUsedInputs = allUsedInputs.deduplicate(isSorted = true)

  # echo allUsedInputs

  for input in allUsedInputs:
    for modifiersNum in 0..0b111:
      let modifiers = cast[Modifiers](modifiersNum)

      var line = ""

      # Input
      var chStr = inputToString(input, modifiers)

      if currentInput != 0 and input == currentInput and modifiers == currentMods:
        chStr = fmt"({chStr})"
      line.add fmt"{chStr:^7.7}|"

      # Next state
      var notEmpty = false
      for state in 0..<dfa.states.len:
        let nextState = if input in dfa.states[state].inputs:
          dfa.states[state].inputs[input].next.getOrDefault(modifiers, 0)
        else: 0

        if nextState == 0 and (state != currentState or input != currentInput or modifiers != currentMods):
          line.add "       |"
        else:
          var nextStateStr = $nextState
          if state == currentState and currentInput != 0 and input == currentInput and modifiers == currentMods:
            nextStateStr = fmt"({nextStateStr})"
          line.add fmt"{nextStateStr:^7.7}|"
          notEmpty = true

      if notEmpty:
        echo line

  stdout.write '_'.repeat(dfa.states.len * 8 + 8)
  echo ""