import std/[json, options]
import misc/[custom_async, custom_logger, util]
import platform/filesystem
import workspace

logCategory "ws-null"

type
  WorkspaceFolderNull* = ref object of Workspace

method settings*(self: WorkspaceFolderNull): JsonNode =
  result = newJObject()

method getRelativePathSync*(self: WorkspaceFolderNull, absolutePath: string): Option[string] =
  return string.none

method getRelativePath*(self: WorkspaceFolderNull, absolutePath: string):
    Future[Option[string]] {.async.} =
  return string.none

method isReadOnly*(self: WorkspaceFolderNull): bool = false

method getWorkspacePath*(self: WorkspaceFolderNull): string = "/"

method setFileReadOnly*(self: WorkspaceFolderNull, relativePath: string, readOnly: bool):
    Future[bool] {.async.} =
  return false

method isFileReadOnly*(self: WorkspaceFolderNull, relativePath: string): Future[bool] {.async.} =
  return false

method fileExists*(self: WorkspaceFolderNull, path: string): Future[bool] {.async.} =
  return false

method loadFile*(self: WorkspaceFolderNull, relativePath: string): Future[string] {.async.} =
  return ""

method loadFile*(self: WorkspaceFolderNull, relativePath: string, data: ptr string):
    Future[void] {.async.} =
  data[] = ""

method saveFile*(self: WorkspaceFolderNull, relativePath: string, content: string):
    Future[void] {.async.} =
  discard

method getDirectoryListing*(self: WorkspaceFolderNull, relativePath: string):
    Future[DirectoryListing] {.async.} =
  return DirectoryListing()

method searchWorkspace*(self: WorkspaceFolderNull, query: string, maxResults: int):
    Future[seq[SearchResult]] {.async.} =
  return @[]

proc createInfo(): Future[WorkspaceInfo] {.async.} =
  return WorkspaceInfo(name: "Null")

proc newWorkspaceFolderNull*(): WorkspaceFolderNull =
  new result
  result.name = fmt"NullWorkspace"
  result.info = createInfo()

proc newWorkspaceFolderNull*(settings: JsonNode): WorkspaceFolderNull =
  return newWorkspaceFolderNull()
