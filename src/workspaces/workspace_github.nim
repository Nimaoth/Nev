import std/[os, tables, json, uri, base64, strutils, options]
import workspace, custom_async, custom_logger, async_http_client, platform/filesystem

type
  WorkspaceFolderGithub* = ref object of WorkspaceFolder
    baseUrl: string
    user*: string
    repository*: string
    branchOrHash*: string

    cachedDirectoryListings: Table[string, DirectoryListing]
    pathToSha: Table[string, string]

proc getAccessToken(): Option[string] =
  let token = fs.loadApplicationFile("GithubAccessToken")
  if token.len > 0:
    return token.some
  return string.none

method isReadOnly*(self: WorkspaceFolderGithub): bool = true

method loadFile*(self: WorkspaceFolderGithub, relativePath: string): Future[string] {.async.} =
  let relativePath = if relativePath.startsWith("./"): relativePath[2..^1] else: relativePath
  let url = self.baseUrl & "/contents/" & relativePath & "?ref=" & self.branchOrHash
  logger.log(lvlInfo, fmt"[github] loadFile '{url}'")

  let token = getAccessToken()
  let response = await httpGet(url, token)

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

proc parseDirectoryListing(self: WorkspaceFolderGithub, basePath: string, jsn: JsonNode): DirectoryListing =
  if jsn.hasKey("tree") and jsn["tree"].kind == JArray:
    let tree = jsn["tree"]
    for item in tree.items:
      if item.kind != JObject:
        continue

      let path = item["path"].getStr ""
      let typ = item["type"].getStr ""
      let url = item["url"].getStr ""
      let sha = item["sha"].getStr ""

      self.pathToSha[basePath / path] = sha

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

  let token = getAccessToken()

  let url = if relativePath.len == 0 or relativePath == ".":
    self.baseUrl & "/git/trees/" & self.branchOrHash
  elif self.pathToSha.contains(relativePath):
    self.baseUrl & "/git/trees/" & self.pathToSha[relativePath]
  else:
    logger.log(lvlError, fmt"[github] Failed to get directory listing for '{relativePath}'")
    return DirectoryListing()

  let response = await httpGet(url, token)

  try:
    let jsn = parseJson(response)
    # debugf"response: {jsn.pretty}"
    let listing = self.parseDirectoryListing(relativePath, jsn)
    self.cachedDirectoryListings[relativePath] = listing
    return listing

  except:
    logger.log(lvlError, fmt"Failed to parse github response: {response}")

  return DirectoryListing()

proc newWorkspaceFolderGithub*(user, repository, branchOrHash: string): WorkspaceFolderGithub =
  new result

  result.baseUrl = fmt"https://api.github.com/repos/{user}/{repository}"
  debugf"Opening new github workspace folder at {result.baseUrl}"

  result.user = user
  result.repository = repository
  result.branchOrHash = branchOrHash
  result.cachedDirectoryListings = initTable[string, DirectoryListing]()
  result.pathToSha = initTable[string, string]()