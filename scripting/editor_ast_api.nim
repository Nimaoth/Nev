import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8120185081(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8120185184(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8120185246(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8120185296(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8120185353(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8120185409(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8120185485(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8120185561(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8120185774(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8120185827(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8120185880(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8120185979(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8120186055(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8120186131(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8120186305(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8120186447(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8120186588(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8120186728(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8120186822(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8120186920(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8120186980(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8120187098(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8120187154(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8120187218(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8120187268(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_8120187329(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_8120187390(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8120187553(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8120187603(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8120187653(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8120187706(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8120187860(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8120188015(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8120188065(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8120188115(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8120188969(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8120189238(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8120189299(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8120189356(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8120189813(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8120189874(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8120189942(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8120189996(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8120190085(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8120190141(self, context)
