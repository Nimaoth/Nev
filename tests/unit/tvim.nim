discard """
  action: "run"
  cmd: "nim $target $options -d:exposeScriptingApi=true $file"
  timeout: 500
  targets: "c"
  matrix: ""
"""

import std/[unittest, options, json, sequtils, tables, strutils]
import misc/[util, custom_logger, jsonex]
import config_provider, service, document, document_editor, text_component, text_editor_component
import text/[text, text_editor, text_document]
import platform/platform, platform_service, events, input_api, command_service, layout/layout, input
import vim, register
import scripting_api except TextDocumentEditor

defineSetAllDefaultSettings()

type
  NilPlatform* = ref object of Platform

logger().enableConsoleLogger()

gServices = Services()
gServices.addBuiltinServices()
gServices.getService(PlatformService).get.setPlatform(NilPlatform())

init_module_register()
init_module_command_service()
init_module_layout()
init_module_text()
init_module_vim()

gServices.waitForServices()

getServiceChecked(CommandService).logCommands = true
let eventService = getServiceChecked(EventHandlerService)

proc removeCommandScript(context: string, keys: string) =
  let context = if context.endsWith("."):
    context[0..^2]
  else:
    context

  let (baseContext, subContext) = if (let i = context.find('#'); i != -1):
    (context[0..<i], context[i+1..^1])
  else:
    (context, "")

  let config = eventService.getEventHandlerConfig(baseContext)
  eventService.commandDescriptions.del(baseContext & subContext & keys)
  config.removeCommandDescription(keys)
  config.removeCommand(subContext, keys)
  eventService.invalidateCommandToKeysMap()

proc addCommandScript*(context: string, keys: string, action: string, arg: string = "", description: string = "", source: tuple[filename: string, line: int, column: int] = ("", 0, 0)) =
  let command = if arg.len == 0: action else: action & " " & arg

  let context = if context.endsWith("."):
    context[0..^2]
  else:
    context

  let (baseContext, subContext) = if (let i = context.find('#'); i != -1):
    (context[0..<i], context[i+1..^1])
  else:
    (context, "")

  if description.len > 0:
    eventService.commandDescriptions[baseContext & subContext & keys] = description
    eventService.getEventHandlerConfig(baseContext).addCommandDescription(keys, description)

  var source = source

  eventService.getEventHandlerConfig(baseContext).addCommand(subContext, keys, command, source)
  eventService.invalidateCommandToKeysMap()

proc loadKeybindingsFromJson*(json: JsonNodeEx, filename: string) =
  try:
    for (context, commands) in json.fields.pairs:
      let loc = (line: commands.loc.line.int, column: commands.loc.column.int + 1)
      try:
        if (context.startsWith("<set-") or context.startsWith("<add-")) and context.endsWith(">"):
          let name = context[5..^2]
          var keys = newSeq[string]()
          let addLeaders = context.startsWith("<add-")

          if commands.kind == JString:
            keys = @[commands.getStr]
          elif commands.kind == JArray:
            keys = commands.jsonTo(seq[string]).catch:
              echo &"Invalid value for '{context}': {commands}. Expected string | string[]"
              assert false
              continue

          if addLeaders:
            eventService.addKeyDefinitions(name, keys)
          else:
            eventService.setKeyDefinitions(name, keys)
          continue

        elif context.startsWith("-"):
          # e.g. "-vim.base": {...} -> remove commands in this context
          if commands.kind != JArray:
            echo &"Value has to be array for '{context}'"
            assert false
            continue

          let actualContext = context[1..^1]
          for keys in commands.elems:
            if keys.kind == JString:
              removeCommandScript(actualContext, keys.getStr)
            else:
              echo &"Value has to be string in '{context}', but is {keys}"
              assert false
          continue
      except CatchableError:
        echo &"Invalid key definition in '{filename}:{loc.line}{loc.column}': {getCurrentExceptionMsg()}"
        assert false

      if commands.kind != JObject:
        echo &"Invalid value for '{context}' in '{filename}', expected object, got {commands}"
        assert false
        continue

      for (keys, command) in commands.fields.pairs:
        let loc = (filename: filename, line: command.loc.line.int, column: command.loc.column.int + 1)
        try:
          if command.kind == JObject:
            if command.hasKey("command"):
              let cmd = command["command"]
              var (name, args, ok) = cmd.parseCommand()
              if not ok:
                echo &"Invalid command in keybinding settings '{filename}:{loc.line}:{loc.column}': {cmd}"
                assert false
              else:
                let description = command.fields.getOrDefault("description", newJexString("")).getStr
                addCommandScript(context, keys, name, args, description, source = loc)
            else:
              let description = command.fields.getOrDefault("description", newJexString("")).getStr
              eventService.addCommandDescription(context, keys, description)

          else:
            let (name, args, ok) = command.parseCommand()
            if not ok:
              echo &"Invalid command in keybinding settings '{filename}:{loc.line}:{loc.column}': {command}"
              assert false
            else:
              addCommandScript(context, keys, name, args, source = loc)

        except CatchableError:
          echo &"Invalid command in '{filename}:{loc.line}{loc.column}': {getCurrentExceptionMsg()}"
          assert false

  except CatchableError:
    echo &"Failed to load keybindings from json: {getCurrentExceptionMsg()}\n{json.pretty}"
    assert false

let baseStore = ConfigStore.new("settings", "settings", settings = readFile("config/settings.json").parseJsonex())
let vimStore = ConfigStore.new("settings-vim", "settings-vim", settings = readFile("config/settings-vim.json").parseJsonex())
getServiceChecked(ConfigService).storeGroups["test"] = @[baseStore, vimStore]
getServiceChecked(ConfigService).groups = @["test"]
getServiceChecked(ConfigService).reconnectGroups()


# let keybindingsFile = readFile("../../config/keybindings.json")
let keybindingsFile = readFile("config/keybindings.json")
let keybindingsJson = keybindingsFile.parseJsonex()
loadKeybindingsFromJson(keybindingsJson, "")

proc parseTextAndSelections(templ: string): tuple[text: string, selections: seq[Selection]] =
  var s: Selection = ((0, 0), (0, 0))
  var inSelection = false
  var current: Cursor = (0, 0)
  for c in templ:
    case c
    of '\n':
      result.text.add c
      current.line += 1
      current.column = 0
    of '$':
      result.selections.add current.toSelection
      inSelection = false
    of '[':
      if inSelection:
        s.last = (current.line, current.column + 1)
        result.selections.add s
        inSelection = false
      else:
        s.first = current
        inSelection = true
    of ']':
      s.last = current
      result.selections.add s
      inSelection = false
    else:
      result.text.add c
      current.column += 1

proc testInput(keys, oldText, newText: string) =
  let (oldText, oldSel) = parseTextAndSelections oldText
  let (newText, newSel) = parseTextAndSelections newText
  let document = newTextDocument(gServices, "", oldText)
  let editor = getServiceChecked(LayoutService).createAndAddView(document).get
  editor.TextDocumentEditor.selections = oldSel
  var delayed: seq[tuple[handle: EventHandler, input: int64, modifiers: Modifiers]] = @[]
  for (inputs, mods, text) in parseInputs(keys):
    let handlers = editor.getEventHandlers(initTable[string, EventHandler]())
    discard handlers.handleEvent(inputs.a, mods, delayed, debug = true)
  let newTextActual = document.contentString()
  let newSelActual = editor.TextDocumentEditor.selections
  check newTextActual == newText
  check newSelActual == newSel

suite "Document with components":

  test "create document":
    let document = newTextDocument(gServices, "", "abc")
    let editor = newTextEditor(document, gServices, newJexObject())

  test "parse":
    let (text, s) = parseTextAndSelections """[]abc
d[e]f
g[h[i
$jkl"""

    check text == """abc
def
ghi
jkl"""

    check s == @[(0, 0).toSelection, ((1, 1), (1, 2)), ((2, 1), (2, 3)), ((3, 0), (3, 0))]

  var keysCounter = initTable[string, int]()

  let cases = readFile("tests/unit/tvim.txt").split("---")
  for c in cases:
    let parts = c.split("-")
    if parts.len != 3:
      continue

    let keys = parts[0].strip()
    let old = parts[1].strip()
    let new = parts[2].strip()
    let counter = keysCounter.mgetOrPut(keys, 1).addr
    let name = $(counter[]) & ": " & keys
    inc counter[]
    test name:
      testInput(keys, old, new)
