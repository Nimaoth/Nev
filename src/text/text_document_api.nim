import std/[options, json]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import document
import misc/[custom_async]
import nimsumtree/rope
include dynlib_export

proc getLanguageWordBoundary*(self: Document, cursor: Cursor): Selection {.rtlImport.}
func contentString*(self: Document, selection: Selection, inclusiveEnd: bool = false): string {.rtlImport.}
proc getImportedFiles*(self: Document): Future[Option[seq[string]]] {.rtlImport.}
proc textDocumentApplyMove*(self: Document, selections: openArray[Range[Point]], move: string, count: int = 0, includeEol: bool = true, wrap: bool = true, options: JsonNode = nil): seq[Range[Point]] {.rtlImport.}
proc textDocumentContentString*(self: Document, selection: Range[Point], inclusiveEnd: bool = false): string {.rtlImport.}

# Nice wrappers
proc applyMove*(self: Document, selections: openArray[Range[Point]], move: string, count: int = 0, includeEol: bool = true, wrap: bool = true, options: JsonNode = nil): seq[Range[Point]] {.inline.} = textDocumentApplyMove(self, selections, move, count, includeEol, wrap, options)
proc contentString*(self: Document, selection: Range[Point], inclusiveEnd: bool = false): string = textDocumentContentString(self, selection, inclusiveEnd)
