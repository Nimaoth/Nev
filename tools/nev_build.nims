import std/[os, parseopt, compilesettings, strformat, strutils]

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
  if fileExists src:
    echo "Copy ", name, " to ", dst/name
    cpFile src, dst/name
  else:
    if not optional:
      echo "[ERROR] File " & src & " does not exist"
      exitCode = 1

template catch(exp: untyped, then: untyped): untyped =
  try:
    exp
  except CatchableError:
    then

############################################################################################################

const version = "0.5.1"
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

const staticLibDir = "nimcache" / "nuigi-static" / "libs"
const staticLibraries = when defined(windows):
    ["SDL3.lib", "freetype.lib"]
  else:
    ["libSDL3.a", "libfreetype.a"]

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

proc buildStatic() =
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
  let staticArgs = "-d:sdlPlatform -d:nuiNoHarfbuzz -u:useDynlib -u:sdl3 -u:freetypeStatic --dynlibOverride:SDL3 --dynlibOverride:freetype"
  let pathArgs = " " & ("--path:" & (nuigiDir / "src")).quoteShell &
    " " & ("--path:" & (nuigiDir / "vendor" / "nimfreetype")).quoteShell
  let output = when defined(windows): "nev-static.exe" else: "nev-static"
  exec "nim c -o:" & output & " --opt:speed --cc:clang --passC:-Wno-incompatible-function-pointer-types -d:enableSystemClipboard=true -d:exposeScriptingApi --debuginfo:on -g --lineDir:off --passC:-g --passC:-std=gnu11 --nimcache:nimcache/nev-static " &
    staticArgs & pathArgs & linkArgs & " src/desktop_main.nim"

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
    of "help", "h":
      echo """Nev build commands (run from the repository root):
  nuigi-deps-static  Build and stage Nuigi's static SDL3 and FreeType archives.
  build-static      Build nev-static using those archives, without HarfBuzz/FriBidi.
  --nuigi-dir:PATH   Nuigi checkout (default: NUIGI_DIR or deps/nuigi).
Existing build, release and package commands are unchanged."""
      quit 0

  of cmdEnd: assert(false) # cannot happen

echo &"Run commands {cmds}"
var i = 0
while i < cmds.len:
  defer:
    inc i
  case cmds[i]
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
    try:
      exec """nim c --out:nev.exe -D:enableGui=false -D:enableTerminal=true --app:console -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} --cc:clang --passC:-Wno-incompatible-function-pointer-types --passL:-ladvapi32.lib src/desktop_main.nim"""
      exec """./rcedit-x64.exe nev.exe --set-icon ./res/icon.ico"""
    finally:
      discard
    try:
      exec """nim c --out:nevg.exe -D:enableGui=true -D:enableTerminal=false --app:gui -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} --cc:clang --passC:-Wno-incompatible-function-pointer-types "--passL:-ladvapi32.lib -luser32.lib" src/desktop_main.nim"""
      exec """./rcedit-x64.exe nevg.exe --set-icon ./res/icon.ico"""
    finally:
      discard

  of "markdown-plugin":
    echo &"Build markdown plugin..."
    withDir "plugins/markdown":
      # todo: on windows
      # exec """powershell -Command ./emsdk/emsdk.ps1 activate 4.0.10"""
      exec """nim c -d:release --skipParentCfg --passL:"-o markdown.m.wasm" markdown.nim"""

  of "build":
    exec "nim c -o:nev.exe --opt:speed --cc:clang --passC:-Wno-incompatible-function-pointer-types -d:enableSystemClipboard=true -d:exposeScriptingApi --debuginfo:on -g --lineDir:off --passC:-g --passC:-std=gnu11 --nimcache:nimcache/debug_clang ./src/desktop_main.nim"

  of "nuigi-deps-static":
    buildNuigiStaticDependencies()

  of "build-static":
    buildStatic()

  of "debug-win":
    echo &"Build debug for windows..."
    # exec """nim c --out:nev.exe -D:enableGui=true -D:enableTerminal=true -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} --cc:clang --passC:-Wno-incompatible-function-pointer-types "--passL:-ladvapi32.lib -luser32.lib" --passC:-std=gnu11 src/desktop_main.nim"""
    buildNuigiStaticDependencies()
    buildStatic()

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
    echo &"Build release for windows..."
    exec "atlas rep"
    exec """nim c --out:nev --cc:clang --passC:-Wno-incompatible-function-pointer-types -D:enableGui=false -D:enableTerminal=true --app:console -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} src/desktop_main.nim"""
    exec """nim c --out:nevg --cc:clang --passC:-Wno-incompatible-function-pointer-types -D:enableGui=true -D:enableTerminal=false --app:gui -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} src/desktop_main.nim"""
    exec """nim c --out:nev-musl --cc:clang --passC:-Wno-incompatible-function-pointer-types -D:enableGui=false -D:enableTerminal=true --app:console -d:musl -d:nimWasmtimeBuildMusl -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} src/desktop_main.nim"""

  of "debug-linux":
    echo &"Build debug for linux..."
    # exec &"""nim c --out:nev --cc:clang --passC:-Wno-incompatible-function-pointer-types -D:enableGui=true -D:enableTerminal=true --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={isCINimbleCached} src/desktop_main.nim"""
    buildNuigiStaticDependencies()
    buildStatic()

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
