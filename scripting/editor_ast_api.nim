import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8120185019(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8120185122(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8120185184(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8120185234(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8120185291(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8120185347(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8120185423(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8120185499(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8120185712(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8120185765(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8120185818(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8120185917(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8120185993(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8120186069(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8120186243(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8120186385(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8120186526(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8120186666(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8120186760(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8120186858(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8120186918(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8120187036(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8120187092(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8120187156(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8120187206(self)
proc selectNextCompletion*(self: AstDocumentEditor) =
  selectNextCompletionScript2_8120187273(self)
proc applySelectedCompletion*(self: AstDocumentEditor) =
  applySelectedCompletionScript2_8120187340(self)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8120187503(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8120187553(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8120187603(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8120187656(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8120187810(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8120187965(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8120188015(self)
proc openGotoSymbolPopup*(self: AstDocumentEditor) =
  openGotoSymbolPopupScript_8120188082(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8120188371(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8120188850(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8120189119(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8120189180(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8120189237(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8120189694(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8120189755(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8120189823(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8120189877(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8120189966(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8120190022(self, context)
