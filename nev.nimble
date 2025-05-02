# Package

# This is required for LSP to work with this file and not show tons of errros
when defined(nimsuggest):
  import system/nimscript
  var commandLineParams: seq[string]

version       = "0.3.0"
author        = "Nimaoth"
description   = "Text Editor"
license       = "MIT"
srcDir        = "src"
bin           = @["nev"]

# Dependencies

requires "nim >= 2.0.0"
requires "nimgen >= 0.5.4"
requires "https://github.com/Nimaoth/vmath#661bdaa"
requires "https://github.com/Nimaoth/pixie >= 5.0.10"
requires "chroma >= 0.2.7"
requires "winim >= 3.9.4"
requires "fusion >= 1.2"
requires "nimsimd >= 1.2.13"
requires "regex >= 0.25.0"
requires "glob#64f71af" # "glob >= 0.11.2" # the newest version of glob doesn't have a version but is required for Nim 2.0
requires "patty >= 0.3.5"
requires "nimclipboard >= 0.1.2"
requires "npeg >= 1.3.0"
requires "asynctools#a1a17d0"
requires "stew >= 0.1.0"
requires "results >= 0.5.0"
requires "chronos >= 4.0.3"
requires "https://github.com/Nimaoth/fsnotify >= 0.1.6"
requires "https://github.com/Nimaoth/ws >= 0.5.0"
requires "https://github.com/Nimaoth/windy >= 0.0.5"
requires "https://github.com/Nimaoth/wasm3 >= 0.1.17"
requires "https://github.com/Nimaoth/lrucache.nim >= 1.1.4"
requires "https://github.com/Nimaoth/boxy >= 0.4.4"
requires "https://github.com/Nimaoth/nimtreesitter-api >= 0.1.20"
requires "https://github.com/Nimaoth/nimwasmtime >= 0.2.1"
requires "https://github.com/Nimaoth/nimsumtree >= 0.5.6"
requires "https://github.com/Nimaoth/zippy >= 0.10.17"

# Use this to include all treesitter languages (takes longer to download)
requires "https://github.com/Nimaoth/nimtreesitter >= 0.1.11"

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
  exec "nim doc --project --index:on --git.url:https://github.com/Nimaoth/Nev/ --git.commit:main ./scripting/plugin_runtime.nim"
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

task setup2, "Setup":
  exec "nimble setup"
  when defined(windows):
    cpFile "nimble.paths", "nimble-win.paths"
  else:
    cpFile "nimble.paths", "nimble-linux.paths"

task buildDesktop, "Build the desktop version":
  selfExec fmt"c -o:nev{exe} -d:exposeScriptingApi -d:appBuildWasmtime --passC:-std=gnu11 {getCommandLineParams()} ./src/desktop_main.nim"
  # selfExec fmt"c --passL:advapi32.lib -o:nev{exe} -d:exposeScriptingApi -d:appBuildWasmtime {getCommandLineParams()} ./src/desktop_main.nim"
  # selfExec fmt"c -o:nev{exe} -d:exposeScriptingApi -d:appBuildWasmtime --objChecks:off --fieldChecks:off --rangeChecks:off --boundChecks:off --overflowChecks:off --floatChecks:off --nanChecks:off --infChecks:off {getCommandLineParams()} ./src/desktop_main.nim"

task buildTerminal, "Build the terminal version":
  selfExec fmt"c -o:nev{exe} -d:exposeScriptingApi -d:appBuildWasmtime -d:enableTerminal -d:enableGui=false --passC:-std=gnu11 {getCommandLineParams()} ./src/desktop_main.nim"

task buildTerminalDebug, "Build the terminal version (debug)":
  selfExec fmt"c -o:nev{exe} --debuginfo:on --debugger:native --lineDir:off -d:exposeScriptingApi -d:appBuildWasmtime -d:enableTerminal -d:enableGui=false --passC:-std=gnu11 {getCommandLineParams()} ./src/desktop_main.nim"

task buildDebug, "Build the debug version":
  selfExec fmt"c -o:nev{exe} --debuginfo:on --debugger:native --lineDir:off -d:exposeScriptingApi -d:appBuildWasmtime --passC:-std=gnu11 --nimcache:nimcache/debug {getCommandLineParams()} ./src/desktop_main.nim"

task buildDebugVcc, "Build the debug version":
  selfExec fmt"c -o:nevd{exe} -d:debug -u:release --linetrace:on --stacktrace:on --debuginfo:on -d:treesitterBuiltins= -d:futureLogging --debugger:native --nimcache:C:/nc -d:enableSystemClipboard=false --cc:vcc --lineDir:off -d:exposeScriptingApi -d:appBuildWasmtime {getCommandLineParams()} ./src/desktop_main.nim"

task buildDesktopClang, "Build the desktop version":
  selfExec fmt"c -o:nev{exe} --cc:clang --passC:-Wno-incompatible-function-pointer-types --passL:-ladvapi32.lib -d:enableSystemClipboard=false -d:exposeScriptingApi -d:appBuildWasmtime --lineDir:on --panics:on --passC:-g --passC:-std=gnu11 --stacktrace:off --linetrace:off --nimcache:nimcache/release_clang {getCommandLineParams()} ./src/desktop_main.nim"

task buildDesktopDebugClang, "Build the desktop version (debug)":
  selfExec fmt"c -o:nev{exe} --cc:clang --passC:-Wno-incompatible-function-pointer-types --passL:-ladvapi32.lib --passL:-luser32.lib -d:enableSystemClipboard=true -d:exposeScriptingApi -d:enableSysFatalStackTrace --debuginfo:on -g --lineDir:on --panics:on --passC:-g --passC:-std=gnu11 --stacktrace:off --linetrace:off --nimcache:nimcache/debug_clang {getCommandLineParams()} ./src/desktop_main.nim"

task buildDesktopDebug, "Build the desktop version (debug)":
  selfExec fmt"c -o:nevd{exe} -d:exposeScriptingApi -d:appBuildWasmtime --debuginfo:on -g -D:debug --lineDir:on --panics:off --passC:-g --passC:-std=gnu11 --stacktrace:on --linetrace:on --nimcache:nimcache/debug {getCommandLineParams()} ./src/desktop_main.nim"
  # selfExec fmt"c -o:nev{exe} -d:exposeScriptingApi -d:appBuildWasmtime --objChecks:off --fieldChecks:off --rangeChecks:off --boundChecks:off --overflowChecks:off --floatChecks:off --nanChecks:off --infChecks:off {getCommandLineParams()} ./src/desktop_main.nim"

task buildDesktopWindows, "Build the desktop version for windows":
  selfExec fmt"c -o:nev{exe} {crossCompileWinArgs} -d:exposeScriptingApi -d:appBuildWasmtime {getCommandLineParams()} ./src/desktop_main.nim"

task buildDll, "Build the dll version":
  # Disable clipboard for now because it breaks hot reloading
  selfExec fmt"c -o:nev.dll -d:exposeScriptingApi -d:appBuildWasmtime -d:enableSystemClipboard=false --noMain --app:lib {getCommandLineParams()} ./src/dynlib_main.nim"

task buildWorkspaceServer, "Build the server for hosting workspaces":
  selfExec fmt"c -o:./tools/workspace-server{exe} {getCommandLineParams()} ./src/servers/workspace_server.nim"

task buildLanguagesServer, "Build the server for hosting languages servers":
  selfExec fmt"c -o:./tools/languages-server{exe} {getCommandLineParams()} ./src/servers/languages_server.nim"

task buildRemoteWorkspaceHost, "Build the server for hosting workspaces and language servers":
  selfExec fmt"c -o:./tools/remote-workspace-host{exe} {getCommandLineParams()} ./src/servers/server_main.nim"

task buildRemoteWorkspaceHostWindows, "Build the server for hosting workspaces and language servers":
  selfExec fmt"c -o:./tools/remote-workspace-host{exe} {crossCompileWinArgs} {getCommandLineParams()} ./src/servers/server_main.nim"

task buildLspWs, "Build the websocket proxy for language servers":
  selfExec fmt"c -o:./tools/lsp-ws{exe} {getCommandLineParams()} ./tools/lsp_ws.nim"

task buildLspWsWindows, "Build the websocket proxy for language servers":
  selfExec fmt"c -o:./tools/lsp-ws{exe} {crossCompileWinArgs} {getCommandLineParams()} ./tools/lsp_ws.nim"

task buildNimConfigWasm, "Compile the nim script config file to wasm":
  withDir "config":
    selfExec fmt"c -d:release -o:wasm/{projectName()}.wasm {getCommandLineParams()}"

task buildNimConfigWasmAll, "Compile the nim script config file to wasm":
  exec fmt"nimble buildNimConfigWasm keybindings_plugin.nim"
  exec fmt"nimble buildNimConfigWasm harpoon.nim"
  exec fmt"nimble buildNimConfigWasm vscode_config_plugin.nim"

task flamegraph, "Perf/flamegraph":
  exec "PERF=/usr/lib/linux-tools/5.4.0-186-generic/perf ~/.cargo/bin/flamegraph -o flamegraph.svg -- nevtd -s:linux.nev-session"
