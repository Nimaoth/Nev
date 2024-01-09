import absytree_runtime
import misc/[event]

proc handleCallback*(id: int, args: JsonNode): bool = handleCallbackImpl(id, args)
proc handleAnyCallback*(id: int, args: JsonNode): JsonNode = handleAnyCallbackImpl(id, args)
proc handleScriptAction*(name: string, args: JsonNode): JsonNode = handleScriptActionImpl(name, args)

proc handleGlobalAction*(action: string, args: JsonNode): bool =
  if action == "lambda-action":
    return handleLambdaAction(args)
  return handleAction(action, args)

proc handleEditorAction*(id: EditorId, action: string, args: JsonNode): bool =
  # infof"handleEditorAction {id} {action} {args}"
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

when defined(wasm):
  proc postInitializeWasm(): bool {.wasmexport.} =
    try:
      return postInitialize()
    except:
      infof "postInitializeWasm failed: {getCurrentExceptionMsg()}"
      return false

  proc handleGlobalActionWasm(action: cstring, args: cstring): bool {.wasmexport.} =
    try:
      return handleGlobalAction($action, ($args).parseJson)
    except:
      infof "handleGlobalActionWasm failed: {action} {args}: {getCurrentExceptionMsg()}"
      return false

  proc handleUnknownDocumentEditorActionWasm(id: int32, action: cstring, args: cstring): bool {.wasmexport.} =
    # infof"handleUnknownDocumentEditorActionWasm {id} {action} {args}"
    try:
      return handleEditorAction(id.EditorId, $action, ($args).parseJson)
    except:
      infof "handleUnknownDocumentEditorActionWasm failed: {id} {action} {args}: {getCurrentExceptionMsg()}"
      return false

  proc handleEditorModeChangedWasm(id: int32, oldMode: cstring, newMode: cstring) {.wasmexport.} =
    try:
      handleEditorModeChanged(id.EditorId, $oldMode, $newMode)
    except:
      infof "handleEditorModeChangedWasm failed: {id} {oldMode} {newMode}: {getCurrentExceptionMsg()}"

  proc handleUnknownPopupActionWasm(id: int32, action: cstring, args: cstring): bool {.wasmexport.} =
    try:
      return handleUnknownPopupAction(id.EditorId, $action, ($args).parseJson)
    except:
      infof "handleUnknownPopupAction failed: {id} {action} {args}: {getCurrentExceptionMsg()}"
      return false

  proc handleCallbackWasm(id: int32, args: cstring): bool {.wasmexport.} =
    try:
      return handleCallback(id.int, ($args).parseJson)
    except:
      infof "handleCallbackWasm failed: {id} {args}: {getCurrentExceptionMsg()}"
      return false

  proc handleAnyCallbackWasm(id: int32, args: cstring): cstring {.wasmexport.} =
    # infof"handleAnyCallbackWasm {id.int} {args}"
    try:
      let res = handleAnyCallback(id.int, ($args).parseJson)
      if res.isNil:
        return ""
      return cstring $res
    except:
      infof "handleAnyCallbackWasm failed: {id.int} {args}: {getCurrentExceptionMsg()}"
      return "error: " & getCurrentExceptionMsg()

  proc handleScriptActionWasm(name: cstring, args: cstring): cstring {.wasmexport.} =
    # infof"handleScriptActionWasm {name} {args}"
    try:
      let res = handleScriptAction($name, ($args).parseJson)
      if res.isNil:
        return ""
      return cstring $res
    except CatchableError as e:
      echo e.msg
      infof "handleScriptActionWasm failed: {args}: {getCurrentExceptionMsg()}"
      return "error: " & getCurrentExceptionMsg()