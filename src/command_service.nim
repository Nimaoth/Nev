import std/[strutils, sequtils, sugar, options, json, streams, strformat, tables,
  deques, sets, algorithm, os]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import misc/[id, util, rect_utils, event, custom_logger, custom_async, custom_unicode, myjsonutils, timer]
import scripting/[expose, scripting_base]
import platform/[platform]
import text/language/[language_server_base]
import document, document_editor, events, input
import dispatch_tables, config_provider, service, platform_service
import language_server_command_line

logCategory "commands"

{.push gcsafe.}
{.push raises: [].}

type
  CommandHandler* = proc(command: Option[string]): bool {.gcsafe.}

  CommandService* = ref object of Service
    events*: EventHandlerService
    platform*: Platform
    config*: ConfigProvider

    commandLineMode*: bool
    commandLineEditor*: DocumentEditor
    languageServerCommandLine*: LanguageServer
    defaultCommandHandler*: CommandHandler
    commandHandler*: CommandHandler

    currentHistoryEntry*: int = 0
    eventHandler*: EventHandler
    commandLineEventHandlerHigh*: EventHandler
    commandLineEventHandlerLow*: EventHandler

func serviceName*(_: typedesc[CommandService]): string = "CommandService"

addBuiltinService(CommandService, PlatformService, EventHandlerService, ConfigService)

method init*(self: CommandService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"CommandService.init"
  self.platform = self.services.getService(PlatformService).get.platform
  self.events = self.services.getService(EventHandlerService).get
  self.config = self.services.getService(ConfigService).get.asConfigProvider
  assert self.platform != nil

  return ok()

proc handleCommand*(self: CommandService, command: string): bool =
  try:
    if self.commandHandler.isNotNil:
      return self.commandHandler(command.some)
    if self.defaultCommandHandler.isNotNil:
      return self.defaultCommandHandler(command.some)
    log lvlError, &"Unhandled command 'command'"
    return false
  except Exception as e:
    log lvlError, &"Failed to run command '{command}'"
    return false

var commandLineImpl*: proc(self: CommandService, initialValue: string) {.gcsafe, raises: [].}
proc openCommandLine*(self: CommandService, initialValue: string = "", handler: CommandHandler = nil) =
  {.gcsafe.}:
    commandLineImpl(self, initialValue)
    self.commandHandler = handler
