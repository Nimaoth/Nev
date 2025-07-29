import std/[compilesettings]
import plugin_runtime
import misc/[event, embed_source]

generateEmbeddedSourceMap()

const projPath = querySetting(SingleValueSetting.projectPath).normalizeSourcePath & "/"

for path, content in embeddedSourceFiles():
  let relPath = if path.startsWith(projPath):
    path[projPath.len..^1]
  else:
    path
  registerPluginSourceCode(relPath, content)

proc handleCallback*(id: int, args: JsonNode): bool = handleCallbackImpl(id, args)
proc handleAnyCallback*(id: int, args: JsonNode): JsonNode = handleAnyCallbackImpl(id, args)
proc handleScriptAction*(name: string, args: JsonNode): JsonNode = handleScriptActionImpl(name, args)

proc postInitializeWasm(): bool {.wasmexport.} =
  when compiles(postInitialize()):
    try:
      return postInitialize()
    except:
      info &"postInitializeWasm failed: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return false
  else:
    true

proc handleCallbackWasm(id: int32, args: cstring): bool {.wasmexport.} =
  try:
    return handleCallback(id.int, ($args).parseJson)
  except:
    info &"handleCallbackWasm failed: {id} {args}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
    return false

var handleAnyCallbackWasmResult = ""
proc handleAnyCallbackWasm(id: int32, args: cstring): cstring {.wasmexport.} =
  # infof"handleAnyCallbackWasm {id.int} {args}"
  try:
    let res = handleAnyCallback(id.int, ($args).parseJson)
    if res.isNil:
      return ""
    handleAnyCallbackWasmResult = $res
    return handleAnyCallbackWasmResult.cstring
  except:
    info &"handleAnyCallbackWasm failed: {id.int} {args}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
    return cstring ("error: " & getCurrentExceptionMsg())

var handleScriptActionWasmResult = ""
proc handleScriptActionWasm(name: cstring, args: cstring): cstring {.wasmexport.} =
  # infof"handleScriptActionWasm {name} {args}"
  try:
    let res = handleScriptAction($name, ($args).parseJson)
    if res.isNil:
      return ""
    handleScriptActionWasmResult = $res
    return handleScriptActionWasmResult.cstring
  except:
    info &"handleScriptActionWasm failed: {name} '{args}': {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
    handleScriptActionWasmResult = "error: " & getCurrentExceptionMsg()
    return handleScriptActionWasmResult.cstring
