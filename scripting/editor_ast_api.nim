import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8103407201(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8103407304(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8103407366(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8103407416(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8103407473(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8103407529(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8103407605(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8103407681(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8103407894(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8103407947(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8103408000(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8103408099(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8103408175(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8103408251(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8103408425(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8103408567(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8103408708(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8103408848(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8103408942(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8103409040(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8103409100(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8103409218(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8103409274(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8103409338(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8103409388(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_8103409449(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_8103409510(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8103409673(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8103409723(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8103409773(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8103409826(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8103409980(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8103410135(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8103410185(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8103410235(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8103411089(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8103411358(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8103411419(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8103411476(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8103411933(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8103411994(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8103412062(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8103412116(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8103412205(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8103412261(self, context)
