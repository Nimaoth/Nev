import std/hashes
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
  appFile*: bool                        ## Whether this is an application file (e.g. stored in local storage on the browser)
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

proc newDocument*(): Document =
  new(result)
  let self = result
  self.uniqueId = newId()

# DLL API
proc documentLocalizedPath*(self: Document): string {.apprtl, gcsafe, raises: [].}
proc localizedPath*(self: Document): string {.inline.} = documentLocalizedPath(self)

proc documentSave*(self: Document, filename: string = ""): Future[void] {.apprtl, gcsafe, async: (raises: []).}
proc documentLoad*(self: Document, filename: string = "", temp: bool = false) {.apprtl, gcsafe, raises: [].}

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

when implModule:
  method `$`*(document: Document): string {.base, gcsafe, raises: [].} = return ""
  method save*(self: Document, filename: string = "", app: bool = false): Future[void] {.base, gcsafe, async: (raises: []).} = return
  method load*(self: Document, filename: string = "", temp: bool = false) {.base, gcsafe, raises: [].} = discard
  method deinit*(self: Document) {.base, gcsafe, raises: [].} = discard
  method getStatisticsString*(self: Document): string {.base, gcsafe, raises: [].} = discard

  proc normalizedPath*(self: Document): string {.gcsafe, raises: [].} =
    return self.vfs.normalize(self.filename)

  proc documentLocalizedPath*(self: Document): string {.gcsafe, raises: [].} = self.vfs.localize(self.filename)

  proc documentSave*(self: Document, filename: string = ""): Future[void] {.async: (raises: []).} = await self.save(filename)
  proc documentLoad*(self: Document, filename: string = "", temp: bool = false) = self.load(filename, temp)

else:
  proc save*(self: Document, filename: string = ""): Future[void] {.async: (raises: []).} = await documentSave(self, filename)
  proc load*(self: Document, filename: string = "", temp: bool = false) = documentLoad(self, filename, temp)
