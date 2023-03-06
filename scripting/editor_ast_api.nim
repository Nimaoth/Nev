import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8120185001(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8120185104(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8120185166(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8120185216(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8120185273(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8120185329(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8120185405(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8120185481(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8120185694(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8120185747(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8120185800(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8120185899(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8120185975(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8120186051(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8120186225(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8120186367(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8120186508(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8120186648(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8120186742(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8120186840(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8120186900(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8120187018(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8120187074(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8120187138(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8120187188(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_8120187249(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_8120187310(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8120187473(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8120187523(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8120187573(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8120187626(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8120187780(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8120187935(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8120187985(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8120188035(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8120188889(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8120189158(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8120189219(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8120189276(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8120189733(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8120189794(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8120189862(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8120189916(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8120190005(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8120190061(self, context)
