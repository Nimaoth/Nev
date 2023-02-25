import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8120184089(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8120184192(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8120184254(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8120184304(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8120184361(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8120184417(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8120184493(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8120184569(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8120184782(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8120184835(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8120184888(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8120184987(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8120185063(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8120185139(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8120185313(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8120185455(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8120185596(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8120185736(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8120185830(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8120185928(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8120185988(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8120186106(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8120186162(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8120186226(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8120186276(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_8120186337(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_8120186398(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8120186561(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8120186611(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8120186661(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8120186714(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8120186868(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8120187023(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8120187073(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8120187123(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8120187959(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8120188228(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8120188289(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8120188346(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8120188803(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8120188864(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8120188932(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8120188986(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8120189075(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8120189131(self, context)
