import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8120185012(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8120185115(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8120185177(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8120185227(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8120185284(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8120185340(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8120185416(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8120185492(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8120185705(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8120185758(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8120185811(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8120185910(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8120185986(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8120186062(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8120186236(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8120186378(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8120186519(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8120186659(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8120186753(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8120186851(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8120186911(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8120187029(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8120187085(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8120187149(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8120187199(self)
proc selectNextCompletion*(self: AstDocumentEditor) =
  selectNextCompletionScript2_8120187263(self)
proc applySelectedCompletion*(self: AstDocumentEditor) =
  applySelectedCompletionScript2_8120187327(self)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8120187490(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8120187540(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8120187590(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8120187643(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8120187797(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8120187952(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8120188002(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8120188052(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8120188573(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8120188842(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8120188903(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8120188960(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8120189417(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8120189478(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8120189546(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8120189600(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8120189689(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8120189745(self, context)
