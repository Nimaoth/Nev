import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_7935634713(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_7935634816(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_7935634878(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_7935634928(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_7935634985(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_7935635041(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_7935635117(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_7935635193(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_7935635406(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_7935635459(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_7935635512(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_7935635611(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_7935635687(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_7935635763(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_7935635937(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_7935636079(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_7935636220(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_7935636360(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_7935636454(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_7935636552(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_7935636612(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_7935636730(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_7935636786(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_7935636850(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_7935636900(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_7935636961(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_7935637022(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_7935637185(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_7935637235(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_7935637285(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_7935637338(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_7935637492(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_7935637647(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_7935637697(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_7935637747(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_7935638583(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_7935638852(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_7935638913(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_7935638970(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_7935639427(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_7935639488(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_7935639556(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_7935639610(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_7935639699(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_7935639755(self, context)
