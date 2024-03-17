import std/[os, strformat]

## This module provides a sequence type that can store a small number of elements inline,
## requiring no heap allocation.

const MAX_COUNT8 = 127 ## Max number of elements that can be store inline for types with a size of 1 byte.

type
  Data[T; Count: static int] {.union.} = object
    when sizeof(T) == 1 and Count <= MAX_COUNT8:
      # Store the length in one byte, so we can use the other 7 bytes for the array.
      inline8: tuple[len: uint8, arr: array[max(Count, 23), T]]
    inline: tuple[len: uint64, arr: array[Count, T]]
    heap: tuple[len: uint64, arr: ptr UncheckedArray[T], capacity: int]

  SmallSeq*[T; Count: static int] = object
    ## Sequence type which can store a small number of elements inline, requiring no heap allocation.
    ## A small sequence is at least 24 bytes in size, and can store at least `Count` elements inline.
    ## Whether the data is currently stored inline or on the heap is indicated by the lowest bit of the first byte of the SmallSeq.
    ## If the lowest bit of the first byte is 0, the data is stored inline, otherwise it's stored on the heap.
    ## The length of the sequence is stored multiplied by 2.
    ##
    ## For creating an empty SmallSeq use `initSmallSeq proc #initSmallSeq`
    data: Data[T, Count]

static:
  assert sizeof(Data[uint8, 15]) == 24 # 1 byte for the length, 15 for the array, and 8 padding
  assert sizeof(Data[uint8, 16]) == 24 # 1 byte for the length, 16 for the array, and 7 padding
  assert sizeof(Data[uint8, MAX_COUNT8 + 1]) == 8 + MAX_COUNT8 + 1 # 8 bytes for the length, and the rest for the array
  assert sizeof(Data[uint16, 16]) == 8 + 32 # 8 bytes for the length, and the rest for the array

proc getInlineData[T; Count: static int](s: ptr SmallSeq[T, Count]): ptr UncheckedArray[T] =
  ## Returns a pointer to the inline data array
  when sizeof(T) == 1 and Count <= MAX_COUNT8:
    return cast[ptr UncheckedArray[T]](s.data.inline8.arr.addr)
  else:
    return cast[ptr UncheckedArray[T]](s.data.inline.arr.addr)

proc isInline[T; Count: static int](s: SmallSeq[T, Count]): bool =
  ## Returns true if the sequence is stored inline
  let tag = cast[ptr uint8](s.addr)[]
  return (tag and 1) == 0

proc setInline[T; Count: static int](s: var SmallSeq[T, Count], inline: bool) =
  ## CHanges the flag that indicates if the sequence is stored inline
  let tag = cast[ptr uint8](s.addr)
  if inline:
    tag[] = tag[] and 0b1111_1110
  else:
    tag[] = tag[] or 1

proc getData*[T; Count: static int](s: ptr SmallSeq[T, Count]): ptr UncheckedArray[T] =
  if s[].isInline:
    return s.getInlineData()
  else:
    return s.data.heap.arr

func len*[T; Count: static int](s: SmallSeq[T, Count]): int =
  ## Returns the current length of the seq
  if s.isInline:
    when sizeof(T) == 1 and Count <= MAX_COUNT8:
      return int(s.data.inline8.len shr 1)
    else:
      return int(s.data.inline.len shr 1)
  else:
    return int(s.data.heap.len shr 1)

func `high`*[T; Count: static int](s: SmallSeq[T, Count]): int =
  ## Returns the highest valid index of the sequence, or -1 if the sequence is empty
  s.len - 1

func `len=`[T; Count: static int](s: var SmallSeq[T, Count], len: int) =
  ## Internal: set the length of the sequence
  if s.isInline:
    when sizeof(T) == 1 and Count <= MAX_COUNT8:
      s.data.inline8.len = len.uint8 shl 1
    else:
      s.data.inline.len = len.uint64 shl 1
  else:
    s.data.heap.len = (len.uint64 shl 1) or 1

template `[]`*[T; Count: static int; I: Ordinal](s: SmallSeq[T, Count], slice: Slice[I]): openArray[T] =
  ## Converts the SmallSeq to an openArray
  s.addr.getData().toOpenArray(slice.a, slice.b)

func `[]`*[T; Count: static int; I: Ordinal](s: SmallSeq[T, Count], index: I): lent T =
  ## Returns the element at the given index
  assert index >= 0
  assert index < s.len
  return s.addr.getData()[index]

func inlineCapacity*(T: typedesc, Count: static int): int =
  ## Returns the capacity of the inline storage for the given type and count
  when sizeof(T) == 1 and Count <= MAX_COUNT8:
    return max(Count, 23)
  else:
    return Count

func capacity*[T; Count: static int](s: SmallSeq[T, Count]): int =
  ## Returns the current capacity of the sequence
  if s.isInline:
    return inlineCapacity(T, Count)
  else:
    return s.data.heap.capacity

proc initSmallSeq*(T: typedesc, count: static int): SmallSeq[T, count] =
  ## Initializes a new SmallSeq
  result.data.inline.len = 0

iterator items*[T; Count: static int](s: SmallSeq[T, Count]): lent T =
  if s.isInline:
    let arr = s.addr.getInlineData
    for i in 0..<s.len:
      yield arr[i]
  else:
    let arr = s.data.heap.arr
    for i in 0..<s.len:
      yield arr[i]

iterator mitems*[T; Count: static int](s: var SmallSeq[T, Count]): var T =
  if s.isInline:
    let arr = s.addr.getInlineData
    for i in 0..<s.len:
      yield arr[i]
  else:
    let arr = s.data.heap.arr
    for i in 0..<s.len:
      yield arr[i]

iterator pairs*[T; Count: static int](s: SmallSeq[T, Count]): tuple[key: int, value: lent T] =
  var i = 0
  for v in s.items:
    yield (i, v)
    inc i

iterator mpairs*[T; Count: static int](s: var SmallSeq[T, Count]): tuple[key: int, value: var T] =
  var i = 0
  for v in s.mitems:
    yield (i, v)
    inc i

proc `$`*[T; Count: static int](s: SmallSeq[T, Count]): string =
  result = "s["
  if s.isInline:
    result.add "inline "
  else:
    result.add "heap "

  for i, v in s:
    if i > 0:
      result.add ", "
    result.add $v

  result.add " | "
  result.add $(s.capacity - s.len)
  result.add " ]"

proc moveToHeap[T; Count: static int](s: var SmallSeq[T, Count], slack: int) =
  ## Move the data from the inline storage to the heap
  assert s.isInline
  let len = s.len
  let inlineArr = s.addr.getInlineData
  let capacity = inlineCapacity(T, Count) + slack
  var heapArr = cast[ptr UncheckedArray[T]](alloc0(sizeof(T) * capacity))
  for i in 0..<len:
    heapArr[i] = inlineArr[i]
  s.data.heap.len = (len.uint64 shl 1) or 1
  s.data.heap.arr = heapArr
  s.data.heap.capacity = capacity

proc shrink[T; Count: static int](s: var SmallSeq[T, Count], slack: int = 0) =
  ## Try to shrink the capacity of the sequence to fit the current length + `slack`
  if s.isInline:
    return

  let len = s.len
  let newCapacity = len + slack
  let capacity = s.data.heap.capacity

  if newCapacity <= inlineCapacity(T, Count):
    # move to inline
    let arr = s.data.heap.arr

    s.setInline true
    s.len = len
    let inlineArr = s.addr.getInlineData

    for i in 0..<len:
      inlineArr[i] = arr[i]

    dealloc(arr)
    assert s.isInline
    assert s.len == len

  elif newCapacity < capacity:
    let heapArr = s.data.heap.arr
    let newHeapArr = cast[ptr UncheckedArray[T]](realloc0(heapArr.pointer, sizeof(T) * capacity, sizeof(T) * newCapacity))
    s.data.heap.arr = newHeapArr
    s.data.heap.capacity = newCapacity

proc grow[T; Count: static int](s: var SmallSeq[T, Count], newSize: int) =
  ## Grow the capacity of the sequence to `newSize`
  assert not s.isInline
  assert newSize > s.data.heap.capacity

  let heapArr = s.data.heap.arr
  let newHeapArr = cast[ptr UncheckedArray[T]](realloc0(heapArr.pointer, sizeof(T) * s.data.heap.capacity, sizeof(T) * newSize))
  s.data.heap.arr = newHeapArr
  s.data.heap.capacity = newSize

proc add*[T; Count: static int](s: var SmallSeq[T, Count], value: sink T) =
  ## Add a new element to the end of the sequence

  let len = s.len
  if s.isInline and len < inlineCapacity(T, Count):
    when sizeof(T) == 1 and Count <= MAX_COUNT8:
      s.data.inline8.arr[len] = value
      s.data.inline8.len += 2
    else:
      s.data.inline.arr[len] = value
      s.data.inline.len += 2
  else:
    if s.isInline:
      s.moveToHeap(5)

    if len == s.data.heap.capacity:
      s.grow(s.data.heap.capacity * 2)

    s.data.heap.arr[len] = value
    s.data.heap.len += 2

proc shift[T; Count: static int](s: var SmallSeq[T, Count], index: int, offset: int) =
  ## Shift the elements of the sequence starting at `index` by `offset` positions

  let len = s.len
  let arr = s.addr.getData()
  for i in countdown(len - 1, index):
    arr[i + offset] = arr[i]

proc insert*[T; Count: static int](s: var SmallSeq[T, Count], index: int, values: openArray[T]) =
  ## Insert the given values at the given index

  let len = s.len
  if s.isInline and len + values.len <= inlineCapacity(T, Count):
    s.shift(index, values.len)
    let arr = s.addr.getInlineData()
    for i in 0..<values.len:
      arr[index + i] = values[i]
    s.len = s.len + values.len

  else:
    # todo: this could be optimized by shiftingand moving to the heap in one operation instead of splitting it up
    if s.isInline:
      s.moveToHeap(5)

    if len == s.data.heap.capacity:
      s.resize(s.data.heap.capacity * 2)

    s.shift(index, values.len)

    for i in 0..<values.len:
      s.data.heap.arr[index + i] = values[i]

    s.len = s.len + values.len

proc insert*[T; Count: static int](s: var SmallSeq[T, Count], index: int, value: sink T) =
  ## Insert the given value at the given index

  let len = s.len
  if s.isInline and len + 1 <= inlineCapacity(T, Count):
    s.shift(index, 1)
    let arr = s.addr.getInlineData()
    arr[index] = value
    s.len = s.len + 1

  else:
    # todo: this could be optimized by shiftingand moving to the heap in one operation instead of splitting it up
    if s.isInline:
      s.moveToHeap(5)

    if len == s.data.heap.capacity:
      s.grow(s.data.heap.capacity * 2)

    s.shift(index, 1)

    s.data.heap.arr[index] = value

    s.len = s.len + 1

when isMainModule:
  var s = initSmallSeq(int8, 10)
  echo $s

  s.add 1
  s.add 2

  echo s, s[0]

  s.moveToHeap(0)

  echo s, s[0]

  s.shrink(0)

  echo s

  s.insert 0, 3
  s.insert 1, 4

  echo s, s[0..3]

  for i in 10..20:
    s.add i.int8

  echo s, s[0..3]

  for i in 35..37:
    s.insert 5, i.int8

  echo s, s[0..<4]

  s.shrink(0)

  echo s