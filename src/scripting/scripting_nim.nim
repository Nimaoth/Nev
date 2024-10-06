when defined(js):
  {.error: "scripting_nim.nim does not work in js backend.".}

import std/[os, osproc, tables, strformat, json, strutils, macrocache, macros, genasts, sugar]
from logging import nil
import fusion/matching
import compiler/[renderer, ast, llstream, lineinfos]
import compiler/options as copts
from compiler/vmdef import TSandboxFlag
import nimscripter, nimscripter/[vmconversion, vmaddins]

import misc/[util, custom_logger, custom_async, timer]
import platform/filesystem
import scripting_base, compilation_config, popup, document_editor
import scripting_api as api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, Popup, SelectorPopup

export scripting_base, nimscripter

logCategory "scripting-nim"

type InterpreterState = enum Uninitialized, Initializing, Initialized

type ScriptContextNim* = ref object of ScriptContext
  state: InterpreterState = Uninitialized
  inter*: Option[Interpreter]
  script: NimScriptPath
  apiModule: string # The module in which functions exposed to the script will be implemented using `implementRoutine`
  addins: VMAddins
  postCodeAdditions: string # Text which gets appended to the script before being executed
  searchPaths: seq[string]
  stdPath: string

let loggerPtr = addr logger

proc myGetTime*(): int32 = timer.myGetTime()
proc myGetTicks(): int64 = timer.myGetTicks()
proc mySubtractTicks(a: int64, b: int64): int64 = timer.mySubtractTicks(a, b)

exportTo(timerAddinsImpl, myGetTime, myGetTicks, mySubtractTicks)

var timerAddins: seq[(string, VmAddins)]
timerAddins.add ("timer", implNimScriptModule(timerAddinsImpl))

proc errorHook(config: ConfigRef; info: TLineInfo; msg: string; severity: Severity) {.gcsafe.} =
  if (severity == Error or severity == Warning) and config.errorCounter >= config.errorMax:
    var fileName: string
    for k, v in config.m.filenameToIndexTbl.pairs:
      if v == info.fileIndex:
        fileName = k

    var line = info.line
    if fileName == "custom":
      # todo: calculate this number
      line -= 935
    logging.log(loggerPtr[], lvlError, fmt"[vm {severity}]: {fileName}:{line}:{(info.col + 1)} {msg}.")
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

const defaultDefines = @{"nimscript": "true", "nimvm": "true"}

proc getSearchPath(path: string): seq[string] =
  result.add path
  for dir in walkDirRec(path, {pcDir}):
    result.add dir

proc evalString(intr: Interpreter; code: string) =
  let stream = llStreamOpen(code)
  intr.evalScript(stream)
  llStreamClose(stream)

proc createInterpreterAsync(args: (ptr Interpreter, string, seq[string], seq[(string, string)], VMAddins, seq[(string, VMAddins)], string)): void =
  {.gcsafe.}:
    setUseIc(true)

    var intr = createInterpreter(args[1], args[2], flags = {allowInfiniteLoops}, defines = args[3])

    # todo: how is this name determined?
    const moduleName = appName

    for uProc in args[4].procs:
      intr.implementRoutine(moduleName, args[6], uProc.name, uProc.vmProc)

    for (module, addins) in args[5]:
      for uProc in addins.procs:
        intr.implementRoutine(moduleName, module, uProc.name, uProc.vmProc)

    setUseIc(true)

    let initCode = """
import std/[strformat, sequtils, macros, tables, options, sugar, strutils, genasts, json, typetraits]

import scripting_api
import misc/[util, myjsonutils]
import plugin_runtime
    """
    intr.evalString(initCode)

    args[0][] = intr

proc myCreateInterpreter(
  script: NimScriptFile or NimScriptPath;
  apiModule: string,
  addins: VMAddins;
  stdPath: string;
  searchPaths: sink seq[string] = @[];
  moreAddins: seq[(string, VMAddins)];
  defines = defaultDefines): Future[Option[Interpreter]] {.async.} =

  const isFile = script is NimScriptPath
  let path = when isFile: fs.getApplicationFilePath(script.string) else: ""

  var searchPaths = getSearchPath(stdPath) & searchPaths

  when isFile: # If is file we want to enable relative imports
    searchPaths.add path.parentDir

  let timer = startTimer()
  var intr: Interpreter = nil
  when true:
    await spawnAsync(createInterpreterAsync, (intr.addr, path, searchPaths, defines, addins, moreAddins, apiModule))
    setUseIc(true)
  else:
    createInterpreterAsync((intr.addr, path, searchPaths, defines, addins, moreAddins, apiModule))

  log lvlInfo, fmt"createInterpreter took {timer.elapsed.ms}ms"

  return intr.option

proc myLoadScript(
  intr: Interpreter,
  script: NimScriptFile or NimScriptPath;
  apiModule: string,
  addins: VMAddins;
  postCodeAdditions: string,
  modules: seq[string];
  vmErrorHook: proc(config: ConfigRef; info: TLineInfo; msg: string; severity: Severity) {.gcsafe.};
  stdPath: string;
  searchPaths: sink seq[string] = @[];
  moreAddins: seq[(string, VMAddins)];
  defines = defaultDefines) {.async.} =
  ## Loads an interpreter from a file or from string, with given addtions and userprocs.
  ## To load from the filesystem use `NimScriptPath(yourPath)`.
  ## To load from a string use `NimScriptFile(yourFile)`.
  ## `addins` is the overrided procs/addons from `impleNimScriptModule
  ## `modules` implict imports to add to the module.
  ## `stdPath` to use shipped path instead of finding it at compile time.
  ## `vmErrorHook` a callback which should raise `VmQuit`, refer to `errorHook` for reference.
  ## `searchPaths` optional paths one can use to supply libraries or packages for the
  const isFile = script is NimScriptPath

  var script = script.string
  when isFile:
    try:
      script = fs.loadApplicationFile(script)
    except CatchableError:
      return

  var additions = addins.additions
  for `mod` in modules: # Add modules
    additions.insert("import " & `mod` & "\n", 0)

  intr.registerErrorHook(vmErrorHook)
  try:
    additions.add script
    additions.add "\n"
    additions.add postCodeAdditions
    additions.add "\n"
    # @note 2023-08-20: this current generates code containing generated names which contain `, which is not a valid nim identifier
    # but this right now only includes checks which aren't necessary for running scripts,
    # only for reporting errors of missing functions
    # additions.add addins.postCodeAdditions
    when defined(debugScript):
      writeFile("debugscript.nims", additions)

    log lvlInfo, fmt"evalScript"
    let timer = startTimer()
    intr.evalScript(llStreamOpen(additions))
    log lvlInfo, fmt"evalScript took {timer.elapsed.ms}ms"

  except VMQuit: discard

proc mySafeLoadScriptWithState*(self: ScriptContextNim, modules: seq[string]) {.async.} =
  ## Same as loadScriptWithState but saves state then loads the intepreter into `intr` if there were no script errors.
  ## Tries to keep the interpreter running.
  let state = self.inter.map((i) => i.saveState())
  self.state = Initializing
  let newIntr = await myCreateInterpreter(self.script, self.apiModule, self.addins, self.stdPath, self.searchPaths, timerAddins, defaultDefines)
  self.state = Initialized
  if newIntr.getSome(inter):
    self.inter = inter.some
    await myLoadScript(inter, self.script, self.apiModule, self.addins, self.postCodeAdditions, modules, errorHook, self.stdPath, self.searchPaths, timerAddins, defaultDefines)
    if state.getSome(state):
      inter.loadState(state)

proc myFindNimStdLib(): Option[string] =
  ## Tries to find a path to a valid "system.nim" file.
  ## Returns "" on failure.

  let customNimStdLib = getAppDir() / "scripting" / "nim" / "lib"
  if dirExists(customNimStdLib):
    log lvlInfo, fmt"Using custom nim std lib '{customNimStdLib}'"
    return customNimStdLib.some

  try:
    log lvlInfo, "Searching for nim std lib directory using 'nim --verbosity:0 dump --dump.format:json .'"
    let nimdump = execProcess("nim", ".", ["--verbosity:0", "dump", "--dump.format:json", "."], options={poUsePath, poDaemon})
    let nimdumpJson = try:
      nimdump.parseJson()
    except:
      log lvlError, &"Failed to parse output of nim dump: {getCurrentExceptionMsg()}\n{nimdump}"
      return string.none

    return nimdumpJson["libpath"].getStr("").some
  except OSError, ValueError:
    log lvlError, &"Failed to find nim std path using nim dump: {getCurrentExceptionMsg()}"
    return string.none

proc newScriptContext*(path: string, apiModule: string, addins: VMAddins, postCodeAdditions: string, searchPaths: seq[string], stdPath: Option[string]): Future[Option[ScriptContext]] {.async.} =
  let stdPath = stdPath.getOr:
    myFindNimStdLib().getOr:
      log lvlError, "Failed to find nim std path"
      return ScriptContext.none

  let res = ScriptContextNim()
  res.script = NimScriptPath(path)
  res.apiModule = apiModule
  res.addins = addins
  res.postCodeAdditions = postCodeAdditions
  res.searchPaths = searchPaths
  res.stdPath = stdPath

  log lvlInfo, fmt"Creating new script context (search paths: {searchPaths}, std path: {res.stdPath})"

  return res.ScriptContext.some

method init*(self: ScriptContextNim, path: string, fs: Filesystem): Future[void] {.async.} =
  self.fs = fs
  self.state = Initializing
  self.inter = await myCreateInterpreter(self.script, self.apiModule, self.addins, self.stdPath, self.searchPaths, timerAddins, defaultDefines)
  self.state = Initialized
  if self.inter.getSome(inter):
    await myLoadScript(
      inter,
      self.script, self.apiModule, self.addins, self.postCodeAdditions, @["scripting_api", "std/json", "misc/util", "misc/myjsonutils"],
      stdPath = self.stdPath, searchPaths = self.searchPaths, vmErrorHook = errorHook, moreAddins = timerAddins)
  if self.inter.isNone:
    log(lvlError, fmt"Failed to create script context")

method reload*(ctx: ScriptContextNim): Future[void] {.async.} =
  log(lvlInfo, fmt"Reloading script context (search paths: {ctx.searchPaths})")
  asyncCheck ctx.mySafeLoadScriptWithState(@["scripting_api", "std/json"])

proc generateScriptingApi*(addins: VMAddins) {.compileTime.} =
  if exposeScriptingApi:
    echo fmt"Generate scripting api files: {addins.procs.len} procs"

    # nimscript
    var script_internal_content = """
      ## This file is auto generated, don't modify.

      import std/[json, options]
      import scripting_api

      template varargs*() {.pragma.}

    """.unindent(8, " ")
    createDir("scripting")
    createDir("int")

    # Add stub proc impls generated by nimscripter
    for uProc in addins.procs:
      var implNim = uProc.vmRunImpl

      # Hack to make these functions public
      let parenIndex = implNim.find("(")
      if parenIndex > 0 and implNim[parenIndex - 1] != '*':
        implNim.insert("*", parenIndex)

      script_internal_content.add implNim

    echo fmt"Writing scripting/plugin_api_internal.nim"
    writeFile(fmt"scripting/plugin_api_internal.nim", script_internal_content)

template createScriptContextConstructor*(addins: untyped): untyped =
  proc createScriptContextNim(filepath: string, searchPaths: seq[string], stdPath: Option[string]): Future[Option[ScriptContext]] {.async.} =
    return await newScriptContext(filepath, "plugin_api_internal", addins, "include plugin_runtime_impl", searchPaths, stdPath)

macro invoke(self: ScriptContext; pName: untyped;
    args: varargs[typed]; returnType: typedesc = void): untyped =
  ## Invoke but takes an option and unpacks it, if `intr.`isNone, assertion is raised
  let inter = quote do:
    `self`.inter.get
  var call = newCall("invokeDynamic", inter, pName.toStrLit)
  for x in args:
    call.add x
  call.add nnkExprEqExpr.newTree(ident"returnType", returnType)

  return genAst(self, call, name = pName.repr.newLit):
    if self.state != Initialized:
      log lvlWarn, fmt"ScriptContext not initialized yet. State is {self.state} (trying to invoke" & name & ")"
      return
    if self.inter.isNone:
      log lvlError, fmt"Interpreter is none. State is {self.state}"
      return

    call

method handleEditorModeChanged*(self: ScriptContextNim, editor: DocumentEditor, oldMode: string, newMode: string) =
  try:
    self.invoke(handleEditorModeChanged, editor.id, oldMode, newMode, returnType = void)
  except:
    log lvlError, &"Failed to run handleEditorModeChanged {editor.id}, {oldMode}, {newMode}: {getCurrentExceptionMsg()}"

method postInitialize*(self: ScriptContextNim): bool =
  try:
    return self.invoke(postInitialize, returnType = bool)
  except:
    log lvlError, &"Failed to run postInitialize: {getCurrentExceptionMsg()}"
    return false

method handleCallback*(self: ScriptContextNim, id: int, arg: JsonNode): bool =
  try:
    return self.invoke(handleCallback, id, arg, returnType = bool)
  except:
    log lvlError, &"Failed to run handleCallback {id}, {arg}: {getCurrentExceptionMsg()}"
    return false

method handleAnyCallback*(self: ScriptContextNim, id: int, arg: JsonNode): JsonNode =
  try:
    return self.invoke(handleAnyCallback, id, arg, returnType = JsonNode)
  except:
    log lvlError, &"Failed to run handleAnyCallback {id}, {arg}: {getCurrentExceptionMsg()}"
    return nil

method handleScriptAction*(self: ScriptContextNim, name: string, args: JsonNode): JsonNode =
  try:
    return self.invoke(handleScriptAction, name, args, returnType = JsonNode)
  except:
    log lvlError, &"Failed to run handleScriptAction {name}, {args}: {getCurrentExceptionMsg()}"
    return nil