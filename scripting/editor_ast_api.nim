import std/[json]
import "../src/scripting_api"
import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_7902080281(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_7902080383(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_7902080444(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_7902080493(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_7902080549(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_7902080604(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_7902080679(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_7902080754(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_7902080966(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_7902081018(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_7902081070(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_7902081168(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_7902081243(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_7902081318(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_7902081491(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_7902081632(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_7902081772(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_7902081911(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_7902082004(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_7902082101(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_7902082160(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_7902082277(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_7902082332(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_7902082395(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_7902082444(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_7902082504(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_7902082564(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_7902082726(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_7902082775(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_7902082824(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_7902082876(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_7902083029(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_7902083183(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_7902083232(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_7902083281(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_7902084116(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_7902084384(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_7902084444(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_7902084500(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_7902084956(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_7902085016(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_7902085083(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_7902085136(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_7902085224(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_7902085279(self, context)
