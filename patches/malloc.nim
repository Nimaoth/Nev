{.push stackTrace: off.}

const nevModuleName {.strdefine.}: string = ""
const implModule = nevModuleName == "nev"

when defined(mallocImport):
  proc allocImpl2(size: Natural): pointer {.importc, dynlib: "nev.exe".}
  proc alloc0Impl2(size: Natural): pointer {.importc, dynlib: "nev.exe".}
  proc reallocImpl2(p: pointer, newSize: Natural): pointer {.importc, dynlib: "nev.exe".}
  proc deallocImpl2(p: pointer) {.importc, dynlib: "nev.exe".}

  proc allocImpl(size: Natural): pointer = allocImpl2(size)
  proc alloc0Impl(size: Natural): pointer = alloc0Impl2(size)
  proc reallocImpl(p: pointer, newSize: Natural): pointer = reallocImpl2(p, newSize)
  proc deallocImpl(p: pointer) = deallocImpl2(p)
else:
  proc allocImpl(size: Natural): pointer =
    result = c_malloc(size.csize_t)
    when defined(zephyr):
      if result == nil:
        raiseOutOfMem()

  proc alloc0Impl(size: Natural): pointer =
    result = c_calloc(size.csize_t, 1)
    when defined(zephyr):
      if result == nil:
        raiseOutOfMem()

  proc reallocImpl(p: pointer, newSize: Natural): pointer =
    result = c_realloc(p, newSize.csize_t)
    when defined(zephyr):
      if result == nil:
        raiseOutOfMem()

  proc deallocImpl(p: pointer) =
    c_free(p)

  when defined(mallocExport):
    proc allocImpl2(size: Natural): pointer {.exportc, dynlib.} = allocImpl(size)
    proc alloc0Impl2(size: Natural): pointer {.exportc, dynlib.} = alloc0Impl(size)
    proc reallocImpl2(p: pointer, newSize: Natural): pointer {.exportc, dynlib.} = reallocImpl(p, newSize)
    proc deallocImpl2(p: pointer) {.exportc, dynlib.} = deallocImpl(p)

    proc host_malloc*(size: csize_t): pointer {.exportc: "host_malloc", dynlib.} = c_malloc(size)
    proc host_calloc*(nmemb, size: csize_t): pointer {.exportc: "host_calloc", dynlib.} = c_calloc(nmemb, size)
    proc host_realloc*(p: pointer, newsize: csize_t): pointer {.exportc: "host_realloc", dynlib.} = c_realloc(p, newsize)
    proc host_free*(p: pointer) {.exportc: "host_free", dynlib.} = c_free(p)

proc realloc0Impl(p: pointer, oldsize, newSize: Natural): pointer =
  result = realloc(p, newSize.csize_t)
  if newSize > oldSize:
    zeroMem(cast[pointer](cast[uint](result) + uint(oldSize)), newSize - oldSize)

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
