
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
import
  channel

type
  Process* = object
    handle*: int32
proc processProcessDrop(a: int32): void {.
    wasmimport("[resource-drop]process", "nev:plugins/process").}
proc `=copy`*(a: var Process; b: Process) {.error.}
proc `=destroy`*(a: Process) =
  if a.handle != 0:
    processProcessDrop(a.handle - 1)

proc processProcessStartImported(a0: int32; a1: int32; a2: int32; a3: int32): int32 {.
    wasmimport("[static]process.start", "nev:plugins/process").}
proc processStart*(name: WitString; args: WitList[WitString]): Process {.
    nodestroy.} =
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
  if args.len > 0:
    arg2 = cast[int32](args[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](args.len)
  let res = processProcessStartImported(arg0, arg1, arg2, arg3)
  result.handle = res + 1

proc processStderrImported(a0: int32): int32 {.
    wasmimport("[method]process.stderr", "nev:plugins/process").}
proc stderr*(self: Process): ReadChannel {.nodestroy.} =
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = processStderrImported(arg0)
  result.handle = res + 1

proc processStdoutImported(a0: int32): int32 {.
    wasmimport("[method]process.stdout", "nev:plugins/process").}
proc stdout*(self: Process): ReadChannel {.nodestroy.} =
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = processStdoutImported(arg0)
  result.handle = res + 1

proc processStdinImported(a0: int32): int32 {.
    wasmimport("[method]process.stdin", "nev:plugins/process").}
proc stdin*(self: Process): WriteChannel {.nodestroy.} =
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = processStdinImported(arg0)
  result.handle = res + 1
