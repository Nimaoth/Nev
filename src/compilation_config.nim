import std/strutils

const exposeScriptingApi* {.booldefine.}: bool = false
const enableGui* {.booldefine.}: bool = false
const enableTerminal* {.booldefine.}: bool = false
const enableTableIdCacheChecking* {.booldefine.}: bool = false
const enableSystemClipboard* {.booldefine.}: bool = true
const enableNimscript* {.booldefine.}: bool = false
const enableAst* {.booldefine.}: bool = false
const copyWasmtimeDll* {.booldefine.}: bool = true

const treesitterBuiltins {.strdefine.}: string = ""
const builtinTreesitterLanguages: seq[string] = treesitterBuiltins.split(",")

func useBuiltinTreesitterLanguage*(name: string): bool = builtinTreesitterLanguages.contains(name)

static:
  echo "Builtin treesitter languages: ", builtinTreesitterLanguages

when enableNimscript:
  static:
    echo "Nimscript plugin api enabled"

when enableAst:
  static:
    echo "Ast framework enabled"

when not defined(js):
  when not enableGui and not enableTerminal:
    {.error: "No backend enabled".}