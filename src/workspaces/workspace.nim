import std/[json, options, os, strutils, sequtils]
import misc/[custom_async, id, util, regex, custom_logger, event, timer, async_process]
import vfs, vfs_service, service, compilation_config

{.push gcsafe.}
{.push raises: [].}

logCategory "workspace"

type
  WorkspaceInfo* = object
    name*: string
    folders*: seq[tuple[path: string, name: Option[string]]]

  Workspace* = ref object
    name*: string
    path*: string
    additionalPaths*: seq[string]
    info*: Future[WorkspaceInfo]
    id*: Id
    ignore*: Globs
    cachedFiles*: seq[string]
    onCachedFilesUpdated*: Event[void]
    isCacheUpdateInProgress: bool = false
    vfs*: VFS

  DirectoryListing* = object
    files*: seq[string]
    folders*: seq[string]

  SearchResult* = object
    path*: string
    line*: int
    column*: int
    text*: string

  WorkspacePath* = distinct string

  WorkspaceService* = ref object of Service
    workspace*: Workspace
    vfs*: VFS

func serviceName*(_: typedesc[WorkspaceService]): string = "WorkspaceService"

addBuiltinService(WorkspaceService, VFSService)

method init*(self: WorkspaceService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"WorkspaceService.init"
  self.vfs = self.services.getService(VFSService).get.vfs
  return ok()

proc ignorePath*(workspace: Workspace, path: string): bool =
  if workspace.ignore.excludePath(path) or workspace.ignore.excludePath(path.extractFilename):
    if workspace.ignore.includePath(path) or workspace.ignore.includePath(path.extractFilename):
      return false

    return true
  return false

proc ignorePath*(ignore: Globs, path: string): bool =
  if ignore.excludePath(path) or ignore.excludePath(path.extractFilename):
    if ignore.includePath(path) or ignore.includePath(path.extractFilename):
      return false

    return true
  return false

proc settings*(self: Workspace): JsonNode =
  try:
    result = newJObject()
    result["path"] = newJString(self.path.absolutePath)
    result["additionalPaths"] = %self.additionalPaths
  except ValueError, OSError:
    discard

proc clearDirectoryCache*(self: Workspace) = discard

proc collectFiles(dir: string, ignore: Globs, files: var seq[string]) =
  if ignore.ignorePath(dir):
    return

  try:
    for (kind, path) in walkDir(dir, relative=false):
      let pathNorm = path.normalizePathUnix
      case kind
      of pcFile:
        if ignore.ignorePath(pathNorm):
          continue

        files.add pathNorm
      of pcDir:
        collectFiles(pathNorm, ignore, files)
      else:
        discard

  except OSError:
    discard

proc collectFilesThread(args: tuple[roots: seq[string], ignore: Globs]):
    tuple[files: seq[string], time: float] =
  try:
    let t = startTimer()

    for path in args.roots:
      collectFiles(path.normalizePathUnix, args.ignore, result.files)

    result.time = t.elapsed.ms
  except:
    discard

proc recomputeFileCacheAsync(self: Workspace): Future[void] {.async.} =
  if self.isCacheUpdateInProgress:
    return
  self.isCacheUpdateInProgress = true
  defer:
    self.isCacheUpdateInProgress = false

  log lvlInfo, "[recomputeFileCacheAsync] Start"
  let args = (@[self.path] & self.additionalPaths, self.ignore)
  try:
    let res = spawnAsync(collectFilesThread, args).await
    log lvlInfo, fmt"[recomputeFileCacheAsync] Found {res.files.len} files in {res.time}ms"

    self.cachedFiles = res.files
    self.onCachedFilesUpdated.invoke()
  except CancelledError:
    discard

proc recomputeFileCache*(self: Workspace) =
  asyncSpawn self.recomputeFileCacheAsync()

proc getWorkspacePath*(self: Workspace): string =
  try:
    self.path.absolutePath
  except ValueError, OSError:
    return ""

proc searchWorkspaceFolder(self: Workspace, query: string, root: string, maxResults: int):
    Future[seq[SearchResult]] {.async.} =
  let output = runProcessAsync("rg", @["--line-number", "--column", "--heading", query, root],
    maxLines=maxResults).await
  var res: seq[SearchResult]

  var currentFile = ""
  for line in output:
    if currentFile == "":
      if line.isAbsolute:
        currentFile = line.normalizePathUnix
      else:
        currentFile = root // line
      continue

    if line == "":
      currentFile = ""
      continue

    var separatorIndex1 = line.find(':')
    if separatorIndex1 == -1:
      continue

    let lineNumber = line[0..<separatorIndex1].parseInt.catch(0)

    let separatorIndex2 = line.find(':', separatorIndex1 + 1)
    if separatorIndex2 == -1:
      continue

    let column = line[(separatorIndex1 + 1)..<separatorIndex2].parseInt.catch(0)
    let text = line[(separatorIndex2 + 1)..^1]
    res.add SearchResult(path: currentFile, line: lineNumber, column: column, text: text)

    if res.len == maxResults:
      break

  return res

proc searchWorkspace*(self: Workspace, query: string, maxResults: int): Future[seq[SearchResult]] {.async.} =
  var futs: seq[Future[seq[SearchResult]]]
  futs.add self.searchWorkspaceFolder(query, self.path, maxResults)
  for path in self.additionalPaths:
    futs.add self.searchWorkspaceFolder(query, path, maxResults)

  var res: seq[SearchResult]
  for fut in futs:
    res.add fut.await

    if res.len >= maxResults:
      break

  return res

proc getAbsolutePath*(self: Workspace, path: string): string =
  if path.isAbsolute:
    return path.normalizePathUnix
  else:
    (self.getWorkspacePath() / path).normalizePathUnix

proc getRelativePathSync*(self: Workspace, absolutePath: string): Option[string] =
  try:
    if absolutePath.startsWith(self.path):
      return absolutePath.relativePath(self.path, '/').normalizePathUnix.some

    for path in self.additionalPaths:
      if absolutePath.startsWith(path):
        return absolutePath.relativePath(path, '/').normalizePathUnix.some

    return string.none
  except:
    return string.none

proc getRelativePath*(self: Workspace, absolutePath: string): Future[Option[string]] {.async.} =
  return self.getRelativePathSync(absolutePath)

{.pop.} # raises: []
{.pop.} # gcsafe

proc loadIgnoreFile(self: Workspace, path: string): Option[Globs] =
  try:
    let globLines = readFile(self.getAbsolutePath(path))
    return globLines.parseGlobs.some
  except:
    return Globs.none

proc loadDefaultIgnoreFile(self: Workspace) =
  if self.loadIgnoreFile(&".{appName}-ignore").getSome(ignore):
    self.ignore = ignore
    log lvlInfo, &"Using ignore file '.{appName}-ignore' for workpace {self.name}"
  elif self.loadIgnoreFile(".gitignore").getSome(ignore):
    self.ignore = ignore
    log lvlInfo, &"Using ignore file '.gitignore' for workpace {self.name}"
  else:
    log lvlInfo, &"No ignore file for workpace {self.name}"

proc createInfo(path: string, additionalPaths: seq[string]): Future[WorkspaceInfo] {.async.} =
  let additionalPaths = additionalPaths.mapIt((it.absolutePath, it.some))
  return WorkspaceInfo(name: path, folders: @[(path.absolutePath, path.some)] & additionalPaths)

proc newWorkspace*(path: string, additionalPaths: seq[string] = @[]): Workspace =
  new result
  result.path = path # path.absolutePath.catch(path).normalizePathUnix
  result.name = fmt"Local:{result.path}"
  result.additionalPaths = additionalPaths # additionalPaths.mapIt(it.absolutePath.catch(path).normalizePathUnix)
  result.info = createInfo(path, result.additionalPaths)

  result.loadDefaultIgnoreFile()

  result.recomputeFileCache()

proc newWorkspace*(settings: JsonNode): Workspace =
  try:
    let path = settings["path"].getStr
    let additionalPaths = settings["additionalPaths"].elems.mapIt(it.getStr)
    return newWorkspace(path, additionalPaths)
  except:
    return nil

