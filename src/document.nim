
type Document* = ref object of RootObj
  discard

method `$`*(document: Document): string {.base.} =
  return ""

method save*(self: Document, filename: string = "") {.base.} =
  discard

method load*(self: Document, filename: string = "") {.base.} =
  discard