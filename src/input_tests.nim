import std/unittest
import input

# suite "description for this stuff":
#   echo "suite setup: run once before the tests"
  
#   setup:
#     echo "run before each test"
  
#   teardown:
#     echo "run after each test"
  
#   test "essential truths":
#     # give up and stop if this fails
#     require(true)
  
#   test "slightly less obvious stuff":
#     # print a nasty message and move on, skipping
#     # the remainder of this block
#     check(1 == 1)
#     check("asd"[2] == 'd')
  
#   test "out of bounds error is thrown on bad access":
#     let v = @[1, 2, 3]  # you can do initialization here
#     expect(IndexDefect):
#       discard v[4]
  
#   echo "suite teardown: run once after the tests"


suite "Input DFA":
  test "a":
    var commands: seq[(string, string)] = @[]
    commands.add ("a", "a")
    var dfa = buildDFA(commands)
    let state = dfa.step(0, ord('a'), {})
    check dfa.isTerminal(state)
    check dfa.getAction(state) == "a"

  test "A : A":
    var commands: seq[(string, string)] = @[]
    commands.add ("A", "A")
    var dfa = buildDFA(commands)
    let state = dfa.step(0, ord('A'), {})
    check dfa.isTerminal(state)
    check dfa.getAction(state) == "A"

  test "A : <S-a>":
    var commands: seq[(string, string)] = @[]
    commands.add ("A", "A")
    var dfa = buildDFA(commands)
    let state = dfa.step(0, ord('a'), {Shift})
    check dfa.isTerminal(state)
    check dfa.getAction(state) == "A"

  test "<S-a> : A":
    var commands: seq[(string, string)] = @[]
    commands.add ("<S-a>", "A")
    var dfa = buildDFA(commands)
    let state = dfa.step(0, ord('A'), {})
    check dfa.isTerminal(state)
    check dfa.getAction(state) == "A"

  test "shift a : shift a":
    var commands: seq[(string, string)] = @[]
    commands.add ("<S-a>", "A")
    var dfa = buildDFA(commands)
    let state = dfa.step(0, ord('a'), {Shift})
    check dfa.isTerminal(state)
    check dfa.getAction(state) == "A"

  test "escape":
    var commands: seq[(string, string)] = @[]
    commands.add ("<ESCAPE>", "escape")
    var dfa = buildDFA(commands)
    let state = dfa.step(0, INPUT_ESCAPE, {})
    check dfa.isTerminal(state)
    check dfa.getAction(state) == "escape"

  test "aB<A-c><C-ENTER>":
    var commands: seq[(string, string)] = @[]
    commands.add ("aB<A-c><C-ENTER>", "success")
    var dfa = buildDFA(commands)

    var state = dfa.step(0, ord('a'), {})
    check not dfa.isTerminal(state)
    check dfa.getAction(state) == ""

    state = dfa.step(state, ord('B'), {})
    check not dfa.isTerminal(state)
    check dfa.getAction(state) == ""

    state = dfa.step(state, ord('c'), {Alt})
    check not dfa.isTerminal(state)
    check dfa.getAction(state) == ""

    state = dfa.step(state, INPUT_ENTER, {Control})
    check dfa.isTerminal(state)
    check dfa.getAction(state) == "success"