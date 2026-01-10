import array_view

const defaultBucketSize = 4 * 1024

# This is a stack memory allocator which uses a segmented stack / arena / buckets
# Small allocations reuse the same memory over and over, big allocations
# are allocated in new buckets, and freed when restoring the stack size to a save point.
type
  Bucket = object
    # data: seq[uint8]
    data: ptr UncheckedArray[uint8]
    capacity: int
    len: int

  Arena* = object
    bucketSize: int
    buckets: seq[Bucket] = @[]

proc align(address, alignment: int): int =
  if alignment == 0: # Actually, this is illegal. This branch exists to actively
                     # hide problems.
    result = address
  else:
    result = (address + (alignment - 1)) and not (alignment - 1)

proc initArena*(bucketSize: int = defaultBucketSize): Arena =
  result = Arena(bucketSize: bucketSize)

proc addBucket(arena: var Arena, bucketSize: int) =
  arena.buckets.add Bucket(
    data: cast[ptr UncheckedArray[uint8]](allocShared0(bucketSize)),
    capacity: bucketSize,
    len: 0,
  )
  # echo "allocate bucket ", arena.buckets.len, " with size ", bucketSize, " -> ", cast[int](arena.buckets[arena.buckets.high].data)

proc alloc*(arena: var Arena, size: int, alignment: int): pointer =
  ## Allocate memory on top of the stack.

  # The size check is a bit pessimistic, can be improved to save a bit of memory.
  if arena.buckets.len == 0 or arena.buckets[arena.buckets.high].len + size + alignment >= arena.buckets[arena.buckets.high].capacity:
    let bucketSize = max(arena.bucketSize, size + alignment)
    arena.addBucket(bucketSize)

  let bucket = arena.buckets[arena.buckets.high].addr
  let address = cast[uint64](bucket[].data[bucket[].len].addr)
  let alignedAddress = align(address.int, alignment.int).uint64
  # echo &"mem_stack_alloc {size}, {alignment} -> {address} -> {alignedAddress} ({bucket[].len})"

  bucket.len += (alignedAddress - address).int + size.int
  assert bucket.len <= bucket.capacity
  return cast[pointer](alignedAddress)

proc allocEmptyArray*(arena: var Arena, num: int, T: typedesc): ArrayView[T] =
  if num == 0:
    return ArrayView[T].default
  let data = cast[ptr UncheckedArray[T]](arena.alloc(num * sizeof(T), alignof(T)))
  return initArrayView(data, len = 0, capacity = num)

proc allocArray*(arena: var Arena, num: int, T: typedesc): ArrayView[T] =
  if num == 0:
    return ArrayView[T].default
  let data = cast[ptr UncheckedArray[T]](arena.alloc(num * sizeof(T), alignof(T)))
  return initArrayView(data, len = num, capacity = num)

proc realloc*(arena: var Arena, address: pointer, oldSize: int, size: int, alignment: int): pointer =
  ## Allocate memory on top of the stack.

  # echo &"stackRealloc {cast[int](address)}, {oldSize} -> {size}, align: {alignment}"
  # defer:
  #   echo &"-> {cast[int](result)}"

  if address == nil or arena.buckets.len == 0:
    return arena.alloc(size, alignment)

  let addressInt = cast[int](address)

  var bucket: ptr Bucket = nil
  for i in countdown(arena.buckets.high, 0):
    # echo &"{addressInt} in {cast[int](arena.buckets[i].data)}..{cast[int](arena.arena.buckets[i].data) + arena.buckets[i].len}"
    if addressInt >= cast[int](arena.buckets[i].data) and addressInt < cast[int](arena.buckets[i].data) + arena.buckets[i].len:
      bucket = arena.buckets[i].addr
      break

  if bucket == nil:
    echo "Trying to realloc address " & $addressInt & " in arena but it wasn't allocated with the arena"
    assert bucket != nil, "Trying to realloc address " & $addressInt & " in arena but it wasn't allocated with the arena"
    return nil

  let offsetInBucket = addressInt - cast[int](bucket[].data)
  assert offsetInBucket >= 0
  assert offsetInBucket < bucket[].len

  let isLastAllocation = offsetInBucket + oldSize == bucket[].len

  if size < oldSize:
    if isLastAllocation:
      bucket[].len = offsetInBucket + size
    return address

  var inPlace = true
  if align(addressInt, alignment) != addressInt:
    # Alignment changed
    inPlace = false

  elif not isLastAllocation:
    # Not the last allocation in the current bucket
    inPlace = false

  elif offsetInBucket + size >= bucket[].capacity:
    # No space in current bucket
    inPlace = false

  if inPlace:
    bucket[].len = offsetInBucket + size
    return address
  else:
    let newMem = arena.alloc(size, alignment)
    copyMem(newMem, address, oldSize)
    return newMem

proc checkpoint*(arena: var Arena): uint64 =
  ## Save the current stack size, to be restored with stackRestore
  if arena.buckets.len == 0:
    return 0
  let len = arena.buckets[arena.buckets.high].len
  # echo &"mem_stack_save {arena.buckets.len}, {len}"
  return (arena.buckets.len.uint64 shl 32) or len.uint64

proc restoreCheckpoint*(arena: var Arena, p: uint64) =
  ## Restore the arena to the saved position. Frees overallocated memory.
  # if arena.buckets.len > 0:
    # echo "mem_stack_restore 1: ", cast[ptr (array[4, int], array[12, char])](arena.buckets[0].data)[]
  let oldLen = if arena.buckets.len > 0: arena.buckets[arena.buckets.high].len else: 0
  let oldBucketsLen = arena.buckets.len

  let bucketsLen = (p shr 32).int
  let len = (p and 0xFFFFFFFF.uint64).int
  while arena.buckets.len > bucketsLen and arena.buckets.len > 1:
    # echo "free bucket ", arena.buckets.len - 1, " with size ", arena.buckets[buckets.high].capacity
    deallocShared(arena.buckets[arena.buckets.high].data)
    discard arena.buckets.pop()

  # echo &"mem_stack_restore {oldBucketsLen}, {oldLen} -> {bucketsLen}, {len}"
  if arena.buckets.len > 0:
    arena.buckets[arena.buckets.high].len = len
    assert arena.buckets[arena.buckets.high].len <= arena.buckets[arena.buckets.high].capacity
