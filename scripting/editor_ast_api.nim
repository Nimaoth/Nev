import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8120185007(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8120185110(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8120185172(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8120185222(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8120185279(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8120185335(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8120185411(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8120185487(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8120185700(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8120185753(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8120185806(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8120185905(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8120185981(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8120186057(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8120186231(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8120186373(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8120186514(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8120186654(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8120186748(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8120186846(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8120186906(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8120187024(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8120187080(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8120187144(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8120187194(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_8120187255(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_8120187316(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8120187479(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8120187529(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8120187579(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8120187632(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8120187786(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8120187941(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8120187991(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8120188041(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8120188562(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8120188831(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8120188892(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8120188949(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8120189406(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8120189467(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8120189535(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8120189589(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8120189678(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8120189734(self, context)
