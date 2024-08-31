import std/[tables, json, options, strutils, os]
import misc/[custom_async, custom_logger, async_http_client, array_buffer, myjsonutils, timer, event]
import workspace, platform/filesystem

logCategory "ws-remote"

type
  DirectoryListingWrapper = object
    done: bool
    listing: DirectoryListing

  WorkspaceRemote* = ref object of Workspace
    baseUrl*: string
    cachedDirectoryListings: Table[string, DirectoryListingWrapper]
    cachedRelativePaths: Table[string, Option[string]]
    isCacheUpdateInProgress: bool = false
    cachedInfo: Option[WorkspaceInfo]

proc recomputeFileCacheAsync(self: WorkspaceRemote): Future[void] {.async.} =
  if self.isCacheUpdateInProgress:
    return
  self.isCacheUpdateInProgress = true
  defer:
    self.isCacheUpdateInProgress = false

  log lvlInfo, "[recomputeFileCacheAsync] Start"
  let t = startTimer()
  let res = await self.getDirectoryListingRec("")
  log lvlInfo, fmt"[recomputeFileCacheAsync] Finished in {t.elapsed.ms}ms"

  self.cachedFiles = res
  self.onCachedFilesUpdated.invoke()

method recomputeFileCache*(self: WorkspaceRemote) =
  asyncCheck self.recomputeFileCacheAsync()

method isReadOnly*(self: WorkspaceRemote): bool = false
method settings*(self: WorkspaceRemote): JsonNode =
  result = newJObject()
  result["baseUrl"] = newJString(self.baseUrl)

method clearDirectoryCache*(self: WorkspaceRemote) =
  self.cachedDirectoryListings.clear()

proc getWorkspaceInfo(self: WorkspaceRemote): Future[WorkspaceInfo] {.async.} =
  let localFolderFut = httpGet(self.baseUrl & "/info/name")
  let workspaceFoldersFut = httpGet(self.baseUrl & "/info/workspace-folders")

  let localFolder = localFolderFut.await
  let name = fmt"Remote:{self.baseUrl}/{localFolder}"

  let workspaceFolders = workspaceFoldersFut.await.parseJson
  let folders = workspaceFolders.jsonTo(typeof(WorkspaceInfo().folders))

  return WorkspaceInfo(name: name, folders: folders)

proc updateWorkspaceName(self: WorkspaceRemote): Future[void] {.async.} =
  try:
    self.info = self.getWorkspaceInfo()
    self.info.thenIt:
      self.name = it.name
      self.cachedInfo = it.some
      log lvlInfo, fmt"Remote workspace updated. Name: '{it.name}', Folders: {it.folders}"
  except:
    log lvlError, &"Failed to update workspace info: {getCurrentExceptionMsg()}:\n{getCurrentException().getStackTrace()}"

method loadFile*(self: WorkspaceRemote, relativePath: string): Future[string] {.async.} =
  let relativePath = relativePath.normalizePathUnix

  let url = self.baseUrl & "/contents/" & relativePath
  log(lvlInfo, fmt"loadFile '{url}'")

  return await httpGet(url)

method loadFile*(self: WorkspaceRemote, relativePath: string, data: ptr string): Future[void] {.async.} =
  data[] = await self.loadFile(relativePath)

method saveFile*(self: WorkspaceRemote, relativePath: string, content: string): Future[void] {.async.} =
  let relativePath = relativePath.normalizePathUnix

  let url = self.baseUrl & "/contents/" & relativePath
  log(lvlInfo, fmt"saveFile '{url}'")

  discard httpPost(url, content).await

method saveFile*(self: WorkspaceRemote, relativePath: string, content: ArrayBuffer): Future[void] {.async.} =
  let relativePath = relativePath.normalizePathUnix

  let url = self.baseUrl & "/contents/" & relativePath
  log(lvlInfo, fmt"saveFileBinary '{url}'")

  discard httpPost(url, content).await

proc parseDirectoryListing(self: WorkspaceRemote, basePath: string, jsn: JsonNode): DirectoryListing =
  if jsn.hasKey("files") and jsn["files"].kind == JArray:
    let files = jsn["files"]
    for item in files.items:
      result.files.add item.getStr
  if jsn.hasKey("folders") and jsn["folders"].kind == JArray:
    let folders = jsn["folders"]
    for item in folders.items:
      result.folders.add item.getStr

method getDirectoryListing*(self: WorkspaceRemote, relativePath: string): Future[DirectoryListing] {.async.} =
  let relativePath = relativePath.normalizePathUnix
  while self.cachedDirectoryListings.contains(relativePath) and not self.cachedDirectoryListings[relativePath].done:
    await sleepAsync(2)

  if self.cachedDirectoryListings.contains(relativePath):
    return self.cachedDirectoryListings[relativePath].listing

  self.cachedDirectoryListings[relativePath] = DirectoryListingWrapper()

  let url = if relativePath.len == 0 or relativePath == ".":
    self.baseUrl & "/list"
  else:
    self.baseUrl & "/list/" & relativePath

  let response = await httpGet(url)

  try:
    let jsn = parseJson(response)
    let listing = self.parseDirectoryListing(relativePath, jsn)
    self.cachedDirectoryListings[relativePath] = DirectoryListingWrapper(done: true, listing: listing)
    return listing
  except CatchableError:
    log(lvlError, fmt"Failed to parse server response: {response}")

  if self.cachedDirectoryListings.contains(relativePath):
    self.cachedDirectoryListings[relativePath].done = true
    return self.cachedDirectoryListings[relativePath].listing

  return DirectoryListing()

method getRelativePath*(self: WorkspaceRemote, absolutePath: string): Future[Option[string]] {.async.} =
  if not self.cachedRelativePaths.contains(absolutePath):
    let response = await httpGet(self.baseUrl & "/relative-path/" & absolutePath)
    if response == "":
      self.cachedRelativePaths[absolutePath] = string.none
    else:
      self.cachedRelativePaths[absolutePath] = response.some

  return self.cachedRelativePaths[absolutePath]

method getRelativePathSync*(self: WorkspaceRemote, absolutePath: string): Option[string] =
  if not self.cachedInfo.isSome:
    return string.none

  for (path, _) in self.cachedInfo.get.folders:
    if absolutePath.startsWith(path):
      return absolutePath.relativePath(path, '/').normalizePathUnix.some

  return string.none

proc newWorkspaceRemote*(url: string): WorkspaceRemote =
  new result

  result.baseUrl = url

  asyncCheck result.updateWorkspaceName()

proc newWorkspaceRemote*(settings: JsonNode): WorkspaceRemote =
  let url = settings["baseUrl"].getStr
  return newWorkspaceRemote(url)