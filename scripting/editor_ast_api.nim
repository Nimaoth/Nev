import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8120184417(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8120184520(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8120184582(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8120184632(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8120184689(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8120184745(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8120184821(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8120184897(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8120185110(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8120185163(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8120185216(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8120185315(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8120185391(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8120185467(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8120185641(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8120185783(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8120185924(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8120186064(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8120186158(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8120186256(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8120186316(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8120186434(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8120186490(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8120186554(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8120186604(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_8120186665(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_8120186726(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8120186889(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8120186939(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8120186989(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8120187042(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8120187196(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8120187351(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8120187401(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8120187451(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8120188305(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8120188574(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8120188635(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8120188692(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8120189149(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8120189210(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8120189278(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8120189332(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8120189421(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8120189477(self, context)
