import std/[sequtils, options]

type GenerationalSeq*[T; K] = object
  ## Even generation means empty slot, odd means it's filled
  data: seq[tuple[generation: uint32, value: T]]
  len: int

proc `$`*[T; K](self: GenerationalSeq[T, K]): string =
  result = "^["
  for i, e in self.data:
    if i > 0:
      result.add ", "
    result.add $(e.generation.uint64 shl 32)
  result.add "]"

proc freeIndex[T; K](self: var GenerationalSeq[T, K]): uint32 =
  # Could also store a list of free indices instead.
  for i, entry in self.data:
    if (entry.generation and 0x1) == 0:
      return i.uint32
  self.data.add (0.uint32, T.default)
  return self.data.high.uint32

proc split[K](genIndex: K): tuple[generation, index: uint32] =
  return ((genIndex.uint64 shr 32).uint32, genIndex.uint32)

proc del*[T; K](self: var GenerationalSeq[T, K], key: K) =
  let (generation, index) = key.split()
  if index.int in 0..self.data.high:
    let data = self.data[index].addr
    if (data[].generation and 0x1) == 1:
      inc data[].generation
      assert (data[].generation and 0x1) == 0
      data[].value = T.default
      dec self.len

proc add*[T; K](self: var GenerationalSeq[T, K], val: sink T): K =
  let index = self.freeIndex()
  let data = self.data[index].addr
  inc data[].generation
  assert (data[].generation and 0x1) == 1
  data[].value = val.ensureMove
  inc self.len
  return K((data[].generation.uint64 shl 32) or index.uint64)

proc contains*[T; K](self: GenerationalSeq[T, K], key: K): bool =
  let (generation, index) = key.split()
  if index.int notin 0..self.data.high:
    return false
  let data = self.data[index].addr
  if generation != data[].generation:
    return false
  return true

proc tryGet*[T; K](self: GenerationalSeq[T, K], key: K): Option[T] =
  let (generation, index) = key.split()
  if (generation and 0x1) == 0:
    return T.none
  if index.int notin 0..self.data.high:
    return T.none
  let data = self.data[index].addr
  if generation != data[].generation:
    return T.none
  return data[].value.some

proc `[]`*[T; K](self: var GenerationalSeq[T, K], key: K): var T =
  let (generation, index) = key.split()
  assert index.int in 0..self.data.high
  let data = self.data[index].addr
  assert generation == data[].generation
  return data[].value

proc `[]`*[T; K](self: GenerationalSeq[T, K], key: K): lent T =
  let (generation, index) = key.split()
  assert index.int in 0..self.data.high
  let data = self.data[index].addr
  assert generation == data[].generation
  return data[].value

iterator items*[T; K](self: GenerationalSeq[T, K]): lent T =
  for item in self.data:
    if (item.generation and 0x1) == 1:
      yield item.value

iterator items*[T; K](self: var GenerationalSeq[T, K]): var T =
  for item in self.data.mitems:
    if (item.generation and 0x1) == 1:
      yield item.value

iterator pairs*[T; K](self: GenerationalSeq[T, K]): (K, lent T) =
  var i = -1
  for item in self.data:
    if (item.generation and 0x1) == 1:
      inc i
      yield (K((item.generation.uint64 shl 32) or i.uint64), item.value)

iterator pairs*[T; K](self: var GenerationalSeq[T, K]): (K, var T) =
  var i = -1
  for item in self.data.mitems:
    if (item.generation and 0x1) == 1:
      inc i
      yield (K((item.generation.uint64 shl 32) or i.uint64), item.value)

func len*[T; K](self: GenerationalSeq[T, K]): int = self.len
