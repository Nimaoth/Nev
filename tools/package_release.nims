import std/[os, parseopt]

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
const releaseWeb = "release_web"

mkDir releaseWindows
mkDir releaseLinux
# mkDir releaseWeb

proc copySharedFilesTo(dir: string) =
  cpDir2 "config", dir
  cpDir2 "fonts", dir
  cpDir2 "languages", dir
  cpDir2 "themes", dir
  cpDir2 "scripting", dir
  cpDir2 "docs", dir
  mkDir dir/"src"
  mkDir dir/"src/misc"
  cpFile2 "src/scripting_api.nim", dir/"src"
  cpFile2 "src/input_api.nim", dir/"src"
  cpFile2 "src/misc/timer.nim", dir/"src/misc"
  cpFile2 "src/misc/id.nim", dir/"src/misc"
  cpFile2 "src/misc/myjsonutils.nim", dir/"src/misc"
  cpFile2 "src/misc/event.nim", dir/"src/misc"
  cpFile2 "src/misc/util.nim", dir/"src/misc"
  cpFile2 "src/misc/macro_utils.nim", dir/"src/misc"
  cpFile2 "src/misc/wrap.nim", dir/"src/misc"
  cpFile2 "src/misc/custom_unicode.nim", dir/"src/misc"
  cpDir2 "LICENSES", dir
  cpFile2 "LICENSE", dir
  cpFile2 "absytree.nimble", dir
  cpFile2 "config.nims", dir

var packageWindows = false
var packageLinux = false
var packageWeb = false

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
    of "web", "W":
      packageWeb = true

  of cmdEnd: assert(false) # cannot happen

if packageWindows:
  echo "Package windows..."
  copySharedFilesTo releaseWindows
  if fileExists "ast.exe":
    cpFile2 "astg.exe", releaseWindows
    cpFile2 "ast.exe", releaseWindows
    cpFile2 "astt.exe", releaseWindows, optional=true
    cpFile2 "wasmtime.dll", releaseWindows, optional=true
    cpFile2 "tools/absytree-server.exe", releaseWindows
    cpFile2 "tools/lsp-ws.exe", releaseWindows

if packageLinux:
  echo "Package linux..."
  copySharedFilesTo releaseLinux
  if fileExists "ast":
    cpFile2 "astg", releaseLinux
    cpFile2 "ast", releaseLinux
    cpFile2 "astt", releaseLinux, optional=true
    cpFile2 "ast-musl", releaseLinux
    cpFile2 "tools/absytree-server", releaseLinux
    cpFile2 "tools/lsp-ws", releaseLinux

if packageWeb:
  echo "Package web..."
  if fileExists "build/ast.js":
    copySharedFilesTo releaseWeb
    cpFile2 "build/ast.js", releaseWeb
    cpFile2 "web/absytree_browser.html", releaseWeb
    cpFile2 "web/ast_glue.js", releaseWeb
    cpFile2 "web/scripting_runtime.js", releaseWeb
    withDir releaseWeb:
      catch exec("wget -Otree-sitter.js https://raw.githubusercontent.com/Nimaoth/AbsytreeBrowser/main/tree-sitter.js"):
        echo "[ERROR] Failed to download tree-sitter.js"
        exitCode = 1

      catch exec("wget -Otree-sitter.wasm https://raw.githubusercontent.com/Nimaoth/AbsytreeBrowser/main/tree-sitter.wasm"):
        echo "[ERROR] Failed to download tree-sitter.wasm"
        exitCode = 1

quit exitCode