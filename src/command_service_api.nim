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

import command_service

import text/text_editor

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

proc commandLine*(self: CommandService, initialValue: string = "") {.expose("commands").} =
  let editor = self.commandLineEditor.TextDocumentEditor
  editor.document.content = initialValue
  if self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.len == 0:
    self.languageServerCommandLine.LanguageServerCommandLine.commandHistory.add ""
  self.languageServerCommandLine.LanguageServerCommandLine.commandHistory[0] = ""
  self.currentHistoryEntry = 0
  self.commandLineMode = true
  self.commandHandler = nil
  editor.setMode("insert")
  editor.disableCompletions = false
  self.events.rebuildCommandToKeysMap()
  self.platform.requestRender()

commandLineImpl = commandLine

proc exitCommandLine*(self: CommandService) {.expose("commands").} =
  let editor = self.commandLineEditor.TextDocumentEditor
  editor.document.content = ""
  editor.hideCompletions()
  self.commandLineMode = false
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
  self.commandLineMode = false

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

  for command in commands:
    if not self.handleCommand(command):
      return false

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

addGlobalDispatchTable "commands", genDispatchTable("commands")
