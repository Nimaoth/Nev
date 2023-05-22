switch("path", "$nim")
switch("path", "scripting")
switch("path", "src")

switch("o", "ast")
switch("d", "mingw")
switch("mm", "refc")
switch("tlsEmulation", "off")
switch("d", "enableGui=true")
switch("d", "enableTerminal=true")
switch("d", "exposeScriptingApi")
switch("d", "ssl")

switch("d", "wasm3HasWasi")
switch("d", "wasm3VerboseErrorMessages")
# switch("d", "wasm3EnableStrace2")
# switch("d", "wasm3RecordBacktraces")

# switch("d", "wasm3LogModule")
# switch("d", "wasm3LogCompile")
# switch("d", "wasm3LogParse")
# switch("d", "wasm3LogRuntime")

let mode = 0
case mode
of 0:
  switch("d", "release")
of 1:
  switch("d", "release")
  switch("stackTrace", "on")
  switch("lineTrace", "on")
of 2:
  switch("d", "debug")
  switch("debuginfo", "on")
of 3:
  switch("d", "release")
  switch("debuginfo", "on")
  switch("cc", "vcc")
  switch("nimcache", "D:\\nc")
else:
  discard

# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
