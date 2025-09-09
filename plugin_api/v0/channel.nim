
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
type
  ChannelListenResponse* = enum
    Continue = "continue", Stop = "stop"
  ## Represents the read end of a channel. All APIs are non-blocking.
  ReadChannel* = object
    handle*: int32
  ## Represents the write end of a channel. All APIs are non-blocking.
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
  ## Returns the minimum number of bytes available for reading. More data might be available after calling a read function or 'flush-read'.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = channelPeekImported(arg0)
  result = convert(res, int32)

proc channelFlushReadImported(a0: int32): int32 {.
    wasmimport("[method]read-channel.flush-read", "nev:plugins/channel").}
proc flushRead*(self: ReadChannel): int32 {.nodestroy.} =
  ## Read data into the internal buffer of the channel. This is required for 'peek' to work. Other read functions as well
  ## as 'listen' and 'wait-read' already do this internally so you usually don't need to call 'flush-read'.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = channelFlushReadImported(arg0)
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
  ## Listen for data being ready to read. When data is ready 'fun' is called with 'data'.
  var
    arg0: int32
    arg1: uint32
    arg2: uint32
  arg0 = cast[int32](self.handle - 1)
  arg1 = fun
  arg2 = data
  channelListenImported(arg0, arg1, arg2)

proc channelWaitReadImported(a0: int32; a1: uint64; a2: int32): bool {.
    wasmimport("[method]read-channel.wait-read", "nev:plugins/channel").}
proc waitRead*(self: ReadChannel; task: uint64; num: int32): bool {.nodestroy.} =
  ## If 'num' bytes are available in the channel return true, otherwise return false and call 'task' later once the
  ## requested amount of data is available.
  var
    arg0: int32
    arg1: uint64
    arg2: int32
  arg0 = cast[int32](self.handle - 1)
  arg1 = task
  arg2 = num
  let res = channelWaitReadImported(arg0, arg1, arg2)
  result = res.bool

proc channelReadChannelOpenImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[static]read-channel.open", "nev:plugins/channel").}
proc readChannelOpen*(path: WitString): Option[ReadChannel] {.nodestroy.} =
  var
    retArea: array[8, uint8]
    arg0: int32
    arg1: int32
  if path.len > 0:
    arg0 = cast[int32](path[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](path.len)
  channelReadChannelOpenImported(arg0, arg1, cast[int32](retArea[0].addr))
  if cast[ptr int32](retArea[0].addr)[] != 0:
    var temp: ReadChannel
    temp.handle = cast[ptr int32](retArea[4].addr)[] + 1
    result = temp.some

proc channelReadChannelMountImported(a0: int32; a1: int32; a2: int32; a3: bool;
                                     a4: int32): void {.
    wasmimport("[static]read-channel.mount", "nev:plugins/channel").}
proc readChannelMount*(channel: sink ReadChannel; path: WitString; unique: bool): WitString {.
    nodestroy.} =
  var
    retArea: array[16, uint8]
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: bool
  arg0 = cast[int32](channel.handle - 1)
  if path.len > 0:
    arg1 = cast[int32](path[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](path.len)
  arg3 = unique
  channelReadChannelMountImported(arg0, arg1, arg2, arg3,
                                  cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc channelCloseImported(a0: int32): void {.
    wasmimport("[method]write-channel.close", "nev:plugins/channel").}
proc close*(self: WriteChannel): void {.nodestroy.} =
  ## Close the write end.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  channelCloseImported(arg0)

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
  ## Write a string to the channel
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
  ## Write a buffer to the channel
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

proc channelWriteChannelOpenImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[static]write-channel.open", "nev:plugins/channel").}
proc writeChannelOpen*(path: WitString): Option[WriteChannel] {.nodestroy.} =
  var
    retArea: array[8, uint8]
    arg0: int32
    arg1: int32
  if path.len > 0:
    arg0 = cast[int32](path[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](path.len)
  channelWriteChannelOpenImported(arg0, arg1, cast[int32](retArea[0].addr))
  if cast[ptr int32](retArea[0].addr)[] != 0:
    var temp: WriteChannel
    temp.handle = cast[ptr int32](retArea[4].addr)[] + 1
    result = temp.some

proc channelWriteChannelMountImported(a0: int32; a1: int32; a2: int32; a3: bool;
                                      a4: int32): void {.
    wasmimport("[static]write-channel.mount", "nev:plugins/channel").}
proc writeChannelMount*(channel: sink WriteChannel; path: WitString;
                        unique: bool): WitString {.nodestroy.} =
  var
    retArea: array[16, uint8]
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: bool
  arg0 = cast[int32](channel.handle - 1)
  if path.len > 0:
    arg1 = cast[int32](path[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](path.len)
  arg3 = unique
  channelWriteChannelMountImported(arg0, arg1, arg2, arg3,
                                   cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc channelNewInMemoryChannelImported(a0: int32): void {.
    wasmimport("new-in-memory-channel", "nev:plugins/channel").}
proc newInMemoryChannel*(): (ReadChannel, WriteChannel) {.nodestroy.} =
  ## Creates a new channel which buffers data in memory and returns the read and write end.
  var retArea: array[8, uint8]
  channelNewInMemoryChannelImported(cast[int32](retArea[0].addr))
  result[0].handle = cast[ptr int32](retArea[0].addr)[] + 1
  result[1].handle = cast[ptr int32](retArea[4].addr)[] + 1

proc channelCreateTerminalImported(a0: int32; a1: int32; a2: int32; a3: int32): void {.
    wasmimport("create-terminal", "nev:plugins/channel").}
proc createTerminal*(stdin: sink WriteChannel; stdout: sink ReadChannel;
                     group: WitString): void {.nodestroy.} =
  ## Creates a new channel which buffers data in memory and returns the read and write end.
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
  arg0 = cast[int32](stdin.handle - 1)
  arg1 = cast[int32](stdout.handle - 1)
  if group.len > 0:
    arg2 = cast[int32](group[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](group.len)
  channelCreateTerminalImported(arg0, arg1, arg2, arg3)
