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

  DirectoryListing* = object
    files*: seq[string]
    folders*: seq[string]

  SearchResult* = object
    path*: string
    line*: int
    column*: int
    text*: string

  Workspace* = ref object of Service
    name*: string
    path*: string
    additionalPaths*: seq[string]
    id*: Id
    ignore*: Globs
    cachedFiles*: seq[string]
    onCachedFilesUpdated*: Event[void]
    onWorkspaceFolderAdded*: Event[string]
    onWorkspaceFolderRemoved*: Event[string]
    isCacheUpdateInProgress: bool = false
    vfs*: VFS

func serviceName*(_: typedesc[Workspace]): string = "Workspace"

addBuiltinService(Workspace, VFSService)

method init*(self: Workspace): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"Workspace.init"
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
      collectFiles(path, args.ignore, result.files)

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

proc searchWorkspaceFolder(self: Workspace, query: string, root: string, maxResults: int, customArgs: seq[string]):
    Future[seq[SearchResult]] {.async: (raises: []).} =
  try:
    let args = @["--line-number", "--column", "--heading"] & customArgs & @[query, root]
    let output = runProcessAsync("rg", args, maxLines=maxResults).await
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
  except CatchableError:
    return @[]

proc searchWorkspace*(self: Workspace, query: string, maxResults: int, customArgs: seq[string] = @[]): Future[seq[SearchResult]] {.async: (raises: []).} =
  var futs: seq[InternalRaisesFuture[seq[SearchResult], void]]
  futs.add self.searchWorkspaceFolder(query, self.path, maxResults, customArgs)
  for path in self.additionalPaths:
    futs.add self.searchWorkspaceFolder(query, path, maxResults, customArgs)

  var res: seq[SearchResult]
  for fut in futs:
    res.add fut.await

    if res.len >= maxResults:
      break

  return res

proc getAbsolutePath*(self: Workspace, path: string): string =
  if path.isAbsolute:
    return path.normalizeNativePath
  else:
    self.getWorkspacePath() // path

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

proc getRelativePathAndWorkspaceSync*(self: Workspace, absolutePath: string): Option[tuple[root, path: string]] =
  try:
    if absolutePath.startsWith(self.path):
      return ("ws0://", absolutePath.relativePath(self.path, '/').normalizePathUnix).some

    for i, path in self.additionalPaths:
      if absolutePath.startsWith(path):
        return (&"ws{i + 1}://", absolutePath.relativePath(path, '/').normalizePathUnix).some
  except:
    discard

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
    log lvlInfo, &"Using ignore file '.{appName}-ignore' for workspace {self.name}"
  elif self.loadIgnoreFile(".gitignore").getSome(ignore):
    self.ignore = ignore
    log lvlInfo, &"Using ignore file '.gitignore' for workspace {self.name}"
  else:
    log lvlInfo, &"No ignore file for workspace {self.name}"

proc info*(self: Workspace): WorkspaceInfo =
  let additionalPaths = self.additionalPaths.mapIt((it.absolutePath, it.some))
  return WorkspaceInfo(name: self.path, folders: @[(self.path.absolutePath, self.path.some)] & additionalPaths)

proc removeWorkspaceFolder*(self: Workspace, path: string, recomputeFileCache: bool = true) =
  let idx = if path == self.path:
    -1
  else:
    let idx = self.additionalPaths.find(path)
    if idx == -1:
      log lvlError, &"Can't remove unknown workspace folder '{path}'"
      return
    idx

  if idx != -1:
    self.additionalPaths.removeShift(idx)
  elif self.additionalPaths.len > 0:
    self.path = self.additionalPaths[0]
    self.additionalPaths.removeShift(0)
  else:
    log lvlError, &"Can't remove last workspace folder '{path}'"
    return

  let (wsVfs, _) = self.vfs.getVFS("ws://")
  self.vfs.unmount(&"ws{self.additionalPaths.len + 1}://")
  wsVfs.unmount(&"{self.additionalPaths.len + 1}")

  # rebuild vfs
  for i, path in @[self.path] & self.additionalPaths:
    self.vfs.mount(&"ws{i}://", VFSLink(target: self.vfs.getVFS("").vfs, targetPrefix: path & "/"))
    wsVfs.mount($i, VFSLink(target: self.vfs.getVFS("").vfs, targetPrefix: path & "/"))

  self.onWorkspaceFolderRemoved.invoke(path)

  if recomputeFileCache:
    self.recomputeFileCache()

proc addWorkspaceFolder*(self: Workspace, path: string, recomputeFileCache: bool = true) =
  if self.path.len == 0:
    self.path = path
    self.loadDefaultIgnoreFile()

    # todo: make this configurable
    self.ignore.original.add ".git"
  else:
    self.additionalPaths.add path

  self.vfs.mount(&"ws{self.additionalPaths.len}://", VFSLink(target: self.vfs.getVFS("").vfs, targetPrefix: path & "/"))

  let (wsVfs, _) = self.vfs.getVFS("ws://")
  wsVfs.mount($self.additionalPaths.len, VFSLink(target: self.vfs.getVFS("").vfs, targetPrefix: path & "/"))

  self.onWorkspaceFolderAdded.invoke(path)
  if recomputeFileCache:
    self.recomputeFileCache()

proc restore*(self: Workspace, settings: JsonNode) =
  try:
    let path = settings["path"].getStr
    let additionalPaths = settings["additionalPaths"].elems.mapIt(it.getStr)
    self.addWorkspaceFolder(path, recomputeFileCache = false)
    for path in additionalPaths:
      self.addWorkspaceFolder(path, recomputeFileCache = false)

    self.name = fmt"Local:{path}"
    self.recomputeFileCache()

  except CatchableError as e:
    log lvlError, &"Failed to restore workspace from settings: {e.msg}\n{settings.pretty}"
