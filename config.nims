switch("path", "$nim")
switch("path", "scripting")
switch("d", "mingw")
switch("mm", "refc")
switch("tlsEmulation", "off")
switch("d", "enableGui=true")
switch("d", "enableTerminal=true")

if true:
  switch("d", "release")
else:
  switch("d", "release")
  switch("debuginfo", "on")
  switch("cc", "vcc")
  switch("nimcache", "D:\\nc")