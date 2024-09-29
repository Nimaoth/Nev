# This is required for LSP to work with this file and not show tons of errros
when defined(nimsuggest):
  import system/nimscript

switch("path", "$nim")
switch("path", "scripting")
switch("path", "src")

switch("d", "mingw")
switch("mm", "orc")
switch("d", "useMalloc")
switch("tlsEmulation", "off")


# performance
switch("panics", "on")
switch("d", "release")
# switch("d", "lto")
# switch("opt", "size")

switch("stacktrace", "off")
switch("linetrace", "off")

# checks
# --objChecks:off
# --fieldChecks:off
# --boundChecks:off
# --overflowChecks:off
# --floatChecks:off
# --nanChecks:off
# --infChecks:off

# --rangeChecks:off # this causes issues on js backend with some prng initialization

# --nilChecks:on

# required for actual builds, but for lsp this should be off to improve performance because it doesn't need to generate as many functions
# switch("d", "exposeScriptingApi")

switch("d", "npegGcsafe=true")

switch("d", "enableGui=true")
switch("d", "enableTerminal=true")
switch("d", "enableNimscript=false")
switch("d", "enableAst=false")


# uncomment to see logs in the console
switch("d", "allowConsoleLogger")


switch("d", "wasm3HasWasi")
switch("d", "wasm3VerboseErrorMessages")

# Configure which treesitter languages are compiled into the editor (ignored on js backend)
# switch("d", "treesitterBuiltins=cpp,nim,agda,bash,c,css,go,html,java,javascript,python,ruby,rust,scala,csharp,zig,haskell")
switch("d", "treesitterBuiltins=cpp,c,nim,csharp,rust,python,javascript,json")

# Automatically build wasmtime when compiling the editor
const appBuildWasmtime {.booldefine.} = false
const isCI {.booldefine.} = false
const isCINimbleCached {.strdefine.} = ""
when isCI and isCINimbleCached != "true":
  echo "Will build wasmtime"
  switch("d", "nimWasmtimeBuild")

when not isCI and appBuildWasmtime:
  echo "Will build wasmtime"
  switch("d", "nimWasmtimeBuild")

# switch("d", "nimWasmtimeBuildDebug")

# Enable wasi support in nimwasmtime
switch("d", "nimWasmtimeFeatureWasi")

# Enable wasm parser support in treesitter
switch("d", "treesitterFeatureWasm")

# Static linking doesn't work on windows for some reason, so dynamically link
when defined(windows):
  switch("d", "nimWasmtimeStatic=false")

  # todo: This doesn't work for GUI, crashes with nil access
  # switch("d", "nimWasmtimeStatic=true")
  # switch("passC", "-static")
  # switch("passL", "-lucrt -lws2_32 -lntdll -luserenv -lole32 -lbcrypt")
else:
  switch("d", "nimWasmtimeStatic=true")

# results prints a ton of hints, silence them
switch("d", "resultsGenericsOpenSymWorkaroundHint=false")

when defined(musl):
  var muslGcc = findExe("musl-gcc")
  # muslGcc = "/home/nimaoth/musl/musl/bin/musl-gcc"
  echo "Build static binary with musl " & muslGcc
  switch("gcc.exe", muslGcc)
  switch("gcc.linkerexe", muslGcc)
  switch("passL", "-static")

  # Disable system clipboard because it doesn't build with musl right now
  switch("d", "enableSystemClipboard=false")

else:
  switch("d", "ssl")

when defined(enableSysFatalStackTrace):
  patchFile("stdlib", "fatal", "patches/fatal")
patchFile("stdlib", "excpt", "patches/excpt")
patchFile("stdlib", "tables", "patches/tables") # Patch tables.nim to remove exceptions
patchFile("chronos", "asyncengine", "patches/asyncengine") # Patch this to enable 0 timeout poll

# switches for debugging
# switch("d", "wasm3EnableStrace2")
# switch("d", "wasm3RecordBacktraces")
# switch("d", "wasm3LogModule")
# switch("d", "wasm3LogCompile")
# switch("d", "wasm3LogParse")
# switch("d", "wasm3LogRuntime")
# switch("d", "uiNodeDebugData")
# switch("d", "futureLogging")
# switch("d", "nimBurnFree")
# switch("d", "nimArcIds")
# switch("d", "traceArc")
# switch("d", "nimTypeNames")

when defined(linux):
  switch("nimcache", "nimcache/linux")
else:
  switch("nimcache", "nimcache/windows")

# todo: build with clang
# switch("cc", "clang")
# switch("passC", "-fno-omit-frame-pointer -g -Wno-incompatible-function-pointer-types")
# switch("passC", "-flto")
# switch("passC", "-fno-omit-frame-pointer -ggdb3 -g -Wno-incompatible-function-pointer-types -gcodeview -fuse-ld=lld")
# switch("d", "enableSystemClipboard=false")
# switch("lineDir", "off")
# switch("profiler", "on")

when defined(linux):
  when withDir(thisDir(), system.fileExists("nimble-linux.paths")):
    include "nimble-linux.paths"
else:
  when withDir(thisDir(), system.fileExists("nimble-win.paths")):
    include "nimble-win.paths"

# begin Nimble config (version 2)
# --noNimblePath
# when withDir(thisDir(), system.fileExists("nimble.paths")):
#   include "nimble.paths"
# end Nimble config

when defined(useMimalloc):
  switch("define", "useMalloc")
  patchFile("stdlib", "malloc", "$lib/patchedstd/mimalloc")
