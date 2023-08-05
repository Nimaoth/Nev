discard """
  action: "run"
  cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 60
  targets: "c js"
  matrix: ""
"""

import std/[unittest, options, json, sequtils]
import util, traits, text/text_document, config_provider, scripting_api

type MockConfigProvider = ref object

implTrait ConfigProvider, MockConfigProvider:
  proc getConfigValue(self: MockConfigProvider, path: string): Option[JsonNode] = discard
  proc setConfigValue(self: MockConfigProvider, path: string, value: JsonNode) = discard

var mockConfigProvider = MockConfigProvider()

suite "Text Document":

  test "create document":
    let document = newTextDocument(mockConfigProvider.asConfigProvider, "", "abc", false)
    check document.isNotNil
    check document.contentString == "abc"

  test "insert text":
    let document = newTextDocument(mockConfigProvider.asConfigProvider, "", "abc", false)
    check document.contentString == "abc"

    let selection = (0, 3).toSelection
    let newSelections = document.insert([selection], [selection], ["def"], false, false)

    check newSelections == [(0, 6).toSelection]
    check document.contentString == "abcdef"

  test "delete text":
    let document = newTextDocument(mockConfigProvider.asConfigProvider, "", "abcdef", false)
    check document.contentString == "abcdef"

    let selection = ((0, 2), (0, 5))
    let newSelections = document.delete([selection], [selection], false, false)

    check newSelections == [(0, 2).toSelection]
    check document.contentString == "ab"