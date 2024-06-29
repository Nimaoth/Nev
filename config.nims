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
# switch("d", "enableNimscript=true")
# switch("d", "enableAst=true")


# uncomment to see logs in the console
switch("d", "allowConsoleLogger")


switch("d", "wasm3HasWasi")
switch("d", "wasm3VerboseErrorMessages")

# Configure which treesitter languages are compiled into the editor (ignored on js backend)
# switch("d", "treesitterBuiltins=cpp,nim,agda,bash,c,css,go,html,java,javascript,python,ruby,rust,scala,csharp,zig,haskell")
# switch("d", "treesitterBuiltins=cpp,nim,c,css,html,javascript,python,rust,csharp")
switch("d", "treesitterBuiltins=cpp,nim,csharp,rust,python,javascript")

when defined(musl):
  const muslGcc = findExe("musl-gcc")
  echo "Build static binary with musl " & muslGcc
  --gcc.exe:muslGcc
  --gcc.linkerexe:muslGcc
  --passL:"-static"

  # Disable system clipboard because it doesn't build with musl right now
  switch("d", "enableSystemClipboard=false")

  # Remove nim from treesitterBuiltins because it doesn't build with musl right now
  switch("d", "treesitterBuiltins=cpp,csharp,rust,python,javascript")

else:
  switch("d", "ssl")

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
