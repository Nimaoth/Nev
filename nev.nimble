# Package

# This is required for LSP to work with this file and not show tons of errros
when defined(nimsuggest):
  import system/nimscript
  var commandLineParams: seq[string]

version       = "0.5.0"
author        = "Nimaoth"
description   = "Text Editor"
license       = "MIT"
srcDir        = "src"
bin           = @["nev"]

# Dependencies

requires "nim >= 2.2.6"
requires "https://github.com/Nimaoth/vmath#661bdaa"
requires "https://github.com/Nimaoth/pixie >= 5.0.10"
requires "chroma >= 0.2.7"
requires "winim >= 3.9.4"
requires "fusion >= 1.2"
requires "https://github.com/nitely/nim-regex#cb8b7bf"
requires "glob#64f71af" # "glob >= 0.11.2" # the newest version of glob doesn't have a version but is required for Nim 2.0
requires "patty >= 0.3.5"
requires "npeg >= 1.3.0"
requires "stew >= 0.1.0"
requires "results >= 0.5.0"
requires "chronos >= 4.0.3"
requires "https://github.com/Araq/malebolgia#ab17bef"
requires "https://github.com/Nimaoth/fsnotify >= 0.1.6"
requires "https://github.com/Nimaoth/windy#e09b336"
requires "https://github.com/Nimaoth/lrucache.nim#479d4cf"
requires "https://github.com/Nimaoth/boxy#1ec24eb"
requires "https://github.com/Nimaoth/nimtreesitter-api#893dd71"
requires "https://github.com/Nimaoth/nimwasmtime#2a33f8b"
requires "https://github.com/Nimaoth/nimsumtree#9143986"
requires "https://github.com/Nimaoth/asynctools#214b057"
requires "https://github.com/Nimaoth/zippy >= 0.10.17"
requires "libssh2 >= 0.1.9"
requires "ssh2 >= 0.1.9"
requires "https://github.com/Nimaoth/nimtreesitter >= 0.1.11"

import strformat, strutils

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
  selfExec fmt"c -o:nev{exe} -d:exposeScriptingApi -d:appBuildWasmtime --passC:-std=gnu11 {getCommandLineParams()} ./src/desktop_main.nim"

task buildTerminal, "Build the terminal version":
  selfExec fmt"c -o:nev{exe} -d:exposeScriptingApi -d:appBuildWasmtime -d:enableTerminal -d:enableGui=false --passC:-std=gnu11 {getCommandLineParams()} ./src/desktop_main.nim"

task buildTerminalDebug, "Build the terminal version (debug)":
  selfExec fmt"c -o:nev{exe} --debuginfo:on --debugger:native --lineDir:off -d:exposeScriptingApi -d:appBuildWasmtime -d:enableTerminal -d:enableGui=false --passC:-std=gnu11 {getCommandLineParams()} ./src/desktop_main.nim"

task buildDebug, "Build the debug version":
  selfExec fmt"c -o:nev{exe} --debuginfo:on --debugger:native --lineDir:off -d:exposeScriptingApi -d:appBuildWasmtime --passC:-std=gnu11 --nimcache:nimcache/debug {getCommandLineParams()} ./src/desktop_main.nim"

task buildDebugVcc, "Build the debug version":
  selfExec fmt"c -o:nevd{exe} -d:debug -u:release --linetrace:on --stacktrace:on --debuginfo:on -d:treesitterBuiltins= -d:futureLogging --debugger:native --nimcache:C:/nc -d:enableSystemClipboard=false --cc:vcc --lineDir:off -d:exposeScriptingApi -d:appBuildWasmtime {getCommandLineParams()} ./src/desktop_main.nim"

task buildDesktopClang, "Build the desktop version":
  selfExec fmt"c -o:nev{exe} --cc:clang --passC:-Wno-incompatible-function-pointer-types --passL:-ladvapi32.lib -d:enableSystemClipboard=false -d:exposeScriptingApi -d:appBuildWasmtime --lineDir:on --passC:-g --passC:-std=gnu11 --nimcache:nimcache/release_clang {getCommandLineParams()} ./src/desktop_main.nim"

task buildDesktopDebugClang, "Build the desktop version (debug)":
  selfExec fmt"c -o:nev{exe} --cc:clang --passC:-Wno-incompatible-function-pointer-types --passL:-ladvapi32.lib --passL:-luser32.lib -d:enableSystemClipboard=true -d:exposeScriptingApi --passC:-std=gnu11 --nimcache:nimcache/debug_clang {getCommandLineParams()} ./src/desktop_main.nim"

task buildDesktopDebugClangLinux, "Build the desktop version (debug)":
  selfExec fmt"c -o:nev{exe} --cc:clang --passC:-Wno-incompatible-function-pointer-types -d:enableSystemClipboard=true -d:exposeScriptingApi --debuginfo:on -g --lineDir:on --passC:-g --passC:-std=gnu11 --nimcache:nimcache/debug_clang {getCommandLineParams()} ./src/desktop_main.nim"

task buildDesktopDebug, "Build the desktop version (debug)":
  selfExec fmt"c -o:nevd{exe} -d:exposeScriptingApi -d:appBuildWasmtime --debuginfo:on -g -D:debug --lineDir:on --passC:-g --passC:-std=gnu11 --stacktrace:on --linetrace:on --nimcache:nimcache/debug {getCommandLineParams()} ./src/desktop_main.nim"

task buildDesktopWindows, "Build the desktop version for windows":
  selfExec fmt"c -o:nev{exe} {crossCompileWinArgs} -d:exposeScriptingApi -d:appBuildWasmtime {getCommandLineParams()} ./src/desktop_main.nim"

task buildDll, "Build the dll version":
  # Disable clipboard for now because it breaks hot reloading
  selfExec fmt"c -o:nev.dll -d:exposeScriptingApi -d:appBuildWasmtime -d:enableSystemClipboard=false --noMain --app:lib {getCommandLineParams()} ./src/dynlib_main.nim"

task buildNimConfigWasmAll, "Compile the nim script config file to wasm":
  exec fmt"nimble buildNimConfigWasm keybindings_plugin.nim"
  exec fmt"nimble buildNimConfigWasm harpoon.nim"
  exec fmt"nimble buildNimConfigWasm vscode_config_plugin.nim"
  exec fmt"nimble buildNimConfigWasm lisp_plugin.nim"

proc buildPlugin(name: string) =
  withDir &"plugins/{name}":
    exec &"nimble setup"
    exec &"nim c -d:release --skipParentCfg --passL:\"-o {name}.m.wasm\" {getCommandLineParams()} {name}.nim"
    # exec &"nim c -d:release --skipParentCfg -d:pluginWorld=plugin-thread-safe --passL:\"-o {name}_thread.m.wasm\" {getCommandLineParams()} {name}_thread.nim"

task flamegraph, "Perf/flamegraph":
  exec "PERF=/usr/lib/linux-tools/5.4.0-186-generic/perf ~/.cargo/bin/flamegraph -o flamegraph.svg -- nevtd -s:linux.nev-session"

task buildStacktracer, "Build stacktracer (Rust library for getting stack traces)":
  withDir "stacktracer":
    exec "cargo build --release"
  when defined(windows):
    exec "cp ./stacktracer/target/release/stacktracer.dll ."

# Put custom build commands which shouldn't be commited in nev.nimble
when withDir(thisDir(), fileExists("local-nimble.nim")):
  include "local-nimble.nim"
