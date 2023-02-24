import std/[os]
import workspace, custom_async

type
  WorkspaceFolderLocal* = ref object of WorkspaceFolder
    path*: string

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
