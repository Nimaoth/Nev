#use command_service layout text_editor_component register command_component decoration_component decoration_component event_service session language_server_component
import std/[options, strutils, sequtils, strformat, json, streams]
import misc/[jsonex, myjsonutils]
import service, lisp, document_editor, log, command_service

const currentSourcePath2 = currentSourcePath()
include module_base

logCategory "command-line"

type
  CommandLineService* = ref object of DynamicService
    logCommands*: bool = false
    dontRecord*: bool = false
    commandLineInputMode*: bool
    commandLineResultMode*: bool

func serviceName*(_: typedesc[CommandLineService]): string = "CommandLineService"

# DLL API
{.push modrtl, gcsafe, raises: [].}
proc commandServiceCommandLineMode(self: CommandLineService): bool
proc commandServiceCommandLineEditor(self: CommandLineService): DocumentEditor
proc commandServiceOpenCommandLine(self: CommandLineService, initialValue: string = "", prefix: string = "", handler: CommandHandler = nil)
proc commandServiceHandleCommand(self: CommandLineService, command: string): Option[string]
proc commandLineReplayCommands(self: CommandLineService, register: string)
proc commandLineExitCommandLine(self: CommandLineService)
{.pop.}

# Nice wrappers
proc commandLineMode*(self: CommandLineService): bool {.inline.} = commandServiceCommandLineMode(self)
proc commandLineEditor*(self: CommandLineService): DocumentEditor {.inline.} = commandServiceCommandLineEditor(self)
proc openCommandLine*(self: CommandLineService, initialValue: string = "", prefix: string = "", handler: CommandHandler = nil) {.inline.} = commandServiceOpenCommandLine(self, initialValue, prefix, handler)
proc handleCommand*(self: CommandLineService, command: string): Option[string] {.inline.} = commandServiceHandleCommand(self, command)

# Implementation
when implModule:
  import std/[strformat, tables, sugar, json, streams, hashes]
  import misc/[util, custom_async, custom_unicode, myjsonutils, parsejsonex, timer, rope_utils, async_process, delayed_task, jsonex]
  import nimsumtree/[rope, sumtree]
  import scripting/[expose]
  import platform/[platform], platform_service
  import layout/layout
  import text/language/[language_server_base]
  import text/[display_map, overlay_map]
  import config_provider, dispatch_tables, input_api, events
  import decoration_component, document, vfs_service, vfs, register
  import language_server_command_line, command_component, text_editor_component, text_component, document_editor
  import scripting_api, event_service

  {.push gcsafe.}
  {.push raises: [].}

  type
    CommandLineServiceImpl* = ref object of CommandLineService
      mCommands: CommandService
      mRegisters*: Registers
      commandHandler*: command_service.CommandHandler
      mCommandLineEditor*: DocumentEditor
      mLanguageServerCommandLine: LanguageServer

      currentHistoryEntry*: int = 0
      eventHandler*: EventHandler

      shellCommandOutput*: Rope
      prefix*: string
      prefixOverlayId*: Option[int]

  func serviceName*(_: typedesc[CommandLineServiceImpl]): string = "CommandLineService"

  proc commandLine(self: CommandLineService, initialValue: string = "", prefix: string = "")

  proc requestRender(self: CommandLineService) =
    if self.services.getService(PlatformService).getSome(platform):
      platform.platform.requestRender()

  proc newCommandLineService(): CommandLineServiceImpl =
    let self = CommandLineServiceImpl()
    let eventService = getServiceChecked(EventService)
    eventService.listen(newId(), "app/initialized"):
      proc(event, payload: string) =
        log lvlInfo, "Create command line text editor"
        let editors = getServiceChecked(DocumentEditorService)
        let commandLineDocument = editors.createDocument("text", "ed://.command-line", load = false, %%*{
          "language": "command-line",
        })
        assert commandLineDocument != nil
        self.mCommandLineEditor = editors.createEditorForDocument(commandLineDocument, %%*{
          "usage": "command-line",
          "settings": {
            "text.disable-completions": true,
            "ui.line-numbers": "none",
            "ui.whitespace-char": " ",
            "text.cursor-margin": 0,
            "text.disable-scrolling": true,
            "text.default-mode": "vim.insert",
            "text.highlight-matches.enable": false,
          },
        }).get(nil)
        self.mCommandLineEditor.renderHeader = false
        discard self.mCommandLineEditor.onMarkedDirty.subscribe () => self.requestRender()
        editors.commandLineEditor = self.mCommandLineEditor
        getServiceChecked(LayoutService).commandLineEditor = self.mCommandLineEditor

    return self

  proc languageServerCommandLine*(self: CommandLineServiceImpl): LanguageServer =
    if self.mLanguageServerCommandLine == nil:
      self.mLanguageServerCommandLine = getService(LanguageServerCommandLineService).mapIt(it.languageServer).get(nil)
    return self.mLanguageServerCommandLine

  proc commands(self: CommandLineServiceImpl): CommandService =
    if self.mCommands == nil:
      self.mCommands = getService(CommandService).get
    return self.mCommands

  proc registers(self: CommandLineServiceImpl): Registers =
    if self.mRegisters == nil:
      self.mRegisters = getService(Registers).get(nil)
    return self.mRegisters

  proc config(self: CommandLineServiceImpl): ConfigStore =
    return getService(ConfigService).get.runtime

  proc commandServiceHandleCommand(self: CommandLineService, command: string): Option[string] =
    let self = self.CommandLineServiceImpl
    try:
      if self.commandHandler.isNotNil:
        return self.commandHandler(command.some)
      return self.commands.executeCommand(command)
    except Exception as e:
      log lvlError, &"Failed to run command '{command}': {e.msg}"
      return string.none

  proc commandServiceCommandLineMode(self: CommandLineService): bool =
    let self = self.CommandLineServiceImpl
    self.commandLineInputMode or self.commandLineResultMode

  proc commandServiceCommandLineEditor(self: CommandLineService): DocumentEditor =
    let self = self.CommandLineServiceImpl
    self.mCommandLineEditor

  proc commandServiceOpenCommandLine(self: CommandLineService, initialValue: string = "", prefix: string = "", handler: command_service.CommandHandler = nil) =
    {.gcsafe.}:
      let self = self.CommandLineServiceImpl
      let editor = self.commandLineEditor
      if editor.currentDocument.getTextComponent().getSome(text):
        text.content = initialValue
      if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len == 0:
        self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.add ""
      self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[0] = ""
      self.currentHistoryEntry = 0
      self.commandLineInputMode = true
      self.commandLineResultMode = false
      editor.active = true
      self.commandHandler = nil
      self.prefix = prefix
      editor.config.set("text.disable-completions", false)
      editor.config.set("text.disable-scrolling", true)
      editor.config.set("ui.line-numbers", "none")
      editor.currentDocument.setReadOnly(false)
      if self.prefixOverlayId.isSome:
        if editor.getDecorationComponent().getSome(decos):
          decos.clearOverlays(self.prefixOverlayId.get)
      editor.getCommandComponent().get.executeCommand("set-default-mode true")
      if self.prefix != "":
        if editor.getDecorationComponent().getSome(decos):
          if self.prefixOverlayId.isNone:
            self.prefixOverlayId = decos.allocateOverlayId()
          if self.prefixOverlayId.isSome:
            decos.addOverlay(point(0, 0)...point(0, 0), self.prefix, self.prefixOverlayId.get, scope = "comment", bias = Bias.Left)
      if self.services.getService(EventHandlerService).getSome(events):
        events.rebuildCommandToKeysMap()
      self.requestRender()
      self.commandHandler = handler

  proc getCommandLineService(): Option[CommandLineService] =
    {.gcsafe.}:
      if getServices().isNil: return CommandLineService.none
      return getServices().getService(CommandLineService)

  static:
    addInjector(CommandLineService, getCommandLineService)

  proc commandLine(self: CommandLineService, initialValue: string = "", prefix: string = "") {.expose("commands").} =
    self.commandServiceOpenCommandLine(initialValue, prefix)

  proc commandLineExitCommandLine(self: CommandLineService) =
    let self = self.CommandLineServiceImpl
    let editor = self.commandLineEditor
    if editor.currentDocument.getTextComponent().getSome(text):
      text.content = ""
    if self.prefixOverlayId.isSome and editor.getDecorationComponent().getSome(decos):
      decos.clearOverlays(self.prefixOverlayId.get)
      decos.releaseOverlayId(self.prefixOverlayId.get)
      self.prefixOverlayId = int.none
    editor.getCommandComponent().get.executeCommand("hide-completions")
    editor.config.set("text.disable-scrolling", true)
    editor.config.set("ui.line-numbers", "none")
    editor.currentDocument.setReadOnly(false)
    self.commandLineInputMode = false
    self.commandLineResultMode = false
    editor.active = false
    try:
      if self.commandHandler.isNotNil:
        discard self.commandHandler(string.none)
      elif self.commands.defaultCommandHandler.isNotNil:
        discard self.commands.defaultCommandHandler(string.none)
    except Exception as e:
      log lvlError, &"exitCommandLine: {e.msg}"
    self.commandHandler = nil
    self.requestRender()

  proc exitCommandLine*(self: CommandLineService) {.expose("commands").} =
    commandLineExitCommandLine(self)

  proc commandLineResult*(self: CommandLineService, value: string, showInCommandLine: bool = false,
      appendAndShowInFile: bool = false, filename: string = "ed://.shell-command-results") {.expose("commands").} =
    let self = self.CommandLineServiceImpl
    let editor = self.commandLineEditor
    if showInCommandLine:
      if editor.currentDocument.getTextComponent().getSome(text):
        text.content = value
      if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len == 0:
        self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.add ""
      self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[0] = ""
      self.currentHistoryEntry = 0
      self.commandLineInputMode = false
      self.commandLineResultMode = true
      editor.active = true
      self.commandHandler = nil
    editor.config.set("text.disable-completions", false)
    editor.config.set("text.disable-scrolling", false)
    editor.config.set("ui.line-numbers", "absolute")
    editor.currentDocument.setReadOnly(true)
    if editor.getTextEditorComponent().getSome(te):
      te.selection = point(0, 0).toRange
      te.centerCursor(point(0, 0))
      if self.services.getService(EventHandlerService).getSome(events):
        events.rebuildCommandToKeysMap()
      self.requestRender()

    else:
      self.exitCommandLine()

    if appendAndShowInFile and filename.len > 0:
      self.shellCommandOutput.add("\n")
      self.shellCommandOutput.add(value)
      let vfsService = getServiceChecked(VFSService)
      vfsService.vfs2.write(filename, self.shellCommandOutput).thenIt:
        let layout = self.services.getService(LayoutService).get
        discard layout.openFile(filename)

  proc clearCommandLineResults*(self: CommandLineService) {.expose("commands").} =
    let self = self.CommandLineServiceImpl
    self.shellCommandOutput = Rope.new("")
    let vfsService = getServiceChecked(VFSService)
    asyncSpawn vfsService.vfs2.write("ed://.shell-command-results", self.shellCommandOutput)

  proc executeCommandLine*(self: CommandLineService): bool {.expose("commands").} =
    let self = self.CommandLineServiceImpl
    defer:
      self.requestRender()
      self.commandHandler = nil

    let editor = self.commandLineEditor
    self.commandLineInputMode = false
    self.commandLineResultMode = false
    editor.active = false

    var input = ""
    if editor.currentDocument.getTextComponent().getSome(text):
      input = $text.content
    if input == "":
      if self.commandHandler != nil:
        try:
          return self.commandHandler("".some).isSome
        except Exception:
          discard
      return false

    let commands = input.split("\n")

    for command in commands:
      if (let i = self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.find(command); i >= 0):
        self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.delete i

    if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len == 0:
      self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.add ""

    for command in commands:
      self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.insert command, 1

    let maxHistorySize = self.config.get("editor.command-line.history-size", 100)
    if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len > maxHistorySize:
      self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.setLen maxHistorySize

    var allResults = ""
    for command in commands:
      let res = self.handleCommand(command)
      if res.getSome(res):
        if allResults.len > 0:
          allResults.add "\n"
        allResults.add res

    if editor.currentDocument.getTextComponent().getSome(text):
      text.content = ""

    if self.prefixOverlayId.isSome and editor.getDecorationComponent().getSome(decos):
      decos.clearOverlays(self.prefixOverlayId.get)
      decos.releaseOverlayId(self.prefixOverlayId.get)
      self.prefixOverlayId = int.none

    if allResults.len > 0:
      self.commandLineResult(allResults, showInCommandLine = true, appendAndShowInFile = false)
    return true

  proc selectPreviousCommandInHistory*(self: CommandLineService) {.expose("commands").} =
    let self = self.CommandLineServiceImpl
    let editor = self.commandLineEditor
    if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len == 0:
      self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.add ""

    var command = ""
    if editor.currentDocument.getTextComponent().getSome(text):
      command = $text.content
    if command != self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[self.currentHistoryEntry]:
      self.currentHistoryEntry = 0
      self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[0] = command

    self.currentHistoryEntry += 1
    if self.currentHistoryEntry >= self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len:
      self.currentHistoryEntry = 0

    if editor.currentDocument.getTextComponent().getSome(text):
      text.content = self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[self.currentHistoryEntry]
    if self.prefix != "":
      if editor.getDecorationComponent().getSome(decos):
        if self.prefixOverlayId.isSome:
          decos.addOverlay(point(0, 0)...point(0, 0), self.prefix, self.prefixOverlayId.get, scope = "comment", bias = Bias.Left)
    self.requestRender()

  proc selectNextCommandInHistory*(self: CommandLineService) {.expose("commands").} =
    let self = self.CommandLineServiceImpl
    let editor = self.commandLineEditor
    if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len == 0:
      self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.add ""

    var command = ""
    if editor.currentDocument.getTextComponent().getSome(text):
      command = $text.content
    if command != self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[self.currentHistoryEntry]:
      self.currentHistoryEntry = 0
      self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[0] = command

    self.currentHistoryEntry -= 1
    if self.currentHistoryEntry < 0:
      self.currentHistoryEntry = self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.high

    if editor.currentDocument.getTextComponent().getSome(textComponent):
      textComponent.content = self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[self.currentHistoryEntry]
    if self.prefix != "":
      if editor.getDecorationComponent().getSome(decos):
        if self.prefixOverlayId.isSome:
          decos.addOverlay(point(0, 0)...point(0, 0), self.prefix, self.prefixOverlayId.get, scope = "comment", bias = Bias.Left)
    self.requestRender()

  proc runProcessAndShowResultAsync(self: CommandLineService, command: string, options: RunShellCommandOptions) {.async.} =
    let self = self.CommandLineServiceImpl
    log lvlInfo, &"Run shell command '{command}'"
    try:
      type ShellOptions = object
        command: string
        args: seq[string]
        eval: bool = false

      let shell = self.config.get("editor.shells." & options.shell, newJObject()).jsonTo(ShellOptions, JOptions(allowMissingKeys: true))

      var flushOutputTask = startDelayedAsync(100, false):
        if self.services.getService(VFSService).getSome(vfsService):
          try:
            await vfsService.vfs2.write(options.filename, self.shellCommandOutput)
          except CatchableError:
            discard

      proc handleOutput(line: string) {.closure, gcsafe, raises: [].} =
        if options.filename.len > 0:
          self.shellCommandOutput.add("\n")
          self.shellCommandOutput.add(line)
          flushOutputTask.schedule()

      proc handleError(line: string) {.closure, gcsafe, raises: [].} =
        if options.filename.len > 0:
          self.shellCommandOutput.add("\n")
          self.shellCommandOutput.add(line)
          flushOutputTask.schedule()

      let layout = self.services.getService(LayoutService).get
      discard layout.openFile(options.filename)

      let start = startTimer()
      var finalCommand = ""
      if shell.eval:
        finalCommand = shell.command & " " & command
        await runProcessAsyncCallback(shell.command & " " & command, eval = true,
          handleOutput=handleOutput, handleError=handleError)
      else:
        finalCommand = shell.command & " " & shell.args.join(" ") & " " & command
        await runProcessAsyncCallback(shell.command, args = shell.args & @[command], eval = false,
          handleOutput=handleOutput, handleError=handleError)

      let time = start.elapsed.ms

      log lvlDebug, &"Finished '{finalCommand}' took {time} ms"
      self.shellCommandOutput.add(&"\n'{finalCommand}' took {time} ms\n")
      flushOutputTask.schedule()
    except Exception as e:
      log lvlError, &"Failed to run shell command '{command}': {e.msg}\n{e.getStackTrace()}"

  proc runShellCommand*(self: CommandLineService, options: RunShellCommandOptions = RunShellCommandOptions()) {.expose("commands").} =
    ## Opens the command line where you can enter a shell command.
    ## The command is run using the specified shell, which can be configured using `editor.shells.xyz`.
    ## `options.shell`               - Name of the shell (not the exe name). If the name is `xyz` then the configuration for the shell is in `editor.shells.xyz`.
    ## `options.initialValue`        - Initial text to put in the command line, after the prompt.
    ## `options.prompt`              - Text to show as prompt in the command line. Default: `> `
    ## `options.filename`            - Path of the file where the output is appended. Default: `ed://.shell-command-results`

    let self = self.CommandLineServiceImpl
    log lvlInfo, &"runShellCommand '{options}'"

    self.commandLine(options.initialValue, prefix = options.prompt)
    let weakSelf {.cursor.} = self
    self.commandHandler = proc(command: Option[string]): Option[string] =
      if command.getSome(command):
        asyncSpawn weakSelf.runProcessAndShowResultAsync(command, options)

  proc commandLineReplayCommands(self: CommandLineService, register: string) =
    let self = self.CommandLineServiceImpl
    if not self.registers.registers.contains(register) or self.registers.registers[register].kind != RegisterKind.Text:
      log lvlError, fmt"No commands recorded in register '{register}'"
      return

    if self.registers.bIsReplayingCommands:
      log lvlError, fmt"replayCommands '{register}': Already replaying commands"
      return

    log lvlInfo, &"replayCommands '{register}':\n{self.registers.registers[register].text}"
    self.registers.bIsReplayingCommands = true
    defer:
      self.registers.bIsReplayingCommands = false

    for command in self.registers.registers[register].text.splitLines:
      discard self.handleCommand(command)

  proc replayCommands*(self: CommandLineService, register: string) {.expose("commands").} =
    commandLineReplayCommands(self, register)

  addGlobalDispatchTable "commands", genDispatchTable("commands")

  proc toStringResult(node: JsonNode): string =
    if node != nil and node.kind != JNull:
        return $node
    return ""

  proc init_module_command_line*() {.cdecl, exportc, dynlib.} =
    getServices().addService(newLanguageServerCommandLineService())
    getServices().addService(newCommandLineService())
    let commands = getServiceChecked(CommandService)
    let table = genDispatchTable("commands")
    for value in table:
      capture value:
        discard commands.registerCommand(command_service.Command(
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
        ), override = true)

else:
  proc replayCommands*(self: CommandLineService, register: string) =
    commandLineReplayCommands(self, register)
  proc exitCommandLine*(self: CommandLineService) =
    commandLineExitCommandLine(self)
