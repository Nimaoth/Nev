import std/[strformat, strutils, tables, algorithm, unicode, sequtils]
import custom_logger

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
    nextState: int # The state to go to next if we are in a terminal state
    persistent: bool # Whether we want to set the default state for when an action succeded to this state
    function: string
    inputs: Table[InputKey, DFAInput]
  CommandDFA* = ref object
    persistentState: int
    states: seq[DFAState]

  CommandState* = object
    current*: int
    persistent: int

  MouseButton* {.pure.} = enum
    Left, Middle, Right, DoubleClick, TripleClick, Unknown

proc isAscii*(input: int64): bool =
  if input >= char.low.ord and input <= char.high.ord:
    return true
  return false

proc step*(dfa: CommandDFA, state: CommandState, currentInput: int64, mods: Modifiers): CommandState =
  if currentInput == 0:
    log(lvlError, "Input 0 is invalid")
    return

  if currentInput notin dfa.states[state.current].inputs:
    return CommandState(current: 0, persistent: 0)

  if mods notin dfa.states[state.current].inputs[currentInput].next:
    return CommandState(current: 0, persistent: 0)

  result.current = dfa.states[state.current].inputs[currentInput].next[mods]

  if dfa.states[result.current].persistent:
    result.persistent = result.current
  else:
    result.persistent = state.persistent

proc isTerminal*(dfa: CommandDFA, state: int): bool =
  return dfa.states[state].isTerminal

proc getDefaultState*(dfa: CommandDFA, state: int): int =
  return dfa.states[state].nextState

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

proc getInputCodeFromSpecialKey(specialKey: string, leader: (int64, Modifiers)): (int64, Modifiers) =
  let runes = specialKey.toRunes
  if runes.len == 1:
    result = (runes[0].int64, {})
  else:
    result[1] = {}
    result[0] = case specialKey:
      of "LEADER":
        return leader

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
        log(lvlError, fmt"Invalid key '{specialKey}'")
        0

proc linkState(dfa: var CommandDFA, currentState: int, nextState: int, inputCode: int64, mods: Modifiers) =
  if not (inputCode in dfa.states[currentState].inputs):
    dfa.states[currentState].inputs[inputCode] = DFAInput()
  dfa.states[currentState].inputs[inputCode].next[mods] = nextState

proc createOrUpdateState(dfa: var CommandDFA, currentState: int, inputCode: int64, mods: Modifiers, persistent: bool): int =
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
  dfa.states[nextState].persistent = persistent
  linkState(dfa, currentState, nextState, inputCode, mods)
  return nextState

proc parseNextInput(input: openArray[Rune], index: int, leader: (int64, Modifiers) = (0, {})): tuple[inputCode: int64, mods: Modifiers, nextIndex: int, persistent: bool] =
  result.inputCode = 0
  result.mods = {}
  result.nextIndex = index
  result.persistent = false

  type State = enum
    Normal
    Special

  var state = State.Normal
  var specialKey = ""

  for i in index..<input.len:
    var rune = input[i]
    var ascii = if rune.int64.isAscii: rune.char else: '\0'

    let isEscaped = i > 0 and input[i - 1].int64.isAscii and input[i - 1].char == '\\'
    if not isEscaped and ascii == '\\':
      continue

    result.inputCode = if not isEscaped and ascii == '<':
      state = State.Special
      0.int64
    elif not isEscaped and ascii == '>':
      if state != State.Special:
        log(lvlError, "Error: > without <")
        return
      let (inputCode, specialMods) = getInputCodeFromSpecialKey(specialKey, leader)
      result.mods = result.mods + specialMods
      state = State.Normal
      specialKey = ""
      inputCode

    else:
      if state == State.Special:
        if not isEscaped and ascii == '-':
          # Parse stuff so far as mods
          result.mods = {}
          for m in specialKey:
            case m:
              of 'C': result.mods = result.mods + {Modifier.Control}
              of 'S': result.mods = result.mods + {Modifier.Shift}
              of 'A': result.mods = result.mods + {Modifier.Alt}
              of '*': result.persistent = true
              else: log(lvlError, fmt"Invalid modifier '{m}'")
          specialKey = ""
        else:
          specialKey.add rune
        0.int64
      else:
        result.mods = {}
        rune.int64

    if result.inputCode != 0:
      result.nextIndex = i + 1
      return

proc handleNextInput(dfa: var CommandDFA, input: openArray[Rune], function: string, index: int, currentState: int, defaultState: int, leader: (int64, Modifiers)) =
  ##
  ## function: the action to be executed when reaching the final state
  ## index: index into input
  ## currentState: the state we are currently in

  if index >= input.len:
    # Mark last state as terminal state.
    dfa.states[currentState].isTerminal = true
    dfa.states[currentState].function = function
    dfa.states[currentState].nextState = defaultState
    return

  let (inputCode, mods, nextIndex, persistent) = parseNextInput(input, index, leader)

  if inputCode == 0:
    log(lvlError, fmt"Failed to parse input")
    return

  let nextState = createOrUpdateState(dfa, currentState, inputCode, mods, persistent)

  if inputCode > 0 and (mods == {} or mods == {Shift}):
    let rune = Rune(inputCode)
    let bIsLower = rune.isLower
    if not bIsLower:
      linkState(dfa, currentState, nextState, rune.toLower.int64, mods + {Shift})
      linkState(dfa, currentState, nextState, inputCode, mods + {Shift})

    if bIsLower and Shift in mods:
      linkState(dfa, currentState, nextState, rune.toUpper.int64, mods - {Shift})
      linkState(dfa, currentState, nextState, rune.toUpper.int64, mods)

  let nextDefaultState = if persistent: nextState else: defaultState
  handleNextInput(dfa, input, function, nextIndex, nextState, nextDefaultState, leader)

proc buildDFA*(commands: seq[(string, string)], leader: string): CommandDFA =
  new(result)

  result.states.add DFAState()
  var currentState = 0

  let (leaderInput, leaderMods, _, _) = parseNextInput(leader.toRunes, 0)

  for command in commands:
    currentState = 0

    let input = command[0]
    let function = command[1]

    if input.len > 0:
      handleNextInput(result, input.toRunes, function, index = 0, currentState = 0, defaultState = 0, leader = (leaderInput, leaderMods))

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
  var buff = ""
  buff.add '_'.repeat(dfa.states.len * 8 + 8)
  echo ""
  buff.add "cmd\\sta|"
  for state in 0..<dfa.states.len:
    var stateStr = $state
    if state == currentState:
      stateStr = fmt"({stateStr})"
    buff.add fmt"{stateStr:^7.7}|"
  echo ""

  buff.add "       |"
  for state in dfa.states:
    if state.isTerminal:
      buff.add fmt"{state.function:^7.7}|"
    else:
      buff.add fmt"       |"

  echo buff

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

  echo '_'.repeat(dfa.states.len * 8 + 8)