import misc/util
import vfs

type Document* = ref object of RootObj
  appFile*: bool                        ## Whether this is an application file (e.g. stored in local storage on the browser)
  isBackedByFile*: bool = false
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
  if self.vfs.isNotNil:
    return self.vfs.normalize(self.filename)
  return self.filename
