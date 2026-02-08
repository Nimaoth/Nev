import std/[parseopt, options, strutils, os, strformat, dirs, sequtils, unicode, osproc, times, tables, json, jsonutils, threadpool, sets]
import src/misc/timer

var optParser = initOptParser("")

const helpText = """Nev build helper
"""

type
  FileInfo = object
    modificationTime: int64
  ModuleInfo = object
    path: string
    dirty: bool
    files: Table[string, FileInfo]
    dependencies: seq[string]

var dry = false
var force = false
var parallel = true
var modulesToBuild = initHashSet[string]()

type IdentifierCase* = enum Camel, Pascal, Kebab, Snake, ScreamingSnake

proc splitCase*(s: string): tuple[cas: IdentifierCase, parts: seq[string]] =
  if s == "":
    return (IdentifierCase.Camel, @[])

  if s.find('_') != -1:
    result.cas = IdentifierCase.Snake
    result.parts = s.split('_').mapIt(toLower(it))
    for r in s.runes:
      if r != '_'.Rune and not r.isLower:
        result.cas = IdentifierCase.ScreamingSnake
        break

  elif s.find('-') != -1:
    result.cas = IdentifierCase.Kebab
    result.parts = s.split('-').mapIt(toLower(it))
  else:
    if s[0].isUpperAscii:
      result.cas = IdentifierCase.Pascal
    else:
      result.cas = IdentifierCase.Camel

    result.parts.add ""
    for r in s.runes:
      if not r.isLower and result.parts[^1].len > 0:
        result.parts.add ""
      result.parts[^1].add(toLower(r))

proc joinCase*(parts: seq[string], cas: IdentifierCase): string =
  if parts.len == 0:
    return ""
  case cas
  of IdentifierCase.Camel:
    parts[0] & parts[1..^1].mapIt(it.capitalize).join("")
  of IdentifierCase.Pascal:
    parts.mapIt(it.capitalize).join("")
  of IdentifierCase.Kebab:
    parts.join("-")
  of IdentifierCase.Snake:
    parts.join("_")
  of IdentifierCase.ScreamingSnake:
    parts.mapIt(toUpper(it)).join("_")

proc cycleCase*(s: string): string =
  if s.len == 0:
    return s
  let (cas, parts) = s.splitCase()
  let nextCase = if cas == IdentifierCase.high:
    IdentifierCase.low
  else:
    cas.succ
  return parts.joinCase(nextCase)

proc toCamelCase(str: string): string =
  return str.splitCase.parts.joinCase(Camel)

proc toPascalCase(str: string): string =
  return str.splitCase.parts.joinCase(Pascal)

proc readDependencies(str: string): seq[string] =
  try:
    let f = readFile(str)
    for l in f.splitLines:
      if l.startsWith("#use "):
        return l[5..^1].split(" ")
  except CatchableError as e:
    echo &"Failed to read file dependencies from '{str}': {e.msg}"

  return @[]

proc gatherModules(): Table[string, ModuleInfo] =
  try:
    for (kind, path) in walkDir("modules", relative=false):
      case kind
      of pcFile:
        if not path.endsWith(".nim"):
          continue
        let name = path.splitFile.name
        if name == "module_base":
          continue
        var files = initTable[string, FileInfo]()
        files[path] = FileInfo(modificationTime: getLastModificationTime(path).toUnix)
        let dependencies = readDependencies(path)
        result[name] = ModuleInfo(path: path, dirty: true, files: files, dependencies: dependencies)
      of pcDir:
        let name = path.splitPath.tail
        if name == "module_base":
          continue
        var files = initTable[string, FileInfo]()
        var mainFile = ""
        for subPath in walkDirRec(path, skipSpecial = true):
          files[subPath] = FileInfo(modificationTime: getLastModificationTime(subPath).toUnix)
        let dependencies = readDependencies(path / name & ".nim")
        result[name] = ModuleInfo(path: path / name & ".nim", dirty: true, files: files, dependencies: dependencies)

      of pcLinkToFile:
        discard
      of pcLinkToDir:
        discard

  except OSError as e:
    echo &"Failed to gather modules: {e.msg}"

proc loadBuildOutput(): Table[string, ModuleInfo] =
  try:
    let f = readFile("build.json")
    return f.parseJson().jsonTo(Table[string, ModuleInfo])
  except CatchableError as e:
    echo &"Failed to load module results: {e.msg}"

proc anyFileChanged(new: ModuleInfo, old: ModuleInfo): bool =
  for (name, file) in new.files.pairs:
    if name notin old.files:
      # new file
      return true
    if file.modificationTime > old.files[name].modificationTime:
      return true

  return false

proc getAllModules(): Table[string, ModuleInfo] =
  var modules = gatherModules()
  let buildOutput = loadBuildOutput()
  for name in modules.keys:
    let dll = &"native_plugins/{name}.dll"
    if fileExists(dll):
      # echo &"Check if dll is up to date for {name}"
      var lastSourceModificationTime = 0.int64
      for file in modules[name].files.values:
        lastSourceModificationTime = max(lastSourceModificationTime, file.modificationTime)
      let dllModificationTime = getLastModificationTime(dll).toUnix
      # echo &"lastSourceMod: {lastSourceModificationTime}, lastDllMod: {dllModificationTime}, {dllModificationTime - lastSourceModificationTime}"
      if lastSourceModificationTime < dllModificationTime:
        modules[name].dirty = false
  return modules

proc runCmdAsync(cmd: string): FlowVar[tuple[output: string, exitCode: int]] =
  echo &"{cmd}"
  if not dry:
    return spawn execCmdEx(cmd)

proc runCmdSync(cmd: string): int =
  echo &"{cmd}"
  if not dry:
    result = execCmd(cmd)
    echo &"{cmd}    -> {result}"

proc buildDirtyModules(modules: Table[string, ModuleInfo]) =
  echo &"buildDirtyModules"
  var numBuilt = 0
  var numFailed = 0
  var numSkipped = 0
  var cmds: seq[tuple[fv: FlowVar[tuple[output: string, exitCode: int]], module: string]] = @[]
  for (name, m) in modules.pairs:
    echo name, ": ", m

    if modulesToBuild.len > 0 and name notin modulesToBuild:
      echo &"Skip {name} (deps: {m.dependencies})"
      inc numSkipped
      continue

    if not m.dirty and not force:
      echo &"Skip {name} (deps: {m.dependencies})"
      inc numSkipped
      continue

    try:
      let dependencies = m.dependencies.join(",")
      let cmd = &"nim c --colors:on --hints:off -o:native_plugins/{name}.dll --nimcache:nimcache/{name} --app:lib -d:useDynlib -d:nevModuleName={name} -d:nevDeps={dependencies} --path:modules --cc:clang --passC:-Wno-incompatible-function-pointer-types --passL:-ladvapi32.lib --passL:-luser32.lib --passC:-std=gnu11 --opt:none --lineDir:off -d:mallocImport {m.path}"
      if parallel:
        let v = runCmdAsync(cmd)
        if v != nil:
          cmds.add((v, name))
      else:
        echo &"=========================================== Build output for {name} ================================"
        if runCmdSync(cmd) == 0:
          inc numBuilt
        else:
          inc numFailed
    except CatchableError as e:
      echo &"Failed to build {name}: {e.msg}"
      inc numFailed

  while cmds.len > 0:
    for i in countdown(cmds.high, 0):
      if cmds[i].fv.isReady:
        let (output, err) = ^cmds[i].fv
        if err == 0:
          inc numBuilt
        else:
          inc numFailed
        echo &"=========================================== Build output for {cmds[i].module} ================================"
        echo output
        cmds.del(i)

    sleep(10)

  try:
    echo &"==========================================================================="
    echo &"Skipped: {numSkipped}, Built: {numBuilt}, Failed: {numFailed}"
    if not dry:
      writeFile("build.json", modules.toJson.pretty)
  except CatchableError as e:
    echo &"Failed to write build.json: {e.msg}"

  try:
    var imports = ""
    var inits = "proc initModules*() =\n"
    var deinits = "proc shutdownModules*() =\n"
    for (name, m) in modules.pairs:
      let path = m.path.replace("\\", "/")
      imports.add &"import \"../{path}\"\n"
      inits.add &"  init_module_{name}()\n"
      deinits.add &"  when declared(shutdown_module_{name}): shutdown_module_{name}()\n"

    if not dry:
      writeFile("src/module_imports.nim", &"{imports}\n{inits}\n{deinits}")
  except CatchableError as e:
    echo &"Failed to write module_imports.nim: {e.msg}"

proc main() =
  var cmd = "build"

  for kind, key, val in optParser.getopt():
    case kind
    of cmdArgument:
      modulesToBuild.incl key
      echo modulesToBuild

    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h":
        echo helpText
        quit(0)

      of "singlethreaded", "s":
        parallel = false
      of "force", "f":
        force = true
      of "dry":
        dry = true
    of cmdEnd: assert(false) # cannot happen

  case cmd
  of "build":
    echo "Build Nev"
    var s = startTimer()
    buildDirtyModules(getAllModules())
    let t = s.elapsed
    echo &"Build took {t.float} s"

main()
