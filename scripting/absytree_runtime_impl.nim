import absytree_runtime

proc handleGlobalAction*(action: string, args: JsonNode): bool =
  if action == "lambda-action":
    return handleLambdaAction(args)
  return handleAction(action, args)

proc handleEditorAction*(id: EditorId, action: string, args: JsonNode): bool =
  if action == "lambda-action":
    return handleLambdaAction(args)

  if id.isTextEditor(editor):
    return handleTextEditorAction(editor, action, args)

  elif id.isAstEditor(editor):
    return handleAstEditorAction(editor, action, args)

  return handleDocumentEditorAction(id, action, args)

proc handleUnknownPopupAction*(id: EditorId, action: string, args: JsonNode): bool =
  return handlePopupAction(id, action, args)

proc handleCallback*(id: int, args: JsonNode): bool = handleCallbackImpl(id, args)
