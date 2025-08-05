import std/[options, strformat, tables, sugar, sequtils, json, streams, strutils, hashes]
import misc/[util, custom_logger, custom_async, custom_unicode, myjsonutils]
import text/language/[language_server_base]
import document_editor, events
import config_provider, service, dispatch_tables
import nimsumtree/rope

logCategory "commands"

{.push gcsafe.}
{.push raises: [].}

type
  CommandHandler* = proc(command: Option[string]): Option[string] {.gcsafe.}

  CommandId* = distinct int

  Command* = object
    id: CommandId
    name*: string
    description*: string
    parameters*: seq[tuple[name: string, `type`: string]]
    returnType*: string
    signature*: string
    execute*: proc(args: string): string {.gcsafe.}

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

    currentHistoryEntry*: int = 0
    eventHandler*: EventHandler

    shellCommandOutput*: Rope
    prefix*: string

    scopedCommandHandlers: Table[string, proc(command: string): Option[string] {.gcsafe, raises: [].}]
    prefixCommandHandlers: seq[tuple[prefix: string, execute: proc(command: string): Option[string] {.gcsafe, raises: [].}]]
    commandIdCounter: int = 1
    commands*: Table[string, Command]
    idToCommand*: Table[CommandId, string]

proc all*(_: typedesc[CommandPermissions]) = CommandPermissions(allowAll: some(true), disallowAll: some(true))
proc none*(_: typedesc[CommandPermissions]) = CommandPermissions(allowAll: some(false), disallowAll: some(none))

func serviceName*(_: typedesc[CommandService]): string = "CommandService"

addBuiltinService(CommandService)

proc registerCommand*(self: CommandService, command: sink Command, override: bool = false): CommandId

proc `==`(a, b: CommandId): bool {.borrow.}
proc hash(a: CommandId): Hash {.borrow.}
proc `$`(a: CommandId): string {.borrow.}

method init*(self: CommandService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"CommandService.init"
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

                let resJson = value.dispatch(argsJson)
                return $resJson
              except CatchableError as e:
                log lvlError, &"Failed to execute command '{value.name}': {e.msg}"
                return ""
            )
          ))

  return ok()

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
    self.commands.del(self.idToCommand[id])
    self.idToCommand.del(id)

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
  self.scopedCommandHandlers[prefix] = handler

proc addScopedCommandHandler*(self: CommandService, prefix: string, handler: proc(command: string): Option[string] {.gcsafe, raises: [].}) =
  self.prefixCommandHandlers.add((prefix, handler))

proc executeCommand*(self: CommandService, command: string): Option[string] =
  for handler in self.prefixCommandHandlers:
    if command.startsWith(handler.prefix):
      return handler.execute(command[handler.prefix.len..^1])

  let i = command.find('.')
  let (prefix, command) = if i <= 0:
    ("", command)
  else:
    (command[0..<i], command[(i + 1)..^1])

  if prefix in self.scopedCommandHandlers:
    let handler = self.scopedCommandHandlers[prefix]
    return handler(command)

  return string.none

proc checkPermissions*(self: CommandService, command: string, permissions: CommandPermissions): bool =
  if permissions.disallowAll.get(true) or command in permissions.disallow:
    return false
  if not permissions.allowAll.get(false) and command notin permissions.allow:
    return false
  return true

proc handleCommand*(self: CommandService, command: string): Option[string] =
  try:
    if self.commandHandler.isNotNil:
      return self.commandHandler(command.some)
    if self.defaultCommandHandler.isNotNil:
      return self.defaultCommandHandler(command.some)
    log lvlError, &"Unhandled command 'command'"
    return string.none
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
