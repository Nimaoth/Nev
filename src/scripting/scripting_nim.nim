when defined(js):
  {.error: "scripting_nim.nim does not work in js backend. Use scripting_js.nim instead.".}

import std/[os, tables, strformat, json, strutils, macrocache, macros]
import fusion/matching
import compiler/[renderer, ast, llstream, lineinfos]
import compiler/options as copts
from compiler/vmdef import TSandboxFlag
import nimscripter, nimscripter/[vmconversion, vmaddins]

import util, custom_logger, scripting_base, compilation_config, expose, popup, document_editor
import scripting_api as api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, Popup, SelectorPopup

export scripting_base, nimscripter

type ScriptContextNim* = ref object of ScriptContext
  inter*: Option[Interpreter]
  script: NimScriptPath
  apiModule: string # The module in which functions exposed to the script will be implemented using `implementRoutine`
  addins: VMAddins
  postCodeAdditions: string # Text which gets appended to the script before being executed
  searchPaths: seq[string]

let stdPath = "D:/.choosenim/toolchains/nim-#devel/lib"

let loggerPtr = addr logger

proc errorHook(config: ConfigRef; info: TLineInfo; msg: string; severity: Severity) {.gcsafe.} =
  if (severity == Error or severity == Warning) and config.errorCounter >= config.errorMax:
    var fileName: string
    for k, v in config.m.filenameToIndexTbl.pairs:
      if v == info.fileIndex:
        fileName = k

    var line = info.line
    if fileName == "absytree_config":
      line -= 935
    loggerPtr[].log(lvlError, fmt"[vm {severity}]: {fileName}:{line}:{(info.col + 1)} {msg}.")
    raise (ref VMQuit)(info: info, msg: msg)

proc setGlobalVariable*[T](intr: Option[Interpreter] or Interpreter; name: string, value: T) =
  ## Easy access of a global nimscript variable
  when intr is Option[Interpreter]:
    assert intr.isSome
    let intr = intr.get
  let sym = intr.selectUniqueSymbol(name)
  if sym != nil:
    intr.setGlobalValue(sym, toVm(value))
  else:
    raise newException(VmSymNotFound, name & " is not a global symbol in the script.")

const defaultDefines = @{"nimscript": "true", "nimconfig": "true"}

proc getSearchPath(path: string): seq[string] =
  result.add path
  for dir in walkDirRec(path, {pcDir}):
    result.add dir

proc myLoadScript(
  script: NimScriptFile or NimScriptPath;
  apiModule: string,
  addins: VMAddins;
  postCodeAdditions: string,
  modules: varargs[string];
  vmErrorHook: proc(config: ConfigRef; info: TLineInfo; msg: string; severity: Severity) {.gcsafe.};
  stdPath: string;
  searchPaths: sink seq[string] = @[];
  defines = defaultDefines): Option[Interpreter] =
  ## Loads an interpreter from a file or from string, with given addtions and userprocs.
  ## To load from the filesystem use `NimScriptPath(yourPath)`.
  ## To load from a string use `NimScriptFile(yourFile)`.
  ## `addins` is the overrided procs/addons from `impleNimScriptModule
  ## `modules` implict imports to add to the module.
  ## `stdPath` to use shipped path instead of finding it at compile time.
  ## `vmErrorHook` a callback which should raise `VmQuit`, refer to `errorHook` for reference.
  ## `searchPaths` optional paths one can use to supply libraries or packages for the
  const isFile = script is NimScriptPath
  if not isFile or fileExists(script.string):
    var additions = addins.additions
    for `mod` in modules: # Add modules
      additions.insert("import " & `mod` & "\n", 0)

    var searchPaths = getSearchPath(stdPath) & searchPaths
    let scriptName = when isFile: script.string.splitFile.name else: "script"

    when isFile: # If is file we want to enable relative imports
      searchPaths.add script.string.parentDir

    let
      intr = createInterpreter(scriptName, searchPaths, flags = {allowInfiniteLoops},
        defines = defines
      )
      script = when isFile: readFile(script.string) else: script.string

    for uProc in addins.procs:
      intr.implementRoutine("Absytree", apiModule, uProc.name, uProc.vmProc)

    intr.registerErrorHook(vmErrorHook)
    try:
      additions.add script
      additions.add addins.postCodeAdditions
      additions.add "\n"
      additions.add postCodeAdditions
      when defined(debugScript):
        writeFile("debugscript.nims", additions)
      intr.evalScript(llStreamOpen(additions))
      result = option(intr)
    except VMQuit: discard

proc mySafeLoadScriptWithState*(
  intr: var Option[Interpreter];
  script: NimScriptFile or NimScriptPath;
  apiModule: string,
  addins: VMAddins = VMaddins();
  postCodeAdditions: string,
  modules: varargs[string];
  vmErrorHook: proc(config: ConfigRef; info: TLineInfo; msg: string; severity: Severity) {.gcsafe.};
  stdPath: string;
  searchPaths: sink seq[string] = @[];
  defines = defaultDefines) =
  ## Same as loadScriptWithState but saves state then loads the intepreter into `intr` if there were no script errors.
  ## Tries to keep the interpreter running.
  let state =
    if intr.isSome:
      intr.get.saveState()
    else:
      @[]
  let tempIntr = myLoadScript(script, apiModule, addins, postCodeAdditions, modules, vmErrorHook, stdPath, searchPaths, defines)
  if tempIntr.isSome:
    intr = tempIntr
    intr.get.loadState(state)

proc newScriptContext*(path: string, apiModule: string, addins: VMAddins, postCodeAdditions: string, searchPaths: seq[string]): ScriptContextNim =
  new result
  result.script = NimScriptPath(path)
  result.apiModule = apiModule
  result.addins = addins
  result.postCodeAdditions = postCodeAdditions
  result.searchPaths = searchPaths
  logger.log(lvlInfo, fmt"Creating new script context (search paths: {searchPaths})")
  result.inter = myLoadScript(result.script, apiModule, addins, postCodeAdditions, ["scripting_api", "std/json"], stdPath = stdPath, searchPaths = searchPaths, vmErrorHook = errorHook)

method reload*(ctx: ScriptContextNim) =
  logger.log(lvlInfo, fmt"Reloading script context (search paths: {ctx.searchPaths})")
  ctx.inter.mySafeLoadScriptWithState(ctx.script, ctx.apiModule, ctx.addins, ctx.postCodeAdditions, ["scripting_api", "std/json"], stdPath = stdPath, searchPaths = ctx.searchPaths, vmErrorHook = errorHook)

proc generateScriptingApi*(addins: VMAddins) {.compileTime.} =
  if exposeScriptingApi:
    echo "Generate scripting api files"

    var script_internal_content = "import std/[json]\nimport \"../src/scripting_api\"\n\n## This file is auto generated, don't modify.\n\n"
    createDir("scripting")
    createDir("int")

    # Add stub proc impls generated by nimscripter
    for uProc in addins.procs:
      var impl = uProc.vmRunImpl

      # Hack to make these functions public
      let parenIndex = impl.find("(")
      if parenIndex > 0 and impl[parenIndex - 1] != '*':
        impl.insert("*", parenIndex)

      script_internal_content.add impl
    writeFile(fmt"scripting/absytree_internal.nim", script_internal_content)

    generateScriptingApiPerModule()

macro createScriptContextConstructor*(addins: untyped): untyped =
  return quote do:
    proc createScriptContextNim(filepath: string, searchPaths: seq[string]): ScriptContext =
      return newScriptContext(filepath, "absytree_internal", `addins`, "include absytree_runtime_impl", searchPaths)

macro invoke*(self: ScriptContext; pName: untyped;
    args: varargs[typed]; returnType: typedesc = void): untyped =
  ## Invoke but takes an option and unpacks it, if `intr.`isNone, assertion is raised
  let inter = quote do:
    `self`.ScriptContextNim.inter.get
  result = newCall("invokeDynamic", inter, pName.toStrLit)
  for x in args:
    result.add x
  result.add nnkExprEqExpr.newTree(ident"returnType", returnType)

method handleUnknownPopupAction*(self: ScriptContextNim, popup: Popup, action: string, arg: JsonNode): bool =
  return self.invoke(handleUnknownPopupAction, popup.id, action, arg, returnType = bool)

method handleUnknownDocumentEditorAction*(self: ScriptContextNim, editor: DocumentEditor, action: string, arg: JsonNode): bool =
  return self.invoke(handleEditorAction, editor.id, action, arg, returnType = bool)

method handleGlobalAction*(self: ScriptContextNim, action: string, arg: JsonNode): bool =
  return self.invoke(handleGlobalAction, action, arg, returnType = bool)