import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8120185005(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8120185108(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8120185170(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8120185220(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8120185277(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8120185333(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8120185409(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8120185485(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8120185698(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8120185751(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8120185804(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8120185903(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8120185979(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8120186055(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8120186229(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8120186371(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8120186512(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8120186652(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8120186746(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8120186844(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8120186904(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8120187022(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8120187078(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8120187142(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8120187192(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_8120187253(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_8120187314(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8120187477(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8120187527(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8120187577(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8120187630(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8120187784(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8120187939(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8120187989(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8120188039(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8120188560(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8120188829(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8120188890(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8120188947(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8120189404(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8120189465(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8120189533(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8120189587(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8120189676(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8120189732(self, context)
