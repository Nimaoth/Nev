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
    setOption "", json, override=false

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
    info &"Failed to load keybindings from file: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc loadLspConfigFromJson*(file: string = "config/lsp.json") {.expose("load-lsp-config-from-json").} =
  try:
    let str = loadApplicationFile(file).get
    let json = str.parseJson()
    infof"Loaded lsp config from file"
    setOption "editor.text.lsp", json
  except:
    info &"Failed to load lsp config from file: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc loadSnippetsFromJson*(file: string, language: string) {.expose("load-snippets-from-json").} =
  try:
    let str = loadApplicationFile(file).get
    let json = str.parseJson()
    infof"Loaded snippet config for {language} from {file}"
    # todo: better deal with languages
    setOption "editor.text.snippets." & language, json
  except:
    info &"Failed to load lsp config from file: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc loadDebuggerConfigFromJson*(file: string) {.expose("load-debugger-config-from-json").} =
  try:
    let str = loadApplicationFile(file).get
    let json = str.parseJson()
    infof"Loaded debugger config from {file}"
    for key, value in json.fields.pairs:
      setOption "debugger.configuration." & key, value
  except:
    info &"Failed to load debugger config from file: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc loadVSCodeDebuggerConfigFromJson*(file: string) {.expose("load-vscode-debugger-config-from-json").} =
  try:
    let str = loadApplicationFile(file).get
    let json = str.parseJson()
    infof"Loaded debugger config from {file}"
    for value in json["configurations"].elems:
      setOption "debugger.configuration." & value["name"].getStr, value
  except:
    info &"Failed to load debugger config from file: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

when defined(wasm):
  include absytree_runtime_impl
