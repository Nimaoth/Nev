import std/[os, json, options]
import misc/[custom_async, custom_logger]
import workspace

logCategory "ws-local"

type
  WorkspaceFolderLocal* = ref object of WorkspaceFolder
    path*: string

method settings*(self: WorkspaceFolderLocal): JsonNode =
  result = newJObject()
  result["path"] = newJString(self.path.absolutePath)

proc getAbsolutePath(self: WorkspaceFolderLocal, relativePath: string): string =
  if relativePath.isAbsolute:
    relativePath
  else:
    self.path.absolutePath / relativePath

method isReadOnly*(self: WorkspaceFolderLocal): bool = false

method getWorkspacePath*(self: WorkspaceFolderLocal): string = self.path.absolutePath

method loadFile*(self: WorkspaceFolderLocal, relativePath: string): Future[string] {.async.} =
  return readFile(self.getAbsolutePath(relativePath))

method saveFile*(self: WorkspaceFolderLocal, relativePath: string, content: string): Future[void] {.async.} =
  writeFile(self.getAbsolutePath(relativePath), content)

method getDirectoryListing*(self: WorkspaceFolderLocal, relativePath: string): Future[DirectoryListing] {.async.} =
  when not defined(js):
    var res = DirectoryListing()
    for (kind, file) in walkDir(self.getAbsolutePath(relativePath), relative=true):
      case kind
      of pcFile:
        res.files.add file
      of pcDir:
        res.folders.add file
      else:
        log lvlError, fmt"getDirectoryListing: Unhandled file type {kind} for {file}"
    return res

proc createInfo(path: string): Future[WorkspaceInfo] {.async.} =
  return WorkspaceInfo(name: path, folders: @[(path.absolutePath, path.some)])

proc newWorkspaceFolderLocal*(path: string): WorkspaceFolderLocal =
  new result
  result.path = path
  result.name = fmt"Local:{path.absolutePath}"
  result.info = createInfo(path)

proc newWorkspaceFolderLocal*(settings: JsonNode): WorkspaceFolderLocal =
  let path = settings["path"].getStr
  return newWorkspaceFolderLocal(path)