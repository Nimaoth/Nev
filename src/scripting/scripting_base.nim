import std/[macros, macrocache, json, strutils]
import misc/[custom_logger, custom_async]
import expose, document_editor, compilation_config

type ScriptContext* = ref object of RootObj
  discard

method init*(self: ScriptContext, path: string): Future[void] {.base.} = discard
method deinit*(self: ScriptContext) {.base.} = discard
method reload*(self: ScriptContext): Future[void] {.base.} = discard

method handleEditorModeChanged*(self: ScriptContext, editor: DocumentEditor, oldMode: string, newMode: string) {.base.} = discard
method postInitialize*(self: ScriptContext): bool {.base.} = discard
method handleCallback*(self: ScriptContext, id: int, arg: JsonNode): bool {.base.} = discard
method handleAnyCallback*(self: ScriptContext, id: int, arg: JsonNode): JsonNode {.base.} = discard
method handleScriptAction*(self: ScriptContext, name: string, args: JsonNode): JsonNode {.base.} = discard
method getCurrentContext*(self: ScriptContext): string {.base.} = ""

proc generateScriptingApiPerModule*() {.compileTime.} =
  var imports_content = "import \"../src/scripting_api\"\nexport scripting_api\n\n## This file is auto generated, don't modify.\n\n"

  for moduleName, list in exposedFunctions:
    when enableNimscript:
      var script_api_content = """
import std/[json, options]
import "../src/scripting_api"
import plugin_api_internal

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
import std/[json, options]
import scripting_api, misc/myjsonutils

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

    when enableNimscript:
      echo fmt"Writing scripting/{file_name}_api.nim"
      writeFile(fmt"scripting/{file_name}_api.nim", script_api_content)

      # todo: separate map files for wasm
      echo fmt"Writing int/{file_name}_api.map"
      writeFile(fmt"int/{file_name}_api.map", $mappings)

    echo fmt"Writing scripting/{file_name}_api_wasm.nim"
    writeFile(fmt"scripting/{file_name}_api_wasm.nim", script_api_content_wasm)

    imports_content.add "when defined(wasm):\n"
    imports_content.add fmt"  import {file_name}_api_wasm" & "\n"
    imports_content.add fmt"  export {file_name}_api_wasm" & "\n"
    imports_content.add "else:\n"
    imports_content.add fmt"  import {file_name}_api" & "\n"
    imports_content.add fmt"  export {file_name}_api" & "\n"

  when enableAst:
    imports_content.add "\nconst enableAst* = true\n"
  else:
    imports_content.add "\nconst enableAst* = false\n"

  echo fmt"Writing scripting/plugin_api.nim"
  writeFile(fmt"scripting/plugin_api.nim", imports_content)