
type Document* = ref object of RootObj
  discard

type AstDocument* = ref object of Document
  filename*: string

method `$`*(document: Document): string {.base.} =
  return ""

method `$`*(document: AstDocument): string =
  return document.filename