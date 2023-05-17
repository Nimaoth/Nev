import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8690610363(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8690610459(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8690610514(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8690610557(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8690610607(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8690610656(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8690610725(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8690610794(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8690611000(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8690611046(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8690611092(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8690611184(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8690611253(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8690611322(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8690611489(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8690611624(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8690611758(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8690611891(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8690611978(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8690612069(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8690612122(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8690612233(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8690612282(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8690612339(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8690612382(self)
proc selectNextCompletion*(self: AstDocumentEditor) =
  selectNextCompletionScript2_8690612442(self)
proc applySelectedCompletion*(self: AstDocumentEditor) =
  applySelectedCompletionScript2_8690612502(self)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8690612658(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8690612701(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8690612744(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8690612790(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8690612937(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8690613085(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8690613128(self)
proc openGotoSymbolPopup*(self: AstDocumentEditor) =
  openGotoSymbolPopupScript_8690613188(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8690613470(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8690613942(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8690614204(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8690614258(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8690614308(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8690614758(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8690614812(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8690614873(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8690614920(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8690615002(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8690615051(self, context)
