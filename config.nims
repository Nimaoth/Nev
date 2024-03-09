switch("path", "$nim")
switch("path", "scripting")
switch("path", "src")

switch("d", "mingw")
switch("mm", "orc")
switch("tlsEmulation", "off")
switch("d", "enableGui=true")
switch("d", "enableTerminal=true")
switch("d", "ssl")
switch("d", "exposeScriptingApi")

# uncomment to see logs in the console
switch("d", "allowConsoleLogger")

switch("d", "wasm3HasWasi")
switch("d", "wasm3VerboseErrorMessages")

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

# checks
# --objChecks:off
# --fieldChecks:off
# --rangeChecks:off
# --boundChecks:off
# --overflowChecks:off
# --floatChecks:off
# --nanChecks:off
# --infChecks:off

# switch("cc", "vcc")
# switch("nimcache", "D:\\nc")

case 0
of 0:
  switch("d", "release")
of 1:
  switch("d", "release")
  switch("stackTrace", "on")
  switch("lineTrace", "on")
of 2:
  switch("cc", "vcc")
  switch("d", "debug")
  switch("debuginfo", "on")
of 3:
  switch("d", "release")
  switch("debuginfo", "on")
  switch("stackTrace", "on")
  switch("lineTrace", "on")
  switch("nimcache", "D:\\nc")
else:
  discard

# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
