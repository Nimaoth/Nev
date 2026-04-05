import std/[os, parseopt, compilesettings, strformat]

# Helper functions

var exitCode = 0

############################################################################################################

var packageWindows = false
var packageLinux = false
var cacheHit = ""

var optParser = initOptParser("")
for kind, key, val in optParser.getopt():
  case kind
  of cmdArgument:
    discard

  of cmdLongOption, cmdShortOption:
    case key
    of "windows", "w":
      packageWindows = true
    of "linux", "l":
      packageLinux = true
    of "cache":
      cacheHit = val

  of cmdEnd: assert(false) # cannot happen

proc buildPlugin(name: string) =
  withDir &"plugins/{name}":
    exec(&"nim c -d:release --skipParentCfg --passL:\"-o {name}.m.wasm\" {name}.nim")

buildPlugin("vim")
buildPlugin("markdown")
buildPlugin("harpoon")

if packageWindows:
  exec(&"nim c --out:nev.exe -D:enableGui=false -D:enableTerminal=true --app:console -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={cacheHit} src/desktop_main.nim")
  exec(&"nim c --out:nevg.exe -D:enableGui=true -D:enableTerminal=false --app:gui -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={cacheHit} src/desktop_main.nim")
  exec(&"nim c --out:nevc.exe -D:enableGui=true -D:enableTerminal=false --app:gui -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={cacheHit} --cc:clang --passC:-Wno-incompatible-function-pointer-types \"--passL:-ladvapi32.lib -luser32.lib\" -d:enableSystemClipboard=false src/desktop_main.nim")

if packageLinux:
  exec(&"nim c --out:nev -D:enableGui=false -D:enableTerminal=true --app:console -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={cacheHit} src/desktop_main.nim")
  exec(&"nim c --out:nevg -D:enableGui=true -D:enableTerminal=false --app:gui -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={cacheHit} src/desktop_main.nim")
  exec(&"nim c --out:nev-musl -D:enableGui=false -D:enableTerminal=true --app:console -d:musl -d:nimWasmtimeBuildMusl -D:forceLogToFile --passC:-std=gnu11 -d:exposeScriptingApi -D:isCI -D:isCINimbleCached={cacheHit} src/desktop_main.nim")

quit exitCode
