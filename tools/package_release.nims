import std/[os, parseopt, compilesettings]

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

const releaseWindows = "release_windows"
const releaseLinux = "release_linux"

proc copySharedFilesTo(dir: string) =
  cpDir2 "config", dir
  cpDir2 "fonts", dir
  cpDir2 "languages", dir
  cpDir2 "themes", dir
  cpDir2 "scripting", dir
  cpDir2 "docs", dir
  mkDir dir / "src"
  mkDir dir / "src/misc"
  cpFile2 "src/scripting_api.nim", dir / "src"
  cpFile2 "src/input_api.nim", dir / "src"
  cpFile2 "src/misc/timer.nim", dir / "src/misc"
  cpFile2 "src/misc/id.nim", dir / "src/misc"
  cpFile2 "src/misc/myjsonutils.nim", dir / "src/misc"
  cpFile2 "src/misc/event.nim", dir / "src/misc"
  cpFile2 "src/misc/util.nim", dir / "src/misc"
  cpFile2 "src/misc/macro_utils.nim", dir / "src/misc"
  cpFile2 "src/misc/wrap.nim", dir / "src/misc"
  cpFile2 "src/misc/custom_unicode.nim", dir / "src/misc"
  cpFile2 "src/misc/embed_source.nim", dir / "src/misc"
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

var packageWindows = false
var packageLinux = false

var optParser = initOptParser("")
for kind, key, val in optParser.getopt():
  case kind
  of cmdArgument:
    discard

  of cmdLongOption, cmdShortOption:
    case key
    of "windows", "w":
      packageWindows = true
    of "linux", "l":
      packageLinux = true

  of cmdEnd: assert(false) # cannot happen

if packageWindows:
  echo "Package windows..."
  mkDir releaseWindows
  copySharedFilesTo releaseWindows
  if fileExists "nev.exe":
    cpFile2 "nevg.exe", releaseWindows
    cpFile2 "nev.exe", releaseWindows
    cpFile2 "nevt.exe", releaseWindows, optional=true
    cpFile2 "wasmtime.dll", releaseWindows, optional=true
    # cpFile2 "tools/remote-workspace-host.exe", releaseWindows
    # cpFile2 "tools/lsp-ws.exe", releaseWindows

if packageLinux:
  echo "Package linux..."
  mkDir releaseLinux
  copySharedFilesTo releaseLinux
  if fileExists "nev":
    cpFile2 "nevg", releaseLinux
    cpFile2 "nev", releaseLinux
    cpFile2 "nevt", releaseLinux, optional=true
    cpFile2 "nev-musl", releaseLinux
    # cpFile2 "tools/remote-workspace-host", releaseLinux
    # cpFile2 "tools/lsp-ws", releaseLinux

quit exitCode