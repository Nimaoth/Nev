discard """
  action: "run"
  cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 60
  targets: "c"
  matrix: ""
"""

import std/[tables, unittest, strformat]
import input

suite "Input DFA":

  proc stepString(dfa: CommandDFA, input: string): string =
    # echo &"stepString: {input}"
    var states: seq[CommandState] = @[]
    for (inputCode, mods, text) in parseInputs(input):
      states = dfa.stepAll(states, inputCode.a, mods)
      # echo &"-> {states.len} states: {states}"

    if states.len != 1:
      check false
      return $states

    let (function, args) = dfa.getAction(states[0])
    if args.len > 0:
      return function & " " & args
    else:
      return function

  test "advanced":
    var commands = initTable[string, Table[string, string]]()
    commands[""] = @[
      ("<?-count>dd", "delete-line <#count>"),
      ("<?-count>cc", "change-line <#count>"),
      ("<?-count>d<move>", "delete-move <move> <#count>"),
      ("<?-count>d<text_object>", "delete-move <text_object> <#count>"),
      ("<?-count>c<move>", "change-move <move> <#count>"),
      ("<move>", "select-last <move>"),
      ("<C-w>", "test"),
      ("aba<move>", "aba"),
      ("aca<move>", "aca"),
      ("ada", "ada"),
    ].toTable

    commands["move"] = @[
      ("<?-count>w", "word <#move.count>"),
      ("<?-count>W", "WORD <#move.count>"),
      ("<?-count>f<CHAR>", "to <move.CHAR> <#move.count>"),
      ("<?-count>t<CHAR>", "before <move.CHAR> <#move.count>"),
    ].toTable

    commands["text_object"] = @[
      ("<?-count>iw", "inside-word <#text_object.count>"),
      ("<?-count>aw", "outside-word <#text_object.count>"),
    ].toTable

    commands["count"] = @[
      ("<-1-9><o-0-9>", ""),
    ].toTable

    var dfa = buildDFA(commands)

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
    var commands = initTable[string, Table[string, string]]()
    commands[""] = @[
      ("a", "a"),
    ].toTable
    var dfa = buildDFA(commands)
    check dfa.stepString("a") == "a"

  test "A : A":
    var commands = initTable[string, Table[string, string]]()
    commands[""] = @[
      ("A", "A"),
    ].toTable
    var dfa = buildDFA(commands)
    check dfa.stepString("A") == "A"

  test "A : <S-a>":
    var commands = initTable[string, Table[string, string]]()
    commands[""] = @[
      ("A", "A"),
    ].toTable
    var dfa = buildDFA(commands)
    check dfa.stepString("<S-a>") == "A"

  test "<S-a> : A":
    var commands = initTable[string, Table[string, string]]()
    commands[""] = @[
      ("<S-a>", "A"),
    ].toTable
    var dfa = buildDFA(commands)
    check dfa.stepString("A") == "A"

  test "shift a : shift a":
    var commands = initTable[string, Table[string, string]]()
    commands[""] = @[
      ("<S-a>", "A"),
    ].toTable
    var dfa = buildDFA(commands)
    check dfa.stepString("<S-a>") == "A"

  test "escape":
    var commands = initTable[string, Table[string, string]]()
    commands[""] = @[
      ("<ESCAPE>", "escape"),
    ].toTable
    var dfa = buildDFA(commands)
    check dfa.stepString("<ESCAPE>") == "escape"

  test "aB<A-c><C-ENTER>":
    var commands = initTable[string, Table[string, string]]()
    commands[""] = @[
      ("aB<A-c><C-ENTER>", "success"),
    ].toTable
    var dfa = buildDFA(commands)
    check dfa.stepString("aB<A-c><C-ENTER>") == "success"

  test "<S-:>":
    var commands = initTable[string, Table[string, string]]()
    commands[""] = @[
      ("<S-:>", "success"),
    ].toTable
    var dfa = buildDFA(commands)
    check dfa.stepString("<S-:>") == "success"
