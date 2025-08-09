
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
type
  ReadChannel* = object
    handle*: int32
  WriteChannel* = object
    handle*: int32
proc channelReadChannelDrop(a: int32): void {.
    wasmimport("[resource-drop]read-channel", "nev:plugins/channel").}
proc `=copy`*(a: var ReadChannel; b: ReadChannel) {.error.}
proc `=destroy`*(a: ReadChannel) =
  if a.handle != 0:
    channelReadChannelDrop(a.handle - 1)

proc channelWriteChannelDrop(a: int32): void {.
    wasmimport("[resource-drop]write-channel", "nev:plugins/channel").}
proc `=copy`*(a: var WriteChannel; b: WriteChannel) {.error.}
proc `=destroy`*(a: WriteChannel) =
  if a.handle != 0:
    channelWriteChannelDrop(a.handle - 1)

proc channelCanReadImported(a0: int32): bool {.
    wasmimport("[method]read-channel.can-read", "nev:plugins/channel").}
proc canRead*(self: ReadChannel): bool {.nodestroy.} =
  ## Returns whether the channel is still open and usable.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = channelCanReadImported(arg0)
  result = res.bool

proc channelAtEndImported(a0: int32): bool {.
    wasmimport("[method]read-channel.at-end", "nev:plugins/channel").}
proc atEnd*(self: ReadChannel): bool {.nodestroy.} =
  ## Returns whether the channel at the end, meaning no further data will be returned from any read function.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = channelAtEndImported(arg0)
  result = res.bool

proc channelPeekImported(a0: int32): int32 {.
    wasmimport("[method]read-channel.peek", "nev:plugins/channel").}
proc peek*(self: ReadChannel): int32 {.nodestroy.} =
  ## Returns how much data is in the buffer available for reading
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = channelPeekImported(arg0)
  result = convert(res, int32)

proc channelReadStringImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[method]read-channel.read-string", "nev:plugins/channel").}
proc readString*(self: ReadChannel; num: int32): WitString {.nodestroy.} =
  ## Read
  var
    retArea: array[8, uint8]
    arg0: int32
    arg1: int32
  arg0 = cast[int32](self.handle - 1)
  arg1 = num
  channelReadStringImported(arg0, arg1, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc channelReadBytesImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[method]read-channel.read-bytes", "nev:plugins/channel").}
proc readBytes*(self: ReadChannel; num: int32): WitList[uint8] {.nodestroy.} =
  ## Read
  var
    retArea: array[8, uint8]
    arg0: int32
    arg1: int32
  arg0 = cast[int32](self.handle - 1)
  arg1 = num
  channelReadBytesImported(arg0, arg1, cast[int32](retArea[0].addr))
  result = wl(cast[ptr typeof(result[0])](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc channelReadAllStringImported(a0: int32; a1: int32): void {.
    wasmimport("[method]read-channel.read-all-string", "nev:plugins/channel").}
proc readAllString*(self: ReadChannel): WitString {.nodestroy.} =
  ## Read everything currently available in the channel.
  var
    retArea: array[8, uint8]
    arg0: int32
  arg0 = cast[int32](self.handle - 1)
  channelReadAllStringImported(arg0, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc channelReadAllBytesImported(a0: int32; a1: int32): void {.
    wasmimport("[method]read-channel.read-all-bytes", "nev:plugins/channel").}
proc readAllBytes*(self: ReadChannel): WitList[uint8] {.nodestroy.} =
  ## Read everything currently available in the channel.
  var
    retArea: array[8, uint8]
    arg0: int32
  arg0 = cast[int32](self.handle - 1)
  channelReadAllBytesImported(arg0, cast[int32](retArea[0].addr))
  result = wl(cast[ptr typeof(result[0])](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc channelListenImported(a0: int32; a1: uint32; a2: uint32): void {.
    wasmimport("[method]read-channel.listen", "nev:plugins/channel").}
proc listen*(self: ReadChannel; fun: uint32; data: uint32): void {.nodestroy.} =
  var
    arg0: int32
    arg1: uint32
    arg2: uint32
  arg0 = cast[int32](self.handle - 1)
  arg1 = fun
  arg2 = data
  channelListenImported(arg0, arg1, arg2)

proc channelCanWriteImported(a0: int32): bool {.
    wasmimport("[method]write-channel.can-write", "nev:plugins/channel").}
proc canWrite*(self: WriteChannel): bool {.nodestroy.} =
  ## Returns whether the channel is still open and usable.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = channelCanWriteImported(arg0)
  result = res.bool

proc channelWriteStringImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[method]write-channel.write-string", "nev:plugins/channel").}
proc writeString*(self: WriteChannel; data: WitString): void {.nodestroy.} =
  ## Write
  var
    arg0: int32
    arg1: int32
    arg2: int32
  arg0 = cast[int32](self.handle - 1)
  if data.len > 0:
    arg1 = cast[int32](data[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](data.len)
  channelWriteStringImported(arg0, arg1, arg2)

proc channelWriteBytesImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[method]write-channel.write-bytes", "nev:plugins/channel").}
proc writeBytes*(self: WriteChannel; data: WitList[uint8]): void {.nodestroy.} =
  ## Write
  var
    arg0: int32
    arg1: int32
    arg2: int32
  arg0 = cast[int32](self.handle - 1)
  if data.len > 0:
    arg1 = cast[int32](data[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](data.len)
  channelWriteBytesImported(arg0, arg1, arg2)
