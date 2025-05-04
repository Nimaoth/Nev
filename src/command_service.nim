import std/[options, strformat]
import misc/[util, custom_logger, custom_async, custom_unicode]
import platform/[platform]
import text/language/[language_server_base]
import document_editor, events
import config_provider, service, platform_service, vfs_service, vfs
import nimsumtree/rope

logCategory "commands"

{.push gcsafe.}
{.push raises: [].}

type
  CommandHandler* = proc(command: Option[string]): Option[string] {.gcsafe.}

  CommandService* = ref object of Service
    events*: EventHandlerService
    platform*: Platform
    config*: ConfigStore
    vfs*: VFS

    commandLineInputMode*: bool
    commandLineResultMode*: bool
    commandLineEditor*: DocumentEditor
    languageServerCommandLine*: LanguageServer
    defaultCommandHandler*: CommandHandler
    commandHandler*: CommandHandler

    currentHistoryEntry*: int = 0
    eventHandler*: EventHandler
    commandLineEventHandlerHigh*: EventHandler
    commandLineEventHandlerLow*: EventHandler
    commandLineResultEventHandlerHigh*: EventHandler
    commandLineResultEventHandlerLow*: EventHandler

    shellCommandOutput*: Rope
    prefix*: string

func serviceName*(_: typedesc[CommandService]): string = "CommandService"

addBuiltinService(CommandService, PlatformService, EventHandlerService, ConfigService, DocumentEditorService, VFSService)

method init*(self: CommandService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"CommandService.init"
  self.platform = self.services.getService(PlatformService).get.platform
  self.events = self.services.getService(EventHandlerService).get
  self.config = self.services.getService(ConfigService).get.runtime
  self.vfs = self.services.getService(VFSService).get.vfs
  assert self.platform != nil

  self.shellCommandOutput = Rope.new("")
  asyncSpawn self.vfs.write("ed://.shell-command-results", "")

  return ok()

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
