
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
type
  Platform* = enum
    Gui = "gui", Tui = "tui"
proc coreApiVersionImported(): int32 {.wasmimport("api-version",
    "nev:plugins/core").}
proc apiVersion*(): int32 {.nodestroy.} =
  ## Returns the plugin API version this plugin is using.
  ## 0 means the latest version, 1 or bigger means a specific version.
  let res = coreApiVersionImported()
  result = convert(res, int32)

proc coreGetTimeImported(): float64 {.wasmimport("get-time", "nev:plugins/core").}
proc getTime*(): float64 {.nodestroy.} =
  ## Returns the time since the plugin was loaded. Returns 0 if the plugin has no 'time' permission.
  let res = coreGetTimeImported()
  result = convert(res, float64)

proc coreGetPlatformImported(): int8 {.wasmimport("get-platform",
    "nev:plugins/core").}
proc getPlatform*(): Platform {.nodestroy.} =
  ## Returns what kind platform the app is running on. E.g. 'terminal' or 'gui'
  let res = coreGetPlatformImported()
  result = cast[Platform](res)

proc coreIsMainThreadImported(): bool {.wasmimport("is-main-thread",
    "nev:plugins/core").}
proc isMainThread*(): bool {.nodestroy.} =
  ## Returns true if this plugin is running on the main thread. Some APIs are not available when not on the main thread.
  let res = coreIsMainThreadImported()
  result = res.bool

proc coreGetArgumentsImported(a0: int32): void {.
    wasmimport("get-arguments", "nev:plugins/core").}
proc getArguments*(): WitString {.nodestroy.} =
  ## Returns the arguments this plugin instance was created with.
  var retArea: array[8, uint8]
  coreGetArgumentsImported(cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc coreSpawnBackgroundImported(a0: int32; a1: int32): void {.
    wasmimport("spawn-background", "nev:plugins/core").}
proc spawnBackground*(args: WitString): void {.nodestroy.} =
  ## Creates another instance of the plugin running in a background thread. 'args' is available in the new instance
  ## using the 'get-arguments' function
  var
    arg0: int32
    arg1: int32
  if args.len > 0:
    arg0 = cast[int32](args[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](args.len)
  coreSpawnBackgroundImported(arg0, arg1)

proc coreFinishBackgroundImported(): void {.
    wasmimport("finish-background", "nev:plugins/core").}
proc finishBackground*(): void {.nodestroy.} =
  ## Destroy the current plugin instance.
  coreFinishBackgroundImported()
