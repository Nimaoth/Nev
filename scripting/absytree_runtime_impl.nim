import absytree_runtime

proc handleGlobalAction*(action: string, arg: string): bool =
  if action == "lambda-action":
    return handleLambdaAction(arg)
  return handleAction(action, arg)

proc handleEditorAction*(id: EditorId, action: string, args: JsonNode): bool =
  if action == "lambda-action":
    return handleLambdaAction(args[0].str)

  if id.isTextEditor(editor):
    return handleTextEditorAction(editor, action, args)

  elif id.isAstEditor(editor):
    return handleAstEditorAction(editor, action, args)

  return handleDocumentEditorAction(id, action, args)

proc handleUnknownPopupAction*(id: EditorId, action: string, arg: string): bool =
  return handlePopupAction(id, action, arg)

proc handleCallback*(id: int, args: JsonNode): bool = handleCallbackImpl(id, args)
