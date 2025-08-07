import std/hashes
import misc/[util, id]
import vfs

type DocumentId* = distinct uint64

proc `==`*(a, b: DocumentId): bool {.borrow.}
proc hash*(vr: DocumentId): Hash {.borrow.}
proc `$`*(vr: DocumentId): string {.borrow.}

type Document* = ref object of RootObj
  id*: DocumentId
  appFile*: bool                        ## Whether this is an application file (e.g. stored in local storage on the browser)
  isBackedByFile*: bool = false
  requiresLoad*: bool = false           ## Whether the document content has not been scheduled for loading yet.
  filename*: string
  revision*: int
  undoableRevision*: int
  lastSavedRevision*: int               ## Undobale revision at the time we saved the last time
  vfs*: VFS

method `$`*(document: Document): string {.base, gcsafe, raises: [].} = return ""
method save*(self: Document, filename: string = "", app: bool = false) {.base, gcsafe, raises: [].} = discard
method load*(self: Document, filename: string = "") {.base, gcsafe, raises: [].} = discard
method deinit*(self: Document) {.base, gcsafe, raises: [].} = discard
method getStatisticsString*(self: Document): string {.base, gcsafe, raises: [].} = discard

proc normalizedPath*(self: Document): string {.gcsafe, raises: [].} =
  return self.vfs.normalize(self.filename)

proc localizedPath*(self: Document): string {.gcsafe, raises: [].} =
  return self.vfs.localize(self.filename)
