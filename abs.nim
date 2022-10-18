# import std/logging

type AnyDocumentEditor = DocumentEditor | TextDocumentEditor | AstDocumentEditor
type AnyPopup = Popup

proc addCommand*(context: string, keys: string, action: string, arg: string = "") =
  scriptAddCommand(context, keys, action, arg)

proc removeCommand*(context: string, keys: string) =
  scriptRemoveCommand(context, keys)

proc runAction*(action: string, arg: string = "") =
  scriptRunAction(action, arg)

template isTextEditor*(editor: DocumentEditor, injected: untyped): bool =
  ((let o = editor; scriptIsTextEditor(editor.id))) and ((let injected {.inject.} = editor.TextDocumentEditor; true))

template isAstEditor*(editor: DocumentEditor, injected: untyped): bool =
  ((let o = editor; scriptIsAstEditor(editor.id))) and ((let injected {.inject.} = editor.AstDocumentEditor; true))

proc getActiveEditor*(): DocumentEditor =
  return DocumentEditor(id: scriptGetActiveEditorHandle())

proc getEditor*(index: int): DocumentEditor =
  return DocumentEditor(id: scriptGetEditorHandle(index))

proc handleDocumentEditorAction*(editor: DocumentEditor, action: string, arg: string): bool
proc handleTextEditorAction*(editor: TextDocumentEditor, action: string, arg: string): bool
proc handleAstEditorAction*(editor: AstDocumentEditor, action: string, arg: string): bool
proc handlePopupAction*(popup: Popup, action: string, arg: string): bool

proc handleEditorAction*(id: EditorId, action: string, arg: string): bool =
  let editor = DocumentEditor(id: id)

  if editor.isTextEditor(editor):
    return handleTextEditorAction(editor, action, arg)

  elif editor.isAstEditor(editor):
    return handleAstEditorAction(editor, action, arg)

  return handleDocumentEditorAction(editor, action, arg)

proc handleUnknownPopupAction*(id: EditorId, action: string, arg: string): bool =
  let popup = Popup(id: id)

  return handlePopupAction(popup, action, arg)

proc runAction*(editor: DocumentEditor, action: string, arg: string = "") =
  scriptRunActionFor(editor.id, action, arg)

proc runAction*(popup: Popup, action: string, arg: string = "") =
  scriptRunActionForPopup(popup.id, action, arg)

proc insertText*(editor: AnyDocumentEditor, text: string) =
  scriptInsertTextInto(editor.id, text)

proc selection*(editor: TextDocumentEditor): Selection =
  return scriptTextEditorSelection(editor.id)

proc `selection=`*(editor: TextDocumentEditor, selection: Selection) =
  scriptSetTextEditorSelection(editor.id, selection)

proc getLine*(editor: TextDocumentEditor, line: int): string =
  return scriptGetTextEditorLine(editor.id, line)

proc getLineCount*(editor: TextDocumentEditor): int =
  return scriptGetTextEditorLineCount(editor.id)

proc log*(args: varargs[string, `$`]) =
  var msgLen = 0
  for arg in args:
    msgLen += arg.len
  var result = newStringOfCap(msgLen + 5)
  for arg in args:
    result.add(arg)
  scriptLog(result)