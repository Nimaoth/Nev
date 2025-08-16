
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
import
  types

import
  commands

type
  VfsError* = enum
    NotAllowed = "not-allowed", NotFound = "not-found"
  ReadFlag* = enum
    Binary = "binary"
  ReadFlags* = set[ReadFlag]
proc vfsReadSyncImported(a0: int32; a1: int32; a2: uint8; a3: int32): void {.
    wasmimport("read-sync", "nev:plugins/vfs").}
proc readSync*(path: WitString; readFlags: ReadFlags): Result[WitString,
    VfsError] {.nodestroy.} =
  ## Read the given file synchronously. Requires 'filesystemRead' permissions.
  ## By default files are checked to be valid UTF-8 when loading. To skip this check pass the 'binary' flag.
  ## Paths are virtual paths for the virtual file system.
  var
    retArea: array[12, uint8]
    arg0: int32
    arg1: int32
    arg2: uint8
  if path.len > 0:
    arg0 = cast[int32](path[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](path.len)
  arg2 = cast[uint8](readFlags)
  vfsReadSyncImported(arg0, arg1, arg2, cast[int32](retArea[0].addr))
  if cast[ptr int32](retArea[0].addr)[] == 0:
    var tempOk: WitString
    tempOk = ws(cast[ptr char](cast[ptr int32](retArea[4].addr)[]),
                cast[ptr int32](retArea[8].addr)[])
    result = results.Result[WitString, VfsError].ok(tempOk)
  else:
    var tempErr: VfsError
    tempErr = cast[VfsError](cast[ptr int32](retArea[4].addr)[])
    result = results.Result[WitString, VfsError].err(tempErr)

proc vfsReadRopeSyncImported(a0: int32; a1: int32; a2: uint8; a3: int32): void {.
    wasmimport("read-rope-sync", "nev:plugins/vfs").}
proc readRopeSync*(path: WitString; readFlags: ReadFlags): Result[Rope, VfsError] {.
    nodestroy.} =
  ## Read the given file synchronously. Requires 'filesystemRead' permissions.
  ## By default files are checked to be valid UTF-8 when loading. To skip this check pass the 'binary' flag.
  ## Paths are virtual paths for the virtual file system.
  var
    retArea: array[12, uint8]
    arg0: int32
    arg1: int32
    arg2: uint8
  if path.len > 0:
    arg0 = cast[int32](path[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](path.len)
  arg2 = cast[uint8](readFlags)
  vfsReadRopeSyncImported(arg0, arg1, arg2, cast[int32](retArea[0].addr))
  if cast[ptr int32](retArea[0].addr)[] == 0:
    var tempOk: Rope
    tempOk.handle = cast[ptr int32](retArea[4].addr)[] + 1
    result = results.Result[Rope, VfsError].ok(tempOk)
  else:
    var tempErr: VfsError
    tempErr = cast[VfsError](cast[ptr int32](retArea[4].addr)[])
    result = results.Result[Rope, VfsError].err(tempErr)

proc vfsWriteSyncImported(a0: int32; a1: int32; a2: int32; a3: int32; a4: int32): void {.
    wasmimport("write-sync", "nev:plugins/vfs").}
proc writeSync*(path: WitString; content: WitString): Result[bool, VfsError] {.
    nodestroy.} =
  ## Write the given file synchronously. Requires 'filesystemWrite' permissions.
  ## Paths are virtual paths for the virtual file system.
  var
    retArea: array[16, uint8]
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
  if path.len > 0:
    arg0 = cast[int32](path[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](path.len)
  if content.len > 0:
    arg2 = cast[int32](content[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](content.len)
  vfsWriteSyncImported(arg0, arg1, arg2, arg3, cast[int32](retArea[0].addr))
  if cast[ptr int8](retArea[0].addr)[] == 0:
    var tempOk: bool
    tempOk = cast[ptr bool](retArea[1].addr)[].bool
    result = results.Result[bool, VfsError].ok(tempOk)
  else:
    var tempErr: VfsError
    tempErr = cast[VfsError](cast[ptr bool](retArea[1].addr)[])
    result = results.Result[bool, VfsError].err(tempErr)

proc vfsWriteRopeSyncImported(a0: int32; a1: int32; a2: int32; a3: int32): void {.
    wasmimport("write-rope-sync", "nev:plugins/vfs").}
proc writeRopeSync*(path: WitString; rope: sink Rope): Result[bool, VfsError] {.
    nodestroy.} =
  ## Write the given file synchronously. Requires 'filesystemWrite' permissions.
  ## Paths are virtual paths for the virtual file system.
  var
    retArea: array[12, uint8]
    arg0: int32
    arg1: int32
    arg2: int32
  if path.len > 0:
    arg0 = cast[int32](path[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](path.len)
  arg2 = cast[int32](rope.handle - 1)
  vfsWriteRopeSyncImported(arg0, arg1, arg2, cast[int32](retArea[0].addr))
  if cast[ptr int8](retArea[0].addr)[] == 0:
    var tempOk: bool
    tempOk = cast[ptr bool](retArea[1].addr)[].bool
    result = results.Result[bool, VfsError].ok(tempOk)
  else:
    var tempErr: VfsError
    tempErr = cast[VfsError](cast[ptr bool](retArea[1].addr)[])
    result = results.Result[bool, VfsError].err(tempErr)

proc vfsLocalizeImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("localize", "nev:plugins/vfs").}
proc localize*(path: WitString): WitString {.nodestroy.} =
  ## Turns a virtual file system path to a path in the local file system, which can be passed to e.g. external processes.
  ## E.g. 'local://C:/Users' becomes 'C:/Users'
  ## E.g. 'home://.nev' becomes 'C:/Users/username/.nev'
  var
    retArea: array[8, uint8]
    arg0: int32
    arg1: int32
  if path.len > 0:
    arg0 = cast[int32](path[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](path.len)
  vfsLocalizeImported(arg0, arg1, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])
