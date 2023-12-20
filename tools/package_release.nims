import std/[os]

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

proc cpFile2(src: string, dst: string) =
  let name = src.splitPath[1]
  if fileExists src:
    echo "Copy ", name, " to ", dst/name
    cpFile src, dst/name
  else:
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
mkDir releaseWeb

proc copySharedFilesTo(dir: string) =
  cpDir2 "config", dir
  cpDir2 "fonts", dir
  cpDir2 "languages", dir
  cpDir2 "themes", dir
  cpDir2 "scripting", dir
  cpDir2 "docs", dir
  mkDir dir/"src"
  cpFile2 "src/scripting_api.nim", dir/"src"
  cpFile2 "src/misc/timer.nim", dir/"src/misc"
  cpFile2 "src/misc/id.nim", dir/"src/misc"
  cpFile2 "src/misc/myjsonutils.nim", dir/"src/misc"
  cpFile2 "src/misc/event.nim", dir/"src/misc"
  cpFile2 "src/misc/util.nim", dir/"src/misc"
  cpFile2 "src/misc/macro_utils.nim", dir/"src/misc"
  cpFile2 "src/misc/wrap.nim", dir/"src/misc"
  cpDir2 "LICENSES", dir
  cpFile2 "LICENSE", dir
  cpFile2 "absytree.nimble", dir
  cpFile2 "config.nims", dir

copySharedFilesTo releaseWindows
copySharedFilesTo releaseLinux
copySharedFilesTo releaseWeb

cpFile2 "ast.exe", releaseWindows
cpFile2 "tools/absytree-server.exe", releaseWindows
cpFile2 "tools/nimsuggest-ws.exe", releaseWindows
# cpFile2 "libgcc_s_seh-1.dll", releaseWindows
# cpFile2 "libstdc++-6.dll", releaseWindows
# cpFile2 "libwinpthread-1.dll", releaseWindows

cpFile2 "ast", releaseLinux
cpFile2 "tools/absytree-server", releaseLinux
cpFile2 "tools/nimsuggest-ws", releaseLinux

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