import std/[json, options, os, strutils]
import misc/[custom_async, id, array_buffer, cancellation_token, util, regex, custom_logger, event]
import platform/filesystem
import vcs/vcs
import vfs

logCategory "workspace"

type
  WorkspaceInfo* = object
    name*: string
    folders*: seq[tuple[path: string, name: Option[string]]]

  Workspace* = ref object of RootObj
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

  VFSWorkspace* = ref object of VFS
    workspace*: Workspace

type WorkspacePath* = distinct string

proc encodePath*(workspace: Workspace, path: string): WorkspacePath =
  return WorkspacePath(fmt"ws://{workspace.id}/{path}")

proc decodePath*(path: WorkspacePath): Option[tuple[id: Id, path: string]] =
  let path = path.string
  if not path.startsWith("ws://"):
    return

  let slashIndex = path.find('/', 5)
  assert slashIndex > 0

  let id = path[5..<slashIndex].parseId
  return (id, path[(slashIndex + 1)..^1]).some

proc ignorePath*(workspace: Workspace, path: string): bool =
  if workspace.ignore.excludePath(path) or workspace.ignore.excludePath(path.extractFilename):
    if workspace.ignore.includePath(path) or workspace.ignore.includePath(path.extractFilename):
      return false

    return true
  return false

method getVcsForFile*(self: Workspace, file: string): Option[VersionControlSystem] {.base.} = discard
method getAllVersionControlSystems*(self: Workspace): seq[VersionControlSystem] {.base.} = discard

method isReadOnly*(self: Workspace): bool {.base.} = true
method settings*(self: Workspace): JsonNode {.base.} = discard

method clearDirectoryCache*(self: Workspace) {.base.} = discard
method recomputeFileCache*(self: Workspace) {.base.} = discard

method setFileReadOnly*(self: Workspace, relativePath: string, readOnly: bool): Future[bool] {.
  base.} = false.toFuture

method isFileReadOnly*(self: Workspace, relativePath: string): Future[bool] {.base.} =
  false.toFuture

method fileExists*(self: Workspace, path: string): Future[bool] {.base.} =
  false.toFuture

method loadFile*(self: Workspace, relativePath: string): Future[string] {.base.} =
  discard

method loadFile*(self: Workspace, relativePath: string, data: ptr string): Future[void] {.base.} =
  discard

method saveFile*(self: Workspace, relativePath: string, content: string): Future[void] {.base.} =
  discard

method saveFile*(self: Workspace, relativePath: string, content: ArrayBuffer):
    Future[void] {.base.} =
  discard

method getWorkspacePath*(self: Workspace): string {.base.} = discard

method getDirectoryListing*(self: Workspace, relativePath: string): Future[DirectoryListing] {.base.} = discard
method searchWorkspace*(self: Workspace, query: string, maxResults: int): Future[seq[SearchResult]] {.base.} = discard

proc getAbsolutePath*(self: Workspace, path: string): string =
  if path.isAbsolute:
    return path.normalizePathUnix
  else:
    (self.getWorkspacePath() / path).normalizePathUnix

proc getRelativePathEmpty(): Future[Option[string]] {.async.} =
  return string.none

method getRelativePath*(self: Workspace, absolutePath: string): Future[Option[string]] {.base.} =
  return getRelativePathEmpty()

method getRelativePathSync*(self: Workspace, absolutePath: string): Option[string] {.base.} =
  return string.none

proc shouldIgnore(folder: Workspace, path: string): bool =
  if folder.ignore.excludePath(path) or folder.ignore.excludePath(path.extractFilename):
    if folder.ignore.includePath(path) or folder.ignore.includePath(path.extractFilename):
      return false

    return true
  return false

proc getDirectoryListingRec*(folder: Workspace, path: string): Future[seq[string]] {.async.} =
  var resultItems: seq[string]

  let items = await folder.getDirectoryListing(path)
  for file in items.files:
    let fullPath = if file.isAbsolute:
      file
    else:
      path // file

    if folder.shouldIgnore(fullPath):
      continue

    resultItems.add(fullPath)

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

proc iterateDirectoryRec*(folder: Workspace, path: string, cancellationToken: CancellationToken, callback: proc(files: seq[string]): Future[void]): Future[void] {.async.} =
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

  await sleepAsync(10)

  await callback(resultItems)

  if cancellationToken.canceled:
    return

  var futs: seq[Future[void]]

  for dir in folders:
    futs.add iterateDirectoryRec(folder, dir, cancellationToken, callback)

  for fut in futs:
    await fut

  return

method name*(self: VFSWorkspace): string = "VFSWorkspace"

method readImpl*(self: VFSWorkspace, path: string): Future[Option[string]] {.async.} =
  debugf"[VFSWorkspace] read({path})"
  return self.workspace.loadFile(path).await.some

method normalizeImpl*(self: VFSWorkspace, path: string): string =
  return self.workspace.getAbsolutePath(path)

var gWorkspace*: Workspace = nil
var gWorkspaceFuture = newResolvableFuture[Workspace]("gWorkspace")

proc getGlobalWorkspace*(): Future[Workspace] = gWorkspaceFuture.future
proc setGlobalWorkspace*(w: Workspace) =
  gWorkspace = w
  gWorkspaceFuture.complete(w)

when not defined(js):
  import workspace_local
  export workspace_local

import workspace_null
export workspace_null

import workspace_github
export workspace_github

import workspace_remote
export workspace_remote
