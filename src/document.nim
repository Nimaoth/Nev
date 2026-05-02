import std/[strformat, hashes, json]
import misc/[util, event, custom_async, id]
import nimsumtree/[arc]
import vfs, component

export component

include dynlib_export

type DocumentId* = distinct uint64

proc `==`*(a, b: DocumentId): bool {.borrow.}
proc hash*(vr: DocumentId): Hash {.borrow.}
proc `$`*(vr: DocumentId): string {.borrow.}

type Document* = ref object of ComponentOwner
  isInitialized*: bool
  id*: DocumentId
  uniqueId*: Id
  isBackedByFile*: bool = false
  requiresLoad*: bool = false           ## Whether the document content has not been scheduled for loading yet.
  isLoadingAsync*: bool = false
  readOnly*: bool = false
  staged*: bool = false
  filename*: string
  revision*: int
  undoableRevision*: int
  lastSavedRevision*: int               ## Undobale revision at the time we saved the last time
  vfs*: VFS
  vfs2*: Arc[VFS2]
  usage*: string
  preSaveHandlers*: seq[proc (self: Document): Future[void] {.async: (raises: []).}]
  onDocumentBeforeSave*: Event[Document]
  onDocumentSaved*: Event[Document]
  onDocumentLoaded*: Event[Document]

  deinitImpl*: proc(self: Document) {.gcsafe, raises: [].}
  saveImpl*: proc(self: Document, filename: string = ""): Future[void] {.gcsafe, async: (raises: []).}
  loadImpl*: proc(self: Document, filename: string = "", temp: bool = false) {.gcsafe, raises: [].}

  getMemoryStatsImpl*: proc(self: Document): JsonNode {.gcsafe, raises: [].}

proc newDocument*(): Document =
  new(result)
  let self = result
  self.uniqueId = newId()

# DLL API
{.push apprtl, gcsafe, raises: [].}
proc documentLocalizedPath*(self: Document): string
{.pop.}

proc localizedPath*(self: Document): string {.inline.} = documentLocalizedPath(self)

proc deinit*(self: Document) {.gcsafe, raises: [].} =
  if self.deinitImpl != nil:
    self.deinitImpl(self)

proc save*(self: Document, filename: string = ""): Future[void] {.async: (raises: []).} =
  if self.saveImpl != nil:
    await self.saveImpl(self, filename)

proc load*(self: Document, filename: string = "", temp: bool = false) =
  if self.loadImpl != nil:
    self.loadImpl(self, filename, temp)

proc getMemoryStats*(self: Document): JsonNode =
  if self.getMemoryStatsImpl != nil:
    return self.getMemoryStatsImpl(self)
  return newJObject()

proc setReadOnly*(self: Document, readOnly: bool) =
  ## Sets the interal readOnly flag, but doesn't not changed permission of the underlying file
  self.readOnly = readOnly

proc setFileReadOnlyAsync*(self: Document, readOnly: bool): Future[bool] {.async.} =
  ## Tries to set the underlying file permissions
  try:
    await self.vfs.setFileAttributes(self.filename, FileAttributes(writable: not readOnly, readable: true))
    self.readOnly = readOnly
    return true
  except IOError:
    return false

proc isReady*(self: Document): bool =
  return not (self.requiresLoad or self.isLoadingAsync)

func `$`*(document: Document): string {.gcsafe, raises: [].} =
  if document == nil:
    "Document(nil)"
  else:
    &"Document({document.id}, {document.filename})"

proc normalizedPath*(self: Document): string {.gcsafe, raises: [].} =
  return self.vfs.normalize(self.filename)

when implModule:
  proc documentLocalizedPath*(self: Document): string {.gcsafe, raises: [].} = self.vfs.localize(self.filename)
