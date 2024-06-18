import std/[strutils, sequtils, tables]
import absytree_runtime

proc handleAction*(action: string, args: JsonNode): bool {.wasmexport.} =
  return false

proc handlePopupAction*(popup: EditorId, action: string, args: JsonNode): bool {.wasmexport.} =
  return false

proc handleDocumentEditorAction*(id: EditorId, action: string, args: JsonNode): bool {.wasmexport.} =
  return false

proc handleTextEditorAction*(editor: TextDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} =
  return false

proc handleModelEditorAction*(editor: ModelDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} =
  return false

proc postInitialize*(): bool {.wasmexport.} =
  return true

proc loadConfigFromJson*(file: string) {.expose("load-config-from-json").} =
  try:
    let str = loadApplicationFile(file).get
    let json = str.parseJson()
    # setOption "editor.text.lsp", json

  except:
    info &"Failed to load lsp config from file: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc loadKeybindingsFromJson*(file: string) {.expose("load-keybindings-from-json").} =
  try:
    let str = loadApplicationFile(file).get
    let json = str.parseJson()
    for (scope, commands) in json.fields.pairs:
      for (keys, command) in commands.fields.pairs:
        if command.kind == JString:
          let commandStr = command.getStr
          let spaceIndex = commandStr.find(" ")

          let (name, args) = if spaceIndex == -1:
            (commandStr, "")
          else:
            (commandStr[0..<spaceIndex], commandStr[spaceIndex+1..^1])

          infof"addCommandScript {scope}, {keys}, {name}, {args}"
          addCommandScript(scope, "", keys, name, args)

        elif command.kind == JObject:
          let name = command["command"].getStr
          let args = command["args"].elems.mapIt($it).join(" ")
          infof"addCommandScript {scope}, {keys}, {name}, {args}"
          addCommandScript(scope, "", keys, name, args)

  except:
    info &"Failed to load lsp config from file: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

when defined(wasm):
  include absytree_runtime_impl
