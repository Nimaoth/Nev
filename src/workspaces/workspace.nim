import std/[json, options, os, strutils]
import misc/[custom_async, id, array_buffer, cancellation_token, util, regex, custom_logger, event]
import platform/filesystem

logCategory "workspace"

type
  WorkspaceInfo* = object
    name*: string
    folders*: seq[tuple[path: string, name: Option[string]]]

  Workspace* = ref object
    folders*: seq[WorkspaceFolder]

  WorkspaceFolder* = ref object of RootObj
    name*: string
    info*: Future[WorkspaceInfo]
    id*: Id
    ignore*: Globs
    cachedFiles*: seq[string]
    onCachedFilesUpdated*: Event[void]

  DirectoryListing* = object
    files*: seq[string]
    folders*: seq[string]

  SearchResult* = object
    path*: string
    line*: int
    column*: int
    text*: string

type WorkspacePath* = distinct string

proc encodePath*(workspace: WorkspaceFolder, path: string): WorkspacePath =
  return WorkspacePath(fmt"ws://{workspace.id}/{path}")

proc decodePath*(path: WorkspacePath): Option[tuple[id: Id, path: string]] =
  let path = path.string
  if not path.startsWith("ws://"):
    return

  let slashIndex = path.find('/', 5)
  assert slashIndex > 0

  let id = path[5..<slashIndex].parseId
  return (id, path[(slashIndex + 1)..^1]).some

proc ignorePath*(workspace: WorkspaceFolder, path: string): bool =
  if workspace.ignore.excludePath(path) or workspace.ignore.excludePath(path.extractFilename):
    if workspace.ignore.includePath(path) or workspace.ignore.includePath(path.extractFilename):
      return false

    return true
  return false

method isReadOnly*(self: WorkspaceFolder): bool {.base.} = true
method settings*(self: WorkspaceFolder): JsonNode {.base.} = discard

method clearDirectoryCache*(self: WorkspaceFolder) {.base.} = discard
method recomputeFileCache*(self: WorkspaceFolder) {.base.} = discard

method loadFile*(self: WorkspaceFolder, relativePath: string): Future[string] {.base.} = discard
method saveFile*(self: WorkspaceFolder, relativePath: string, content: string): Future[void] {.base.} = discard
method saveFile*(self: WorkspaceFolder, relativePath: string, content: ArrayBuffer): Future[void] {.base.} = discard
method getWorkspacePath*(self: WorkspaceFolder): string {.base.} = discard
proc getAbsolutePath*(self: WorkspaceFolder, path: string): string =
  if path.isAbsolute:
    return path.normalizePathUnix
  else:
    (self.getWorkspacePath() / path).normalizePathUnix

method getDirectoryListing*(self: WorkspaceFolder, relativePath: string): Future[DirectoryListing] {.base.} = discard
method searchWorkspace*(self: WorkspaceFolder, query: string, maxResults: int): Future[seq[SearchResult]] {.base.} = discard

proc getRelativePathEmpty(): Future[Option[string]] {.async.} =
  return string.none

method getRelativePath*(self: WorkspaceFolder, absolutePath: string): Future[Option[string]] {.base.} =
  return getRelativePathEmpty()

method getRelativePathSync*(self: WorkspaceFolder, absolutePath: string): Option[string] {.base.} =
  return string.none

when not defined(js):
  import workspace_local
  export workspace_local

import workspace_github
export workspace_github

import workspace_absytree_server
export workspace_absytree_server

proc shouldIgnore(folder: WorkspaceFolder, path: string): bool =
  if folder.ignore.excludePath(path) or folder.ignore.excludePath(path.extractFilename):
    if folder.ignore.includePath(path) or folder.ignore.includePath(path.extractFilename):
      return false

    return true
  return false

proc getDirectoryListingRec*(folder: WorkspaceFolder, path: string): Future[seq[string]] {.async.} =
  var resultItems: seq[string]

  let items = await folder.getDirectoryListing(path)
  for file in items.files:
    let fullPath = if file.isAbsolute:
      file
    else:
      path // file

    if folder.shouldIgnore(fullPath):
      continue

    resultItems.add(file)

  var futs: seq[Future[seq[string]]]

  for dir in items.folders:
    let fullPath = if dir.isAbsolute:
      dir
    else:
      path // dir

    if folder.shouldIgnore(fullPath):
      continue

    futs.add getDirectoryListingRec(folder, fullPath)

  for fut in futs:
    let children = await fut
    resultItems.add children

  return resultItems

proc iterateDirectoryRec*(folder: WorkspaceFolder, path: string, cancellationToken: CancellationToken, callback: proc(files: seq[string]): Future[void]): Future[void] {.async.} =
  let path = path
  var resultItems: seq[string]
  var folders: seq[string]

  if cancellationToken.canceled:
    return

  let items = await folder.getDirectoryListing(path)

  if cancellationToken.canceled:
    return

  for file in items.files:
    let fullPath = if file.isAbsolute:
      file
    else:
      path // file
    if folder.shouldIgnore(fullPath):
      continue
    resultItems.add(fullPath)

  for dir in items.folders:
    let fullPath = if dir.isAbsolute:
      dir
    else:
      path // dir
    if folder.shouldIgnore(fullPath):
      continue
    folders.add(fullPath)

  await sleepAsync(1)

  await callback(resultItems)

  if cancellationToken.canceled:
    return

  var futs: seq[Future[void]]

  for dir in folders:
    futs.add iterateDirectoryRec(folder, dir, cancellationToken, callback)

  for fut in futs:
    await fut

  return
