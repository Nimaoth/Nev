# Package

version       = "0.1.1"
author        = "Nimaoth"
description   = "Text Editor"
license       = "MIT"
srcDir        = "src"
bin           = @["ast"]

# Dependencies

requires "nim >= 2.0.0"
requires "nimgen >= 0.5.4"
requires "https://github.com/Nimaoth/vmath#661bdaa"
requires "pixie >= 5.0.7"
requires "chroma >= 0.2.7"
requires "winim >= 3.8.1"
requires "fusion >= 1.2"
requires "print >= 1.0.2"
requires "fuzzy >= 0.1.0"
requires "nimsimd >= 1.2.4"
requires "regex >= 0.20.2"
requires "glob#64f71af" # "glob >= 0.11.2" # the newest version of glob doesn't have a version but is required for Nim 2.0
requires "patty >= 0.3.5"
requires "nimclipboard >= 0.1.2"
requires "npeg >= 0.12.0"
# requires "results >= 0.4.0" # todo: use that at some point?
# requires "chronos >= 4.0.2" # todo: switch to this at some point
requires "https://github.com/Nimaoth/ws >= 0.5.0"
requires "https://github.com/Nimaoth/windy >= 0.0.2"
requires "https://github.com/Nimaoth/wasm3 >= 0.1.13"
requires "https://github.com/Nimaoth/lrucache.nim >= 1.1.4"
requires "https://github.com/Nimaoth/boxy >= 0.4.2"
requires "https://github.com/Nimaoth/nimscripter >= 1.0.21"
requires "https://github.com/Nimaoth/nimtreesitter-api >= 0.1.8"
requires "https://github.com/Nimaoth/nimwasmtime >= 0.1.0"

# Use this to include all treesitter languages (takes longer to download)
requires "https://github.com/Nimaoth/nimtreesitter >= 0.1.3"

# Use these to only install specific treesitter languages. These don't work with the lock file
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_nim >= 0.1.3"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_cpp >= 0.1.3"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_agda >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_bash >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_c >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_css >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_go >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_html >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_java >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_javascript >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_python >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_ruby >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_rust >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_scala >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_c_sharp >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_haskell >= 0.1.2"
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_zig >= 0.1.4"

# typescript doesn't build on linux
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_typescript >= 0.1.2"

# php doesn't build
# requires "https://github.com/Nimaoth/nimtreesitter?subdir=treesitter_php >= 0.1.2"

import strformat, strutils

task createScriptingDocs, "Build the documentation for the scripting API":
  exec "nim doc --project --index:on --git.url:https://github.com/Nimaoth/Absytree/ --git.commit:main ./scripting/absytree_runtime.nim"
  exec "nim buildIndex -o:./scripting/htmldocs/theindex.html ./scripting/htmldocs"
  exec "nim ./tools/postprocess_docs.nims"

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
  selfExec fmt"c -o:ast{exe} -d:exposeScriptingApi --passC:-std=gnu11 {getCommandLineParams()} ./src/absytree.nim"
  # selfExec fmt"c --passL:advapi32.lib -o:ast{exe} -d:exposeScriptingApi {getCommandLineParams()} ./src/absytree.nim"
  # selfExec fmt"c -o:ast{exe} -d:exposeScriptingApi --objChecks:off --fieldChecks:off --rangeChecks:off --boundChecks:off --overflowChecks:off --floatChecks:off --nanChecks:off --infChecks:off {getCommandLineParams()} ./src/absytree.nim"

task buildTerminal, "Build the terminal version":
  selfExec fmt"c -o:ast{exe} -d:exposeScriptingApi -d:enableTerminal -d:enableGui=false --passC:-std=gnu11 {getCommandLineParams()} ./src/absytree.nim"

task buildDesktopDebug, "Build the desktop version (debug)":
  selfExec fmt"c -o:astd{exe} -d:exposeScriptingApi --stacktrace --linetrace --debuginfo -g -D:debug --lineDir:off --nilChecks:on --passC:-std=gnu11 {getCommandLineParams()} ./src/absytree.nim"
  # selfExec fmt"c -o:ast{exe} -d:exposeScriptingApi --objChecks:off --fieldChecks:off --rangeChecks:off --boundChecks:off --overflowChecks:off --floatChecks:off --nanChecks:off --infChecks:off {getCommandLineParams()} ./src/absytree.nim"

task buildDesktopWindows, "Build the desktop version for windows":
  selfExec fmt"c -o:ast{exe} {crossCompileWinArgs} -d:exposeScriptingApi {getCommandLineParams()} ./src/absytree.nim"

task buildDll, "Build the dll version":
  # Disable clipboard for now because it breaks hot reloading
  selfExec fmt"c -o:ast.dll -d:exposeScriptingApi -d:enableSystemClipboard=false --noMain --app:lib {getCommandLineParams()} ./src/absytree_dynlib.nim"

task buildWorkspaceServer, "Build the server for hosting workspaces":
  selfExec fmt"c -o:./tools/workspace-server{exe} {getCommandLineParams()} ./src/servers/workspace_server.nim"

task buildLanguagesServer, "Build the server for hosting languages servers":
  selfExec fmt"c -o:./tools/languages-server{exe} {getCommandLineParams()} ./src/servers/languages_server.nim"

task buildAbsytreeServer, "Build the server for hosting workspaces and language servers":
  selfExec fmt"c -o:./tools/absytree-server{exe} {getCommandLineParams()} ./src/servers/absytree_server.nim"

task buildAbsytreeServerWindows, "Build the server for hosting workspaces and language servers":
  selfExec fmt"c -o:./tools/absytree-server{exe} {crossCompileWinArgs} {getCommandLineParams()} ./src/servers/absytree_server.nim"

task buildLspWs, "Build the websocket proxy for language servers":
  selfExec fmt"c -o:./tools/lsp-ws{exe} {getCommandLineParams()} ./tools/lsp_ws.nim"

task buildLspWsWindows, "Build the websocket proxy for language servers":
  selfExec fmt"c -o:./tools/lsp-ws{exe} {crossCompileWinArgs} {getCommandLineParams()} ./tools/lsp_ws.nim"

task buildBrowser, "Build the browser version":
  selfExec fmt"js -o:./build/ast.js -d:exposeScriptingApi -d:vmathObjBased -d:enableTableIdCacheChecking -d:enableAst=true {getCommandLineParams()} ./src/absytree_js.nim"
  # selfExec fmt"js -o:./build/ast.js -d:exposeScriptingApi -d:vmathObjBased -d:enableTableIdCacheChecking --objChecks:off --fieldChecks:off --rangeChecks:off --boundChecks:off --overflowChecks:off --floatChecks:off --nanChecks:off --infChecks:off --jsbigint64:off {getCommandLineParams()} ./src/absytree_js.nim"

task buildNimConfigWasm, "Compile the nim script config file to wasm":
  withDir "config":
    selfExec fmt"c -d:release -o:wasm/{projectName()}.wasm {getCommandLineParams()}"
