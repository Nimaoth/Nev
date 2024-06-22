import absytree_runtime

{.used.}

let useLSPWebsocketProxy = getBackend() == Browser

if useLSPWebsocketProxy:
  setOption "editor.text.languages-server.url", "localhost"
  setOption "editor.text.languages-server.port", 3001
else:
  setOption "editor.text.languages-server.url", ""
  setOption "editor.text.languages-server.port", 0

proc loadSnippetsFromFile*(file: string, language: string) {.expose("load-snippets-from-file").} =
  try:
    let str = loadApplicationFile(file).get
    let json = str.parseJson()
    infof"Loaded snippet config for {language} from {file}"
    # todo: better deal with languages
    setOption "editor.text.snippets." & language, json
  except:
    info &"Failed to load lsp config from file: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc loadVSCodeDebuggerConfig*(file: string) {.expose("load-vscode-debugger-config").} =
  try:
    let str = loadApplicationFile(file).get
    let json = str.parseJson()
    infof"Loaded debugger config from {file}"
    for value in json["configurations"].elems:
      setOption "debugger.configuration." & value["name"].getStr, value
  except:
    info &"Failed to load debugger config from file: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

