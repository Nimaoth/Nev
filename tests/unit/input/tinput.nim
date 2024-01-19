discard """
  action: "run"
  cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 60
  targets: "c js"
  matrix: ""
"""

import std/[tables, unittest]
import input

suite "Input DFA":

  proc stepString(dfa: CommandDFA, input: string): string =
    var states = @[CommandState.default]
    for (inputCode, mods, text) in parseInputs(input):
      states = dfa.stepAll(states, inputCode.a, mods)

    if states.len != 1:
      check false
      return $states

    return dfa.getAction(states[0])

  test "advanced":
    var commands = initTable[string, Table[string, string]]()
    commands[""] = @[
      ("<?-COUNT>dd", "delete-line <#COUNT>"),
      ("<?-COUNT>cc", "change-line <#COUNT>"),
      ("<?-COUNT>d<MOVE>", "delete-move <MOVE> <#COUNT>"),
      ("<?-COUNT>c<MOVE>", "change-move <MOVE> <#COUNT>"),
      ("<MOVE>", "select-last <MOVE>"),
      ("<C-w>", "test"),
    ].toTable

    commands["MOVE"] = @[
      ("<?-COUNT>w", "word <#MOVE.COUNT>"),
      ("<?-COUNT>W", "WORD <#MOVE.COUNT>"),
      ("<?-COUNT>f<CHAR>", "to <MOVE.CHAR> <#MOVE.COUNT>"),
    ].toTable

    commands["COUNT"] = @[
      ("<-1-9><o-0-9>", ""),
    ].toTable

    var dfa = buildDFA(commands)
    # dfa.dump(0, 0, {})
    writeFile("dfa.dot", dfa.dumpGraphViz())

    check dfa.stepString("w") == "select-last \"word 0\""
    check dfa.stepString("dw") == "delete-move \"word 0\" 0"
    check dfa.stepString("dW") == "delete-move \"WORD 0\" 0"
    check dfa.stepString("d<S-w>") == "delete-move \"WORD 0\" 0"
    check dfa.stepString("d<S-W>") == "delete-move \"WORD 0\" 0"
    check dfa.stepString("23w") == "select-last \"word 23\""
    check dfa.stepString("d23w") == "delete-move \"word 23\" 0"
    check dfa.stepString("d23fi") == """delete-move "to \"i\" 23" 0"""
    check dfa.stepString("23d45w") == "delete-move \"word 45\" 23"
    check dfa.stepString("234567d4567890w") == "delete-move \"word 4567890\" 234567"
    check dfa.stepString("fI") == """select-last "to \"I\" 0""""
    check dfa.stepString("<C-w>") == "test"

  test "a":
    var commands: seq[(string, string)] = @[]
    commands.add ("a", "a")
    var dfa = buildDFA(commands, @[""])
    let state = dfa.step(CommandState.default, ord('a'), {})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state) == "a"

  test "A : A":
    var commands: seq[(string, string)] = @[]
    commands.add ("A", "A")
    var dfa = buildDFA(commands, @[""])
    let state = dfa.step(CommandState.default, ord('A'), {})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state) == "A"

  test "A : <S-a>":
    var commands: seq[(string, string)] = @[]
    commands.add ("A", "A")
    var dfa = buildDFA(commands, @[""])
    let state = dfa.step(CommandState.default, ord('a'), {Shift})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state) == "A"

  test "<S-a> : A":
    var commands: seq[(string, string)] = @[]
    commands.add ("<S-a>", "A")
    var dfa = buildDFA(commands, @[""])
    let state = dfa.step(CommandState.default, ord('A'), {})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state) == "A"

  test "shift a : shift a":
    var commands: seq[(string, string)] = @[]
    commands.add ("<S-a>", "A")
    var dfa = buildDFA(commands, @[""])
    let state = dfa.step(CommandState.default, ord('a'), {Shift})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state) == "A"

  test "escape":
    var commands: seq[(string, string)] = @[]
    commands.add ("<ESCAPE>", "escape")
    var dfa = buildDFA(commands, @[""])
    let state = dfa.step(CommandState.default, INPUT_ESCAPE, {})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state) == "escape"

  test "aB<A-c><C-ENTER>":
    var commands: seq[(string, string)] = @[]
    commands.add ("aB<A-c><C-ENTER>", "success")
    var dfa = buildDFA(commands, @[""])
    writeFile("dfa2.dot", dfa.dumpGraphViz())

    var state = dfa.step(CommandState.default, ord('a'), {})
    check not dfa.isTerminal(state.current)
    check dfa.getAction(state) == ""

    state = dfa.step(state, ord('B'), {})
    check not dfa.isTerminal(state.current)
    check dfa.getAction(state) == ""

    state = dfa.step(state, ord('c'), {Alt})
    check not dfa.isTerminal(state.current)
    check dfa.getAction(state) == ""

    state = dfa.step(state, INPUT_ENTER, {Control})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state) == "success"