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

proc write*(self: var BinaryEncoder, T: typedesc[SomeUnsignedInt], v: T) =
  let startIndex = self.buffer.len
  self.buffer.setLen(startIndex + sizeof(T))
  writeImpl(self, startIndex, sizeof(T), v)

proc write*(self: var BinaryEncoder, T: typedesc[float32], v: T) =
  # todo: make this work in js
  self.write(uint32, cast[uint32](v))

proc write*(self: var BinaryEncoder, T: typedesc[float64], v: T) =
  # todo: make this work in js
  self.write(uint64, cast[uint64](v))

proc writeLEB128*(self: var BinaryEncoder, T: typedesc[SomeUnsignedInt], v: T) =
  var v = v
  while true:
    var b = v and 0b0111_1111
    v = v shr 7
    if v != 0:
      b = b or 0b1000_0000
    self.write(byte, b.byte)
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

    self.write(byte, b.byte)

proc writeString*(self: var BinaryEncoder, v: string) =
  self.writeLEB128(uint32, v.len.uint32)
  self.buffer.add v.toOpenArrayByte(0, v.high)
