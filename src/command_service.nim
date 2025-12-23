import std/[options, strformat, tables, sugar, sequtils, json, streams, strutils, hashes]
import misc/[util, custom_logger, custom_async, custom_unicode, myjsonutils, jsonex, parsejsonex, timer]
import text/language/[language_server_base]
import document_editor, events
import config_provider, service, dispatch_tables, input_api
import nimsumtree/rope, register

logCategory "commands"

{.push gcsafe.}
{.push raises: [].}

type
  CommandHandler* = proc(command: Option[string]): Option[string] {.gcsafe.}

  CommandId* = distinct int

  Command* = object
    id: CommandId
    namespace*: string
    name*: string
    description*: string
    parameters*: seq[tuple[name: string, `type`: string]]
    returnType*: string
    signature*: string
    execute*: proc(args: string): string {.gcsafe, raises: [CatchableError].}

  CommandPermissions* = object
    allowAll*: Option[bool]
    disallowAll*: Option[bool]
    allow*: seq[string]
    disallow*: seq[string]

  CommandService* = ref object of Service
    fallbackConfig: ConfigStore

    commandLineInputMode*: bool
    commandLineResultMode*: bool
    commandLineEditor*: DocumentEditor
    languageServerCommandLine*: LanguageServer
    defaultCommandHandler*: CommandHandler
    commandHandler*: CommandHandler
    registers*: Registers

    currentHistoryEntry*: int = 0
    eventHandler*: EventHandler

    shellCommandOutput*: Rope
    prefix*: string

    scopedCommandHandlers: Table[string, proc(command: string): Option[string] {.gcsafe, raises: [].}]
    prefixCommandHandlers: seq[tuple[prefix: string, execute: proc(command: string): Option[string] {.gcsafe, raises: [].}]]
    commandIdCounter: int = 1
    commands*: Table[string, Command]
    activeCommands*: Table[string, Command]
    idToCommand*: Table[CommandId, string]

    commandsThisFrame: int
    dontRecord*: bool = false

proc all*(_: typedesc[CommandPermissions]) = CommandPermissions(allowAll: some(true), disallowAll: some(true))
proc none*(_: typedesc[CommandPermissions]) = CommandPermissions(allowAll: some(false), disallowAll: some(none))

func serviceName*(_: typedesc[CommandService]): string = "CommandService"

addBuiltinService(CommandService, Registers)

proc registerCommand*(self: CommandService, command: sink Command, override: bool = false): CommandId

proc `==`(a, b: CommandId): bool {.borrow.}
proc hash(a: CommandId): Hash {.borrow.}
proc `$`(a: CommandId): string {.borrow.}

proc toStringResult(node: JsonNode): string =
  if node != nil and node.kind != JNull:
      return $node
  return ""

method init*(self: CommandService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"CommandService.init"
  self.registers = self.services.getService(Registers).get
  self.fallbackConfig = ConfigStore.new("CommandService", "settings://CommandService")
  self.shellCommandOutput = Rope.new("")

  {.gcsafe.}:
    for table in globalDispatchTables.mitems:
      for value in table.functions.values:
        capture value:
          discard self.registerCommand(Command(
            name: value.name,
            parameters: value.params.mapIt((it.name, it.typ)),
            description: value.docs,
            returnType: value.returnType,
            execute: (proc(args: string): string =
              try:
                var argsJson = newJArray()
                try:
                  for a in newStringStream(args).parseJsonFragments():
                    argsJson.add a
                except CatchableError as e:
                  log(lvlError, fmt"Failed to parse arguments '{args}': {e.msg}")

                return value.dispatch(argsJson).toStringResult()
              except CatchableError as e:
                log lvlError, &"Failed to execute command '{value.name}': {e.msg}"
                return ""
            )
          ))

  return ok()

method tick*(self: CommandService) =
  self.commandsThisFrame = 0

proc config*(self: CommandService): ConfigStore =
  if self.services.getService(ConfigService).getSome(configs):
    return configs.runtime
  return self.fallbackConfig

proc unregisterCommand*(self: CommandService, command: string) =
  if self.commands.contains(command):
    let id = self.commands[command].id
    self.commands.del(command)
    self.idToCommand.del(id)

proc unregisterCommand*(self: CommandService, id: CommandId) =
  if self.idToCommand.contains(id):
    let name = self.idToCommand[id]
    self.idToCommand.del(id)

    if self.commands[name].id != id:
      # Command was reassigned, don't delete the new command.
      return
    self.commands.del(name)

proc registerActiveCommand*(self: CommandService, command: sink Command, override: bool = false): CommandId =
  if command.name == "":
    log lvlError, &"Trying to register command with no name"
    return

  if not override and self.activeCommands.contains(command.name):
    log lvlError, &"Trying to register command '{command.name}' which already exists"
    return

  let id = self.commandIdCounter.CommandId
  inc self.commandIdCounter

  self.unregisterCommand(command.name)

  command.id = id
  command.signature = "(" & command.parameters.mapIt(it.name & ": " & it.`type`).join(", ") & ") " & command.returnType
  self.idToCommand[id] = command.name
  self.activeCommands[command.name] = command.ensureMove

  return id

proc registerCommand*(self: CommandService, command: sink Command, override: bool = false): CommandId =
  if command.name == "":
    log lvlError, &"Trying to register command with no name"
    return

  if not override and self.commands.contains(command.name):
    log lvlError, &"Trying to register command '{command.name}' which already exists"
    return

  let id = self.commandIdCounter.CommandId
  inc self.commandIdCounter

  self.unregisterCommand(command.name)

  command.id = id
  command.signature = "(" & command.parameters.mapIt(it.name & ": " & it.`type`).join(", ") & ") " & command.returnType
  self.idToCommand[id] = command.name
  self.commands[command.name] = command.ensureMove

  return id

proc addPrefixCommandHandler*(self: CommandService, prefix: string, handler: proc(command: string): Option[string] {.gcsafe, raises: [].}) =
  self.prefixCommandHandlers.add((prefix, handler))

proc addScopedCommandHandler*(self: CommandService, prefix: string, handler: proc(command: string): Option[string] {.gcsafe, raises: [].}) =
  self.scopedCommandHandlers[prefix] = handler

proc executeCommand*(self: CommandService, command: string, record: bool = true): Option[string]

iterator parseJsonFragmentsAndSubstituteArgs*(s: Stream, args: seq[JsonNodeEx], index: var int): JsonNodeEx =
  var p: JsonexParser
  try:
    p.open(s, "")
    discard getTok(p) # read first token
    while p.tok != tkEof:
      if p.tok == tkError and p.buf[p.bufpos - 1] == '@':
        if p.bufpos < p.buf.len and p.buf[p.bufpos] == '@':
          inc p.bufpos
          for arg in args:
            yield arg

        else:
          var numStr = ""
          while p.buf[p.bufpos] in {'0'..'9'}:
            numStr.add p.buf[p.bufpos]
            inc p.bufpos

          if numStr == "":
            while index < args.len:
              yield args[index]
              inc index

          else:
            index = parseInt(numStr)
            if index < args.len:
              yield args[index]
              inc index

        discard getTok(p) # read next token
      else:
        yield p.parseJsonex(false, false)
  except:
    discard
  finally:
    try:
      p.close()
    except:
      discard

proc handleAlias(self: CommandService, action: string, arg: string, alias: JsonNode): Option[string] =
  var args = newSeq[JsonNodeEx]()
  try:
    for a in newStringStream(arg).parseJsonexFragments():
      args.add a

  except CatchableError:
    log(lvlError, fmt"Failed to parse arguments '{arg}': {getCurrentExceptionMsg()}")

  if alias.kind == JString:
    let (action, arg) = alias.getStr.parseAction
    var aliasArgs = newJexArray()
    try:
      var argIndex = 0
      for a in newStringStream(arg).parseJsonFragmentsAndSubstituteArgs(args, argIndex):
        aliasArgs.add a

    except:
      log(lvlError, fmt"Failed to parse arguments '{arg}': {getCurrentExceptionMsg()}")

    return self.executeCommand(action & " " & aliasArgs.mapIt($it).join(" "), record=false)

  elif alias.kind == JArray:
    var argIndex = 0
    for command in alias:
      if command.kind == JString:
        let (action, arg) = command.getStr.parseAction
        var aliasArgs = newJexArray()
        try:
          for a in newStringStream(arg).parseJsonFragmentsAndSubstituteArgs(args, argIndex):
            aliasArgs.add a

        except:
          log(lvlError, fmt"Failed to parse arguments '{arg}': {getCurrentExceptionMsg()}")
        result = self.executeCommand(action & " " & aliasArgs.mapIt($it).join(" "), record=false)

    return

  else:
    log lvlError, &"Failed to run alias '{action}': invalid configuration. Expected string | string[], got '{alias}'"
    return string.none

proc executeCommand*(self: CommandService, command: string, record: bool = true): Option[string] =
  var doRecord = record
  if self.dontRecord:
    doRecord = false

  let oldDontRecord = self.dontRecord
  if record:
    self.dontRecord = true
  defer:
    if record:
      self.dontRecord = oldDontRecord

  let t = startTimer()
  if not self.registers.bIsReplayingCommands:
    log lvlInfo, &"[executeCommand] '{command}'"
  defer:
    if not self.registers.bIsReplayingCommands:
      let elapsed = t.elapsed
      log lvlInfo, &"[executeCommand] '{command}' took {elapsed.ms} ms -> {result}"

  if not self.registers.bIsReplayingCommands and doRecord:
    self.registers.recordCommand(command)

  if self.commandsThisFrame > self.config.get("max-commands-per-frame", 1000):
    log lvlError, &""
    return string.none

  self.commandsThisFrame.inc()
  for handler in self.prefixCommandHandlers:
    if command.startsWith(handler.prefix):
      return handler.execute(command)

  let i = command.find('.')
  let (prefix, rawCommand) = if i <= 0:
    ("", command)
  else:
    (command[0..<i], command[(i + 1)..^1])

  if prefix in self.scopedCommandHandlers:
    let handler = self.scopedCommandHandlers[prefix]
    return handler(rawCommand)

  var (action, arg) = command.parseAction
  if arg.startsWith("\\"):
    arg = $newJString(arg[1..^1])

  let alias = self.config.get("alias." & action, newJNull())
  if alias != nil and alias.kind != JNull:
    return self.handleAlias(action, arg, alias)

  if self.commands.contains(action):
    try:
      return self.commands[action].execute(arg).some
    except Exception as e:
      log lvlError, &"Failed to run command '{command}': {e.msg}"
      return string.none

  try:
    if self.defaultCommandHandler.isNotNil:
      return self.defaultCommandHandler(command.some)
  except Exception as e:
    log lvlError, &"Failed to run command '{command}': {e.msg}"
    return string.none

  return string.none

proc checkPermissions*(self: CommandService, command: string, permissions: CommandPermissions): bool =
  if permissions.disallowAll.get(false) or command in permissions.disallow:
    return false
  if permissions.allowAll.get(false) or command in permissions.allow:
    return true
  return false

proc handleCommand*(self: CommandService, command: string): Option[string] =
  try:
    if self.commandHandler.isNotNil:
      return self.commandHandler(command.some)
    return self.executeCommand(command)
  except Exception as e:
    log lvlError, &"Failed to run command '{command}': {e.msg}"
    return string.none

# todo: add prefix parameter
var commandLineImpl*: proc(self: CommandService, initialValue: string, prefix: string) {.gcsafe, raises: [].}
proc openCommandLine*(self: CommandService, initialValue: string = "", prefix: string = "", handler: CommandHandler = nil) =
  {.gcsafe.}:
    commandLineImpl(self, initialValue, prefix)
    self.commandHandler = handler

proc commandLineMode*(self: CommandService): bool = self.commandLineInputMode or self.commandLineResultMode

proc parseCommand*(json: JsonNodeEx): tuple[command: string, args: string, ok: bool] {.raises: [ValueError].} =
  if json.kind == JString:
    let commandStr = json.getStr
    let spaceIndex = commandStr.find(" ")

    if spaceIndex == -1:
      return (commandStr, "", true)
    else:
      return (commandStr[0..<spaceIndex], commandStr[spaceIndex+1..^1], true)

  elif json.kind == JArray:
    if json.elems.len > 0:
      let name = json[0].getStr
      let args = json.elems[1..^1].mapIt($it).join(" ")
      return (name, args, true)
    else:
      raise newException(ValueError, "Missing command name, got empty array")

  elif json.kind == JLispVal:
    return ($json.lval, "", true)

  else:
    return ("", "", false)
