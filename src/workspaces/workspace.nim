import custom_async

type
  Workspace* = ref object
    folders: seq[WorkspaceFolder]

  WorkspaceFolder* = ref object of RootObj
    name*: string

  DirectoryListing* = object
    files*: seq[string]
    folders*: seq[string]

method isReadOnly*(self: WorkspaceFolder): bool {.base.} = true

method loadFile*(self: WorkspaceFolder, relativePath: string): Future[string] {.base.} = discard
method saveFile*(self: WorkspaceFolder, relativePath: string, content: string): Future[void] {.base.} = discard

method getDirectoryListing*(self: WorkspaceFolder, relativePath: string): Future[DirectoryListing] {.base.} = discard

import workspace_local
export workspace_local