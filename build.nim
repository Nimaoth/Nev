import std/[parseopt, options, strutils, os, strformat, dirs, sequtils, unicode, osproc, times, tables, json, jsonutils, threadpool, sets, sugar, algorithm]
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
    dependencies: seq[tuple[module: string, features: seq[string]]]

var dry = false
var force = false
var parallel = true
var modulesToBuild = initHashSet[string]()
var debug = true
var logVerbose = false

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

proc readDependencies(str: string): seq[tuple[module: string, features: seq[string]]] =
  try:
    let f = readFile(str)
    for l in f.splitLines:
      if l.startsWith("#use "):
        for dep in l[5..^1].split(" "):
          let parts = dep.split(":")
          let name = parts[0]
          let features = parts[1..^1]
          result.add (name, features)
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
          if subPath.endsWith(name & ".nim"):
            mainFile = subPath
          files[subPath] = FileInfo(modificationTime: getLastModificationTime(subPath).toUnix)

        if mainFile == "":
          echo &"Skip module {name}, no main file {name}.nim"
          continue
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
  if logVerbose:
    echo &"{cmd}"
  if not dry:
    return spawn execCmdEx(cmd)

proc runCmdSync(cmd: string): int =
  if logVerbose:
    echo &"{cmd}"
  if not dry:
    result = execCmd(cmd)
    echo &"{cmd}    -> {result}"

proc buildDirtyModules(modules: Table[string, ModuleInfo]) =
  var numBuilt = 0
  var numFailed = 0
  var numSkipped = 0
  var failedModules: seq[string] = @[]
  var cmds: seq[tuple[fv: FlowVar[tuple[output: string, exitCode: int]], module: string]] = @[]
  var outputs = initTable[string, string]()
  for (name, m) in modules.pairs:
    if modulesToBuild.len > 0 and name notin modulesToBuild:
      inc numSkipped
      continue

    if not m.dirty and not force:
      if logVerbose:
        echo &"Skip {name}"
      inc numSkipped
      continue

    try:
      echo &"Build {name} ({m.path}) {m.dependencies.mapIt(it.module & \" \" & it.features.join(\":\")).join(\", \")}"

      if logVerbose:
        for (file, info) in m.files.pairs:
          echo &"  {file} {info}"

      let builtinDeps = @["log"]
      let dependencies = (m.dependencies.mapIt(it.module) & builtinDeps).join(",")
      let features = collect:
        for dep in m.dependencies:
          for f in dep.features:
            &"-d:feat{f}"
      let allFeatures = features.join(" ")
      let opt = if not debug or name == "text": "speed" else: "none"
      let cmd = &"nim c --colors:on --hints:off -o:native_plugins/{name}.dll --nimcache:nimcache/{name} --app:lib -d:useDynlib -d:nevModuleName={name} -d:nevDeps={dependencies} {allFeatures} --path:modules --cc:clang --passC:-Wno-incompatible-function-pointer-types --passL:-ladvapi32.lib --passL:-luser32.lib --passC:-std=gnu11 --opt:{opt} --lineDir:off -d:mallocImport -d:exposeScriptingApi=true {m.path}"
      if parallel:
        while cmds.len >= 10:
          for i in countdown(cmds.high, 0):
            if cmds[i].fv.isReady:
              let (output, err) = ^cmds[i].fv
              if err == 0:
                inc numBuilt
              else:
                inc numFailed
                failedModules.add(cmds[i].module)
              outputs[cmds[i].module] = output
              cmds.del(i)
              break
          sleep(10)
        let v = runCmdAsync(cmd)
        if v != nil:
          cmds.add((v, name))
      else:
        echo &"=========================================== Build output for {name} ================================"
        if runCmdSync(cmd) == 0:
          inc numBuilt
        else:
          inc numFailed
          failedModules.add(name)
    except CatchableError as e:
      echo &"Failed to build {name}: {e.msg}"
      inc numFailed
      failedModules.add(name)

  while cmds.len > 0:
    for i in countdown(cmds.high, 0):
      if cmds[i].fv.isReady:
        let (output, err) = ^cmds[i].fv
        if err == 0:
          inc numBuilt
        else:
          inc numFailed
          failedModules.add(cmds[i].module)
        outputs[cmds[i].module] = output
        cmds.del(i)

    sleep(10)


  try:
    if numFailed > 0:
      for module in failedModules:
        echo &"=========================================== Build output for {module} ================================"
        echo outputs[module]
    else:
      for module, output in outputs:
        echo &"=========================================== Build output for {module} ================================"
        echo outputs[module]
    echo &"==========================================================================="
    echo &"Skipped: {numSkipped}, Built: {numBuilt}, Failed: {numFailed}"
    for module in failedModules:
      echo module, " FAILED"
    if not dry:
      writeFile("build.json", modules.toJson.pretty)
  except CatchableError as e:
    echo &"Failed to write build.json: {e.msg}"

  try:
    proc topoSort(modules: Table[string, ModuleInfo]): seq[string] =
      var inDegree = initCountTable[string]()
      var graph = initTable[string, seq[string]]()
      for name in modules.keys:
        inDegree[name] = 0
        graph[name] = @[]
      for (name, m) in modules.pairs:
        for dep in m.dependencies:
          if dep.module in modules:
            graph[name].add(dep.module)
            inc inDegree, dep.module
      var queue: seq[string] = @[]
      for name in modules.keys:
        if name in inDegree and inDegree[name] > 0:
          continue
        queue.add(name)
      while queue.len > 0:
        var node = queue.pop()
        result.add(node)
        for neighbor in graph[node]:
          inc inDegree, neighbor, -1
          if inDegree[neighbor] == 0:
            queue.add(neighbor)


    var sortedNames = topoSort(modules)
    if sortedNames.toSet().len != modules.len:
      proc printCycles(modules: Table[string, ModuleInfo], path: seq[string]) =
        for dep in modules[path[^1]].dependencies:
          if dep.module in path:
            echo &"Cycle ", path & dep.module
            continue
          printCycles(modules, path & dep.module)

      for module in modules.keys:
        printCycles(modules, @[module])

    var imports = "when not defined(useDynlib):\n"
    var inits = "proc initModules*() =\n"
    var deinits = "proc shutdownModules*() =\n"
    var loads = "proc loadModulesDynamically*(loadModule: proc(name: string) {.raises: [].}) =\n"

    for name in sortedNames:
      deinits.add &"  when declared(shutdown_module_{name}): shutdown_module_{name}()\n"

    sortedNames.reverse()
    for name in sortedNames:
      let m = modules[name]
      let path = m.path.replace("\\", "/")
      imports.add &"  import \"../{path}\"\n"
      inits.add &"  when declared(init_module_{name}): init_module_{name}()\n"
      loads.add &"  loadModule(\"{name}\")\n"

    if not dry:
      writeFile("src/module_imports.nim", &"{imports}\n{inits}\n{deinits}\n{loads}")
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
      of "rel", "r":
        debug = false
      of "dry":
        dry = true
      of "v", "verbose":
        logVerbose = true
    of cmdEnd: assert(false) # cannot happen

  case cmd
  of "build":
    var s = startTimer()
    buildDirtyModules(getAllModules())
    let t = s.elapsed
    echo &"Build took {t.float} s"

main()
