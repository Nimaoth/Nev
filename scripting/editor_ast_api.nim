import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8707387579(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8707387675(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8707387730(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8707387773(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8707387823(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8707387872(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8707387941(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8707388010(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8707388216(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8707388262(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8707388308(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8707388400(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8707388469(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8707388538(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8707388705(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8707388840(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8707388974(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8707389107(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8707389194(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8707389285(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8707389338(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8707389449(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8707389498(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8707389555(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8707389598(self)
proc selectNextCompletion*(self: AstDocumentEditor) =
  selectNextCompletionScript2_8707389658(self)
proc applySelectedCompletion*(self: AstDocumentEditor) =
  applySelectedCompletionScript2_8707389718(self)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8707389874(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8707389917(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8707389960(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8707390006(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8707390153(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8707390301(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8707390344(self)
proc openGotoSymbolPopup*(self: AstDocumentEditor) =
  openGotoSymbolPopupScript_8707390404(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8707390686(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8707391158(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8707391420(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8707391474(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8707391524(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8707391974(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8707392028(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8707392089(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8707392136(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8707392218(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8707392267(self, context)
