import std/[json]
import "../src/scripting_api"
import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript(self)
proc rename*(self: AstDocumentEditor) =
  renameScript(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2(self, context)
