import std/[strutils, options, json]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import misc/[util, custom_logger, custom_async, custom_unicode, myjsonutils, async_process]
import scripting/[expose]
import platform/[platform]
import events
import dispatch_tables, config_provider, service
import language_server_command_line

import command_service

import nimsumtree/[rope, sumtree]
import text/[text_editor, display_map, overlay_map]
import scripting_api as api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, ModelDocumentEditor, Popup, SelectorPopup

logCategory "commands-api"

{.push gcsafe.}
{.push raises: [].}

###########################################################################

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
  editor.setMode("insert")
  editor.disableCompletions = false
  editor.disableScrolling = true
  editor.lineNumbers = api.LineNumbers.None.some
  editor.document.setReadOnly(false)
  editor.clearOverlays(5)
  if prefix != "":
    editor.displayMap.overlay.addOverlay(point(0, 0)...point(0, 0), prefix, 5, scope = "comment", bias = Bias.Left)
  self.events.rebuildCommandToKeysMap()
  self.platform.requestRender()

proc commandLineResult*(self: CommandService, value: string) {.expose("commands").} =
  let editor = self.commandLineEditor.TextDocumentEditor
  editor.document.content = value
  if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len == 0:
    self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.add ""
  self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[0] = ""
  self.currentHistoryEntry = 0
  self.commandLineInputMode = false
  self.commandLineResultMode = true
  self.commandHandler = nil
  editor.setMode("normal")
  editor.disableCompletions = false
  editor.disableScrolling = false
  editor.lineNumbers = api.LineNumbers.Absolute.some
  editor.document.setReadOnly(true)
  self.events.rebuildCommandToKeysMap()
  self.platform.requestRender()

commandLineImpl = commandLine

proc exitCommandLine*(self: CommandService) {.expose("commands").} =
  let editor = self.commandLineEditor.TextDocumentEditor
  editor.document.content = ""
  editor.hideCompletions()
  editor.disableScrolling = true
  editor.lineNumbers = api.LineNumbers.None.some
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
  self.platform.requestRender()

proc executeCommandLine*(self: CommandService): bool {.expose("commands").} =
  defer:
    self.platform.requestRender()

  let editor = self.commandLineEditor.TextDocumentEditor
  self.commandLineInputMode = false
  self.commandLineResultMode = false

  let commands = editor.document.contentString.split("\n")
  editor.document.content = ""

  for command in commands:
    if (let i = self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.find(command); i >= 0):
      self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.delete i

  if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len == 0:
    self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.add ""

  for command in commands:
    self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.insert command, 1

  let maxHistorySize = self.config.getValue("editor.command-line.history-size", 100)
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
    self.commandLineResult(allResults)
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
  editor.moveLast("file", Both)
  self.platform.requestRender()

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
  editor.moveLast("file", Both)
  self.platform.requestRender()

proc runProcessAndShowResultAsync(self: CommandService, command: string) {.async.} =
  log lvlInfo, &"Run shell command '{command}'"
  try:
    let (output, err) = await runProcessAsyncOutput(command, eval = true)
    var text = "Output:"
    if output.len > 0:
      text.add "\n"
      text.add output
    text.add "\nError:"
    if err.len > 0:
      text.add "\n"
      text.add err

    if output.len > 0 or err.len > 0:
      self.commandLineResult(output)
  except Exception as e:
    log lvlError, &"Failed to run shell command '{command}': {e.msg}\n{e.getStackTrace()}"
    self.commandLineResult(e.msg)

proc runShellCommand*(self: CommandService, initialValue: string = "") {.expose("commands").} =
  self.commandLine(initialValue, prefix = "> ")
  self.commandHandler = proc(command: Option[string]): Option[string] =
    if command.getSome(command):
      asyncSpawn self.runProcessAndShowResultAsync(command)

addGlobalDispatchTable "commands", genDispatchTable("commands")
