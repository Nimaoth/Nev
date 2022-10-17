import std/[strutils, tables, sugar, algorithm, sequtils]
import fuzzy
import editor, text_document, popup, events

type
  SelectorItem* = ref object of RootObj
    discard

  SelectorPopup* = ref object of Popup
    editor*: Editor
    textEditor*: TextDocumentEditor
    selected*: int
    completions*: seq[SelectorItem]
    handleItemConfirmed*: proc(item: SelectorItem)
    handleItemSelected*: proc(item: SelectorItem)
    getCompletions*: proc(self: SelectorPopup, text: string): seq[SelectorItem]

proc updateCompletions(self: SelectorPopup) =
  let text = self.textEditor.document.content.join

  self.completions = self.getCompletions(self, text)

  if self.completions.len > 0:
    self.selected = self.selected.clamp(0, self.completions.len - 1)
  else:
    self.selected = 0

method getEventHandlers*(self: SelectorPopup): seq[EventHandler] =
  return @[self.eventHandler] & self.textEditor.eventHandler

proc handleAction*(self: SelectorPopup, action: string, arg: string): EventResponse =
  case action
  of "accept":
    if self.selected < self.completions.len:
      self.handleItemConfirmed self.completions[self.selected]
    self.editor.popPopup(self)

  of "cancel":
    self.editor.popPopup(self)

  of "prev":
    self.selected = if self.completions.len == 0:
      0
    else:
      (self.selected + self.completions.len - 1) mod self.completions.len

    if self.completions.len > 0 and self.handleItemSelected != nil:
      self.handleItemSelected self.completions[self.selected]

  of "next":
    self.selected = if self.completions.len == 0:
      0
    else:
      (self.selected + 1) mod self.completions.len

    if self.completions.len > 0 and self.handleItemSelected != nil:
      self.handleItemSelected self.completions[self.selected]

  return Handled

proc handleTextChanged*(self: SelectorPopup) =
  self.updateCompletions()
  self.selected = 0

proc newSelectorPopup*(editor: Editor, getCompletions: proc(self: SelectorPopup, text: string): seq[SelectorItem]): SelectorPopup =
  var popup = SelectorPopup(editor: editor)
  popup.textEditor = newTextEditor(newTextDocument())
  popup.textEditor.renderHeader = false
  popup.textEditor.document.singleLine = true
  popup.textEditor.document.textChanged = (doc: TextDocument) => popup.handleTextChanged()
  popup.getCompletions = getCompletions

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
  if popup.completions.len > 0 and popup.handleItemSelected != nil:
    popup.handleItemSelected popup.completions[0]

  return popup