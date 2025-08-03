import std/[options, strformat, tables]
import misc/[util, custom_logger, custom_async, custom_unicode]
import text/language/[language_server_base]
import document_editor, events
import config_provider, service
import nimsumtree/rope

logCategory "commands"

{.push gcsafe.}
{.push raises: [].}

type
  CommandHandler* = proc(command: Option[string]): Option[string] {.gcsafe.}

  Command* = object
    name*: string
    execute*: proc(args: string): string {.gcsafe.}

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
    commands*: Table[string, Command]

func serviceName*(_: typedesc[CommandService]): string = "CommandService"

addBuiltinService(CommandService)

method init*(self: CommandService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"CommandService.init"
  self.fallbackConfig = ConfigStore.new("CommandService", "settings://CommandService")
  self.shellCommandOutput = Rope.new("")

  return ok()

proc config*(self: CommandService): ConfigStore =
  if self.services.getService(ConfigService).getSome(configs):
    return configs.runtime
  return self.fallbackConfig

proc addCommand*(self: CommandService, command: sink Command, override: bool = false) =
  if command.name == "":
    log lvlError, &"Trying to register command with no name"
    return

  if not override and self.commands.contains(command.name):
    log lvlError, &"Trying to register command '{command.name}' which already exists"
    return

  self.commands[command.name] = command.ensureMove

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
