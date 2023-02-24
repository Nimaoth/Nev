import std/[os, tables, json, uri, base64, strutils]
import workspace, custom_async, custom_logger, async_http_client

type
  WorkspaceFolderGithub* = ref object of WorkspaceFolder
    baseUrl: string
    user*: string
    repository*: string
    branchOrHash*: string

    cachedDirectoryListings: Table[string, DirectoryListing]

method isReadOnly*(self: WorkspaceFolderGithub): bool = false

method loadFile*(self: WorkspaceFolderGithub, relativePath: string): Future[string] {.async.} =
  let relativePath = if relativePath.startsWith("./"): relativePath[2..^1] else: relativePath
  let url = self.baseUrl & "/contents/" & relativePath & "?ref=" & self.branchOrHash
  logger.log(lvlInfo, fmt"[github] loadFile '{url}'")
  let response = await httpGet(url)

  try:
    let jsn = parseJson(response)

    if jsn.hasKey("content"):
      let contentBase64 = jsn["content"].getStr
      let content = base64.decode(contentBase64)
      return content

  except:
    logger.log(lvlError, fmt"Failed to parse github response: {response}")

  return ""

method saveFile*(self: WorkspaceFolderGithub, relativePath: string, content: string): Future[void] {.async.} =
  discard

proc parseDirectoryListing*(jsn: JsonNode): DirectoryListing =
  if jsn.hasKey("tree") and jsn["tree"].kind == JArray:
    let tree = jsn["tree"]
    for item in tree.items:
      if item.kind != JObject:
        continue

      let path = item["path"].getStr ""
      let typ = item["type"].getStr ""
      let url = item["url"].getStr ""
      let sha = item["sha"].getStr ""

      case typ
      of "blob":
        result.files.add path
      of "tree":
        result.folders.add path
      else:
        discard


method getDirectoryListing*(self: WorkspaceFolderGithub, relativePath: string): Future[DirectoryListing] {.async.} =
  if self.cachedDirectoryListings.contains(relativePath):
    return self.cachedDirectoryListings[relativePath]

  logger.log(lvlInfo, fmt"[github] getDirectoryListing for {self.baseUrl}")

  if relativePath.len == 0 or relativePath == ".":
    let response = await httpGet(self.baseUrl & "/git/trees/" & self.branchOrHash)

    try:
      let jsn = parseJson(response)
      debugf"response: {jsn.pretty}"
      let listing = jsn.parseDirectoryListing
      self.cachedDirectoryListings[relativePath] = listing
      return listing

    except:
      logger.log(lvlError, fmt"Failed to parse github response: {response}")
  else:
    discard

  return DirectoryListing()

proc newWorkspaceFolderGithub*(user, repository, branchOrHash: string): WorkspaceFolderGithub =
  new result

  result.baseUrl = fmt"https://api.github.com/repos/{user}/{repository}"
  debugf"Opening new github workspace folder at {result.baseUrl}"

  result.user = user
  result.repository = repository
  result.branchOrHash = branchOrHash
  result.cachedDirectoryListings = initTable[string, DirectoryListing]()