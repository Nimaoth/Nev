# Package

version       = "0.1.1"
author        = "Nimaoth"
description   = "Programming language + editor"
license       = "MIT"
srcDir        = "src"
bin           = @["abs"]

# Dependencies

requires "nim >= 2.0.0"
requires "chroma >= 0.2.7"
requires "winim >= 3.8.1"
requires "fusion >= 1.2"
requires "print >= 1.0.2"
requires "fuzzy >= 0.1.0"
requires "nimsimd >= 1.2.4"
requires "regex >= 0.20.2"
requires "glob >= 0.11.2"
requires "patty >= 0.3.5"
requires "https://github.com/Nimaoth/ws >= 0.5.0"
requires "https://github.com/Nimaoth/windy >= 0.0.1"
requires "https://github.com/Nimaoth/wasm3 >= 0.1.12"
requires "https://github.com/Nimaoth/lrucache.nim >= 1.1.4"
requires "https://github.com/Nimaoth/boxy >= 0.4.2"
requires "https://github.com/Nimaoth/nimscripter >= 1.0.18"
requires "https://github.com/Nimaoth/nimtreesitter-api >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_nim >= 0.1.1"

import strformat

task createScriptingDocs, "Build the documentation for the scripting API":
  exec "nim doc --project --index:on --git.url:https://github.com/Nimaoth/Absytree/ --git.commit:main ./scripting/absytree_runtime.nim"
  exec "nim buildIndex -o:./scripting/htmldocs/theindex.html ./scripting/htmldocs"
  exec "nim ./postprocess_docs.nims"

const exe = when defined(windows):
    ".exe"
  else:
    ""

echo fmt"extension: {exe}"

const crossCompileWinArgs = "--gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc --os:windows --cpu:amd64 -d:crossCompileToWindows"

task buildDesktop, "Build the desktop version":
  selfExec fmt"c -o:ast{exe} -d:exposeScriptingApi ./src/absytree.nim"

task buildDesktopWindows, "Build the desktop version for windows":
  selfExec fmt"c -o:ast.exe {crossCompileWinArgs} -d:exposeScriptingApi ./src/absytree.nim"

task buildWorkspaceServer, "Build the server for hosting workspaces":
  selfExec fmt"c -o:workspace-server{exe} ./src/servers/workspace_server.nim"

task buildLanguagesServer, "Build the server for hosting languages servers":
  selfExec fmt"c -o:languages-server{exe} ./src/servers/languages_server.nim"

task buildAbsytreeServer, "Build the server for hosting workspaces and language servers":
  selfExec fmt"c -o:absytree-server{exe} ./src/servers/absytree_server.nim"

task buildAbsytreeServerWindows, "Build the server for hosting workspaces and language servers":
  selfExec fmt"c -o:absytree-server.exe {crossCompileWinArgs} ./src/servers/absytree_server.nim"

task buildNimsuggestWS, "Build the server for hosting workspaces and language servers":
  selfExec fmt"c -o:nimsuggest-ws{exe} ./nimsuggest_ws.nim"

task buildNimsuggestWSWindows, "Build the server for hosting workspaces and language servers":
  selfExec fmt"c -o:nimsuggest-ws.exe {crossCompileWinArgs} ./nimsuggest_ws.nim"

task buildBrowser, "Build the browser version":
  selfExec "js -o:ast.js -d:exposeScriptingApi -d:vmathObjBased -d:enableTableIdCacheChecking --boundChecks:on --rangeChecks:on ./src/absytree_js.nim"

task buildNimConfigWasm, "Compile the nim script config file to wasm":
  withDir "config":
    selfExec "c -d:release -o:./absytree_config_wasm.wasm ./absytree_config_wasm.nim"