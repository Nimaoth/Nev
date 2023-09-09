discard """
  action: "run"
  cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 60
  targets: "c js vcc"
  matrix: ""
"""

import std/unittest
import input

suite "Input DFA":
  test "a":
    var commands: seq[(string, string)] = @[]
    commands.add ("a", "a")
    var dfa = buildDFA(commands, "")
    let state = dfa.step(CommandState.default, ord('a'), {})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state.current) == "a"

  test "A : A":
    var commands: seq[(string, string)] = @[]
    commands.add ("A", "A")
    var dfa = buildDFA(commands, "")
    let state = dfa.step(CommandState.default, ord('A'), {})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state.current) == "A"

  test "A : <S-a>":
    var commands: seq[(string, string)] = @[]
    commands.add ("A", "A")
    var dfa = buildDFA(commands, "")
    let state = dfa.step(CommandState.default, ord('a'), {Shift})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state.current) == "A"

  test "<S-a> : A":
    var commands: seq[(string, string)] = @[]
    commands.add ("<S-a>", "A")
    var dfa = buildDFA(commands, "")
    let state = dfa.step(CommandState.default, ord('A'), {})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state.current) == "A"

  test "shift a : shift a":
    var commands: seq[(string, string)] = @[]
    commands.add ("<S-a>", "A")
    var dfa = buildDFA(commands, "")
    let state = dfa.step(CommandState.default, ord('a'), {Shift})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state.current) == "A"

  test "escape":
    var commands: seq[(string, string)] = @[]
    commands.add ("<ESCAPE>", "escape")
    var dfa = buildDFA(commands, "")
    let state = dfa.step(CommandState.default, INPUT_ESCAPE, {})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state.current) == "escape"

  test "aB<A-c><C-ENTER>":
    var commands: seq[(string, string)] = @[]
    commands.add ("aB<A-c><C-ENTER>", "success")
    var dfa = buildDFA(commands, "")

    var state = dfa.step(CommandState.default, ord('a'), {})
    check not dfa.isTerminal(state.current)
    check dfa.getAction(state.current) == ""

    state = dfa.step(state, ord('B'), {})
    check not dfa.isTerminal(state.current)
    check dfa.getAction(state.current) == ""

    state = dfa.step(state, ord('c'), {Alt})
    check not dfa.isTerminal(state.current)
    check dfa.getAction(state.current) == ""

    state = dfa.step(state, INPUT_ENTER, {Control})
    check dfa.isTerminal(state.current)
    check dfa.getAction(state.current) == "success"