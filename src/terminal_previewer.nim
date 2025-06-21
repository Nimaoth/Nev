import std/[strformat, strutils, tables]
import misc/[util, custom_logger]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import finder/[finder, previewer]
import service, terminal_service, view

logCategory "terminal-previewer"

type
  TerminalPreviewer* = ref object of Previewer
    view*: TerminalView
    terminals: TerminalService

proc newTerminalPreviewer*(services: Services, terminals: TerminalService): TerminalPreviewer =
  new result
  result.terminals = terminals

method deinit*(self: TerminalPreviewer) =
  # logScope lvlInfo, &"[deinit] Destroying terminal previewer"
  self[] = default(typeof(self[]))

method delayPreview*(self: TerminalPreviewer) =
  discard

method previewItem*(self: TerminalPreviewer, item: FinderItem): View =
  logScope lvlInfo, &"previewItem {item}"
  let id = item.data.parseInt.catch:
    log lvlError, fmt"Failed to parse editor id from data '{item}'"
    return

  if id in self.terminals.terminals:
    self.view = self.terminals.terminals[id]
  else:
    self.view = nil
  return self.view
