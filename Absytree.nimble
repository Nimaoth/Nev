# Package

version       = "0.1.1"
author        = "Nimaoth"
description   = "Text Editor"
license       = "MIT"
srcDir        = "src"
bin           = @["ast"]

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
requires "https://github.com/Nimaoth/nimtreesitter-api >= 0.1.3"

import strformat, strutils

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

proc getCommandLineParams(): string =
  defer:
    echo fmt"Additional command line params: {result}"
  if commandLineParams.len < 3:
    return ""
  return commandLineParams[3..^1].join(" ")

task buildDesktop, "Build the desktop version":
  selfExec fmt"c -o:ast{exe} -d:exposeScriptingApi {getCommandLineParams()} ./src/absytree.nim"

task buildDesktopWindows, "Build the desktop version for windows":
  selfExec fmt"c -o:ast.exe {crossCompileWinArgs} -d:exposeScriptingApi {getCommandLineParams()} ./src/absytree.nim"

task buildWorkspaceServer, "Build the server for hosting workspaces":
  selfExec fmt"c -o:workspace-server{exe} {getCommandLineParams()} ./src/servers/workspace_server.nim"

task buildLanguagesServer, "Build the server for hosting languages servers":
  selfExec fmt"c -o:languages-server{exe} {getCommandLineParams()} ./src/servers/languages_server.nim"

task buildAbsytreeServer, "Build the server for hosting workspaces and language servers":
  selfExec fmt"c -o:absytree-server{exe} {getCommandLineParams()} ./src/servers/absytree_server.nim"

task buildAbsytreeServerWindows, "Build the server for hosting workspaces and language servers":
  selfExec fmt"c -o:absytree-server.exe {crossCompileWinArgs} {getCommandLineParams()} ./src/servers/absytree_server.nim"

task buildNimsuggestWS, "Build the server for hosting workspaces and language servers":
  selfExec fmt"c -o:nimsuggest-ws{exe} {getCommandLineParams()} ./nimsuggest_ws.nim"

task buildNimsuggestWSWindows, "Build the server for hosting workspaces and language servers":
  selfExec fmt"c -o:nimsuggest-ws.exe {crossCompileWinArgs} {getCommandLineParams()} ./nimsuggest_ws.nim"

task buildBrowser, "Build the browser version":
  selfExec fmt"js -o:ast.js -d:exposeScriptingApi -d:vmathObjBased -d:enableTableIdCacheChecking --boundChecks:on --rangeChecks:on {getCommandLineParams()} ./src/absytree_js.nim"

task buildNimConfigWasm, "Compile the nim script config file to wasm":
  withDir "config":
    selfExec fmt"c -d:release -o:./absytree_config_wasm.wasm {getCommandLineParams()} ./absytree_config_wasm.nim"