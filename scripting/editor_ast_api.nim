import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_7902080281(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_7902080384(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_7902080446(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_7902080496(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_7902080553(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_7902080609(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_7902080685(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_7902080761(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_7902080974(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_7902081027(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_7902081080(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_7902081179(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_7902081255(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_7902081331(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_7902081505(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_7902081647(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_7902081788(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_7902081928(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_7902082022(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_7902082120(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_7902082180(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_7902082298(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_7902082354(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_7902082418(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_7902082468(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_7902082529(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_7902082590(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_7902082753(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_7902082803(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_7902082853(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_7902082906(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_7902083060(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_7902083215(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_7902083265(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_7902083315(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_7902084151(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_7902084420(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_7902084481(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_7902084538(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_7902084995(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_7902085056(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_7902085124(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_7902085178(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_7902085267(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_7902085323(self, context)
