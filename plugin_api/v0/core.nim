
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
type
  CommandError* = enum
    NotAllowed = "not-allowed", NotFound = "not-found"
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

proc coreDefineCommandImported(a0: int32; a1: int32; a2: bool; a3: int32;
                               a4: int32; a5: int32; a6: int32; a7: int32;
                               a8: int32; a9: int32; a10: int32; a11: uint32;
                               a12: uint32): void {.
    wasmimport("define-command", "nev:plugins/core").}
proc defineCommand*(name: WitString; active: bool; docs: WitString;
                    params: WitList[(WitString, WitString)];
                    returntype: WitString; context: WitString; fun: uint32;
                    data: uint32): void {.nodestroy.} =
  ## Defines a command.
  var
    arg0: int32
    arg1: int32
    arg2: bool
    arg3: int32
    arg4: int32
    arg5: int32
    arg6: int32
    arg7: int32
    arg8: int32
    arg9: int32
    arg10: int32
    arg11: uint32
    arg12: uint32
  if name.len > 0:
    arg0 = cast[int32](name[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](name.len)
  arg2 = active
  if docs.len > 0:
    arg3 = cast[int32](docs[0].addr)
  else:
    arg3 = 0.int32
  arg4 = cast[int32](docs.len)
  if params.len > 0:
    arg5 = cast[int32](params[0].addr)
  else:
    arg5 = 0.int32
  arg6 = cast[int32](params.len)
  if returntype.len > 0:
    arg7 = cast[int32](returntype[0].addr)
  else:
    arg7 = 0.int32
  arg8 = cast[int32](returntype.len)
  if context.len > 0:
    arg9 = cast[int32](context[0].addr)
  else:
    arg9 = 0.int32
  arg10 = cast[int32](context.len)
  arg11 = fun
  arg12 = data
  coreDefineCommandImported(arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7,
                            arg8, arg9, arg10, arg11, arg12)

proc coreRunCommandImported(a0: int32; a1: int32; a2: int32; a3: int32;
                            a4: int32): void {.
    wasmimport("run-command", "nev:plugins/core").}
proc runCommand*(name: WitString; arguments: WitString): Result[WitString,
    CommandError] {.nodestroy.} =
  ## Run the given command. This requires 'command' permissions.
  var
    retArea: array[16, uint8]
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
  if name.len > 0:
    arg0 = cast[int32](name[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](name.len)
  if arguments.len > 0:
    arg2 = cast[int32](arguments[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](arguments.len)
  coreRunCommandImported(arg0, arg1, arg2, arg3,
                         cast[int32](retArea[0].addr))
  if cast[ptr int32](retArea[0].addr)[] == 0:
    var tempOk: WitString
    tempOk = ws(cast[ptr char](cast[ptr int32](retArea[4].addr)[]),
                cast[ptr int32](retArea[8].addr)[])
    result = results.Result[WitString, CommandError].ok(tempOk)
  else:
    var tempErr: CommandError
    tempErr = cast[CommandError](cast[ptr int32](retArea[4].addr)[])
    result = results.Result[WitString, CommandError].err(tempErr)

proc coreGetSettingRawImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("get-setting-raw", "nev:plugins/core").}
proc getSettingRaw*(name: WitString): WitString {.nodestroy.} =
  ## Returns the value of the setting with the given path, encoded as JSON.
  var
    retArea: array[8, uint8]
    arg0: int32
    arg1: int32
  if name.len > 0:
    arg0 = cast[int32](name[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](name.len)
  coreGetSettingRawImported(arg0, arg1, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc coreSetSettingRawImported(a0: int32; a1: int32; a2: int32; a3: int32): void {.
    wasmimport("set-setting-raw", "nev:plugins/core").}
proc setSettingRaw*(name: WitString; value: WitString): void {.nodestroy.} =
  ## Set the value of the setting with the given path. The value must be encoded as JSON.
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
  if name.len > 0:
    arg0 = cast[int32](name[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](name.len)
  if value.len > 0:
    arg2 = cast[int32](value[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](value.len)
  coreSetSettingRawImported(arg0, arg1, arg2, arg3)
