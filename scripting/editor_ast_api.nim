import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
elif defined(wasm):
  # import absytree_internal_wasm
  discard
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8690610363(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8690610473(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8690610541(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8690610597(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8690610671(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8690610743(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8690610834(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8690610926(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8690611146(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8690611234(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8690611293(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8690611408(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8690611490(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8690611572(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8690611991(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8690612175(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8690612358(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8690612540(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8690612676(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8690612816(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8690612882(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8690613054(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8690613123(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8690613230(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8690613286(self)
proc selectNextCompletion*(self: AstDocumentEditor) =
  selectNextCompletionScript2_8690613359(self)
proc applySelectedCompletion*(self: AstDocumentEditor) =
  applySelectedCompletionScript2_8690613432(self)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8690613672(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8690613728(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8690613784(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8690613843(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8690614011(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8690614183(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8690614240(self)
proc openGotoSymbolPopup*(self: AstDocumentEditor) =
  openGotoSymbolPopupScript_8690614314(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8690614645(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8690615243(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8690615519(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8690615587(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8690615651(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8690616134(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8690616202(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8690616277(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8690616337(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8690616459(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8690616521(self, context)
