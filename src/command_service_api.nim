import std/[strutils, options, json, tables]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import misc/[util, custom_logger, custom_async, custom_unicode, myjsonutils, async_process, delayed_task, timer]
import scripting/[expose]
import platform/[platform]
import events, vfs, layout
import dispatch_tables, config_provider, service, platform_service
import language_server_command_line

import command_service

import nimsumtree/[rope, sumtree]
import text/[text_editor, display_map, overlay_map]

logCategory "commands-api"

{.push gcsafe.}
{.push raises: [].}

###########################################################################

proc requestRender(self: CommandService) =
  if self.services.getService(PlatformService).getSome(platform):
    platform.platform.requestRender()

proc getCommandService(): Option[CommandService] =
  {.gcsafe.}:
    if gServices.isNil: return CommandService.none
    return gServices.getService(CommandService)

static:
  addInjector(CommandService, getCommandService)

proc commandLine*(self: CommandService, initialValue: string = "", prefix: string = "") {.expose("commands").} =
  let editor = self.commandLineEditor.TextDocumentEditor
  editor.document.content = initialValue
  if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len == 0:
    self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.add ""
  self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[0] = ""
  self.currentHistoryEntry = 0
  self.commandLineInputMode = true
  self.commandLineResultMode = false
  self.commandHandler = nil
  self.prefix = prefix
  editor.disableCompletions = false
  editor.disableScrolling = true
  editor.uiSettings.lineNumbers.set(api.LineNumbers.None)
  editor.document.setReadOnly(false)
  editor.clearOverlays(overlayIdPrefix)
  editor.setDefaultMode()
  if self.prefix != "":
    editor.clearOverlays(overlayIdPrefix)
    editor.displayMap.overlay.addOverlay(point(0, 0)...point(0, 0), self.prefix, overlayIdPrefix, scope = "comment", bias = Bias.Left)

  if self.services.getService(EventHandlerService).getSome(events):
    events.rebuildCommandToKeysMap()
  self.requestRender()

proc exitCommandLine*(self: CommandService) {.expose("commands").} =
  let editor = self.commandLineEditor.TextDocumentEditor
  editor.document.content = ""
  editor.hideCompletions()
  editor.disableScrolling = true
  editor.uiSettings.lineNumbers.set(api.LineNumbers.None)
  editor.document.setReadOnly(false)
  self.commandLineInputMode = false
  self.commandLineResultMode = false
  try:
    if self.commandHandler.isNotNil:
      discard self.commandHandler(string.none)
    elif self.defaultCommandHandler.isNotNil:
      discard self.defaultCommandHandler(string.none)
  except Exception as e:
    log lvlError, &"exitCommandLine: {e.msg}"
  self.commandHandler = nil
  self.requestRender()

proc commandLineResult*(self: CommandService, value: string, showInCommandLine: bool = false,
    appendAndShowInFile: bool = false, filename: string = "ed://.shell-command-results") {.expose("commands").} =
  let editor = self.commandLineEditor.TextDocumentEditor
  if showInCommandLine:
    editor.document.content = value
    if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len == 0:
      self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.add ""
    self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[0] = ""
    self.currentHistoryEntry = 0
    self.commandLineInputMode = false
    self.commandLineResultMode = true
    self.commandHandler = nil
    editor.disableCompletions = false
    editor.disableScrolling = false
    editor.uiSettings.lineNumbers.set(api.LineNumbers.Absolute)
    editor.document.setReadOnly(true)
    editor.selection = (0, 0).toSelection
    editor.scrollToCursor(scrollBehaviour = ScrollBehaviour.TopOfScreen.some)
    if self.services.getService(EventHandlerService).getSome(events):
      events.rebuildCommandToKeysMap()
    self.requestRender()

  else:
    self.exitCommandLine()

  if appendAndShowInFile and filename.len > 0:
    self.shellCommandOutput.add("\n")
    self.shellCommandOutput.add(value)
    editor.vfs.write(filename, self.shellCommandOutput).thenIt:
      let layout = self.services.getService(LayoutService).get
      discard layout.openFile(filename)

proc clearCommandLineResults*(self: CommandService) {.expose("commands").} =
  let editor = self.commandLineEditor.TextDocumentEditor
  self.shellCommandOutput = Rope.new("")
  asyncSpawn editor.vfs.write("ed://.shell-command-results", self.shellCommandOutput)

commandLineImpl = commandLine

proc executeCommandLine*(self: CommandService): bool {.expose("commands").} =
  defer:
    self.requestRender()
    self.commandHandler = nil

  let editor = self.commandLineEditor.TextDocumentEditor
  self.commandLineInputMode = false
  self.commandLineResultMode = false

  let input = editor.document.contentString
  if input == "":
    return false

  let commands = input.split("\n")
  editor.document.content = ""

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

  if allResults.len > 0:
    self.commandLineResult(allResults, showInCommandLine = true, appendAndShowInFile = false)
  return true

proc selectPreviousCommandInHistory*(self: CommandService) {.expose("commands").} =
  let editor = self.commandLineEditor.TextDocumentEditor
  if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len == 0:
    self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.add ""

  let command = editor.document.contentString
  if command != self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[self.currentHistoryEntry]:
    self.currentHistoryEntry = 0
    self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[0] = command

  self.currentHistoryEntry += 1
  if self.currentHistoryEntry >= self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len:
    self.currentHistoryEntry = 0

  editor.document.content = self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[self.currentHistoryEntry]
  editor.move("(file) (end)")
  if self.prefix != "":
    editor.clearOverlays(overlayIdPrefix)
    editor.displayMap.overlay.addOverlay(point(0, 0)...point(0, 0), self.prefix, overlayIdPrefix, scope = "comment", bias = Bias.Left)
  self.requestRender()

proc selectNextCommandInHistory*(self: CommandService) {.expose("commands").} =
  let editor = self.commandLineEditor.TextDocumentEditor
  if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len == 0:
    self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.add ""

  let command = editor.document.contentString
  if command != self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[self.currentHistoryEntry]:
    self.currentHistoryEntry = 0
    self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[0] = command

  self.currentHistoryEntry -= 1
  if self.currentHistoryEntry < 0:
    self.currentHistoryEntry = self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.high

  editor.document.content = self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[self.currentHistoryEntry]
  editor.move("(file) (end)")
  if self.prefix != "":
    editor.clearOverlays(overlayIdPrefix)
    editor.displayMap.overlay.addOverlay(point(0, 0)...point(0, 0), self.prefix, overlayIdPrefix, scope = "comment", bias = Bias.Left)
  self.requestRender()

proc runProcessAndShowResultAsync(self: CommandService, command: string, options: RunShellCommandOptions) {.async.} =
  log lvlInfo, &"Run shell command '{command}'"
  try:
    type ShellOptions = object
      command: string
      args: seq[string]
      eval: bool = false

    let shell = self.config.get("editor.shells." & options.shell, newJObject()).jsonTo(ShellOptions, JOptions(allowMissingKeys: true))

    let editor = self.commandLineEditor.TextDocumentEditor
    var flushOutputTask = startDelayedAsync(100, false):
      try:
        await editor.vfs.write(options.filename, self.shellCommandOutput)
      except IOError:
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

proc runShellCommand*(self: CommandService, options: RunShellCommandOptions = RunShellCommandOptions()) {.expose("commands").} =
  ## Opens the command line where you can enter a shell command.
  ## The command is run using the specified shell, which can be configured using `editor.shells.xyz`.
  ## `options.shell`               - Name of the shell (not the exe name). If the name is `xyz` then the configuration for the shell is in `editor.shells.xyz`.
  ## `options.initialValue`        - Initial text to put in the command line, after the prompt.
  ## `options.prompt`              - Text to show as prompt in the command line. Default: `> `
  ## `options.filename`            - Path of the file where the output is appended. Default: `ed://.shell-command-results`

  log lvlInfo, &"runShellCommand '{options}'"

  self.commandLine(options.initialValue, prefix = options.prompt)
  self.commandHandler = proc(command: Option[string]): Option[string] =
    if command.getSome(command):
      asyncSpawn self.runProcessAndShowResultAsync(command, options)

addGlobalDispatchTable "commands", genDispatchTable("commands")
