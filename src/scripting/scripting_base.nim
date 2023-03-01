import std/[macros, macrocache, json, strutils]
import custom_logger, expose, popup, document_editor

type ScriptContext* = ref object of RootObj
  discard

method init*(self: ScriptContext, path: string) {.base.} = discard
method reload*(self: ScriptContext) {.base.} = discard

method handleUnknownPopupAction*(self: ScriptContext, popup: Popup, action: string, arg: JsonNode): bool {.base.} = discard
method handleUnknownDocumentEditorAction*(self: ScriptContext, editor: DocumentEditor, action: string, arg: JsonNode): bool {.base.} = discard
method handleGlobalAction*(self: ScriptContext, action: string, arg: JsonNode): bool {.base.} = discard

proc generateScriptingApiPerModule*() {.compileTime.} =
  var imports_content = "import \"../src/scripting_api\"\nexport scripting_api\n\n## This file is auto generated, don't modify.\n\n"

  for name, list in exposedFunctions:
    var script_api_content = "import std/[json]\nimport \"../src/scripting_api\"\nwhen defined(js):\n  import absytree_internal_js\nelse:\n  import absytree_internal\n\n## This file is auto generated, don't modify.\n\n"
    var mappings = newJObject()

    # Add the wrapper for the script function (already stored as string repr)
    var lineNumber = script_api_content.countLines()
    for f in list:
      let code = f[0].strVal
      mappings[$lineNumber] = newJString(f[1].strVal)
      script_api_content.add code
      lineNumber += code.countLines - 1

    let file_name = name.replace(".", "_")
    writeFile(fmt"scripting/{file_name}_api.nim", script_api_content)
    writeFile(fmt"int/{file_name}_api.map", $mappings)
    imports_content.add fmt"import {file_name}_api" & "\n"
    imports_content.add fmt"export {file_name}_api" & "\n"


  writeFile(fmt"scripting/absytree_api.nim", imports_content)