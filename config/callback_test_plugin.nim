import plugin_runtime

proc testAddCallback(f: proc(b: int64) {.cdecl.}) {.importc.}

proc callTestCallback*(f: proc(b: int64) {.cdecl.}, b: int64) {.wasmexport.} =
  f(b)

proc testCallback(b: int64) {.cdecl.} =
  infof"testCallback: {b}"

infof"addCallback"
testAddCallback(testCallback)
infof"call callback"
callTestCallback(testCallback, 456)

include plugin_runtime_impl
