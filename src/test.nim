import sdl2_nim/sdl
import std/[json, jsonutils, strformat, bitops, strutils, tables, algorithm, math]
import os, osproc
import compiler/[nimeval, renderer, ast]

const
  Title = "SDL2 App"
  ScreenW = 640 # Window width
  ScreenH = 480 # Window height
  WindowFlags = 0
  RendererFlags = sdl.RendererAccelerated or sdl.RendererPresentVsync


type
  App = ref AppObj
  AppObj = object
    window*: sdl.Window # Window pointer
    renderer*: sdl.Renderer # Rendering state pointer


# Initialization sequence
proc init(app: App): bool =
  # Init SDL
  if sdl.init(sdl.InitVideo) != 0:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't initialize SDL: %s",
                    sdl.getError())
    return false

  # Create window
  app.window = sdl.createWindow(
    Title,
    sdl.WindowPosUndefined,
    sdl.WindowPosUndefined,
    ScreenW,
    ScreenH,
    WindowFlags)
  if app.window == nil:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't create window: %s",
                    sdl.getError())
    return false

  # Create renderer
  app.renderer = sdl.createRenderer(app.window, -1, RendererFlags)
  if app.renderer == nil:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't create renderer: %s",
                    sdl.getError())
    return false

  # Set draw color
  if app.renderer.setRenderDrawColor(0xFF, 0xFF, 0xFF, 0xFF) != 0:
    sdl.logWarn(sdl.LogCategoryVideo,
                "Can't set draw color: %s",
                sdl.getError())
    return false

  sdl.logInfo(sdl.LogCategoryApplication, "SDL initialized successfully")
  return true


# Shutdown sequence
proc exit(app: App) =
  app.renderer.destroyRenderer()
  app.window.destroyWindow()
  sdl.logInfo(sdl.LogCategoryApplication, "SDL shutdown completed")
  sdl.quit()




########
# MAIN #
########

var
  app = App(window: nil, renderer: nil)
  done = false # Main loop exit condition

const
  INPUT_COUNT = 256 + 10
  INPUT_ENTER = 13
  INPUT_ESCAPE = 27
  INPUT_BACKSPACE = 8
  INPUT_SPACE = 32
  INPUT_DELETE = 127


type
  Modifier = enum
    Control
    Shift
    Alt
  Modifiers = set[Modifier]
  DFAInput = object
    # length 8 because there are 3 modifiers and so 2^3 = 8 possible combinations
    next: array[8, int]
  DFAState = object
    isTerminal: bool
    function: string
    inputs: array[INPUT_COUNT, DFAInput]
  CommandDFA = ref object
    states: seq[DFAState]

proc step(dfa: CommandDFA, currentState: int, currentInput: int, mods: Modifiers): int =
  if currentState < 0 or currentState >= dfa.states.len:
    echo fmt"State {currentState} is out of range 0..{dfa.states.len}"
    return 0

  if currentInput < 0 or currentInput >= INPUT_COUNT:
    echo fmt"Input {currentInput} is out of range 0..{INPUT_COUNT}"
    return 0

  return dfa.states[currentState].inputs[currentInput].next[cast[int](mods)]


proc inputAsString(input: int): string =
  result = case input:
    of INPUT_ENTER: "ENTER"
    of INPUT_ESCAPE: "ESCAPE"
    of INPUT_BACKSPACE: "BACKSPACE"
    of INPUT_SPACE: "SPACE"
    of INPUT_DELETE: "DELETE"
    else: "<UNKNOWN>"

proc dump(dfa: CommandDFA, currentState: int, currentInput: int, currentMods: Modifiers): void =
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

proc buildDFA(commands: seq[(string, string)]): CommandDFA =
  new(result)

  result.states.add DFAState()
  var currentState = 0

  for command in commands:
    echo "Compiling '", command, "'"

    currentState = 0

    let input = command[0]
    let function = command[1]

    type State = enum
      Normal
      Special

    var state = State.Normal
    var mods: Modifiers = {}
    var specialKey = ""

    for i in 0..<input.len:
      echo i, ": ", input[i]

      let code = case input[i]:
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

      echo code, ", ", mods
      if code != 0:
        let modsInt = cast[int](mods)
        let nextState = if result.states[currentState].inputs[code].next[modsInt] != 0:
          result.states[currentState].inputs[code].next[modsInt]
        else:
          result.states.add DFAState()
          result.states.len - 1
        result.states[currentState].inputs[code].next[modsInt] = nextState
        currentState = nextState

    # Mark last state as terminal state.
    result.states[currentState].isTerminal = true
    result.states[currentState].function = function


var commands: seq[(string, string)] = @[]
commands.add ("<ESCAPE>", "exit")
commands.add ("a", "foo")
commands.add ("<A-a>", "AAA")
commands.add ("<C-a><S-b><A-c><CAS-f>f", "you win")
commands.add ("<C-a><S-b>foo", "you loose")
var commandDFA = buildDFA(commands)

commandDFA.dump(0, 0, {})

var currentState = 0
var currentInput = 0
var currentMods: Modifiers

# Event handling
# Return true on app shutdown request, otherwise return false
proc events(): bool =
  result = false
  var e: sdl.Event

  while sdl.pollEvent(addr(e)) != 0:

    # Quit requested
    if e.kind == sdl.Quit:
      return true

    # Key pressed
    elif e.kind == sdl.KeyDown:
      case e.key.keysym.sym:
        of K_LCTRL, K_RCTRL, K_LSHIFT, K_RSHIFT, K_LALT:
          continue
        else:
          discard

      # Show what key was pressed
      sdl.logInfo(sdl.LogCategoryApplication, "Pressed %s %d", $e.key.keysym.sym, int(e.key.keysym.sym))

      currentInput = int(e.key.keysym.sym)
      currentMods = {}

      if bitand(int(e.key.keysym.mods), int(sdl.KMOD_LCTRL)) != 0:
        currentMods = currentMods + {Control}
      if bitand(int(e.key.keysym.mods), int(sdl.KMOD_RCTRL)) != 0:
        currentMods = currentMods + {Control}
      if bitand(int(e.key.keysym.mods), int(sdl.KMOD_LSHIFT)) != 0:
        currentMods = currentMods + {Shift}
      if bitand(int(e.key.keysym.mods), int(sdl.KMOD_RSHIFT)) != 0:
        currentMods = currentMods + {Shift}
      if bitand(int(e.key.keysym.mods), int(sdl.KMOD_LALT)) != 0:
        currentMods = currentMods + {Alt}

      echo currentMods

      currentState = commandDFA.step(currentState, currentInput, currentMods)
      commandDFA.dump(currentState, currentInput, currentMods)

      var close = false
      if commandDFA.states[currentState].isTerminal:
        if commandDFA.states[currentState].function == "exit":
          close = true

        echo "Execute ", commandDFA.states[currentState].function
        echo "-------------------------------------------"
        currentState = 0
        currentMods = {}

      if currentState == 0:
        currentInput = 0
        currentMods = {}

      commandDFA.dump(currentState, currentInput, currentMods)

      # Exit on Escape key press
      if close:
        return true

#var
  #nimdump = execProcess("nim dump")
  # nimlibs = nimdump[nimdump.find("-- end of list --")+18..^2].split
# nimlibs.sort

# echo nimlibs

when false:
  let
    stdlib = "D:/dev/Nim/versions/nim-1.6.0/lib"
    interp = createInterpreter("script.nims", [
      stdlib,
      stdlib/"pure",
      stdlib/"core",
      stdlib/"arch",
      stdlib/"pure"/"unidecode",
      stdlib/"js",
      stdlib/"posix",
      stdlib/"windows",
      stdlib/"wrappers"/"linenoise",
      stdlib/"wrappers",
      stdlib/"impure",
      stdlib/"pure"/"concurrency",
      stdlib/"pure"/"collections",
      stdlib/"deprecated"/"pure",
      stdlib/"deprecated"/"core",
    ])
  interp.evalScript()

  proc getValue[T](interp: Interpreter, name: string): T =
    let sym = interp.selectUniqueSymbol(name)
    let jsonStr = interp.getGlobalValue(sym).getStr()
    return jsonStr.parseJson.jsonTo(T)

  type X = object
    lol: string
    foo: int
    bar: tuple[a: bool, b: char]

  echo interp.getValue[:int]("C")
  echo interp.getValue[:string]("L")
  echo interp.getValue[:bool]("V")
  echo interp.getValue[:X]("x")

  interp.destroyInterpreter()

if true and init(app):

  echo "Press any key..."

  # Main loop
  while not done:
    # Clear screen with draw color
    if app.renderer.renderClear() != 0:
      sdl.logWarn(sdl.LogCategoryVideo,
                  "Can't clear screen: %s",
                  sdl.getError())

    # Update renderer
    app.renderer.renderPresent()

    # Event handling
    done = events()


# Shutdown
exit(app)
