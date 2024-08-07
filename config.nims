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

switch("d", "enableGui=true")
switch("d", "enableTerminal=true")
switch("d", "enableNimscript=true")
# switch("d", "enableAst=true")


# uncomment to see logs in the console
switch("d", "allowConsoleLogger")


switch("d", "wasm3HasWasi")
switch("d", "wasm3VerboseErrorMessages")

# Configure which treesitter languages are compiled into the editor (ignored on js backend)
# switch("d", "treesitterBuiltins=cpp,nim,agda,bash,c,css,go,html,java,javascript,python,ruby,rust,scala,csharp,zig,haskell")
switch("d", "treesitterBuiltins=cpp,c,nim,csharp,rust,python,javascript,json")

# Automatically build wasmtime when compiling the editor
const absytreeBuildWasmtime {.booldefine.} = false
const absytreeCI {.booldefine.} = false
const absytreeCINimbleCached {.strdefine.} = ""
when absytreeCI and absytreeCINimbleCached != "true":
  echo "Will build wasmtime"
  switch("d", "nimWasmtimeBuild")

when not absytreeCI and absytreeBuildWasmtime:
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

patchFile("stdlib", "excpt", "patches/excpt")

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


switch("nimcache", "nimcache")


# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
