# Copied from the compiler
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# this unit handles Nim sets; it implements bit sets
# the code here should be reused in the Nim standard library

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  ElemType = byte
  BitSet* = distinct seq[ElemType]    # we use byte here to avoid issues with
                              # cross-compiling; uint would be more efficient
                              # however
const
  ElemSize* = 8
  One = ElemType(1)
  Zero = ElemType(0)

template modElemSize(arg: untyped): untyped = arg and 7
template divElemSize(arg: untyped): untyped = arg shr 3

proc len*(x: BitSet): int {.borrow.}
proc setLen*(x: var BitSet, l: int) {.borrow.}
proc high*(x: BitSet): int {.borrow.}
proc low*(x: BitSet): int {.borrow.}
proc `[]`*(x: BitSet, l: int): ElemType = (seq[ElemType])(x)[l]
proc `[]=`*(x: var BitSet, l: int, v: ElemType) = (seq[ElemType])(x)[l] = v

# proc len*(x: BitSet): int {.borrow.}
# proc setLen*(x: var BitSet, l: int) {.borrow.}

proc bitSetIn*(x: BitSet, e: int): bool =
  result = (x[int(e.divElemSize)] and (One shl e.modElemSize)) != Zero

proc bitSetIncl*(x: var BitSet, elem: int) =
  assert(elem >= 0)
  let index = int(elem shr 3)
  if index >= x.len:
    x.setLen index + 1
  x[int(elem.divElemSize)] = x[int(elem.divElemSize)] or
      (One shl elem.modElemSize)

proc bitSetExcl*(x: var BitSet, elem: int) =
  x[int(elem.divElemSize)] = x[int(elem.divElemSize)] and
      not(One shl elem.modElemSize)

proc bitSetInit*(b: var BitSet, length: int) =
  newSeq((seq[ElemType])(b), length)

proc bitSetUnion*(x: var BitSet, y: BitSet) =
  if x.len < y.len:
    x.setLen y.len
  for i in 0..high(x): x[i] = x[i] or y[i]

proc bitSetDiff*(x: var BitSet, y: BitSet) =
  for i in 0..high(x): x[i] = x[i] and not y[i]

proc bitSetSymDiff*(x: var BitSet, y: BitSet) =
  for i in 0..high(x): x[i] = x[i] xor y[i]

proc bitSetIntersect*(x: var BitSet, y: BitSet) =
  if x.len > y.len:
    x.setLen y.len
  for i in 0..high(x): x[i] = x[i] and y[i]

proc bitSetEquals*(x, y: BitSet): bool =
  for i in 0..high(x):
    if x[i] != y[i]:
      return false
  result = true

proc bitSetContains*(x, y: BitSet): bool =
  for i in 0..high(x):
    if (x[i] and not y[i]) != Zero:
      return false
  result = true

# Number of set bits for all values of int8
const populationCount: array[uint8, uint8] = block:
    var arr: array[uint8, uint8]

    proc countSetBits(x: uint8): uint8 =
      return
        ( x and 0b00000001'u8) +
        ((x and 0b00000010'u8) shr 1) +
        ((x and 0b00000100'u8) shr 2) +
        ((x and 0b00001000'u8) shr 3) +
        ((x and 0b00010000'u8) shr 4) +
        ((x and 0b00100000'u8) shr 5) +
        ((x and 0b01000000'u8) shr 6) +
        ((x and 0b10000000'u8) shr 7)


    for it in low(uint8)..high(uint8):
      arr[it] = countSetBits(cast[uint8](it))

    arr

proc bitSetCard*(x: BitSet): int =
  result = 0
  for it in (seq[ElemType])(x):
    result.inc int(populationCount[it])

proc bitSetToWord*(s: BitSet; size: int): uint32 =
  result = 0
  for j in 0..<size:
    if j < s.len: result = result or (uint32(s[j]) shl (j * 8))

proc `==`*(x: BitSet, l: BitSet): bool = bitSetEquals(x, l)

proc toBitSet*(values: openArray[int]): BitSet =
  result.bitSetInit(1)
  for v in values:
    result.bitSetIncl v

iterator items*(self: BitSet): int =
  for wordIndex in 0..<self.len:
    let word = self[wordIndex].int
    if word == 0:
      continue
    for bitIndex in 0..<ElemSize:
      if (word and (1 shl bitIndex)) != 0:
        yield wordIndex * ElemSize + bitIndex