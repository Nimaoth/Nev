type DaTag* = enum
  daMain
  daRender
  daEvent
  daPoll
  daMalebolgia
  daThreadpool
  daLspClient
  daTerminal
  daTextEditorCommand
  daProfiler
  daTreesitter

when defined(profiler):
  # Exp
  when defined(useDynlib):
    # We are compiling the file importing the declarations
    {.pragma: apprtl, importc, dynlib: "nev.exe", cdecl.}
  else:
    # We are linking statically
    {.pragma: apprtl, exportc, dynlib.}

  {.push apprtl, gcsafe, raises: [].}
  proc daIncludeCurrentTagBit(bitIndex: uint64) {.importc.}
  proc daExcludeCurrentTagBit(bitIndex: uint64) {.importc.}
  proc profProcessAllocatorEvents*() {.importc.}
  {.pop.}

  template withDaTag*(tag: DaTag, body: untyped): untyped =
    daIncludeCurrentTagBit(uint64(ord(tag)))
    defer:
      daExcludeCurrentTagBit(uint64(ord(tag)))
    body

  template daTag*(tag: DaTag): untyped =
    daIncludeCurrentTagBit(uint64(ord(tag)))
    defer:
      daExcludeCurrentTagBit(uint64(ord(tag)))

  template daGlobalTag*(tag: DaTag): untyped =
    daIncludeCurrentTagBit(uint64(ord(tag)))

  proc stacktracerGetStacktrace*(): cstring {.importc: "stacktracer_get_stacktrace".}
  proc stacktracerFreeStacktrace*(str: cstring) {.importc: "stacktracer_free_stacktrace".}

  proc profStackTrace*() =
    let stack = stacktracerGetStacktrace()
    echo stack
    stacktracerFreeStacktrace(stack)


else:
  template withDaTag*(tag: DaTag, body: untyped): untyped =
    body

  template daTag*(tag: DaTag): untyped =
    discard

  template daGlobalTag*(tag: DaTag): untyped =
    discard

  proc profProcessAllocatorEvents*() = discard

  # proc stacktracerGetStacktrace*(): cstring = ""
  # proc stacktracerFreeStacktrace*(str: cstring) = discard

  # proc profStackTrace*() = discard
  proc stacktracerGetStacktrace*(): cstring {.importc: "stacktracer_get_stacktrace".}
  proc stacktracerFreeStacktrace*(str: cstring) {.importc: "stacktracer_free_stacktrace".}

  proc profStackTrace*() =
    let stack = stacktracerGetStacktrace()
    echo stack
    stacktracerFreeStacktrace(stack)

