import std/[strutils, tables, sugar, algorithm, options]
import fuzzy, bumpy, vmath
import editor, ast_document, text/text_editor, popup, events, compiler, compiler_types, id, util, rect_utils, event, input
from scripting_api import LineNumbers

type AstGotoDefinitionPopup* = ref object of Popup
  editor*: App
  textEditor*: TextDocumentEditor
  document*: AstDocument
  selected*: int
  completions*: seq[Completion]
  handleSymbolSelected*: proc(id: Id)
  lastContentBounds*: Rect
  lastItems*: seq[tuple[index: int, bounds: Rect]]

proc getCompletions*(self: AstGotoDefinitionPopup, text: string): seq[Completion] =
  result = @[]

  # Find everything matching text
  let symbols = ctx.computeSymbols(self.document.rootNode)
  for (key, symbol) in symbols.pairs:
    if symbol.kind != skAstNode:
      continue
    let score = fuzzyMatchSmart(text, symbol.name)
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

proc getItemAtPixelPosition(self: AstGotoDefinitionPopup, posWindow: Vec2): Option[Completion] =
  result = Completion.none
  for (index, rect) in self.lastItems:
    if rect.contains(posWindow) and index >= 0 and index <= self.completions.high:
      return self.completions[index].some

method getEventHandlers*(self: AstGotoDefinitionPopup): seq[EventHandler] =
  return self.textEditor.getEventHandlers() & @[self.eventHandler]

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

  else:
    return self.editor.handleUnknownPopupAction(self, action, arg)

  return Handled

proc handleTextChanged*(self: AstGotoDefinitionPopup) =
  self.updateCompletions()
  self.selected = 0

method handleScroll*(self: AstGotoDefinitionPopup, scroll: Vec2, mousePosWindow: Vec2) =
  self.selected = clamp(self.selected - scroll.y.int, 0, self.completions.len - 1)

method handleMousePress*(self: AstGotoDefinitionPopup, button: MouseButton, mousePosWindow: Vec2) =
  if button == MouseButton.Left:
    if self.getItemAtPixelPosition(mousePosWindow).getSome(item):
      self.handleSymbolSelected(item.id)
      self.editor.popPopup(self)

method handleMouseRelease*(self: AstGotoDefinitionPopup, button: MouseButton, mousePosWindow: Vec2) =
  discard

method handleMouseMove*(self: AstGotoDefinitionPopup, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
  discard

proc newGotoPopup*(editor: App, document: AstDocument): AstGotoDefinitionPopup =
  var popup = AstGotoDefinitionPopup(editor: editor, document: document)
  popup.textEditor = newTextEditor(newTextDocument(editor.asConfigProvider), editor)
  popup.textEditor.setMode("insert")
  popup.textEditor.renderHeader = false
  popup.textEditor.lineNumbers = LineNumbers.None.some
  popup.textEditor.document.singleLine = true
  discard popup.textEditor.document.textChanged.subscribe (doc: TextDocument) => popup.handleTextChanged()

  popup.eventHandler = eventHandler(editor.getEventHandlerConfig("editor.ast.goto")):
    onAction:
      popup.handleAction action, arg
    onInput:
      Ignored

  popup.updateCompletions()

  return popup