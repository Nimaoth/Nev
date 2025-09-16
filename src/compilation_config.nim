import std/[strutils, strformat]

const exposeScriptingApi* {.booldefine.}: bool = false
const enableGui* {.booldefine.}: bool = false
const enableTerminal* {.booldefine.}: bool = false
const enableTableIdCacheChecking* {.booldefine.}: bool = false
const enableSystemClipboard* {.booldefine.}: bool = true
const enableAst* {.booldefine.}: bool = false
const enableOldPluginVersions* {.booldefine.}: bool = false
const enableLibssh* {.booldefine.}: bool = false
const copyWasmtimeDll* {.booldefine.}: bool = true
const appName* {.strdefine.}: string = "nev"

const treesitterBuiltins {.strdefine.}: string = ""
const builtinTreesitterLanguages: seq[string] = treesitterBuiltins.split(",")

const configDirName* = "." & appName
const defaultSessionName* = &".{appName}-session"
const appConfigDir* = "app://config"
const homeConfigDir* = "home://" & configDirName
const workspaceConfigDir* = "ws0://" & configDirName

func useBuiltinTreesitterLanguage*(name: string): bool = builtinTreesitterLanguages.contains(name)

static:
  echo "Builtin treesitter languages: ", builtinTreesitterLanguages

when enableAst:
  static:
    echo "Ast framework enabled"

when not enableGui and not enableTerminal:
  {.error: "No backend enabled".}
