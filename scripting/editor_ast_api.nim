import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8103406873(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8103406976(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8103407038(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8103407088(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8103407145(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8103407201(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8103407277(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8103407353(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8103407566(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8103407619(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8103407672(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8103407771(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8103407847(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8103407923(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8103408097(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8103408239(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8103408380(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8103408520(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8103408614(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8103408712(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8103408772(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8103408890(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8103408946(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8103409010(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8103409060(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_8103409121(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_8103409182(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8103409345(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8103409395(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8103409445(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8103409498(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8103409652(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8103409807(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8103409857(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8103409907(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8103410743(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8103411012(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8103411073(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8103411130(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8103411587(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8103411648(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8103411716(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8103411770(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8103411859(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8103411915(self, context)
