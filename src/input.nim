import std/[strformat, strutils, tables, algorithm, unicode, sequtils, sugar, json, options, parseutils]
import misc/[custom_logger, array_set, util, regex, bitset]

logCategory "input"

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

  InputFlag = enum
    Loop,
    Optional

  Transition = object
    state: int
    capture: string
    functionIndices: BitSet
    function: string

  DFAInput = object
    # length 16 because there are 4 modifiers and so 2^4 = 16 possible combinations
    next: Table[Modifiers, Transition]

  InputKey = int64
  DFAState = object
    isTerminal: bool
    nextState: int # The state to go to next if we are in a terminal state
    persistent: bool # Whether we want to set the default state for when an action succeded to this state
    function: string
    transitions: Table[Slice[InputKey], DFAInput]
    epsilonTransitions: seq[Transition]
    terminalStates: seq[int]
    capture: string
    suffix: string
    functionIndices: BitSet

  CommandDFA* = ref object
    persistentState: int
    states: seq[DFAState]
    functions: seq[string]
    functionIndices: Table[string, int]
    terminalStates: Table[int, string]
    postfixStates: Table[(string, string), int]
    subGraphStates: Table[(string, string, int), tuple[startState: int, endState: int]]

  CommandState* = object
    current*: int
    persistent: int
    captures*: Table[string, string]
    functionIndices*: BitSet

  MouseButton* {.pure.} = enum
    Left, Middle, Right, DoubleClick, TripleClick, Unknown

proc inputToString*(input: int64, modifiers: Modifiers = {}): string

proc isAscii*(input: int64): bool =
  if input >= char.low.ord and input <= char.high.ord:
    return true
  return false

let capturePattern = re"<(.*?)>"
proc getAction*(dfa: CommandDFA, state: CommandState, command: string): string =
  var last = 0
  for bounds in command.findAllBounds(capturePattern):
    defer:
      last = bounds.last + 1
    if last < bounds.first:
      result.add command[last..<bounds.first]

    if command[bounds.first + 1] == '#':
      let captureName = command[(bounds.first + 2)..<bounds.last]
      if state.captures.contains(captureName):
        result.add $state.captures[captureName].parseInt.catch(0)
      else:
        result.add "0"
    elif command[bounds.first + 1] == '$':
      let captureName = command[(bounds.first + 2)..<bounds.last]
      if state.captures.contains(captureName):
        result.add $state.captures[captureName].newJString
      else:
        result.add $newJString("")
    else:
      let captureName = command[(bounds.first + 1)..<bounds.last]
      if state.captures.contains(captureName):
        result.add $state.captures[captureName].newJString
      else:
        result.add command[bounds.first..bounds.last]

  if last < command.len:
    result.add command[last..^1]

proc getAction*(dfa: CommandDFA, state: CommandState): string =
  assert state.functionIndices.bitSetCard == 1
  for functionIndex in state.functionIndices:
    let function = dfa.functions[functionIndex]
    return dfa.getAction(state, function)

proc stepEmpty*(dfa: CommandDFA, state: CommandState): seq[CommandState] =
  # defer:
  #   echo &"stepEmpty {state} -> {result}"
  for transition in dfa.states[state.current].epsilonTransitions:
    var newState = state
    newState.current = transition.state
    newState.functionIndices.bitSetIntersect transition.functionIndices
    if transition.function != "":
      if newState.captures.contains(transition.capture):
        # echo " 1> ", transition, ": ", transition.capture, " -> ", dfa.getAction(newState, transition.function), " | ", transition.function
        newState.captures[transition.capture] = dfa.getAction(newState, transition.function)

    if dfa.states[transition.state].transitions.len > 0 or dfa.states[transition.state].epsilonTransitions.len == 0:
      result.incl newState

    result.incl dfa.stepEmpty(newState)

proc stepAll*(dfa: CommandDFA, state: CommandState, currentInput: int64, mods: Modifiers, beginEmpty: bool): seq[CommandState] =
  if currentInput == 0:
    log(lvlError, "Input 0 is invalid")
    return @[]

  # echo &"stepAll ({currentInput}) {inputToString(currentInput, mods)}, empty {beginEmpty}: {state}"
  if beginEmpty:

    var states = dfa.stepEmpty(state)
    if dfa.states[state.current].transitions.len > 0:
      states.add state

    # echo &"states after epsilon transitions: {states}"
    for state in states:
      for transition in dfa.states[state.current].transitions.pairs:
        # echo &"  check transition {state.current}: {transition}"
        if currentInput in transition[0]:
          if not transition[1].next.contains(mods):
            continue

          let transition = transition[1].next[mods]

          # echo &"  transition {state.current}: {transition}"
          var newState = state
          newState.current = transition.state
          newState.functionIndices.bitSetIntersect transition.functionIndices
          newState.captures.mgetOrPut(dfa.states[transition.state].capture, "").add(inputToString(currentInput, mods))
          # if dfa.states[transition.state].function != "":
          #   # echo " 2> ", nextState, ": ", dfa.states[transition.state].capture, " -> ", dfa.getAction(newState)
          #   newState.captures[dfa.states[transition.state].capture] = dfa.getAction(newState)

          # if dfa.states[transition.state].transitions.len > 0 or dfa.states[transition.state].isTerminal:
          #   result.add newState
          if dfa.states[transition.state].transitions.len > 0 or dfa.states[transition.state].epsilonTransitions.len == 0:
            result.add newState
          result.add dfa.stepEmpty(newState)

  else:
    for transition in dfa.states[state.current].transitions.pairs:
      if currentInput in transition[0]:
        if not transition[1].next.contains(mods):
          continue

        let transition = transition[1].next[mods]

        var newState = state
        newState.current = transition.state
        newState.functionIndices.bitSetIntersect transition.functionIndices
        newState.captures.mgetOrPut(dfa.states[transition.state].capture, "").add(inputToString(currentInput, mods))
        # echo newState
        # if dfa.states[transition.state].function != "":
        #   # echo " 3> ", nextState, ": ", dfa.states[transition.state].capture, " -> ", dfa.getAction(newState)
        #   newState.captures[dfa.states[transition.state].capture] = dfa.getAction(newState)

        # if dfa.states[transition.state].transitions.len > 0 or dfa.states[transition.state].isTerminal:
        if dfa.states[transition.state].transitions.len > 0 or dfa.states[transition.state].epsilonTransitions.len == 0:
          result.add newState
        result.add dfa.stepEmpty(newState)

  return

proc stepAll*(dfa: CommandDFA, states: seq[CommandState], currentInput: int64, mods: Modifiers): seq[CommandState] =
  # echo &"stepAll {inputToString(currentInput, mods)}, {states.len}, {states}"
  # defer:
  #   echo &"stepAll -> {result}"
  let states = if states.len > 0:
    states
  else:
    var functionIndices: BitSet
    for i in 0..<dfa.functions.len:
      functionIndices.bitSetIncl i
    @[CommandState(current: 0, functionIndices: functionIndices)]

  for state in states:
    result.add dfa.stepAll(state, currentInput, mods, states.len == 1 and states[0].current == 0)

proc isTerminal*(dfa: CommandDFA, state: int): bool =
  return dfa.states[state].isTerminal

proc getDefaultState*(dfa: CommandDFA, state: int): int =
  return dfa.states[state].nextState

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

proc inputToString*(inputs: Slice[int64], modifiers: Modifiers = {}): string =
  let special = modifiers != {} or inputs.a < 0 or inputs.a != inputs.b

  if special: result.add "<"
  if Control in modifiers: result.add "C"
  if Shift in modifiers: result.add "S"
  if Alt in modifiers: result.add "A"
  if Super in modifiers: result.add "M"
  if modifiers != {}: result.add "-"

  if inputs.a == 1 and inputs.b == int32.high.int64:
    result.add "CHAR"
  elif inputs.a == int32.low.int64 and inputs.b == int32.high.int64:
    result.add "ANY"
  else:
    if inputs.a > 0 and inputs.a <= int32.high:
      let ch = Rune(inputs.a)
      result.add $ch
    else:
      result.add inputAsString(inputs.a)

    if inputs.a != inputs.b:
      result.add "-"
      if inputs.b > 0 and inputs.b <= int32.high:
        let ch = Rune(inputs.b)
        result.add $ch
      else:
        result.add inputAsString(inputs.b)

  if special: result.add ">"

proc getInputCodeFromSpecialKey(specialKey: string, leaders: seq[(int64, Modifiers)]): seq[tuple[inputCodes: Slice[int64], mods: Modifiers]] =
  let runes = specialKey.toRunes
  if runes.len == 1:
    return @[(runes[0].int64..runes[0].int64, {})]
  else:
    let input = case specialKey:
      of "LEADER":
        return leaders.mapIt((it[0]..it[0], it[1]))

      of "CHAR":
        return @[(1.int64..int32.high.int64, {})]
      of "ANY":
        return @[(int32.low.int64..int32.high.int64, {})]

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
        # log(lvlError, fmt"Invalid key '{specialKey}'") # todo: improve error handling
        0

    return @[(input.int64..input.int64, {})]

proc linkStates(dfa: var CommandDFA, currentState: int, nextState: int, inputCodes: Slice[int64], mods: Modifiers, functionIndex: int, capture: string): bool =
  if not (inputCodes in dfa.states[currentState].transitions):
    dfa.states[currentState].transitions[inputCodes] = DFAInput()
  if mods in dfa.states[currentState].transitions[inputCodes].next:
    template current(): untyped = dfa.states[currentState].transitions[inputCodes].next[mods]
    # echo &"link states {currentState} -> {nextState}, {inputToString(inputCodes, mods)}, {functionIndex}, {capture}, {current}"
    if current.state != nextState:
      log lvlError, fmt"Duplicate transition for {inputToString(inputCodes, mods)} from {currentState} to {current.state}/{nextState}"
      return false

    assert current.state == nextState
    assert current.capture == capture
    dfa.states[currentState].transitions[inputCodes].next[mods].functionIndices.bitSetIncl functionIndex
    return true
  else:
    # echo &"link states {currentState} -> {nextState}, {inputToString(inputCodes, mods)}, {functionIndex}, {capture}"
    dfa.states[currentState].transitions[inputCodes].next[mods] = Transition(state: nextState, functionIndices: [functionIndex].toBitSet, capture: capture)
    return true

proc linkStates(dfa: var CommandDFA, currentState: int, nextState: int, functionIndex: int, capture: string, function: string) =
  for transition in dfa.states[currentState].epsilonTransitions.mitems:
    if transition.state == nextState:
      # echo &"link states {currentState} -> {nextState}, {functionIndex}, {capture}, {transition.function} -> {function}"
      assert transition.capture == capture
      # assert transition.function == function
      transition.functionIndices.bitSetIncl functionIndex
      return

  dfa.states[currentState].epsilonTransitions.add Transition(state: nextState, functionIndices: [functionIndex].toBitSet, capture: capture, function: function)

proc createOrUpdateState(dfa: var CommandDFA, currentState: int, inputCodes: Slice[int64], mods: Modifiers, persistent: bool, loop: bool, capture: string, functionIndex: int): Option[int] =
  let nextState = if loop:
    currentState
  elif inputCodes in dfa.states[currentState].transitions:
    if mods in dfa.states[currentState].transitions[inputCodes].next:
      dfa.states[currentState].transitions[inputCodes].next[mods].state
    else:
      dfa.states.add DFAState()
      # echo &"init states {currentState} -> {dfa.states.len-1}, {inputToString(inputCodes, mods)}, {functionIndex}, {capture}"
      dfa.states[currentState].transitions[inputCodes].next[mods] = Transition(state: dfa.states.len - 1, functionIndices: [functionIndex].toBitSet, capture: capture)
      dfa.states.len - 1
  else:
    dfa.states.add DFAState()
    dfa.states.len - 1

  dfa.states[nextState].persistent = persistent
  # echo &"update state {nextState}, {dfa.states[nextState].capture} -> {capture}"
  dfa.states[nextState].capture = capture
  if not linkStates(dfa, currentState, nextState, inputCodes, mods, functionIndex, capture):
    return int.none
  return nextState.some

proc parseNextInput(input: openArray[Rune], index: int, leaders: seq[(int64, Modifiers)] = @[]):
    tuple[inputs: seq[tuple[inputCodes: Slice[int64], mods: Modifiers]], persistent: bool, flags: set[InputFlag], nextIndex: int, text: string] =

  result.nextIndex = index

  type State = enum
    Normal
    Special
    SpecialKey1
    SpecialKey2

  var state = State.Normal
  var specialKey = ""

  var current: tuple[inputCodes: Slice[int64], mods: Modifiers]

  for i in index..<input.len:
    var rune = input[i]
    var ascii = if rune.int64.isAscii: rune.char else: '\0'

    result.nextIndex = i + 1

    let isEscaped = i > 0 and input[i - 1].int64.isAscii and input[i - 1].char == '\\'
    if not isEscaped and ascii == '\\':
      continue

    case state
    of Normal:
      if not isEscaped and ascii == '<':
        state = State.Special
        continue

      return (@[(rune.int64..rune.int64, {})], false, {}, i + 1, "")

    of Special:
      if not isEscaped and ascii == '-':
        # Parse stuff so far as mods
        current.mods = {}
        for m in specialKey:
          case m:
            of 'C': current.mods = current.mods + {Modifier.Control}
            of 'S': current.mods = current.mods + {Modifier.Shift}
            of 'A': current.mods = current.mods + {Modifier.Alt}
            of '*': result.persistent = true
            of 'o': result.flags.incl Loop
            of '?': result.flags.incl Optional
            else: log(lvlError, fmt"Invalid modifier '{m}'")
        specialKey = ""
        state = State.SpecialKey1

      elif not isEscaped and ascii == '>':
        if specialKey.len == 0:
          log(lvlError, "Invalid input: expected key name or range before '>'")
          return

        for (inputCodes, specialMods) in getInputCodeFromSpecialKey(specialKey, leaders):
          result.inputs.add (inputCodes, current.mods + specialMods)
          result.text = specialKey
        return

      else:
        specialKey.add rune

    of SpecialKey1:
      if not isEscaped and ascii == '-':
        if specialKey.len == 0:
          log(lvlError, "Invalid input: expected start of range before '-'")
          return

        let specialKeys = getInputCodeFromSpecialKey(specialKey, leaders)
        if specialKeys.len != 1:
          log(lvlError, "Invalid input: expected single key before '-'")
          return

        current.mods = current.mods + specialKeys[0].mods
        current.inputCodes.a = specialKeys[0].inputCodes.a
        specialKey = ""
        state = State.SpecialKey2
      elif not isEscaped and ascii == '>':
        if specialKey.len == 0:
          log(lvlError, "Invalid input: expected key name or range before '>'")
          return

        for (inputCodes, specialMods) in getInputCodeFromSpecialKey(specialKey, leaders):
          result.inputs.add (inputCodes, current.mods + specialMods)
          result.text = specialKey
        return
      else:
        specialKey.add rune

    of SpecialKey2:
      if not isEscaped and ascii == '>':
        if specialKey.len == 0:
          log(lvlError, "Invalid input: expected end of range before '>'")
          return

        let specialKeys = getInputCodeFromSpecialKey(specialKey, leaders)
        if specialKeys.len != 1:
          log(lvlError, "Invalid input: expected single key before '-'")
          return

        current.mods = current.mods + specialKeys[0].mods
        current.inputCodes.b = specialKeys[0].inputCodes.a
        result.inputs.add current
        result.text.add "-" & specialKey
        return
      else:
        specialKey.add rune

iterator parseInputs*(input: string): tuple[inputCode: Slice[int64], mods: Modifiers, text: string] =
  let runes = input.toRunes
  var index = 0
  while index < input.len:
    let (keys, _, _, nextIndex, text) = parseNextInput(runes, index)
    if keys.len != 1:
      log(lvlError, fmt"Failed to parse input '{input}'")
      break

    let (inputCode, mods) = keys[0]
    yield (inputCode, mods, text)
    index = nextIndex

proc fillTransitionFunctionIndicesRec(dfa: var CommandDFA, state: int, functionIndices: BitSet, endState: int) =
  # dfa.states[state].functionIndices.incl functionIndices
  # echo &"fillTransitionFunctionIndicesRec({state}, {endState}, {functionIndices})"

  for t in dfa.states[state].epsilonTransitions.mitems:
  # for i in 0..dfa.states[state].epsilonTransitions.high:
    t.functionIndices.bitSetUnion functionIndices
    if t.state == endState:
      continue
    fillTransitionFunctionIndicesRec(dfa, t.state, functionIndices, endState)

  for (_, dfaInput) in dfa.states[state].transitions.mpairs:
    for (_, t) in dfaInput.next.mpairs:
      t.functionIndices.bitSetUnion functionIndices
      if t.state == endState or t.state == state:
        continue
      fillTransitionFunctionIndicesRec(dfa, t.state, functionIndices, endState)

# proc fillTransitionFunctionIndices*(dfa: var CommandDFA) =
#   dfa.fillTransitionFunctionIndicesRec(0, {})

proc handleNextInput(
    dfa: var CommandDFA,
    commands: Table[string, Table[string, string]],
    input: openArray[Rune],
    function: string,
    index: int,
    currentState: int,
    defaultState: int,
    leaders: seq[(int64, Modifiers)],
    functionIndex: int,
    capture = "",
    depth = 0,
    subGraphCounts = newTable[string, int](),
  ): seq[int] =
  ##
  ## function: the action to be executed when reaching the final state
  ## index: index into input
  ## currentState: the state we are currently in
  let suffix = input[index..^1].join("")
  # echo "| ".repeat(depth) & &"handleNextInput '{suffix}', '{function}', {index}, {currentState}"
  # defer:
  #   echo "| ".repeat(depth) & &"-> {result}"

  if index >= input.len:
    # Mark last state as terminal state.
    if dfa.states[currentState].epsilonTransitions.len == 0:
      dfa.states[currentState].isTerminal = true
    dfa.states[currentState].function = function
    dfa.states[currentState].nextState = defaultState
    # echo "set terminal ", currentState, " to ", function
    return @[currentState] # todo: end state

  let (keys, persistent, flags, nextIndex, inputName) = parseNextInput(input, index, leaders)
  # echo "| ".repeat(depth) & &"keys: {keys}, persistent: {persistent}, flags: {flags}, nextIndex: {nextIndex}, inputName: {inputName}"

  assert suffix.len > 0

  # echo "| ".repeat(depth) & &"handleNextInput('{input}', '{function}', {index}, {currentState}, {defaultState}, {leaders})"
  # echo "| ".repeat(depth) & &"  inputCodes: {inputCodes}, mods: {mods}, nextIndex: {nextIndex}, persistent: {persistent}, flags: {flags}, inputName: {inputName}"
  if inputName.len > 0 and commands.contains(inputName):
    let subGraphCount = subGraphCounts.getOrDefault(inputName, 0)
    subGraphCounts[inputName] = subGraphCount + 1

    let subCapture = if capture.len > 0: capture & "." & inputName else: inputName

    # echo "| ".repeat(depth) & &"sub graph {inputName}, {subGraphCounts[]}"
    let subGraphKey = (inputName, capture, subGraphCount)
    if dfa.subGraphStates.contains(subGraphKey):
      # echo "| ".repeat(depth) & &"sub graph {inputName} found -> {dfa.subGraphStates[subGraphKey]}"
      let (nextStartState, nextEndState) = dfa.subGraphStates[subGraphKey]
      dfa.linkStates(currentState, nextStartState, functionIndex, capture, "")
      fillTransitionFunctionIndicesRec(dfa, nextStartState, [functionIndex].toBitSet, nextEndState)
      result = handleNextInput(dfa, commands, input, function, nextIndex, nextEndState, defaultState, leaders, functionIndex, capture, depth + 1, subGraphCounts)
      if Optional in flags:
        dfa.linkStates(currentState, nextEndState, functionIndex, capture, "")
      return

    dfa.states.add DFAState()
    let subState = dfa.states.len - 1
    dfa.states.add DFAState()
    let endState = dfa.states.len - 1
    dfa.linkStates(currentState, subState, functionIndex, capture, "")

    for command in commands[inputName].pairs:
      let (subInput, function) = command
      # echo "| ".repeat(depth) & &"subInput: {subInput}, function: {function}"
      let nextEndStates = handleNextInput(dfa, commands, subInput.toRunes, function, index = 0, currentState = subState, defaultState = defaultState, leaders = leaders, functionIndex, subCapture, depth + 1, subGraphCounts[].neww)
      # echo "| ".repeat(depth) & &"-> endStates: {nextEndStates}"
      for es in nextEndStates:
        dfa.linkStates(es, endState, functionIndex, subCapture, function)

    result = handleNextInput(dfa, commands, input, function, nextIndex, endState, defaultState, leaders, functionIndex, capture, depth + 1, subGraphCounts)

    if Optional in flags:
      dfa.linkStates(currentState, endState, functionIndex, capture, "")

    dfa.subGraphStates[subGraphKey] = (subState, endState)
    return

  # if capture == "" and dfa.postfixStates.contains((suffix, capture)):
  #   # echo "| ".repeat(depth) & &"suffix found -> {dfa.postfixStates[(suffix, capture)]}, {suffix}, {capture}"

  #   let nextState = dfa.postfixStates[(suffix, capture)]
  #   for key in keys:
  #     assert key.inputCodes.a != 0 and key.inputCodes.a != 0
  #     if not linkStates(dfa, currentState, nextState, key.inputCodes, key.mods, functionIndex, dfa.states[nextState].capture):
  #       log lvlError, fmt"""Ambigious keybinding '{input.join("")}' at {index} ({inputToString(key.inputCodes, key.mods)})"""
  #     fillTransitionFunctionIndicesRec(dfa, nextState, [functionIndex].toBitSet, 0)
  #   return @[nextState]

  if keys.len == 0:
    log(lvlError, fmt"Failed to parse input")
    return

  for key in keys:
    let nextState = if inputName == "CHAR" or inputName == "ANY":
      let subCapture = if capture.len > 0: capture & "." & inputName else: inputName
      let nextState = createOrUpdateState(dfa, currentState, key.inputCodes, key.mods, persistent, Loop in flags, subCapture, functionIndex).getOr:
        log lvlError, fmt"""Ambigious keybinding '{input.join("")}' at {index} ({inputToString(key.inputCodes, key.mods)})"""
        continue
      # echo "| ".repeat(depth) & &"create next state {nextState}, {key.inputCodes}, {key.mods}, current state {currentState}"
      nextState

    else:
      let nextState = createOrUpdateState(dfa, currentState, key.inputCodes, key.mods, persistent, Loop in flags, capture, functionIndex).getOr:
        log lvlError, fmt"""Ambigious keybinding '{input.join("")}' at {index} ({inputToString(key.inputCodes, key.mods)})"""
        continue

      dfa.states[nextState].suffix.add " " & suffix

      # echo "| ".repeat(depth) & &"create/update next state {nextState}, {key.inputCodes}, {key.mods}, current state {currentState}"

      if key.inputCodes.a > 0 and (key.mods == {} or key.mods == {Shift}):
        let rune = Rune(key.inputCodes.a)
        let rune2 = Rune(key.inputCodes.b)
        let bIsLower = rune.isLower
        if not bIsLower and rune.isUpper:
          # echo "| ".repeat(depth) & &"    link state {currentState} to {nextState} for {rune.toLower} and {rune.toUpper}"
          discard linkStates(dfa, currentState, nextState, rune.toLower.int64..rune2.toLower.int64, key.mods + {Shift}, functionIndex, capture)
          discard linkStates(dfa, currentState, nextState, key.inputCodes, key.mods + {Shift}, functionIndex, capture)

        if bIsLower and Shift in key.mods:
          # echo "| ".repeat(depth) & &"    link state {currentState} to {nextState} for {rune.toLower} and {rune.toUpper}"
          discard linkStates(dfa, currentState, nextState, rune.toUpper.int64..rune2.toUpper.int64, key.mods - {Shift}, functionIndex, capture)
          discard linkStates(dfa, currentState, nextState, rune.toUpper.int64..rune2.toUpper.int64, key.mods, functionIndex, capture)

      nextState

    dfa.postfixStates[(suffix, capture)] = nextState

    let nextDefaultState = if persistent: nextState else: defaultState
    result.add handleNextInput(dfa, commands, input, function, nextIndex, nextState, nextDefaultState, leaders, functionIndex, capture, depth + 1, subGraphCounts)

# proc fillTransitionFunctionIndices*(dfa: var CommandDFA) =
#   proc fillTransitionFunctionIndicesRec(dfa: var CommandDFA, state: int, functionIndices: BitSet) =
#     dfa.states[state].functionIndices.bitSetIncl functionIndices
#     for t in dfa.states[state].epsilonTransitions.mitems:
#       fillTransitionFunctionIndicesRec(dfa, t.state, dfa.states[state].functionIndices + t.functionIndices)

#     for (mods, next) in dfa.states[state].transitions.mpairs:
#       fillTransitionFunctionIndicesRec(dfa, t.state, dfa.states[state].functionIndices + t.functionIndices)

#   dfa.fillTransitionFunctionIndicesRec(0, {})

proc buildDFA*(commands: Table[string, Table[string, string]], leaders: seq[string] = @[]): CommandDFA =
  new(result)

  # debugf"commands: {commands}"
  result.states.add DFAState()

  let leaders = collect(newSeq):
    for leader in leaders:
      let (keys, _, _, _, _) = parseNextInput(leader.toRunes, 0)
      for key in keys:
        (key.inputCodes.a, key.mods)

  if commands.contains(""):
    for command in commands[""].pairs:
      let input = command[0]
      let function = command[1]

      if input.len > 0:
        # debugf"handle input {input} with leader {leaderInput}"

        let functionIndex = if result.functionIndices.contains(function):
          result.functionIndices[function]
        else:
          result.functions.add function
          result.functionIndices[function] = result.functions.len - 1
          result.functions.len - 1

        discard handleNextInput(result, commands, input.toRunes, function, index = 0, currentState = 0, defaultState = 0, leaders = leaders, functionIndex)

  # echo result.functionIndices

  # {"delete-line <#count>": 3, "change-move <move> <#count>": 1, "select-last <move>": 0, "delete-move <move> <#count>": 2}

proc buildDFA*(commands: seq[(string, string)], leaders: seq[string] = @[]): CommandDFA =
  return buildDFA({"": commands.toTable}.toTable, leaders)

proc autoCompleteRec(dfa: CommandDFA, result: var seq[(string, string)], currentInputs: string, currentState: int) =
  discard

proc autoComplete*(dfa: CommandDFA, currentState: int): seq[(string, string)] =
  result = @[]
  dfa.autoCompleteRec(result, "", currentState)

proc dump*(dfa: CommandDFA, currentState: int, currentInput: int64, currentMods: Modifiers): void =
  const columnWidth = 16

  var buff = ""
  buff.add '_'.repeat(dfa.states.len * (columnWidth + 1) + columnWidth + 1)
  buff.add "\n"
  buff.add " ".repeat(columnWidth - 12) & "  cmd\\sta   |"

  for state in 0..<dfa.states.len:
    var stateStr = $state
    if state == currentState:
      stateStr = fmt"({stateStr})"
    buff.add " ".repeat(columnWidth - 12) & fmt"{stateStr:^12.12}|"
  buff.add "\n"

  buff.add " ".repeat(columnWidth) & "|"
  for state in dfa.states:
    if state.isTerminal:
      buff.add " ".repeat(columnWidth - 12) & fmt"{state.function:^12.12}|"
    else:
      buff.add " ".repeat(columnWidth) & "|"
  buff.add "\n"

  buff.add " ".repeat(columnWidth) & "|"
  for state in dfa.states:
    buff.add " ".repeat(columnWidth - 12) & fmt"{state.capture:^12.12}|"

  echo buff

  var allUsedInputs: seq[Slice[int64]] = @[]
  for state in 0..<dfa.states.len:
    for key in dfa.states[state].transitions.keys:
      allUsedInputs.add key

  allUsedInputs.sort((a, b) => a.a.int - b.a.int)
  allUsedInputs = allUsedInputs.deduplicate(isSorted = true)

  # echo allUsedInputs

  for inputs in allUsedInputs:
    for modifiersNum in 0..0b1111:
      let modifiers = cast[Modifiers](modifiersNum)

      var line = ""

      # Input
      var chStr = inputToString(inputs, modifiers)

      if currentInput != 0 and currentInput in inputs and modifiers == currentMods:
        chStr = fmt"({chStr})"
      line.add " ".repeat(columnWidth - 12) & fmt"{chStr:^12.12}|"

      # Next state
      var notEmpty = false
      for state in 0..<dfa.states.len:
        let nextState = if inputs in dfa.states[state].transitions:
          dfa.states[state].transitions[inputs].next.getOrDefault(modifiers, Transition()).state
        else: 0

        var remainingColumnWidth = columnWidth

        let epsilonTransitions = dfa.states[state].epsilonTransitions.join(",")
        if epsilonTransitions.len > 0:
          line.add "*"
          line.add epsilonTransitions
          line.add "* "
          remainingColumnWidth -= epsilonTransitions.len + 3

        if nextState == 0 and (state != currentState or currentInput notin inputs or modifiers != currentMods):
          line.add " ".repeat(max(0, remainingColumnWidth)) & "|"
        else:
          var nextStateStr = $nextState
          if state == currentState and currentInput != 0 and currentInput in inputs and modifiers == currentMods:
            nextStateStr = fmt"({nextStateStr})"
          line.add " ".repeat(max(0, remainingColumnWidth - 4)) & fmt"{nextStateStr:^4.4}|"
          notEmpty = true

      if notEmpty:
        echo line

  echo '_'.repeat(dfa.states.len * (columnWidth + 1) + columnWidth + 1)

proc dumpGraphViz*(dfa: CommandDFA): string =
  result = "digraph DFA {\n"

  func escape(a: string): string = replace(a, "\"", "\\\"")
  proc addState(res: var string, state: int) =
    let escaped = replace(&"{state}\\n{dfa.states[state].capture}", "\"", "\\\"")
    # let escaped = replace(&"{state}\\n{dfa.states[state].suffix}\\n{dfa.states[state].capture}", "\"", "\\\"")
    res.add &"\"{escaped}\""

  let colors = @["green", "blue", "orange", "purple", "yellow", "brown", "cyan", "magenta", "gray", "black", "white"]
  let shapes = @[""]
  var colorMap = initTable[string, int]()
  var shapeMap = initTable[string, int]()
  for state in 0..<dfa.states.len:
    let capture = dfa.states[state].capture
    let function = dfa.states[state].function
    if capture != "" and colorMap.len < colors.len and capture notin colorMap:
      colorMap[capture] = colorMap.len
    if function != "" and shapeMap.len < shapes.len and function notin shapeMap:
      shapeMap[function] = shapeMap.len

  for key, value in colorMap.pairs:
    result.add &"  node [color={colors[value]}];"
    for i, state in dfa.states:
      if state.capture == key:
        result.add " "
        result.addState i
    result.add ";\n"

  # for key, value in shapeMap.pairs:
  #   result.add &"  node [shape={shapes[value]}];"
  #   for i, state in dfa.states:
  #     if state.function == key:
  #       result.add " "
  #       result.addState i
  #   result.add ";\n"

  result.add "  node [shape = circle, color = gray];\n\n"

  for state in 0..<dfa.states.len:
    for transition in dfa.states[state].transitions.pairs:

      for (modifier, next) in transition[1].next.pairs:
        result.add "  "
        result.addState(state)
        result.add " -> "
        result.addState(next.state)
        # let functionIndices = $next.functionIndices
        # result.add &" [color=black, label=\"{inputToString(transition[0], modifier)}\\n{next.function.escape}\\n{next.capture}\\n{functionIndices}\"]\n"
        result.add &" [color=black, label=\"{inputToString(transition[0], modifier)}\\n{next.function.escape}\\n{next.capture}\"]\n"

    for nextState in dfa.states[state].epsilonTransitions:
      result.add "  "
      result.addState(state)
      result.add " -> "
      result.addState(nextState.state)
      # let functionIndices = $nextState.functionIndices
      # result.add &" [color=red, label=\"ε\\n{nextState.function.escape}\\n{nextState.capture}\\n{functionIndices}\"]\n"
      result.add &" [color=red, label=\"ε\\n{nextState.function.escape}\\n{nextState.capture}\"]\n"

  result.add "\n}"
