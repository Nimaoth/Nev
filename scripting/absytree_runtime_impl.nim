import absytree_runtime
import misc/[event]

proc handleCallback*(id: int, args: JsonNode): bool = handleCallbackImpl(id, args)
proc handleAnyCallback*(id: int, args: JsonNode): JsonNode = handleAnyCallbackImpl(id, args)
proc handleScriptAction*(name: string, args: JsonNode): JsonNode = handleScriptActionImpl(name, args)
proc handleGlobalAction*(action: string, args: JsonNode): bool = handleAction(action, args)

proc handleEditorAction*(id: EditorId, action: string, args: JsonNode): bool =
  # infof"handleEditorAction {id} {action} {args}"
  if id.isTextEditor(editor):
    return handleTextEditorAction(editor, action, args)

  elif id.isModelEditor(editor):
    return handleModelEditorAction(editor, action, args)

  return handleDocumentEditorAction(id, action, args)

proc handleUnknownPopupAction*(id: EditorId, action: string, args: JsonNode): bool =
  return handlePopupAction(id, action, args)

proc handleEditorModeChanged*(editor: EditorId, oldMode: string, newMode: string) =
  # infof"handleEditorModeChanged {editor} {oldMode} {newMode}"
  onEditorModeChanged.invoke (editor, oldMode, newMode)

when defined(wasm):
  proc postInitializeWasm(): bool {.wasmexport.} =
    try:
      return postInitialize()
    except:
      info &"postInitializeWasm failed: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return false

  proc handleGlobalActionWasm(action: cstring, args: cstring): bool {.wasmexport.} =
    try:
      return handleGlobalAction($action, ($args).parseJson)
    except:
      info &"handleGlobalActionWasm failed: {action} {args}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return false

  proc handleUnknownDocumentEditorActionWasm(id: int32, action: cstring, args: cstring): bool {.wasmexport.} =
    # infof"handleUnknownDocumentEditorActionWasm {id} {action} {args}"
    try:
      return handleEditorAction(id.EditorId, $action, ($args).parseJson)
    except:
      info &"handleUnknownDocumentEditorActionWasm failed: {id} {action} {args}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return false

  proc handleEditorModeChangedWasm(id: int32, oldMode: cstring, newMode: cstring) {.wasmexport.} =
    # infof"handleEditorModeChangedWasm {id} {oldMode} {newMode}"
    try:
      handleEditorModeChanged(id.EditorId, $oldMode, $newMode)
    except:
      info &"handleEditorModeChangedWasm failed: {id} {oldMode} {newMode}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

  proc handleUnknownPopupActionWasm(id: int32, action: cstring, args: cstring): bool {.wasmexport.} =
    try:
      return handleUnknownPopupAction(id.EditorId, $action, ($args).parseJson)
    except:
      info &"handleUnknownPopupAction failed: {id} {action} {args}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return false

  proc handleCallbackWasm(id: int32, args: cstring): bool {.wasmexport.} =
    try:
      return handleCallback(id.int, ($args).parseJson)
    except:
      info &"handleCallbackWasm failed: {id} {args}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return false

  proc handleAnyCallbackWasm(id: int32, args: cstring): cstring {.wasmexport.} =
    # infof"handleAnyCallbackWasm {id.int} {args}"
    try:
      let res = handleAnyCallback(id.int, ($args).parseJson)
      if res.isNil:
        return ""
      return cstring $res
    except:
      info &"handleAnyCallbackWasm failed: {id.int} {args}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return cstring ("error: " & getCurrentExceptionMsg())

  proc handleScriptActionWasm(name: cstring, args: cstring): cstring {.wasmexport.} =
    # infof"handleScriptActionWasm {name} {args}"
    try:
      let res = handleScriptAction($name, ($args).parseJson)
      if res.isNil:
        return ""
      return cstring $res
    except:
      info &"handleScriptActionWasm failed: {name} '{args}': {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return cstring("error: " & getCurrentExceptionMsg())