import std/[tables, json, options]
import misc/[custom_async, custom_logger, async_http_client, array_buffer]
import workspace, platform/filesystem

logCategory "ws-absytree-server"

type
  DirectoryListingWrapper = object
    done: bool
    listing: DirectoryListing

  WorkspaceFolderAbsytreeServer* = ref object of WorkspaceFolder
    baseUrl*: string
    cachedDirectoryListings: Table[string, DirectoryListingWrapper]
    cachedRelativePaths: Table[string, Option[string]]

method isReadOnly*(self: WorkspaceFolderAbsytreeServer): bool = false
method settings*(self: WorkspaceFolderAbsytreeServer): JsonNode =
  result = newJObject()
  result["baseUrl"] = newJString(self.baseUrl)

method clearDirectoryCache*(self: WorkspaceFolderAbsytreeServer) =
  self.cachedDirectoryListings.clear()

proc updateWorkspaceName(self: WorkspaceFolderAbsytreeServer): Future[void] {.async.} =
  let url = self.baseUrl & "/info/name"
  let localFolder = await httpGet(url)
  self.name = fmt"AbsytreeServer:{self.baseUrl}/{localFolder}"

method loadFile*(self: WorkspaceFolderAbsytreeServer, relativePath: string): Future[string] {.async.} =
  let relativePath = relativePath.normalizePathUnix

  let url = self.baseUrl & "/contents/" & relativePath
  log(lvlInfo, fmt"loadFile '{url}'")

  return await httpGet(url)

method saveFile*(self: WorkspaceFolderAbsytreeServer, relativePath: string, content: string): Future[void] {.async.} =
  let relativePath = relativePath.normalizePathUnix

  let url = self.baseUrl & "/contents/" & relativePath
  log(lvlInfo, fmt"saveFile '{url}'")

  await httpPost(url, content)

method saveFile*(self: WorkspaceFolderAbsytreeServer, relativePath: string, content: ArrayBuffer): Future[void] {.async.} =
  let relativePath = relativePath.normalizePathUnix

  let url = self.baseUrl & "/contents/" & relativePath
  log(lvlInfo, fmt"saveFileBinary '{url}'")

  await httpPost(url, content)

proc parseDirectoryListing(self: WorkspaceFolderAbsytreeServer, basePath: string, jsn: JsonNode): DirectoryListing =
  if jsn.hasKey("files") and jsn["files"].kind == JArray:
    let files = jsn["files"]
    for item in files.items:
      result.files.add item.getStr
  if jsn.hasKey("folders") and jsn["folders"].kind == JArray:
    let folders = jsn["folders"]
    for item in folders.items:
      result.folders.add item.getStr

method getDirectoryListing*(self: WorkspaceFolderAbsytreeServer, relativePath: string): Future[DirectoryListing] {.async.} =
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
    log(lvlError, fmt"Failed to parse absytree-server response: {response}")

  if self.cachedDirectoryListings.contains(relativePath):
    self.cachedDirectoryListings[relativePath].done = true
    return self.cachedDirectoryListings[relativePath].listing

  return DirectoryListing()

method getRelativePath*(self: WorkspaceFolderAbsytreeServer, absolutePath: string): Future[Option[string]] {.async.} =
  if not self.cachedRelativePaths.contains(absolutePath):
    let response = await httpGet(self.baseUrl & "/relative-path/" & absolutePath)
    if response == "":
      self.cachedRelativePaths[absolutePath] = string.none
    else:
      self.cachedRelativePaths[absolutePath] = response.some

  return self.cachedRelativePaths[absolutePath]

proc newWorkspaceFolderAbsytreeServer*(url: string): WorkspaceFolderAbsytreeServer =
  new result

  result.baseUrl = url

  asyncCheck result.updateWorkspaceName()

proc newWorkspaceFolderAbsytreeServer*(settings: JsonNode): WorkspaceFolderAbsytreeServer =
  let url = settings["baseUrl"].getStr
  return newWorkspaceFolderAbsytreeServer(url)