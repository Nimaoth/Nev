import std/[atomics]
include misc/dynlib_export

const daMetaStackDepth* = 64

type
  DaMetaEventKind* {.size: sizeof(uint8).} = enum
    dmekAlloc = 1
    dmekAlloc0 = 2
    dmekRealloc = 3
    dmekFree = 4

  DaMetaEvent* = object
    gen*: Atomic[uint64]
    sequence*: uint64
    timestamp*: float64
    threadId*: uint64
    tag*: uint64
    stackTrace*: cstring
    returnAddressHash*: uint64
    oldPtr*: uint64
    newPtr*: uint64
    oldUsableSize*: int32
    newUsableSize*: int32
    kind*: DaMetaEventKind
    sequence2*: uint64

{.push apprtl, gcsafe, raises: [].}
proc daGetAllocated*(): int
proc daIncludeCurrentTagBit*(bitIndex: uint64)
proc daExcludeCurrentTagBit*(bitIndex: uint64)
proc daGetCurrentTag*(): uint64
proc daGetMetaCapacity*(): int
proc daGetMetaWriteIndex*(): uint64
proc daGetMetaOldestIndex*(): uint64
proc daReadMetaEvent*(index: uint64, event: var DaMetaEvent): bool
proc daGetStackTraceCacheBytes*(): int
proc daGetDebugAllocatorStaticBytes*(): int
proc daSetBreakOnReturnAddressHash*(returnAddressHash: uint64)
{.pop.}

when implModule:
  import std/[tables, times]

  {.emit: """
  #if defined(_WIN32)
  #include <intrin.h>
  #include <windows.h>
  #endif

  static int da_capture_return_addresses(void** outAddrs, int maxDepth) {
    if (outAddrs == 0 || maxDepth <= 0) {
      return 0;
    }

  #if defined(_WIN32)
    USHORT captured = RtlCaptureStackBackTrace(2, (ULONG)maxDepth, outAddrs, NULL);
    return (int)captured;
  #else
    outAddrs[0] = __builtin_return_address(0);
    return 1;
  #endif
  }
  """.}

  proc stacktracerGetStacktrace(): cstring {.importc: "stacktracer_get_stacktrace".}
  proc stacktracerFreeStacktrace(str: cstring) {.importc: "stacktracer_free_stacktrace".}
  proc daCaptureReturnAddresses(outAddrs: ptr pointer, maxDepth: cint): cint {.importc: "da_capture_return_addresses", nodecl.}

  proc c_malloc*(size: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>".}
  proc c_calloc*(nmemb, size: csize_t): pointer {.importc: "calloc", header: "<stdlib.h>".}
  proc c_free*(p: pointer) {.importc: "free", header: "<stdlib.h>".}
  proc c_realloc*(p: pointer, newsize: csize_t): pointer {.importc: "realloc", header: "<stdlib.h>".}
  proc c_abort*() {.importc: "abort", header: "<stdlib.h>".}
  proc c_printf*(formatstr: cstring): cint {.importc: "printf", varargs, header: "<stdio.h>".}
  proc c_fflush*(stream: pointer): cint {.importc: "fflush", header: "<stdio.h>".}
  proc c_strcmp*(a: cstring, b: cstring): cint {.importc: "strcmp", header: "<string.h>".}
  proc c_strstr*(haystack: cstring, needle: cstring): cstring {.importc: "strstr", header: "<string.h>".}

  when defined(windows):
    proc c_msize*(p: pointer): csize_t {.importc: "_msize", header: "<malloc.h>".}
  elif defined(macosx):
    proc c_malloc_size*(p: pointer): csize_t {.importc: "malloc_size", header: "<malloc/malloc.h>".}
  else:
    proc c_malloc_usable_size*(p: pointer): csize_t {.importc: "malloc_usable_size", header: "<malloc.h>".}

  const daMetaCapacity = 10_000_000

  type
    DaMetaSlot = object
      event: DaMetaEvent

  {.push threadvar.}
  var allocated*: int
  var currentTag*: uint64
  var currentThreadIdCache*: uint64
  var stackTracesByHash: Table[uint64, cstring]
  var inAllocatorHook*: bool
  var breakOnReturnAddressHash*: uint64
  {.pop.}

  var metaWriteIndex: Atomic[uint64]
  var metaRing: array[daMetaCapacity, DaMetaSlot]
  var stackTraceCacheBytesGlobal: Atomic[uint64]
  var stackTraceCacheEntriesGlobal: Atomic[uint64]

  proc daDebugBreak() {.inline, gcsafe, raises: [].} =
    when defined(i386) or defined(amd64):
      asm "int3"
    else:
      c_abort()

  proc blockSize(p: pointer): int

  proc captureNormalizedStacktrace(rawTraceOut: var cstring): cstring =
    rawTraceOut = stacktracerGetStacktrace()
    let rawTrace = rawTraceOut
    if rawTrace.isNil:
      return nil

    const marker = "debug_allocator.nim"
    var searchFrom = rawTrace
    var lastMarkerLineStart: cstring = nil

    while true:
      let found = c_strstr(searchFrom, marker)
      if found.isNil:
        break

      var lineStart = found
      while cast[uint](lineStart) > cast[uint](rawTrace):
        let prev = cast[cstring](cast[uint](lineStart) - 1'u)
        if prev[0] == '\n':
          break
        lineStart = prev

      lastMarkerLineStart = lineStart
      searchFrom = cast[cstring](cast[uint](found) + 1'u)

    if not lastMarkerLineStart.isNil:
      var afterMarkerLine = lastMarkerLineStart
      while afterMarkerLine[0] != '\0' and afterMarkerLine[0] != '\n':
        afterMarkerLine = cast[cstring](cast[uint](afterMarkerLine) + 1'u)

      if afterMarkerLine[0] == '\n':
        return cast[cstring](cast[uint](afterMarkerLine) + 1'u)
      return afterMarkerLine
    return rawTrace

  proc captureStackTraceForHashIfNeeded(returnAddressHash: uint64): cstring =
    if returnAddressHash == 0:
      return nil

    if stackTracesByHash.len == 0:
      stackTracesByHash = initTable[uint64, cstring](50000)

    if stackTracesByHash.hasKey(returnAddressHash):
      return stackTracesByHash[returnAddressHash]

    if not stackTracesByHash.hasRoom:
      return nil

    var traceRaw: cstring = nil
    let trace = captureNormalizedStacktrace(traceRaw)
    if trace.isNil:
      return nil

    let rawTraceBytes =
      if traceRaw.isNil:
        0
      else:
        blockSize(traceRaw)

    stackTracesByHash[returnAddressHash] = trace

    if rawTraceBytes > 0:
      discard stackTraceCacheBytesGlobal.fetchAdd(uint64(rawTraceBytes), moSequentiallyConsistent)
    discard stackTraceCacheEntriesGlobal.fetchAdd(1'u64, moRelaxed)

    return trace

  proc captureNormalizedStacktrace2(rawTraceOut: var cstring): cstring =
    ## wrapper to make sure captureNormalizedStacktrace is at the same depth as when calling captureStackTraceForHashIfNeeded
    captureNormalizedStacktrace(rawTraceOut)

  proc maybeBreakOnAllocation(returnAddressHash: uint64) =
    let targetHash = breakOnReturnAddressHash
    if targetHash == 0 or returnAddressHash != targetHash:
      return

    let cachedHashTrace = captureStackTraceForHashIfNeeded(returnAddressHash)
    var trueTraceRaw: cstring = nil
    let trueTrace = captureNormalizedStacktrace2(trueTraceRaw)
    let tracesDiffer =
      if cachedHashTrace.isNil and trueTrace.isNil:
        false
      elif cachedHashTrace.isNil or trueTrace.isNil:
        true
      else:
        c_strcmp(cachedHashTrace, trueTrace) != 0

    discard c_printf("[debug_allocator] Break on allocation hash matched: 0x%llx\n", targetHash)
    discard c_printf("[debug_allocator] Current allocation hash: 0x%llx\n", returnAddressHash)
    discard c_printf("[debug_allocator] True stack trace differs from hash stack trace: %s\n", if tracesDiffer: "yes" else: "no")
    if tracesDiffer:
      discard c_printf("[debug_allocator] Hash stack trace:\n%s\n", if cachedHashTrace.isNil: "<no hash stack trace>".cstring else: cachedHashTrace)
    discard c_printf("[debug_allocator] True stack trace:\n%s\n", if trueTrace.isNil: "<no true stack trace>".cstring else: trueTrace)
    discard c_fflush(nil)

    if not trueTraceRaw.isNil:
      stacktracerFreeStacktrace(trueTraceRaw)

    daDebugBreak()

  proc getCurrentThreadIdCached(): uint64 =
    if currentThreadIdCache == 0:
      currentThreadIdCache = getThreadId().uint64
    return currentThreadIdCache

  proc hashReturnAddress(returnAddress: uint64): uint64 =
    # SplitMix64 finalizer gives good avalanche for pointer-like integers.
    var x = returnAddress
    x = (x xor (x shr 30)) * 0xbf58476d1ce4e5b9'u64
    x = (x xor (x shr 27)) * 0x94d049bb133111eb'u64
    return x xor (x shr 31)

  proc hashReturnAddresses(returnAddresses: openArray[pointer], returnAddressDepth: int): uint64 =
    var depth = returnAddressDepth
    if depth < 0:
      depth = 0
    if depth > daMetaStackDepth:
      depth = daMetaStackDepth
    if depth > returnAddresses.len:
      depth = returnAddresses.len
    if depth <= 0:
      return 0'u64

    var h = 0x9e3779b97f4a7c15'u64 xor uint64(depth)
    for i in 0..<depth:
      let a = cast[uint64](returnAddresses[i])
      let mixed = hashReturnAddress(a xor (uint64(i) * 0x9e3779b97f4a7c15'u64))
      h = h xor (mixed + 0x9e3779b97f4a7c15'u64 + (h shl 6) + (h shr 2))
    return h

  proc currentTimeSeconds(): float64 =
    getTime().toUnixFloat()

  proc writeMetaEvent(kind: DaMetaEventKind, oldPtr, newPtr: pointer, returnAddresses: openArray[pointer], returnAddressDepth: int, oldUsableSize, newUsableSize: int) =
    let sequence = metaWriteIndex.fetchAdd(1'u64, moSequentiallyConsistent)
    let slotIndex = int(sequence mod daMetaCapacity.uint64)
    let writeSeq = sequence * 2'u64 + 1'u64
    let commitSeq = writeSeq + 1'u64
    assert commitSeq != 0

    var depth = returnAddressDepth
    if depth < 0:
      depth = 0
    if depth > daMetaStackDepth:
      depth = daMetaStackDepth

    let firstReturnAddress =
      if depth > 0 and returnAddresses.len > 0:
        cast[uint64](returnAddresses[0])
      else:
        0'u64

    # if newUsableSize > 100 * 1024 * 1024:
    #   asm "int3"

    var event = DaMetaEvent(
      sequence: sequence,
      sequence2: sequence,
      timestamp: currentTimeSeconds(),
      threadId: getCurrentThreadIdCached(),
      tag: currentTag,
      stackTrace: nil,
      returnAddressHash: hashReturnAddresses(returnAddresses, depth),
      kind: kind,
      oldPtr: cast[uint64](oldPtr),
      newPtr: cast[uint64](newPtr),
      oldUsableSize: oldUsableSize.int32,
      newUsableSize: newUsableSize.int32,
    )
    event.gen.store(writeSeq, moRelaxed)

    assert writeSeq != 0
    metaRing[slotIndex].event.gen.store(writeSeq, moRelease)
    event.stackTrace = captureStackTraceForHashIfNeeded(event.returnAddressHash)
    metaRing[slotIndex].event = event
    assert commitSeq == writeSeq + 1
    metaRing[slotIndex].event.gen.store(commitSeq, moRelease)

  proc blockSize(p: pointer): int =
    if p == nil:
      return 0

    when defined(windows):
      return int(c_msize(p))
    elif defined(macosx):
      return int(c_malloc_size(p))
    else:
      return int(c_malloc_usable_size(p))

  proc daGetAllocated*(): int =
    return allocated

  proc bitMaskFromIndex(bitIndex: uint64): uint64 =
    if bitIndex < 64:
      return 1'u64 shl int(bitIndex)
    return 0'u64

  proc daIncludeCurrentTagBit*(bitIndex: uint64) =
    currentTag = currentTag or bitMaskFromIndex(bitIndex)

  proc daExcludeCurrentTagBit*(bitIndex: uint64) =
    currentTag = currentTag and (not bitMaskFromIndex(bitIndex))

  proc daGetCurrentTag*(): uint64 =
    return currentTag

  proc daGetMetaCapacity*(): int =
    return daMetaCapacity

  proc daGetMetaWriteIndex*(): uint64 =
    return metaWriteIndex.load(moAcquire)

  proc daGetMetaOldestIndex*(): uint64 =
    let write = metaWriteIndex.load(moAcquire)
    if write > daMetaCapacity.uint64:
      return write - daMetaCapacity.uint64
    return 0

  proc daGetStackTraceCacheBytes*(): int =
    let entryCount = stackTraceCacheEntriesGlobal.load(moRelaxed)
    let cacheIndexBytes = entryCount * uint64(sizeof(uint64) + sizeof(cstring))
    int(stackTraceCacheBytesGlobal.load(moRelaxed)) + cacheIndexBytes.int

  proc daGetDebugAllocatorStaticBytes*(): int =
    let globalBytes = uint64(
      sizeof(array[daMetaCapacity, DaMetaSlot])
    )
    int(globalBytes)

  proc daReadMetaEvent*(index: uint64, event: var DaMetaEvent): bool =
    let write = metaWriteIndex.load(moAcquire)
    if index >= write:
      event = DaMetaEvent()
      return false

    if write - index > daMetaCapacity.uint64:
      event = DaMetaEvent()
      return false

    let slotIndex = int(index mod daMetaCapacity.uint64)
    let expectedSeq = index * 2'u64 + 2'u64

    let seq1 = metaRing[slotIndex].event.gen.load(moAcquire)
    event = metaRing[slotIndex].event

    if seq1 != expectedSeq:
      let oldest = if write > daMetaCapacity.uint64:
        write - daMetaCapacity.uint64
      else:
        0
      event = metaRing[slotIndex].event
      return false

    let seq2 = metaRing[slotIndex].event.gen.load(moAcquire)
    if seq2 != seq1:
      return false

    return true

  proc daSetBreakOnReturnAddressHash*(returnAddressHash: uint64) =
    breakOnReturnAddressHash = returnAddressHash

  proc profilerAlloc(size: Natural): pointer {.exportc.} =
    if inAllocatorHook:
      return c_malloc(size.csize_t)

    inAllocatorHook = true
    defer:
      inAllocatorHook = false

    var returnAddresses: array[daMetaStackDepth, pointer]
    let returnAddressDepth = int(daCaptureReturnAddresses(returnAddresses[0].addr, daMetaStackDepth.cint))
    let returnAddressHash = hashReturnAddresses(returnAddresses, returnAddressDepth)
    maybeBreakOnAllocation(returnAddressHash)
    result = c_malloc(size.csize_t)
    if result != nil:
      let usableSize = blockSize(result)
      allocated += usableSize
      writeMetaEvent(dmekAlloc, nil, result, returnAddresses, returnAddressDepth, 0, usableSize)

  proc profilerAlloc0(size: Natural): pointer {.exportc.} =
    if inAllocatorHook:
      return c_calloc(size.csize_t, 1)

    inAllocatorHook = true
    defer:
      inAllocatorHook = false

    var returnAddresses: array[daMetaStackDepth, pointer]
    let returnAddressDepth = int(daCaptureReturnAddresses(returnAddresses[0].addr, daMetaStackDepth.cint))
    let returnAddressHash = hashReturnAddresses(returnAddresses, returnAddressDepth)
    maybeBreakOnAllocation(returnAddressHash)
    result = c_calloc(size.csize_t, 1)
    if result != nil:
      let usableSize = blockSize(result)
      allocated += usableSize
      writeMetaEvent(dmekAlloc0, nil, result, returnAddresses, returnAddressDepth, 0, usableSize)

  proc profilerDealloc(p: pointer) {.exportc.} =
    if inAllocatorHook:
      if p != nil:
        c_free(p)
      return

    inAllocatorHook = true
    defer:
      inAllocatorHook = false

    var returnAddresses: array[daMetaStackDepth, pointer]
    let returnAddressDepth = int(daCaptureReturnAddresses(returnAddresses[0].addr, daMetaStackDepth.cint))
    if p != nil:
      let oldUsableSize = blockSize(p)
      allocated -= oldUsableSize
      writeMetaEvent(dmekFree, p, nil, returnAddresses, returnAddressDepth, oldUsableSize, 0)
      c_free(p)

  proc profilerRealloc(p: pointer, newSize: Natural): pointer {.exportc.} =
    if inAllocatorHook:
      return c_realloc(p, newSize.csize_t)

    inAllocatorHook = true
    defer:
      inAllocatorHook = false

    var returnAddresses: array[daMetaStackDepth, pointer]
    let returnAddressDepth = int(daCaptureReturnAddresses(returnAddresses[0].addr, daMetaStackDepth.cint))
    let returnAddressHash = hashReturnAddresses(returnAddresses, returnAddressDepth)
    maybeBreakOnAllocation(returnAddressHash)
    if p == nil:
      result = c_malloc(newSize.csize_t)
      if result != nil:
        let usableSize = blockSize(result)
        allocated += usableSize
        writeMetaEvent(dmekAlloc, nil, result, returnAddresses, returnAddressDepth, 0, usableSize)
      return

    if newSize == 0:
      let oldUsableSize = blockSize(p)
      allocated -= oldUsableSize
      writeMetaEvent(dmekFree, p, nil, returnAddresses, returnAddressDepth, oldUsableSize, 0)
      c_free(p)
      return nil

    let oldSize = blockSize(p)
    result = c_realloc(p, newSize.csize_t)
    if result != nil:
      let newUsableSize = blockSize(result)
      allocated += newUsableSize - oldSize
      writeMetaEvent(dmekRealloc, p, result, returnAddresses, returnAddressDepth, oldSize, newUsableSize)
    else:
      writeMetaEvent(dmekRealloc, p, nil, returnAddresses, returnAddressDepth, oldSize, 0)
