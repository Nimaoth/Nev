import absytree_runtime
import misc/[event]

proc handleGlobalAction*(action: string, args: JsonNode): bool =
  if action == "lambda-action":
    return handleLambdaAction(args)
  return handleAction(action, args)

proc handleEditorAction*(id: EditorId, action: string, args: JsonNode): bool =
  if action == "lambda-action":
    return handleLambdaAction(args)

  if id.isTextEditor(editor):
    return handleTextEditorAction(editor, action, args)

  elif id.isModelEditor(editor):
    return handleModelEditorAction(editor, action, args)

  return handleDocumentEditorAction(id, action, args)

proc handleUnknownPopupAction*(id: EditorId, action: string, args: JsonNode): bool =
  return handlePopupAction(id, action, args)

proc handleEditorModeChanged*(editor: EditorId, oldMode: string, newMode: string) =
  onEditorModeChanged.invoke (editor, oldMode, newMode)

proc handleCallback*(id: int, args: JsonNode): bool = handleCallbackImpl(id, args)
proc handleScriptAction*(name: string, args: JsonNode): JsonNode = handleScriptActionImpl(name, args)

when defined(wasm):
  proc postInitializeWasm(): bool {.wasmexport.} =
    return postInitialize()

  proc handleGlobalActionWasm(action: cstring, args: cstring): bool {.wasmexport.} =
    return handleGlobalAction($action, ($args).parseJson)

  proc handleUnknownDocumentEditorActionWasm(id: int32, action: cstring, args: cstring): bool {.wasmexport.} =
    return handleEditorAction(id.EditorId, $action, ($args).parseJson)

  proc handleEditorModeChangedWasm(id: int32, oldMode: cstring, newMode: cstring) {.wasmexport.} =
    handleEditorModeChanged(id.EditorId, $oldMode, $newMode)

  proc handleUnknownPopupActionWasm(id: int32, action: cstring, args: cstring): bool {.wasmexport.} =
    return handleUnknownPopupAction(id.EditorId, $action, ($args).parseJson)

  proc handleCallbackWasm(id: int32, args: cstring): bool {.wasmexport.} =
    return handleCallback(id.int, ($args).parseJson)

  proc handleScriptActionWasm(name: cstring, args: cstring): cstring {.wasmexport.} =
    let res = $handleScriptAction($name, ($args).parseJson)
    return res.cstring