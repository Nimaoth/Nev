import std/[json, options, os]
import misc/[custom_async, id, array_buffer, cancellation_token, util, regex]
import platform/filesystem

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

  DirectoryListing* = object
    files*: seq[string]
    folders*: seq[string]

  SearchResult* = object
    path*: string
    line*: int
    column*: int
    text*: string

method isReadOnly*(self: WorkspaceFolder): bool {.base.} = true
method settings*(self: WorkspaceFolder): JsonNode {.base.} = discard

method clearDirectoryCache*(self: WorkspaceFolder) {.base.} = discard

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
method searchWorkspace*(self: WorkspaceFolder, query: string): Future[seq[SearchResult]] {.base.} = discard

proc getRelativePathEmpty(): Future[Option[string]] {.async.} =
  return string.none

method getRelativePath*(self: WorkspaceFolder, absolutePath: string): Future[Option[string]] {.base.} =
  return getRelativePathEmpty()

when not defined(js):
  import workspace_local
  export workspace_local

import workspace_github
export workspace_github

import workspace_absytree_server
export workspace_absytree_server

proc getDirectoryListingRec*(folder: WorkspaceFolder, path: string): Future[seq[string]] {.async.} =
  var resultItems: seq[string]

  let items = await folder.getDirectoryListing(path)
  for file in items.files:
    resultItems.add(path / file)

  var futs: seq[Future[seq[string]]]

  for dir in items.folders:
    futs.add getDirectoryListingRec(folder, path / dir)

  for fut in futs:
    let children = await fut
    resultItems.add children

  return resultItems


proc shouldIgnore(ignore: seq[Regex], path: string): bool =
  for pattern in ignore:
    if path.contains(pattern):
      return true
  return false

proc iterateDirectoryRec*(folder: WorkspaceFolder, path: string, cancellationToken: CancellationToken, ignore: seq[Regex], callback: proc(files: seq[string]): Future[void]): Future[void] {.async.} =
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
    if ignore.shouldIgnore(fullPath) or ignore.shouldIgnore(fullPath.extractFilename):
      continue
    resultItems.add(fullPath)

  for dir in items.folders:
    let fullPath = if dir.isAbsolute:
      dir
    else:
      path // dir
    if ignore.shouldIgnore(fullPath) or ignore.shouldIgnore(fullPath.extractFilename):
      continue
    folders.add(fullPath)

  await sleepAsync(1)

  await callback(resultItems)

  if cancellationToken.canceled:
    return

  var futs: seq[Future[void]]

  for dir in folders:
    futs.add iterateDirectoryRec(folder, dir, cancellationToken, ignore, callback)

  for fut in futs:
    await fut

  return
