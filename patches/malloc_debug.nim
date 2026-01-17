
{.push stackTrace: off.}

type
  AllocMeta* = object
    stacktrace*: cstring
    size*: int
    list*: ptr AllocList
    index*: int64
    timestamp*: int
    threadId*: int

  AllocList = object
    prev: ptr AllocList
    next: ptr AllocList
    allocs: array[1024 * 1024, int64]
    freeIndex: int64

  ThreadAllocLists = object
    head: ptr AllocList
    tail: ptr AllocList

var threadListsHead: ptr ThreadAllocLists = nil
var threadListsTail: ptr ThreadAllocLists = nil

var mallocCaptureStacktrace*: bool = false
var mallocTimestamp*: int = 0
var gDebugLeaks*: bool = false

# var lists {.threadvar.}: ptr ThreadAllocLists
var lists = ThreadAllocLists()
var lock: SysLock
initSysLock(lock)

const PointerMask: uint64 = (1.uint64 shl 63) - 1
const FreeIndex: uint64 = (1.uint64 shl 63)

proc removeSelf(list: ptr AllocList) =
  if list == lists.tail:
    lists.tail = list.prev
    lists.tail.next = nil
  elif list == lists.head:
    lists.head = list.next
    lists.head.prev = nil
  else:
    list.prev.next = list.next
    list.next.prev = list.prev
  list.next = nil
  list.prev = nil

proc moveFirst(list: ptr AllocList) =
  if (list == lists.head and list == lists.tail) or (list == lists.head):
    return
  # list.removeSelf()
  # lists.head.prev = list
  # list.next = lists.head
  # list.prev = nil
  # lists.head = list

proc moveLast(list: ptr AllocList) =
  if (list == lists.head and list == lists.tail) or (list == lists.tail):
    return
  # list.removeSelf()
  # lists.tail.next = list
  # list.prev = lists.tail
  # list.next = nil
  # lists.tail = list

iterator allocationsAt*(timestamp: int): ptr AllocMeta =
  acquireSys(lock)
  defer:
    releaseSys(lock)
  var l = lists.head
  while l != nil:
    for a in l.allocs:
      if a > 0:
        let meta = cast[ptr AllocMeta](a)
        if meta.timestamp == timestamp:
          yield meta
    l = l.next

proc addAlloc(a: ptr AllocMeta) =
  acquireSys(lock)
  defer:
    releaseSys(lock)

  if lists.head == nil:
    lists.head = cast[ptr AllocList](c_calloc(sizeof(AllocList).csize_t, 1))
    lists.head.freeIndex = -1
    for i in 0..lists.head.allocs.high:
      lists.head.allocs[i] = -(i.int64 + 1)
    lists.head.allocs[lists.head.allocs.high] = int64.low

    lists.tail = lists.head
    lists.tail.allocs[0] = cast[int64](a)
    a.list = lists.tail
    a.index = 0


  elif lists.tail.freeIndex != int64.low:
    let index = -lists.tail.freeIndex
    lists.tail.freeIndex = lists.tail.allocs[index]
    assert lists.tail.freeIndex < 0
    lists.tail.allocs[index] = cast[int64](a)
    a.list = lists.tail
    a.index = index
    if lists.tail.freeIndex == int64.low:
      moveFirst(lists.tail)

  else:
    var it = lists.head
    while it != nil:
      if it.freeIndex != int64.low:
        let index = -it.freeIndex
        it.freeIndex = it.allocs[index]
        assert it.freeIndex < 0
        it.allocs[index] = cast[int64](a)
        a.list = it
        a.index = index
        if lists.tail.freeIndex == int64.low:
          moveFirst(lists.tail)
        return
      it = it.next

    # no empty slot found
    var newTail = cast[ptr AllocList](c_calloc(sizeof(AllocList).csize_t, 1))
    newTail.freeIndex = -1
    for i in 0..newTail.allocs.high:
      newTail.allocs[i] = -(i.int64 + 1)
    newTail.allocs[newTail.allocs.high] = int64.low

    newTail.prev = lists.tail
    lists.tail.next = newTail
    lists.tail = newTail
    lists.tail.allocs[0] = cast[int64](a)
    a.list = lists.tail
    a.index = 0

proc removeAlloc(a: ptr AllocMeta) =
  acquireSys(lock)
  defer:
    releaseSys(lock)
  let list = a.list
  let index = a.index
  list.allocs[index] = list.freeIndex
  if list.freeIndex == int64.low:
    moveLast(list)
  list.freeIndex = -index

proc `+*`(a: pointer, b: int): pointer =
  cast[pointer](cast[int](a) + b)

proc allocImpl(size: Natural): pointer =
  result = c_malloc((size + sizeof(AllocMeta)).csize_t)
  when defined(stacktracer):
    if mallocCaptureStacktrace:
      cast[ptr AllocMeta](result).stacktrace = stacktracerGetStacktrace()
    else:
      cast[ptr AllocMeta](result).stacktrace = nil
  cast[ptr AllocMeta](result).size = size
  cast[ptr AllocMeta](result).timestamp = mallocTimestamp
  cast[ptr AllocMeta](result).threadId = getThreadId()
  addAlloc(cast[ptr AllocMeta](result))

  result = result +* sizeof(AllocMeta)
  when defined(zephyr):
    if result == nil:
      raiseOutOfMem()

proc alloc0Impl(size: Natural): pointer =
  result = c_calloc((size + sizeof(AllocMeta)).csize_t, 1)
  when defined(stacktracer):
    if mallocCaptureStacktrace:
      cast[ptr AllocMeta](result).stacktrace = stacktracerGetStacktrace()
    else:
      cast[ptr AllocMeta](result).stacktrace = nil
  cast[ptr AllocMeta](result).size = size
  cast[ptr AllocMeta](result).timestamp = mallocTimestamp
  cast[ptr AllocMeta](result).threadId = getThreadId()
  addAlloc(cast[ptr AllocMeta](result))

  result = result +* sizeof(AllocMeta)
  when defined(zephyr):
    if result == nil:
      raiseOutOfMem()

proc reallocImpl(p: pointer, newSize: Natural): pointer =
  if p == nil:
    return allocImpl(newSize)
  var a = cast[ptr AllocMeta](p +* -sizeof(AllocMeta))
  let oldSize = a.size

  when defined(stacktracer):
    if newSize > oldSize:
      if a.stacktrace != nil:
        stacktracerFreeStacktrace(a.stacktrace)

  removeAlloc(a)
  result = c_realloc(a, (newSize + sizeof(AllocMeta)).csize_t) +* sizeof(AllocMeta)
  a = cast[ptr AllocMeta](result +* -sizeof(AllocMeta))
  a.size = newSize
  a.timestamp = mallocTimestamp
  a.threadId = getThreadId()
  when defined(stacktracer):
    if mallocCaptureStacktrace:
      a.stacktrace = stacktracerGetStacktrace()
  addAlloc(a)
  when defined(zephyr):
    if result == nil:
      raiseOutOfMem()

proc realloc0Impl(p: pointer, oldsize, newSize: Natural): pointer =
  result = reallocImpl(p, newSize.csize_t)
  if newSize > oldSize:
    zeroMem(cast[pointer](cast[uint](result) + uint(oldSize)), newSize - oldSize)

proc deallocImpl(p: pointer) =
  let a = cast[ptr AllocMeta](p +* -sizeof(AllocMeta))
  when defined(stacktracer):
    if a.stacktrace != nil:
      stacktracerFreeStacktrace(a.stacktrace)
  # removeAlloc(a)
  # c_free(a)

proc printMemoryStats*(full: bool = false) =
  acquireSys(lock)
  defer:
    releaseSys(lock)
  var allocCount = 0
  var allocSize = 0

  var it = lists.head
  while it != nil:
    for i in 0..it.allocs.high:
      if it.allocs[i] > 0:
        inc allocCount
        let a = cast[ptr AllocMeta](it.allocs[i])
        inc allocSize, a.size

    it = it.next

  echo "========================= memory stats ========================="
  echo "Count: ", allocCount
  echo "Size: ", allocSize, " b, ", (allocSize / (1024 * 1024)), " mb"
  if full:
    var s = ""

    it = lists.head
    while it != nil:
      for i in 0..it.allocs.high:
        if it.allocs[i] > 0:
          inc allocCount
          let a = cast[ptr AllocMeta](it.allocs[i])
          inc allocSize, a.size
          if a.stacktrace != nil and a.size > 1024:
            echo "--------------------------------------- ", (a.size / (1024 * 1024)), " mb, ", (a.size / 1024), " kb, ", a.size, " b"
            echo a.stacktrace
            # s.add $a.stacktrace
            # s.add "\n\n"

      it = it.next

    # echo s
  echo "================================================================"

# The shared allocators map on the regular ones

proc allocSharedImpl(size: Natural): pointer =
  allocImpl(size)

proc allocShared0Impl(size: Natural): pointer =
  alloc0Impl(size)

proc reallocSharedImpl(p: pointer, newSize: Natural): pointer =
  reallocImpl(p, newSize)

proc reallocShared0Impl(p: pointer, oldsize, newSize: Natural): pointer =
  realloc0Impl(p, oldSize, newSize)

proc deallocSharedImpl(p: pointer) = deallocImpl(p)


# Empty stubs for the GC

proc GC_disable() = discard
proc GC_enable() = discard

when not defined(gcOrc):
  proc GC_fullCollect() = discard
  proc GC_enableMarkAndSweep() = discard
  proc GC_disableMarkAndSweep() = discard

proc GC_setStrategy(strategy: GC_Strategy) = discard

proc getOccupiedMem(): int = discard
proc getFreeMem(): int = discard
proc getTotalMem(): int = discard

proc nimGC_setStackBottom(theStackBottom: pointer) = discard

proc initGC() = discard

proc newObjNoInit(typ: PNimType, size: int): pointer =
  result = alloc(size)

proc growObj(old: pointer, newsize: int): pointer =
  result = realloc(old, newsize)

proc nimGCref(p: pointer) {.compilerproc, inline.} = discard
proc nimGCunref(p: pointer) {.compilerproc, inline.} = discard

when not defined(gcDestructors):
  proc unsureAsgnRef(dest: PPointer, src: pointer) {.compilerproc, inline.} =
    dest[] = src

proc asgnRef(dest: PPointer, src: pointer) {.compilerproc, inline.} =
  dest[] = src
proc asgnRefNoCycle(dest: PPointer, src: pointer) {.compilerproc, inline,
  deprecated: "old compiler compat".} = asgnRef(dest, src)

type
  MemRegion = object

proc alloc(r: var MemRegion, size: int): pointer =
  result = alloc(size)
proc alloc0(r: var MemRegion, size: int): pointer =
  result = alloc0Impl(size)
proc dealloc(r: var MemRegion, p: pointer) = dealloc(p)
proc deallocOsPages(r: var MemRegion) = discard
proc deallocOsPages() = discard

{.pop.}
