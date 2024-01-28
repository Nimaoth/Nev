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

import std/bitops

type
  ElemType = uint32
  BitSet* = distinct seq[ElemType]

const
  ElemSize* = 32
  One = ElemType(1)
  Zero = ElemType(0)

template modElemSize(arg: untyped): untyped = arg and 31
template divElemSize(arg: untyped): untyped = arg shr 5

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
  let index = elem.divElemSize
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

proc bitSetCard*(x: BitSet): int =
  result = 0
  for it in (seq[ElemType])(x):
    result.inc it.countSetBits

proc `==`*(x: BitSet, l: BitSet): bool = bitSetEquals(x, l)

proc toBitSet*(values: openArray[int]): BitSet =
  result.bitSetInit(1)
  for v in values:
    result.bitSetIncl v

iterator items*(self: BitSet): int =
  for wordIndex in 0..<self.len:
    let word = self[wordIndex]
    if word == 0:
      continue
    for bitIndex in 0..<ElemSize:
      if (word and (1.ElemType shl bitIndex)) != 0:
        yield wordIndex * ElemSize + bitIndex

iterator pairs*(self: BitSet): (int, int) =
  var i = 0
  for value in self:
    yield (i, value)
    inc i

proc `$`*(x: BitSet): string =
  result.add "{"
  for i, value in x:
    if i > 0:
      result.add ", "
    result.add $value
  result.add "}"