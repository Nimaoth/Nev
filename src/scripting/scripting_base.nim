import std/[macros, macrocache, json, strutils]
import custom_logger, custom_async, expose, popup, document_editor

type ScriptContext* = ref object of RootObj
  discard

method init*(self: ScriptContext, path: string): Future[void] {.base.} = discard
method reload*(self: ScriptContext) {.base.} = discard

method handleUnknownPopupAction*(self: ScriptContext, popup: Popup, action: string, arg: JsonNode): bool {.base.} = discard
method handleUnknownDocumentEditorAction*(self: ScriptContext, editor: DocumentEditor, action: string, arg: JsonNode): bool {.base.} = discard
method handleGlobalAction*(self: ScriptContext, action: string, arg: JsonNode): bool {.base.} = discard
method handleDocumentEditorModeChanged*(self: ScriptContext, editor: DocumentEditor, oldMode: string, newMode: string) {.base.} = discard
method postInitialize*(self: ScriptContext): bool {.base.} = discard
method handleCallback*(self: ScriptContext, id: int, arg: JsonNode): bool {.base.} = discard

proc generateScriptingApiPerModule*() {.compileTime.} =
  var imports_content = "import \"../src/scripting_api\"\nexport scripting_api\n\n## This file is auto generated, don't modify.\n\n"

  for moduleName, list in exposedFunctions:
    var script_api_content = """
import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
elif defined(wasm):
  # import absytree_internal_wasm
  discard
else:
  import absytree_internal

## This file is auto generated, don't modify.

"""

    var mappings = newJObject()

    # Add the wrapper for the script function (already stored as string repr)
    var lineNumber = script_api_content.countLines()
    for f in list:
      let code = f[0].strVal
      mappings[$lineNumber] = newJString(f[1].strVal)
      script_api_content.add code
      lineNumber += code.countLines - 1

    var script_api_content_wasm = """
import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.

"""

    for m, list in wasmImportedFunctions:
      if moduleName != m:
        continue
      for f in list:
        script_api_content_wasm.add f[2].repr
        script_api_content_wasm.add "\n"
        script_api_content_wasm.add f[1].repr
        script_api_content_wasm.add "\n"

    let file_name = moduleName.replace(".", "_")
    writeFile(fmt"scripting/{file_name}_api.nim", script_api_content)
    writeFile(fmt"scripting/{file_name}_api_wasm.nim", script_api_content_wasm)
    writeFile(fmt"int/{file_name}_api.map", $mappings)
    imports_content.add "when defined(wasm):\n"
    imports_content.add fmt"  import {file_name}_api_wasm" & "\n"
    imports_content.add fmt"  export {file_name}_api_wasm" & "\n"
    imports_content.add "else:\n"
    imports_content.add fmt"  import {file_name}_api" & "\n"
    imports_content.add fmt"  export {file_name}_api" & "\n"


  writeFile(fmt"scripting/absytree_api.nim", imports_content)