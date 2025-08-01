import std/[macros, genasts]
type
  BinaryEncoder* = object
    buffer*: seq[byte]

macro getByte(v: typed, i: static[int]): untyped =
  let shift = i * 8
  result = genAst(v, shift):
    ((v shr shift) and 0xff).byte
  # echo result.repr

macro writeImpl(self: var BinaryEncoder, index: untyped, bytes: static[int], v: untyped): untyped =
  result = nnkStmtList.newTree()
  for i in 0..<bytes:
    let b = genAst(self, v, i):
      self.buffer[startIndex + i] = getByte(v, i)
    result.add(b)
  # echo result.repr

proc write*[T: SomeUnsignedInt](self: var BinaryEncoder, v: T) =
  let startIndex = self.buffer.len
  self.buffer.setLen(startIndex + sizeof(T))
  writeImpl(self, startIndex, sizeof(T), v)

proc write*(self: var BinaryEncoder, v: float32) =
  # todo: make this work in js
  self.write(cast[uint32](v))

proc write*(self: var BinaryEncoder, v: float64) =
  # todo: make this work in js
  self.write(cast[uint64](v))

proc writeLEB128*(self: var BinaryEncoder, T: typedesc[SomeUnsignedInt], v: T) =
  var v = v
  while true:
    var b = v and 0b0111_1111
    v = v shr 7
    if v != 0:
      b = b or 0b1000_0000
    self.write(b.byte)
    if v == 0:
      break

proc writeLEB128*(self: var BinaryEncoder, T: typedesc[SomeSignedInt], v: T) =
  var v = v
  var more = true
  var negative = v < 0
  let size = sizeof(T) * 8

  while more:
    var b = v and 0b0111_1111
    v = v shr 7
    if negative:
      v = v or (T.default.not shl (size - 7))
    let signBitSet = (b and 0x40) != 0
    if (v == 0 and not signBitSet) or (v == -1 and signBitSet):
      more = false
    else:
      b = b or 0b1000_0000

    self.write(b.byte)

proc writeString*(self: var BinaryEncoder, v: string) =
  self.writeLEB128(uint32, v.len.uint32)
  self.buffer.add v.toOpenArrayByte(0, v.high)

type
  BinaryDecoder* = object
    buffer*: ptr UncheckedArray[byte]
    len*: int
    pos*: int

proc init*(_: typedesc[BinaryDecoder], arr: openArray[byte]): BinaryDecoder =
  if arr.len == 0:
    BinaryDecoder(buffer: nil, len: 0, pos: 0)
  else:
    BinaryDecoder(buffer: cast[ptr UncheckedArray[byte]](arr[0].addr), len: arr.len, pos: 0)

proc assertSize(self: var BinaryDecoder, size: int) =
  if self.pos + size > self.len:
    raise newException(ValueError, "Failed to decode data, out of bounds")

proc read*(self: var BinaryDecoder, T: typedesc[SomeUnsignedInt]): T =
  self.assertSize(sizeof(T))
  # todo: endianness and alignment
  result = cast[ptr T](self.buffer[self.pos].addr)[]
  self.pos += sizeof(T)

proc read*(self: var BinaryDecoder, T: typedesc[float32]): float32 =
  self.assertSize(sizeof(T))
  # todo: endianness and alignment
  result = cast[ptr float32](self.buffer[self.pos].addr)[]
  self.pos += sizeof(float32)

proc read*(self: var BinaryDecoder, T: typedesc[float64]): float64 =
  self.assertSize(sizeof(T))
  # todo: endianness and alignment
  result = cast[ptr float64](self.buffer[self.pos].addr)[]
  self.pos += sizeof(float64)

proc readLEB128*(self: var BinaryDecoder, T: typedesc[SomeUnsignedInt]): T =
  result = 0
  var shift = 0
  while true:
    self.assertSize(1)
    let byte = self.buffer[self.pos]
    self.pos += 1
    result = result or (T(byte and 0x7F) shl shift)
    if (byte and 0x80) == 0:
      break
    shift += 7

proc readLEB128*(self: var BinaryDecoder, T: typedesc[SomeSignedInt]): T =
  result = 0
  var shift = 0
  var byte: byte = 0
  let size = sizeof(T) * 8
  while true:
    self.assertSize(1)
    byte = self.buffer[self.pos]
    self.pos += 1
    result = result or (T(byte and 0x7F) shl shift)
    shift += 7
    if (byte and 0x80) == 0:
      break

  if (shift < size) and ((byte and 0x40) != 0):
    result = result or (T(-1) shl shift)

proc readString*(self: var BinaryDecoder): string =
  let len = self.readLEB128(uint32).int
  self.assertSize(len)
  result = newString(len)
  copyMem(result[0].addr, self.buffer[self.pos].addr, len)
  self.pos += len

proc readString*(self: var BinaryDecoder, res: var string) =
  let len = self.readLEB128(uint32).int
  self.assertSize(len)
  let oldLen = res.len
  res.setLen(oldLen + len)
  copyMem(res[oldLen].addr, self.buffer[self.pos].addr, len)
  self.pos += len
