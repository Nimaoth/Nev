import std/[os, parseopt, compilesettings, strformat, strutils, json, tables]

# Helper functions

var exitCode = 0

proc cpDir2(src: string, dst: string) =
  let name = src.splitPath[1]
  if dirExists src:
    echo "Copy ", name, "/ to ", dst/name
    cpDir src, dst/name
  else:
    echo "[ERROR] Dir " & src & " does not exist"
    exitCode = 1

proc cpFile2(src: string, dst: string, optional: bool = false) =
  let name = src.splitPath[1]
  try:
    if fileExists src:
      echo "Copy ", src, " to ", dst/name
      cpFile src, dst/name
    else:
      if not optional:
        echo "[ERROR] File " & src & " does not exist"
        exitCode = 1
  except CatchableError as e:
    if not optional:
      echo "[ERROR] Failed to copy file " & src & ": " & e.msg
      exitCode = 1

template catch(exp: untyped, then: untyped): untyped =
  try:
    exp
  except CatchableError:
    then

############################################################################################################

const version = "0.6.0"
const releaseWindows = &"nev-{version}-x86_64-pc-windows-gnu"
const releaseLinux = &"nev-{version}-x86_64-unknown-linux-gnu"
const releaseLinuxMusl = &"nev-{version}-x86_64-unknown-linux-musl"

proc copySharedFilesTo(dir: string) =
  cpDir2 "config", dir
  cpDir2 "fonts", dir
  cpDir2 "languages", dir
  cpDir2 "themes", dir
  cpDir2 "docs", dir
  cpDir2 "res", dir
  cpDir2 "plugins", dir
  cpDir2 "plugin_api", dir
  mkDir dir / "src"
  mkDir dir / "src/misc"
  cpFile2 "src/misc/input_api.nim", dir / "src"
  cpFile2 "src/misc/custom_unicode.nim", dir / "src/misc"
  cpFile2 "src/misc/embed_source.nim", dir / "src/misc"
  cpFile2 "src/misc/event.nim", dir / "src/misc"
  cpFile2 "src/misc/id.nim", dir / "src/misc"
  cpFile2 "src/misc/macro_utils.nim", dir / "src/misc"
  cpFile2 "src/misc/myjsonutils.nim", dir / "src/misc"
  cpFile2 "src/misc/timer.nim", dir / "src/misc"
  cpFile2 "src/misc/util.nim", dir / "src/misc"
  cpFile2 "src/misc/wrap.nim", dir / "src/misc"
  cpFile2 "src/scripting_api.nim", dir / "src"
  cpDir2 "patches", dir
  cpDir2 "LICENSES", dir
  cpFile2 "LICENSE", dir
  cpFile2 "nev.nimble", dir
  cpFile2 "config.nims", dir

  let stdPath = querySetting(libPath)
  mkDir dir / "nim_std"
  cpDir2 stdPath / "pure", dir / "nim_std"
  cpDir2 stdPath / "core", dir / "nim_std"
  cpDir2 stdPath / "std", dir / "nim_std"
  cpDir2 stdPath / "system", dir / "nim_std"
  cpFile2 stdPath / "system.nim", dir / "nim_std"
  cpFile2 stdPath / "stdlib.nimble", dir / "nim_std"

var isCINimbleCached = "0"
var cmds = newSeq[string]()
var nuigiDir = getEnv("NUIGI_DIR", "deps" / "nuigi").absolutePath
var nuigiPinDir = r"C:\dev\nuigi"
var depsDir = "deps".absolutePath
var lockFile = "atlas.lock".absolutePath

type LockedDependency = object
  name, path, url, commit: string

proc dependencyError(message: string) =
  echo "[ERROR] ", message
  quit 1

proc gitOutput(path, args: string): string =
  let command = "git --no-pager -C " & path.quoteShell & " " & args
  let (output, code) = gorgeEx(command)
  if code != 0:
    dependencyError(command & "\n" & output)
  output.strip

proc replaceCommit(text, prefix, suffix, commit, description: string): string =
  let start = text.find(prefix)
  if start < 0 or text.find(prefix, start + prefix.len) >= 0:
    dependencyError("Expected exactly one " & description)
  let hashStart = start + prefix.len
  let hashEnd = text.find(suffix, hashStart)
  if hashEnd < 0:
    dependencyError("Missing terminator for " & description)
  let oldHash = text[hashStart ..< hashEnd]
  if oldHash.len == 0 or oldHash.toLowerAscii.strip(chars = {'0'..'9', 'a'..'f'}).len != 0:
    dependencyError("Invalid commit hash for " & description)
  text[0 ..< hashStart] & commit & text[hashEnd .. ^1]

proc updateNuigiPin() =
  let commit = gitOutput(nuigiPinDir, "rev-parse --verify HEAD")
  if commit.len != 40 or commit.toLowerAscii.strip(chars = {'0'..'9', 'a'..'f'}).len != 0:
    dependencyError("Expected a full Git commit hash from " & nuigiPinDir)
  try:
    let nimbleFile = "nev.nimble"
    let nimble = readFile(nimbleFile)
    let lock = readFile(lockFile)
    let urlPrefix = "https://github.com/Nimaoth/nuigi#"
    let newNimble = replaceCommit(nimble, urlPrefix, "\"", commit, "nuigi requirement in " & nimbleFile)
    var newLock = replaceCommit(lock, urlPrefix, "\\\"", commit, "nuigi requirement in " & lockFile)
    let entryPrefix = "\"nuigi.Nimaoth.github.com\": {"
    let entryStart = newLock.find(entryPrefix)
    if entryStart < 0 or newLock.find(entryPrefix, entryStart + entryPrefix.len) >= 0:
      dependencyError("Expected exactly one nuigi entry in " & lockFile)
    let entryEnd = newLock.find('}', entryStart)
    if entryEnd < 0:
      dependencyError("Missing terminator for nuigi entry in " & lockFile)
    let entry = newLock[entryStart .. entryEnd]
    let updatedEntry = replaceCommit(entry, "\"commit\": \"", "\"", commit, "nuigi commit in " & lockFile)
    newLock = newLock[0 ..< entryStart] & updatedEntry & newLock[entryEnd + 1 .. ^1]
    if newNimble != nimble:
      writeFile(nimbleFile, newNimble)
    if newLock != lock:
      writeFile(lockFile, newLock)
    echo "Nuigi pinned to ", commit, " from ", nuigiPinDir
  except CatchableError as e:
    dependencyError("Failed to update nuigi pin: " & e.msg)

proc restoreDependencies() =
  var dependencies: seq[LockedDependency]
  var paths = initTable[string, string]()
  try:
    let lock = parseJson(readFile(lockFile))
    if lock.kind != JObject or not lock.hasKey("items") or lock["items"].kind != JObject:
      dependencyError("Lock file must contain an 'items' object: " & lockFile)
    for name, item in lock["items"].pairs:
      if item.kind != JObject:
        dependencyError("Invalid lock entry: " & name)
      for field in ["dir", "url", "commit"]:
        if not item.hasKey(field) or item[field].kind != JString or item[field].getStr.len == 0:
          dependencyError("Missing or invalid '" & field & "' in lock entry: " & name)
      let dir = item["dir"].getStr.replace('\\', '/')
      if not dir.startsWith("$deps/"):
        dependencyError("Expected a $deps/ directory for " & name & ": " & dir)
      let relative = dir[6..^1]
      for part in relative.split('/'):
        if part.len == 0 or part in [".", ".."] or part.contains(':'):
          dependencyError("Invalid dependency directory for " & name & ": " & dir)
      let path = (depsDir / relative).absolutePath
      let key = when defined(windows): path.toLowerAscii else: path
      if paths.hasKey(key):
        dependencyError("Duplicate dependency directory " & dir & " in entries " & paths[key] & " and " & name)
      paths[key] = name
      let commit = item["commit"].getStr.toLowerAscii
      if commit.len != 40 or commit.strip(chars = {'0'..'9', 'a'..'f'}).len != 0:
        dependencyError("Expected a full Git commit hash for " & name)
      let url = item["url"].getStr
      if url.startsWith("-"):
        dependencyError("Invalid repository URL for " & name)
      dependencies.add LockedDependency(name: name, path: path, url: url, commit: commit)
  except CatchableError as e:
    dependencyError("Failed to read " & lockFile & ": " & e.msg)

  var restored, skipped = 0
  for dependency in dependencies:
    let path = dependency.path
    if not dirExists(path):
      if fileExists(path):
        dependencyError("Dependency path is a file: " & path)
      mkDir path.parentDir
      echo "Clone ", dependency.name, " into ", path
      exec "git clone -- " & dependency.url.quoteShell & " " & path.quoteShell
    if not dirExists(path / ".git") and not fileExists(path / ".git"):
      dependencyError("Dependency directory is not a Git checkout: " & path)
    let root = gitOutput(path, "rev-parse --show-toplevel").replace('/', DirSep).absolutePath
    let isRoot = when defined(windows): root.toLowerAscii == path.toLowerAscii
      else: root == path
    if not isRoot:
      dependencyError("Dependency directory is not the repository root: " & path)
    let head = gitOutput(path, "rev-parse --verify HEAD")
    if head.toLowerAscii == dependency.commit:
      echo "Up to date: ", dependency.name
      inc skipped
      continue
    if gitOutput(path, "status --porcelain --untracked-files=all").len != 0:
      dependencyError("Refusing to change a dirty dependency checkout: " & path)
    let (_, commitCode) = gorgeEx("git --no-pager -C " & path.quoteShell &
      " cat-file -e " & (dependency.commit & "^{commit}").quoteShell)
    if commitCode != 0:
      discard gitOutput(path, "fetch --no-tags -- " & dependency.url.quoteShell & " " & dependency.commit)
    echo "Check out ", dependency.name, " at ", dependency.commit
    discard gitOutput(path, "checkout --detach " & dependency.commit)
    if gitOutput(path, "rev-parse HEAD").toLowerAscii != dependency.commit:
      dependencyError("Commit verification failed for " & dependency.name)
    inc restored
  echo "Dependencies: ", restored, " restored, ", skipped, " already up to date."

const staticLibDir = "nimcache" / "nuigi-static" / "libs"
const staticLibraries = when defined(windows):
    ["SDL3.lib", "freetype.lib"]
  else:
    ["libSDL3.a", "libfreetype.a"]

const nimWasmtimeBuildDebug {.booldefine.}: bool = false
const nimWasmtimeBuildMusl {.booldefine.}: bool = false
const nimWasmtimeOverride {.strdefine.}: string = ""
const nimWasmtimeFeatureProfiling {.booldefine.}: bool = true
const nimWasmtimeFeatureWat {.booldefine.}: bool = true
const nimWasmtimeFeatureCache {.booldefine.}: bool = true
const nimWasmtimeFeatureParallelCompilation {.booldefine.}: bool = true
const nimWasmtimeFeatureWasi {.booldefine.}: bool = true
const nimWasmtimeFeatureLogging {.booldefine.}: bool = true
const nimWasmtimeFeatureDisableLogging {.booldefine.}: bool = false
const nimWasmtimeFeatureCoredump {.booldefine.}: bool = true
const nimWasmtimeFeatureAddr2Line {.booldefine.}: bool = true
const nimWasmtimeFeatureDemangle {.booldefine.}: bool = true
const nimWasmtimeFeatureThreads {.booldefine.}: bool = true
const nimWasmtimeFeatureGC {.booldefine.}: bool = true
const nimWasmtimeFeatureAsync {.booldefine.}: bool = true
const nimWasmtimeFeatureCranelift {.booldefine.}: bool = true
const nimWasmtimeFeatureWinch {.booldefine.}: bool = true
const nimWasmtimeFeatureComponentModel {.booldefine.}: bool = false
const nimWasmtimeFeatureDebugBuiltins {.booldefine.}: bool = false
const nimWasmtimeFeaturePoolingAllocator {.booldefine.}: bool = false
const wasmtimeFeatures = [
  ("WASMTIME_FEATURE_PROFILING", "profiling", nimWasmtimeFeatureProfiling),
  ("WASMTIME_FEATURE_WAT", "wat", nimWasmtimeFeatureWat),
  ("WASMTIME_FEATURE_CACHE", "cache", nimWasmtimeFeatureCache),
  ("WASMTIME_FEATURE_PARALLEL_COMPILATION", "parallel-compilation", nimWasmtimeFeatureParallelCompilation),
  ("WASMTIME_FEATURE_WASI", "wasi", nimWasmtimeFeatureWasi),
  ("WASMTIME_FEATURE_LOGGING", "logging", nimWasmtimeFeatureLogging),
  ("WASMTIME_FEATURE_DISABLE_LOGGING", "disable-logging", nimWasmtimeFeatureDisableLogging),
  ("WASMTIME_FEATURE_COREDUMP", "coredump", nimWasmtimeFeatureCoredump),
  ("WASMTIME_FEATURE_ADDR2LINE", "addr2line", nimWasmtimeFeatureAddr2Line),
  ("WASMTIME_FEATURE_DEMANGLE", "demangle", nimWasmtimeFeatureDemangle),
  ("WASMTIME_FEATURE_THREADS", "threads", nimWasmtimeFeatureThreads),
  ("WASMTIME_FEATURE_GC", "gc", nimWasmtimeFeatureGC),
  ("WASMTIME_FEATURE_ASYNC", "async", nimWasmtimeFeatureAsync),
  ("WASMTIME_FEATURE_CRANELIFT", "cranelift", nimWasmtimeFeatureCranelift),
  ("WASMTIME_FEATURE_WINCH", "winch", nimWasmtimeFeatureWinch),
  ("WASMTIME_FEATURE_COMPONENT_MODEL", "component-model", nimWasmtimeFeatureComponentModel),
  ("WASMTIME_FEATURE_DEBUG_BUILTINS", "debug-builtins", nimWasmtimeFeatureDebugBuiltins),
  ("WASMTIME_FEATURE_POOLING_ALLOCATOR", "pooling-allocator", nimWasmtimeFeaturePoolingAllocator),
]

proc wasmtimeSourceDir(): string =
  if nimWasmtimeOverride.len > 0:
    nimWasmtimeOverride
  else:
    depsDir / "nimwasmtime" / "src" / "wasmtime"

proc buildWasmtime(musl = false) =
  let sourceDir = wasmtimeSourceDir()
  let confPath = sourceDir / "crates" / "c-api" / "include" / "wasmtime" / "conf.h.in"
  if not fileExists(confPath):
    dependencyError("Wasmtime source not found at " & sourceDir)

  withDir sourceDir:
    var features: seq[string]
    var conf = readFile(confPath)
    for (defineName, featureName, enabled) in wasmtimeFeatures:
      if enabled:
        features.add featureName
        conf = conf.replace("#cmakedefine " & defineName, "#define " & defineName)
      else:
        conf = conf.replace("#cmakedefine " & defineName, "/* #undef " & defineName & " */")
    features.add "gc-null"
    writeFile("crates/c-api/include/wasmtime/conf.h", conf)

    var cargoArgs = @["cargo", "build", "-p", "wasmtime-c-api", "--no-default-features"]
    if not nimWasmtimeBuildDebug:
      cargoArgs.add "--release"
    if musl:
      cargoArgs.add "--target=x86_64-unknown-linux-musl"
    cargoArgs.add "--features"
    cargoArgs.add features.join(",")
    echo "Build Wasmtime: ", cargoArgs.join(" ")
    exec cargoArgs.join(" ")

proc copyWasmtimeDll() =
  when defined(windows):
    let buildType = if nimWasmtimeBuildDebug: "debug" else: "release"
    let dll = wasmtimeSourceDir() / "target" / buildType / "wasmtime.dll"
    cpFile2 dll, "."
  else:
    echo "Wasmtime DLL is only required on Windows."

proc buildAndCopyWasmtime(musl = false) =
  buildWasmtime(musl)
  copyWasmtimeDll()

proc wasmtimeCompilerArgs(musl = false): string =
  var args = @[
    "-u:nimWasmtimeBuild",
    "-d:nimWasmtimeBuildDebug=" & $nimWasmtimeBuildDebug,
    "-d:nimWasmtimeBuildMusl=" & $musl,
  ]
  for (defineName, _, enabled) in wasmtimeFeatures:
    let nimDefine = defineName.replace("WASMTIME_FEATURE_", "nimWasmtimeFeature")
    args.add "-d:" & nimDefine & "=" & $enabled
  if nimWasmtimeOverride.len > 0:
    args.add ("-d:nimWasmtimeOverride=" & nimWasmtimeOverride).quoteShell
  args.join(" ")

proc compileIconResource(): string =
  when defined(windows):
    mkDir "bin"
    exec "llvm-rc /nologo /fo bin\\nev.res res\\icon.rc"
    result = " -d:noRes --passL:bin/nev.res"

proc requireNuigi() =
  if not fileExists(nuigiDir / "build.nim"):
    echo "[ERROR] Nuigi checkout not found at ", nuigiDir,
      ". Set --nuigi-dir:<path> or NUIGI_DIR."
    quit 1

proc copyStaticLibrary(buildDir, sourceName, targetName: string) =
  for path in walkDirRec(buildDir):
    if path.extractFilename.toLowerAscii == sourceName.toLowerAscii:
      mkDir staticLibDir
      cpFile path, staticLibDir / targetName
      return
  echo "[ERROR] Static library ", sourceName, " not found in ", buildDir
  quit 1

proc buildNuigiStaticDependencies() =
  requireNuigi()
  let buildSource = readFile(nuigiDir / "build.nim")
  if not buildSource.contains("\"sdl3-static\"") or
      not buildSource.contains("\"freetype-static\""):
    echo "[ERROR] This Nuigi checkout does not support static dependency builds.",
      " Update it or select a newer checkout with --nuigi-dir:<path>."
    quit 1
  when defined(linux):
    let sdlSource = nuigiDir / "vendor" / "SDL"
    if not dirExists(sdlSource):
      mkDir(nuigiDir / "vendor")
      withDir nuigiDir / "vendor":
        exec "git clone https://github.com/libsdl-org/SDL"
    exec "cmake -S " & sdlSource.quoteShell & " -B " &
      (nuigiDir / "build" / "sdl3_static").quoteShell &
      " -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=OFF -DSDL_STATIC=ON" &
      " -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF" &
      " -DSDL_X11_XSCRNSAVER=OFF -DSDL_X11_XTEST=OFF"
  withDir nuigiDir:
    exec "nim c -o:bin/nev-nuigi-build build.nim"
    let builder = ("bin" / "nev-nuigi-build" &
      (when defined(windows): ".exe" else: "")).absolutePath.quoteShell
    exec builder & " sdl3-static"
    exec builder & " freetype-static"
  when defined(windows):
    copyStaticLibrary(nuigiDir / "build" / "sdl3_static", "SDL3-static.lib", staticLibraries[0])
    copyStaticLibrary(nuigiDir / "build" / "freetype_static", "freetype.lib", staticLibraries[1])
  else:
    copyStaticLibrary(nuigiDir / "build" / "sdl3_static", staticLibraries[0], staticLibraries[0])
    copyStaticLibrary(nuigiDir / "build" / "freetype_static", staticLibraries[1], staticLibraries[1])

proc buildNev(output = "", extraArgs = "", cacheDir = "nimcache/nev-static") =
  requireNuigi()
  var linkArgs = ""
  for library in staticLibraries:
    let path = (staticLibDir / library).absolutePath
    if not fileExists(path):
      echo "[ERROR] Missing ", path, ". Run nuigi-deps-static first."
      quit 1
    linkArgs.add " " & ("--passL:" & path.quoteShell).quoteShell
  when defined(windows):
    for library in ["kernel32", "user32", "gdi32", "winmm", "imm32",
        "ole32", "oleaut32", "version", "uuid", "advapi32", "setupapi",
        "shell32", "hid", "mincore", "dinput8"]:
      linkArgs.add " --passL:-l" & library
  elif defined(linux):
    linkArgs.add " --passL:-lm --passL:-ldl --passL:-lpthread"
  # Override only these dynlibs so absolute archives win over local library paths.
  let staticArgs = "-d:sdlPlatform -d:nuiNoHarfbuzz -u:sdl3 -u:freetypeStatic --dynlibOverride:SDL3 --dynlibOverride:freetype"
  let pathArgs = " " & ("--path:" & (nuigiDir / "src")).quoteShell &
    " " & ("--path:" & (nuigiDir / "vendor" / "nimfreetype")).quoteShell
  let outputPath = if output.len > 0: output
    else: (when defined(windows): "nev.exe" else: "nev")
  exec "nim c -o:" & outputPath & " --opt:speed --cc:clang --passC:-Wno-incompatible-function-pointer-types -d:enableSystemClipboard=true -d:exposeScriptingApi --debuginfo:on -g --lineDir:off --passC:-g --passC:-std=gnu11 --nimcache:" & cacheDir & " " &
    wasmtimeCompilerArgs() & " " & staticArgs & pathArgs & linkArgs & compileIconResource() & " " & extraArgs & " src/desktop_main.nim"

var optParser = initOptParser("")
for kind, key, val in optParser.getopt():
  case kind
  of cmdArgument:
    cmds.add key

  of cmdLongOption, cmdShortOption:
    case key
    of "cache":
      isCINimbleCached = val
    of "nuigi-dir":
      if val.len == 0:
        echo "[ERROR] --nuigi-dir requires a checkout path."
        quit 1
      nuigiDir = val.absolutePath
      nuigiPinDir = nuigiDir
    of "deps-dir", "lock-file":
      if val.len == 0:
        dependencyError("--" & key & " requires a path.")
      if key == "deps-dir":
        depsDir = val.absolutePath
      else:
        lockFile = val.absolutePath
    of "help", "h":
      echo """Nev build commands (run from the repository root):
  nuigi-deps-static  Build and stage Nuigi's static SDL3 and FreeType archives.
  update-nuigi       Pin Nuigi to the local checkout's HEAD in nev.nimble and atlas.lock.
  build-static      Build nev-static using those archives, without HarfBuzz/FriBidi.
  build-dynamic     Like build-static, but load modules as DLLs from native_plugins.
  modules           Rebuild changed modules (DLLs) and regenerate module imports.
  modules-f         Force a rebuild of all modules.
  build-perf        Build nev-perf with .perfprof performance recording enabled.
  wasmtime          Build Wasmtime and copy its DLL into the repository root (Windows).
  deps              Clone/check out dependencies at the commits in atlas.lock.
  --deps-dir:PATH    Dependency destination (default: deps).
  --lock-file:PATH   Dependency lock file (default: atlas.lock).
  --nuigi-dir:PATH   Nuigi checkout (update-nuigi defaults to C:\dev\nuigi;
                     other commands default to NUIGI_DIR or deps/nuigi).
Build commands prepare Wasmtime before invoking the Nim compiler."""
      quit 0

  of cmdEnd: assert(false) # cannot happen

echo &"Run commands {cmds}"
var i = 0
while i < cmds.len:
  defer:
    inc i
  case cmds[i]
  of "wasmtime":
    buildAndCopyWasmtime(nimWasmtimeBuildMusl)

  of "deps":
    restoreDependencies()

  of "update-nuigi":
    updateNuigiPin()

  of "ci-release":
    when defined(windows):
      cmds.add @["markdown-parser", "release-win", "package-win"]
    else:
      cmds.add @["markdown-parser", "markdown-plugin", "release-linux", "package-linux"]
  of "ci-debug":
    when defined(windows):
      cmds.add @["markdown-parser", "debug-win", "package-win"]
    else:
      cmds.add @["markdown-parser", "markdown-plugin", "debug-linux", "package-linux"]

  of "markdown-parser":
    echo "Download markdown parser"
    let urlTemplate = "https://github.com/Nimaoth/tree-sitter-wasm-binaries/releases/download/v0.3/{language}.tar.gz"

    let languages = @["markdown", "markdown-inline"]
    for language in languages:
      let url = urlTemplate.replace("{language}", language)
      let outputPath = "./languages"
      let tarPath = &"./languages/{language}.tar.gz"
      var cmd: string
      when defined(windows):
        cmd = "powershell -Command \"Invoke-WebRequest -Uri '" & url.quoteShell & "' -OutFile '" & tarPath.quoteShell & "'\""
      else:
        cmd = "wget -O " & tarPath.quoteShell & " " & url.quoteShell
      echo &"Download {cmd}"
      exec(cmd)

      let extractCmd = &"tar -xzf {tarPath.quoteShell} -C {outputPath.quoteShell}"
      echo &"Extracting {extractCmd}"
      exec(extractCmd)
      rmFile(tarPath)

  of "release-win":
    echo &"Build release for windows..."
    buildAndCopyWasmtime()
    buildNuigiStaticDependencies()
    try:
      exec """nim c --out:nev.exe -D:enableGui=false -D:enableTerminal=true --app:console -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} --cc:clang --passC:-Wno-incompatible-function-pointer-types --passL:-ladvapi32.lib """ &
        wasmtimeCompilerArgs() & " src/desktop_main.nim"
    finally:
      discard
    try:
      exec """nim c --out:nevg.exe -D:enableGui=true -D:enableTerminal=false --app:gui -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} --cc:clang --passC:-Wno-incompatible-function-pointer-types "--passL:-ladvapi32.lib -luser32.lib" """ &
        wasmtimeCompilerArgs() & " src/desktop_main.nim"
    finally:
      discard

  of "markdown-plugin":
    echo &"Build markdown plugin..."
    withDir "plugins/markdown":
      # todo: on windows
      # exec """powershell -Command ./emsdk/emsdk.ps1 activate 4.0.10"""
      exec """nim c -d:release --skipParentCfg --passL:"-o markdown.m.wasm" markdown.nim"""

  of "build":
    exec "nim c -o:nev.exe --opt:speed --cc:clang --passC:-Wno-incompatible-function-pointer-types -d:enableSystemClipboard=true -d:exposeScriptingApi --debuginfo:on -g --lineDir:off --passC:-g --passC:-std=gnu11 --nimcache:nimcache/debug_clang" &
      compileIconResource() & " " & wasmtimeCompilerArgs() & " ./src/desktop_main.nim"

  of "nuigi-deps-static":
    buildNuigiStaticDependencies()

  of "modules":
    exec "./bin/build.exe "

  of "modules-f":
    exec "./bin/build.exe -f"

  of "build-dynamic":
    buildNev(extraArgs="-d:useDynlib", cacheDir="nimcache/nev-dynamic")

  of "build-static":
    buildNev()

  of "build-perf":
    let output = when defined(windows): "nev-perf.exe" else: "nev-perf"
    buildNev(output, "-d:perfProfiler -d:nuigiPerfProfiler", "nimcache/nev-perf")

  of "debug-win":
    echo &"Build debug for windows..."
    # exec """nim c --out:nev.exe -D:enableGui=true -D:enableTerminal=true -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} --cc:clang --passC:-Wno-incompatible-function-pointer-types "--passL:-ladvapi32.lib -luser32.lib" --passC:-std=gnu11 src/desktop_main.nim"""
    buildAndCopyWasmtime()
    buildNuigiStaticDependencies()
    buildNev()

  of "package-win":
    echo &"Package for windows..."
    mkDir releaseWindows
    copySharedFilesTo releaseWindows
    cpFile2 "nev.exe", releaseWindows, optional=true
    cpFile2 "nevg.exe", releaseWindows, optional=true
    cpFile2 "nevt.exe", releaseWindows, optional=true
    cpFile2 "wasmtime.dll", releaseWindows, optional=true

    if fileExists(&"{releaseWindows}.zip"):
      echo &"Remove existing {releaseWindows}.zip"
      rmFile(&"{releaseWindows}.zip")

    echo &"Create {releaseWindows}.zip"
    exec(&"powershell -Command Compress-Archive -Force -Path {releaseWindows} -DestinationPath {releaseWindows}.zip")

  of "release-linux":
    buildWasmtime()
    buildNuigiStaticDependencies()
    echo &"Build release for windows..."
    exec "atlas rep"
    exec """nim c --out:nev --cc:clang --passC:-Wno-incompatible-function-pointer-types -D:enableGui=false -D:enableTerminal=true --app:console -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} """ &
      wasmtimeCompilerArgs() & " src/desktop_main.nim"
    exec """nim c --out:nevg --cc:clang --passC:-Wno-incompatible-function-pointer-types -D:enableGui=true -D:enableTerminal=false --app:gui -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} """ &
      wasmtimeCompilerArgs() & " src/desktop_main.nim"
    buildWasmtime(musl=true)
    exec """nim c --out:nev-musl --cc:clang --passC:-Wno-incompatible-function-pointer-types -D:enableGui=false -D:enableTerminal=true --app:console -d:musl -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} """ &
      wasmtimeCompilerArgs(musl=true) & " src/desktop_main.nim"

  of "debug-linux":
    echo &"Build debug for linux..."
    # exec &"""nim c --out:nev --cc:clang --passC:-Wno-incompatible-function-pointer-types -D:enableGui=true -D:enableTerminal=true --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} src/desktop_main.nim"""
    buildWasmtime()
    buildNuigiStaticDependencies()
    buildNev()

  of "package-linux":
    echo &"Package for linux..."
    mkDir releaseLinux
    copySharedFilesTo releaseLinux
    if fileExists "nev":
      cpFile2 "nev", releaseLinux
      if fileExists "nevg":
        cpFile2 "nevg", releaseLinux

      echo &"Create {releaseLinux}.tar"
      exec(&"tar -jcvf {releaseLinux}.tar {releaseLinux}")

    if fileExists "nev-musl":
      mkDir releaseLinuxMusl
      copySharedFilesTo releaseLinuxMusl
      if fileExists "nev":
        cpFile2 "nev-musl", releaseLinuxMusl
        mvFile(releaseLinuxMusl / "nev-musl", releaseLinuxMusl / "nev")

      echo &"Create {releaseLinuxMusl}.tar"
      exec(&"tar -jcvf {releaseLinuxMusl}.tar {releaseLinuxMusl}")

  else:
    echo &"Unknown command '{cmds[i]}'"
    quit 1

quit exitCode
