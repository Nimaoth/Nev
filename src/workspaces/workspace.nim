import std/[json]
import custom_async, id

type
  Workspace* = ref object
    folders*: seq[WorkspaceFolder]

  WorkspaceFolder* = ref object of RootObj
    name*: string
    id*: Id

  DirectoryListing* = object
    files*: seq[string]
    folders*: seq[string]

method isReadOnly*(self: WorkspaceFolder): bool {.base.} = true
method settings*(self: WorkspaceFolder): JsonNode {.base.} = discard

method clearDirectoryCache*(self: WorkspaceFolder) {.base.} = discard

method loadFile*(self: WorkspaceFolder, relativePath: string): Future[string] {.base.} = discard
method saveFile*(self: WorkspaceFolder, relativePath: string, content: string): Future[void] {.base.} = discard

method getDirectoryListing*(self: WorkspaceFolder, relativePath: string): Future[DirectoryListing] {.base.} = discard

import workspace_local
export workspace_local

import workspace_github
export workspace_github

import workspace_absytree_server
export workspace_absytree_server