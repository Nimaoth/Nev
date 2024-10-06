# todo: this is not needed anymore
type ArrayBuffer* = ref object
  buffer*: seq[uint8]

proc toArrayBuffer*(buffer: openArray[uint8]): ArrayBuffer =
  return ArrayBuffer(buffer: @buffer)
