import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8120184996(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8120185099(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8120185161(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8120185211(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8120185268(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8120185324(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8120185400(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8120185476(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8120185689(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8120185742(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8120185795(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8120185894(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8120185970(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8120186046(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8120186220(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8120186362(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8120186503(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8120186643(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8120186737(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8120186835(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8120186895(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8120187013(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8120187069(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8120187133(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8120187183(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_8120187244(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_8120187305(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8120187468(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8120187518(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8120187568(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8120187621(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8120187775(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8120187930(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8120187980(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8120188030(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8120188551(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8120188820(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8120188881(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8120188938(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8120189395(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8120189456(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8120189524(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8120189578(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8120189667(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8120189723(self, context)
