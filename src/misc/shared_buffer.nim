import std/[locks, tables, options]
import misc/id
import nimsumtree/arc

type
  SharedBufferData = object
    bytes: seq[uint8]

  SharedBuffer* = object
    data: Arc[SharedBufferData]

proc new*(_: typedesc[SharedBuffer], len: int): SharedBuffer =
  result = SharedBuffer(data: Arc[SharedBufferData].new(SharedBufferData(bytes: newSeq[uint8](len))))

proc len*(self: SharedBuffer): int =
  assert not self.data.isNil
  self.data.getMutUnsafe.bytes.len

proc high*(self: SharedBuffer): int =
  assert not self.data.isNil
  self.data.getMutUnsafe.bytes.high

# template toOpenArray*(self: SharedBuffer): openArray[uint8] =
#   assert not self.data.isNil
#   self.data.getMutUnsafe.bytes.toOpenArray(0, self.data.getMutUnsafe.bytes.high)

proc write*(self: SharedBuffer, index: int, src: openArray[uint8]) =
  if src.len == 0:
    return
  assert src.len > 0
  assert not self.data.isNil
  let len = self.len
  assert index in 0..<len
  assert index + src.len in 0..len
  copyMem(self.data.getMutUnsafe.bytes[0].addr, src[0].addr, src.len)

proc readInto*(self: SharedBuffer, index: int, dst: openArray[uint8]) =
  if dst.len == 0:
    return
  assert not self.data.isNil
  let len = self.len
  assert index in 0..<len
  assert index + dst.len in 0..len
  copyMem(dst[0].addr, self.data.getMutUnsafe.bytes[0].addr, dst.len)

proc isNil*(self: SharedBuffer): bool = self.data.isNil

type
  BufferRegistry* = object
    lock*: Lock
    buffers*: Table[string, SharedBuffer]

var gBufferRegistry = BufferRegistry()
gBufferRegistry.lock.initLock()

proc openGlobalBuffer*(path: string): Option[SharedBuffer] {.gcsafe.} =
  let buffers = ({.gcsafe.}: gBufferRegistry.addr)
  withLock(buffers.lock):
    var buffer: SharedBuffer
    if buffers.buffers.take(path, buffer):
      return buffer.some
  return SharedBuffer.none

proc mountGlobalBuffer*(path: string, buffer: sink SharedBuffer, unique: bool): string {.gcsafe.} =
  var path = path
  if unique:
    path.add "-" & $newId()
  let buffers = ({.gcsafe.}: gBufferRegistry.addr)
  withLock(buffers.lock):
    buffers.buffers[path] = buffer
    return path
