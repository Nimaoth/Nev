switch("path", "$nim")
switch("path", "scripting")
switch("path", "src")
switch("d", "mingw")
switch("mm", "refc")
switch("tlsEmulation", "off")
switch("d", "enableGui=true")
switch("d", "enableTerminal=true")
switch("d", "ssl")
switch("d", "wasm3HasWasi")

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
