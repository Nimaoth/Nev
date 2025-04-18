discard """
  action: "run"
  cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 60
  targets: "c"
  matrix: ""
"""

import std/[unittest, options, json, sequtils]
import misc/[util, traits]
import text/text_document
import config_provider, scripting_api

suite "Text Document":

  test "create document":
    let document = newTextDocument("", "abc", false)
    check document.isNotNil
    check document.contentString == "abc"

  test "insert text":
    let document = newTextDocument("", "abc", false)
    check document.contentString == "abc"

    let selection = (0, 3).toSelection
    let newSelections = document.insert([selection], [selection], ["def"], false, false)

    check newSelections == [((0, 3), (0, 6))]
    check document.contentString == "abcdef"

  test "delete text":
    let document = newTextDocument("", "abcdef", false)
    check document.contentString == "abcdef"

    let selection = ((0, 2), (0, 5))
    let newSelections = document.delete([selection], [selection], false, false)

    check newSelections == [(0, 2).toSelection]
    check document.contentString == "abf"
