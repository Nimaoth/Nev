import std/[os, tables, json, uri, base64, strutils, options]
import workspace, custom_async, custom_logger, async_http_client, platform/filesystem

type
  WorkspaceFolderAbsytreeServer* = ref object of WorkspaceFolder
    baseUrl: string

method isReadOnly*(self: WorkspaceFolderAbsytreeServer): bool = false

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
  let url = if relativePath.len == 0 or relativePath == ".":
    self.baseUrl & "/list"
  else:
    self.baseUrl & "/list/" & relativePath

  let response = await httpGet(url)

  try:
    let jsn = parseJson(response)
    # debugf"response: {jsn.pretty}"
    let listing = self.parseDirectoryListing(relativePath, jsn)
    return listing

  except:
    logger.log(lvlError, fmt"Failed to parse absytree-server response: {response}")

  return DirectoryListing()

proc newWorkspaceFolderAbsytreeServer*(url: string): WorkspaceFolderAbsytreeServer =
  new result

  result.baseUrl = url
  debugf"Opening new absytree-server workspace folder at {result.baseUrl}"
