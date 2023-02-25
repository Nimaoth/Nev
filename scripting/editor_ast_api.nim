import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript_8120184093(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript_8120184196(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript_8120184258(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript_8120184308(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript_8120184365(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript_8120184421(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript_8120184497(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript_8120184573(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript_8120184786(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript_8120184839(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript_8120184892(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2_8120184991(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2_8120185067(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript_8120185143(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript_8120185317(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript_8120185459(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript_8120185600(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript_8120185740(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript_8120185834(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript_8120185932(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript_8120185992(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript_8120186110(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript_8120186166(self)
proc rename*(self: AstDocumentEditor) =
  renameScript_8120186230(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2_8120186280(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2_8120186341(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2_8120186402(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript_8120186565(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript_8120186615(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript_8120186665(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript_8120186718(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript_8120186872(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2_8120187027(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2_8120187077(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript_8120187127(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript_8120187963(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript_8120188232(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript_8120188293(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript_8120188350(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript_8120188807(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript_8120188868(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript_8120188936(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2_8120188990(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2_8120189079(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2_8120189135(self, context)
