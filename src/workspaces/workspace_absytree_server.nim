import std/[os, tables, json, uri, base64, strutils, options]
import workspace, custom_async, custom_logger, async_http_client, platform/filesystem

type
  WorkspaceFolderAbsytreeServer* = ref object of WorkspaceFolder
    baseUrl*: string
    cachedDirectoryListings: Table[string, DirectoryListing]

method isReadOnly*(self: WorkspaceFolderAbsytreeServer): bool = false
method settings*(self: WorkspaceFolderAbsytreeServer): JsonNode =
  result = newJObject()
  result["baseUrl"] = newJString(self.baseUrl)

method clearDirectoryCache*(self: WorkspaceFolderAbsytreeServer) =
  self.cachedDirectoryListings.clear()

method updateWorkspaceName*(self: WorkspaceFolderAbsytreeServer): Future[void] {.async.} =
  let url = self.baseUrl & "/info/name"
  let localFolder = await httpGet(url)
  self.name = fmt"AbsytreeServer:{self.baseUrl}/{localFolder}"

method loadFile*(self: WorkspaceFolderAbsytreeServer, relativePath: string): Future[string] {.async.} =
  let relativePath = if relativePath.startsWith("./"): relativePath[2..^1] else: relativePath

  let url = self.baseUrl & "/contents/" & relativePath
  logger.log(lvlInfo, fmt"[absytree-server] loadFile '{url}'")

  return await httpGet(url)

method saveFile*(self: WorkspaceFolderAbsytreeServer, relativePath: string, content: string): Future[void] {.async.} =
  let relativePath = if relativePath.startsWith("./"): relativePath[2..^1] else: relativePath

  let url = self.baseUrl & "/contents/" & relativePath
  logger.log(lvlInfo, fmt"[absytree-server] saveFile '{url}'")

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
  if self.cachedDirectoryListings.contains(relativePath):
    return self.cachedDirectoryListings[relativePath]

  let url = if relativePath.len == 0 or relativePath == ".":
    self.baseUrl & "/list"
  else:
    self.baseUrl & "/list/" & relativePath

  let response = await httpGet(url)

  try:
    let jsn = parseJson(response)
    let listing = self.parseDirectoryListing(relativePath, jsn)
    self.cachedDirectoryListings[relativePath] = listing
    return listing

  except:
    logger.log(lvlError, fmt"Failed to parse absytree-server response: {response}")

  return DirectoryListing()

proc newWorkspaceFolderAbsytreeServer*(url: string): WorkspaceFolderAbsytreeServer =
  new result

  result.baseUrl = url

  asyncCheck result.updateWorkspaceName()

proc newWorkspaceFolderAbsytreeServer*(settings: JsonNode): WorkspaceFolderAbsytreeServer =
  let url = settings["baseUrl"].getStr
  return newWorkspaceFolderAbsytreeServer(url)