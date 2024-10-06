import std/[options, os]
import misc/util
import workspaces/[workspace]
import platform/[filesystem]

type Document* = ref object of RootObj
  appFile*: bool                        ## Whether this is an application file (e.g. stored in local storage on the browser)
  isBackedByFile*: bool = false
  filename*: string
  workspace*: Option[Workspace]   ## The workspace this document belongs to
  revision*: int
  undoableRevision*: int
  lastSavedRevision*: int               ## Undobale revision at the time we saved the last time
  fs*: Filesystem

method `$`*(document: Document): string {.base, gcsafe, raises: [].} = return ""
method save*(self: Document, filename: string = "", app: bool = false) {.base, gcsafe, raises: [].} = discard
method load*(self: Document, filename: string = "") {.base, gcsafe, raises: [].} = discard
method deinit*(self: Document) {.base, gcsafe, raises: [].} = discard
method getStatisticsString*(self: Document): string {.base, gcsafe, raises: [].} = discard

proc fullPath*(self: Document): string {.gcsafe, raises: [].} =
  if not self.isBackedByFile:
    return self.filename

  if self.filename.isAbsolute:
    return self.filename
  if self.workspace.getSome(ws):
    return ws.getWorkspacePath() / self.filename
  if self.appFile:
    return self.fs.getApplicationFilePath(self.filename)

  try:
    return self.filename.absolutePath
  except ValueError, OSError:
    return self.filename
