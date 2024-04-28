switch("path", "$nim")
switch("path", "scripting")
switch("path", "src")

switch("d", "mingw")
switch("mm", "orc")
switch("tlsEmulation", "off")
switch("d", "ssl")


# performance
switch("panics", "on")
switch("d", "release")


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
# switch("d", "enableNimscript=true")
# switch("d", "enableAst=true")


# uncomment to see logs in the console
switch("d", "allowConsoleLogger")


switch("d", "wasm3HasWasi")
switch("d", "wasm3VerboseErrorMessages")

# Configure which treesitter languages are compiled into the editor (ignored on js backend)
switch("d", "treesitterBuiltins=cpp,nim,agda,bash,c,css,go,html,java,javascript,python,ruby,rust,scala,csharp,zig,haskell")


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
