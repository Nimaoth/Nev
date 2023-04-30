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
  moveCursorUpScript_8120185115(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8120185170(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8120185213(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8120185263(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8120185312(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8120185381(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8120185450(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8120185656(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8120185702(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8120185748(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8120185840(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8120185909(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8120185978(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8120186145(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8120186280(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8120186414(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8120186547(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8120186634(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8120186725(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8120186778(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8120186889(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8120186938(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8120186995(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8120187038(self)
proc selectNextCompletion*(self: AstDocumentEditor) =
  selectNextCompletionScript2_8120187098(self)
proc applySelectedCompletion*(self: AstDocumentEditor) =
  applySelectedCompletionScript2_8120187158(self)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8120187314(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8120187357(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8120187400(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8120187446(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8120187593(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8120187741(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8120187784(self)
proc openGotoSymbolPopup*(self: AstDocumentEditor) =
  openGotoSymbolPopupScript_8120187844(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8120188126(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8120188598(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8120188860(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8120188914(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8120188964(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8120189414(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8120189468(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8120189529(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8120189576(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8120189658(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8120189707(self, context)
