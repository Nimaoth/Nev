import std/[options]
import workspaces/[workspace]

type Document* = ref object of RootObj
  appFile*: bool                        ## Whether this is an application file (e.g. stored in local storage on the browser)
  filename*: string
  workspace*: Option[WorkspaceFolder]   ## The workspace this document belongs to

method `$`*(document: Document): string {.base.} =
  return ""

method save*(self: Document, filename: string = "", app: bool = false) {.base.} =
  discard

method load*(self: Document, filename: string = "") {.base.} =
  discard