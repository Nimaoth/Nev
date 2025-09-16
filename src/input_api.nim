import std/[strutils, unicode, sequtils, tables]
import misc/[util]

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

  InputFlag* = enum
    Loop,
    Optional

  InputAction* = enum
    Press
    Repeat
    Release

proc isAscii*(input: int64): bool =
  if input >= char.low.ord and input <= char.high.ord:
    return true
  return false

proc getInputCodeFromSpecialKey*(specialKey: string, leaders: Table[string, seq[(int64, Modifiers)]]): seq[tuple[inputCodes: Slice[int64], mods: Modifiers]] =
  let runes = specialKey.toRunes
  if runes.len == 1:
    return @[(runes[0].int64..runes[0].int64, {})]
  else:
    if specialKey in leaders:
      return leaders[specialKey].mapIt((it[0]..it[0], it[1]))

    let input = case specialKey:
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
        0

    return @[(input.int64..input.int64, {})]

proc parseNextInput*(input: openArray[Rune], index: int, leaders = initTable[string, seq[(int64, Modifiers)]]()):
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
            # else: log(lvlError, fmt"Invalid modifier '{m}'") # todo
            else: discard
        specialKey = ""
        state = State.SpecialKey1

      elif not isEscaped and ascii == '>':
        if specialKey.len == 0:
          # log(lvlError, "Invalid input: expected key name or range before '>'") # todo
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
          # log(lvlError, "Invalid input: expected start of range before '-'") # todo
          return

        let specialKeys = getInputCodeFromSpecialKey(specialKey, leaders)
        if specialKeys.len != 1:
          # log(lvlError, "Invalid input: expected single key before '-'") # todo
          return

        current.mods = current.mods + specialKeys[0].mods
        current.inputCodes.a = specialKeys[0].inputCodes.a
        specialKey = ""
        state = State.SpecialKey2
      elif not isEscaped and ascii == '>':
        if specialKey.len == 0:
          # log(lvlError, "Invalid input: expected key name or range before '>'") # todo
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
          # log(lvlError, "Invalid input: expected end of range before '>'") # todo
          return

        let specialKeys = getInputCodeFromSpecialKey(specialKey, leaders)
        if specialKeys.len != 1:
          # log(lvlError, "Invalid input: expected single key before '-'") # todo
          return

        current.mods = current.mods + specialKeys[0].mods
        current.inputCodes.b = specialKeys[0].inputCodes.a
        result.inputs.add current
        result.text.add "-" & specialKey
        return
      else:
        specialKey.add rune

proc parseFirstInput*(input: string): Option[tuple[inputCode: Slice[int64], mods: Modifiers, text: string]] =
  let runes = input.toRunes
  var index = 0
  let (keys, _, _, _, text) = parseNextInput(runes, index)
  if keys.len == 0:
    return

  let (inputCode, mods) = keys[0]
  return (inputCode, mods, text).some

iterator parseInputs*(input: string, leaders = initTable[string, seq[(int64, Modifiers)]]()): tuple[inputCode: Slice[int64], mods: Modifiers, text: string] =
  let runes = input.toRunes
  var index = 0
  while index < input.len:
    let (keys, _, _, nextIndex, text) = parseNextInput(runes, index, leaders)
    if keys.len < 1:
      break

    let (inputCode, mods) = keys[0]
    yield (inputCode, mods, text)
    index = nextIndex

proc parseAction*(action: string): tuple[action: string, arg: string] =
  let spaceIndex = action.find(' ')
  if spaceIndex == -1:
    return (action, "")
  else:
    return (action[0..<spaceIndex], action[spaceIndex + 1..^1])
