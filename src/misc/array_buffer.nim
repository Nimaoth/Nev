
when defined(js):
  import std/[jsffi]
  type ArrayBuffer* = ref object of JsObject
else:
  type ArrayBuffer* = ref object
    buffer*: seq[uint8]

proc toArrayBuffer*(buffer: openArray[uint8]): ArrayBuffer =
  when defined(js):
    proc jsNewArrayBuffer(buffer: openArray[uint8]): ArrayBuffer {.importjs: "(new Uint8Array(#).buffer)".}
    return jsNewArrayBuffer(buffer)
  else:
    return ArrayBuffer(buffer: @buffer)