import std/[strutils, tables, sugar, algorithm]
import fuzzy
import editor, ast_document, text_document, popup, events, compiler, compiler_types, id

type AstGotoDefinitionPopup* = ref object of Popup
  editor*: Editor
  textEditor*: TextDocumentEditor
  document*: AstDocument
  selected*: int
  completions*: seq[Completion]
  handleSymbolSelected*: proc(id: Id)

proc getCompletions*(self: AstGotoDefinitionPopup, text: string): seq[Completion] =
  result = @[]

  # Find everything matching text
  let symbols = ctx.computeSymbols(self.document.rootNode)
  for (key, symbol) in symbols.pairs:
    if symbol.kind != skAstNode:
      continue
    let score = fuzzyMatch(text, symbol.name)
    result.add Completion(kind: SymbolCompletion, score: score, id: symbol.id)

  result.sort((a, b) => cmp(a.score, b.score), Descending)

  return result

proc updateCompletions(self: AstGotoDefinitionPopup) =
  let text = self.textEditor.document.content.join

  self.completions = self.getCompletions(text)

  if self.completions.len > 0:
    self.selected = self.selected.clamp(0, self.completions.len - 1)
  else:
    self.selected = 0

method getEventHandlers*(self: AstGotoDefinitionPopup): seq[EventHandler] =
  return @[self.eventHandler] & self.textEditor.eventHandler

proc handleAction*(self: AstGotoDefinitionPopup, action: string, arg: string): EventResponse =
  case action
  of "accept":
    if self.selected < self.completions.len:
      self.handleSymbolSelected self.completions[self.selected].id
    self.editor.popPopup(self)

  of "cancel":
    self.editor.popPopup(self)

  of "prev":
    self.selected = if self.completions.len == 0:
      0
    else:
      (self.selected + self.completions.len - 1) mod self.completions.len

  of "next":
    self.selected = if self.completions.len == 0:
      0
    else:
      (self.selected + 1) mod self.completions.len

  return Handled

proc handleTextChanged*(self: AstGotoDefinitionPopup) =
  self.updateCompletions()
  self.selected = 0

proc newGotoPopup*(editor: Editor, document: AstDocument): AstGotoDefinitionPopup =
  var popup = AstGotoDefinitionPopup(editor: editor, document: document)
  popup.textEditor = newTextEditor(newTextDocument())
  popup.textEditor.renderHeader = false
  popup.textEditor.document.singleLine = true
  popup.textEditor.document.textChanged = (doc: TextDocument) => popup.handleTextChanged()

  popup.eventHandler = eventHandler2:
    command "<ENTER>", "accept"
    command "<TAB>", "accept"
    command "<ESCAPE>", "cancel"
    command "<UP>", "prev"
    command "<DOWN>", "next"
    onAction:
      popup.handleAction action, arg
    onInput:
      Ignored

  popup.updateCompletions()

  return popup