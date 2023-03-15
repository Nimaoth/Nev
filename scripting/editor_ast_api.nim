import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8120185013(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8120185116(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8120185178(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8120185228(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8120185285(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8120185341(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8120185417(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8120185493(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8120185706(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8120185759(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8120185812(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8120185911(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8120185987(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8120186063(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8120186237(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8120186379(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8120186520(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8120186660(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8120186754(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8120186852(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8120186912(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8120187030(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8120187086(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8120187150(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8120187200(self)
proc selectNextCompletion*(self: AstDocumentEditor) =
  selectNextCompletionScript2_8120187264(self)
proc applySelectedCompletion*(self: AstDocumentEditor) =
  applySelectedCompletionScript2_8120187328(self)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8120187491(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8120187541(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8120187591(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8120187644(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8120187798(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8120187953(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8120188003(self)
proc openGotoSymbolPopup*(self: AstDocumentEditor) =
  openGotoSymbolPopupScript_8120188070(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8120188359(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8120188838(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8120189107(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8120189168(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8120189225(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8120189682(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8120189743(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8120189811(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8120189865(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8120189954(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8120190010(self, context)
