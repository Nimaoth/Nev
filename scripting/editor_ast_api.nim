import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_6425686203(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_6425686299(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_6425686354(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_6425686397(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_6425686447(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_6425686496(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_6425686565(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_6425686634(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_6425686840(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_6425686886(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_6425686932(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_6425687024(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_6425687093(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_6425687162(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_6425687329(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_6425687464(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_6425687598(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_6425687731(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_6425687818(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_6425687909(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_6425687962(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_6425688073(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_6425688122(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_6425688179(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_6425688222(self)
proc selectNextCompletion*(self: AstDocumentEditor) =
  selectNextCompletionScript2_6425688282(self)
proc applySelectedCompletion*(self: AstDocumentEditor) =
  applySelectedCompletionScript2_6425688342(self)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_6425688498(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_6425688541(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_6425688584(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_6425688630(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_6425688777(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_6425688925(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_6425688968(self)
proc openGotoSymbolPopup*(self: AstDocumentEditor) =
  openGotoSymbolPopupScript_6425689028(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_6425689310(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_6425689782(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_6425690044(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_6425690098(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_6425690148(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_6425690598(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_6425690652(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_6425690713(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_6425690760(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_6425690842(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_6425690891(self, context)
