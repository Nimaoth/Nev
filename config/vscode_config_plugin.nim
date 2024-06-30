import absytree_runtime
import std/options

## This plugin adds commands to load certain VSCode configuration files
## like snippets and launch configurations.

proc loadVSCodeSnippets*(file: string, language: string) {.expose("load-vscode-snippets").} =
  loadWorkspaceFile file, proc(content: Option[string]) =
    if content.isNone:
      return

    try:
      let json = content.get.parseJson()
      infof"Loaded snippet config for {language} from {file}"
      # todo: better deal with languages
      setOption "snippets." & language, json
    except:
      info &"Failed to load VSCode snippets: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc loadVSCodeDebuggerConfig*(file: string) {.expose("load-vscode-debugger-config").} =
  loadWorkspaceFile file, proc(content: Option[string]) =
    if content.isNone:
      return

    try:
      let json = content.get.parseJson()
      infof"Loaded debugger config from {file}"
      for value in json["configurations"].elems:
        setOption "debugger.configuration." & value["name"].getStr, value
    except:
      info &"Failed to load debugger config: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

include absytree_runtime_impl
