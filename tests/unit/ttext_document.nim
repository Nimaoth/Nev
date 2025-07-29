discard """
  action: "run"
  cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 60
  targets: "c"
  matrix: ""
"""

import std/[unittest, options, json, sequtils]
import misc/[util, traits, custom_logger]
import text/text_document
import config_provider, scripting_api, service
import platform/platform, platform_service

defineSetAllDefaultSettings()

type
  NilPlatform* = ref object of Platform

gServices = Services()
gServices.addBuiltinServices()
gServices.getService(PlatformService).get.setPlatform(NilPlatform())
gServices.waitForServices()

suite "Text Document":

  test "create document":
    let document = newTextDocument(gServices, "", "abc")
    check document.isNotNil
    check document.contentString == "abc"

  test "insert text":
    let document = newTextDocument(gServices, "", "abc")
    check document.contentString == "abc"

    let selection = (0, 3).toSelection
    let newSelections = document.edit([selection], [selection], ["def"])

    check newSelections == [((0, 3), (0, 6))]
    check document.contentString == "abcdef"

  test "delete text":
    let document = newTextDocument(gServices, "", "abcdef")
    check document.contentString == "abcdef"

    let selection = ((0, 2), (0, 5))
    let newSelections = document.edit([selection], [selection], [""])

    check newSelections == [(0, 2).toSelection]
    check document.contentString == "abf"
