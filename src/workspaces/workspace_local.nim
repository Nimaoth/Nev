import std/[os, json]
import workspace, custom_async, custom_logger

type
  WorkspaceFolderLocal* = ref object of WorkspaceFolder
    path*: string

method settings*(self: WorkspaceFolderLocal): JsonNode =
  result = newJObject()
  result["path"] = newJString(self.path)

func getAbsolutePath(self: WorkspaceFolderLocal, relativePath: string): string = self.path / relativePath

method isReadOnly*(self: WorkspaceFolderLocal): bool = false

method loadFile*(self: WorkspaceFolderLocal, relativePath: string): Future[string] {.async.} =
  return readFile(self.getAbsolutePath(relativePath))

method saveFile*(self: WorkspaceFolderLocal, relativePath: string, content: string): Future[void] {.async.} =
  writeFile(self.getAbsolutePath(relativePath), content)

method getDirectoryListing*(self: WorkspaceFolderLocal, relativePath: string): Future[DirectoryListing] {.async.} =
  when not defined(js):
    for file in walkDirRec(".", relative=true):
      if file.fileExists:
        result.files.add file
      else:
        result.folders.add file

proc newWorkspaceFolderLocal*(path: string): WorkspaceFolderLocal =
  new result
  result.path = path
  result.name = fmt"Local:{path.absolutePath}"

proc newWorkspaceFolderLocal*(settings: JsonNode): WorkspaceFolderLocal =
  let path = settings["path"].getStr
  return newWorkspaceFolderLocal(path)