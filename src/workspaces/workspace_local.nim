import std/[os, json, options, sequtils, strutils]
import misc/[custom_async, custom_logger, async_process, util, regex, timer, event]
import platform/filesystem
import workspace
import vcs/[vcs, vcs_git, vcs_perforce]

logCategory "ws-local"

type
  WorkspaceFolderLocal* = ref object of WorkspaceFolder
    path*: string
    additionalPaths: seq[string]
    versionControlSystems*: seq[VersionControlSystem]
    isCacheUpdateInProgress: bool = false

method settings*(self: WorkspaceFolderLocal): JsonNode =
  result = newJObject()
  result["path"] = newJString(self.path.absolutePath)
  result["additionalPaths"] = %self.additionalPaths

proc ignorePath*(ignore: Globs, path: string): bool =
  if ignore.excludePath(path) or ignore.excludePath(path.extractFilename):
    if ignore.includePath(path) or ignore.includePath(path.extractFilename):
      return false

    return true
  return false

proc collectFiles(dir: string, ignore: Globs, files: var seq[string]) =
  if ignore.ignorePath(dir):
    return

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

proc collectFilesThread(args: tuple[roots: seq[string], ignore: Globs]):
    tuple[files: seq[string], time: float] {.gcsafe.} =
  try:
    let t = startTimer()

    for path in args.roots:
      collectFiles(path.normalizePathUnix, args.ignore, result.files)

    result.time = t.elapsed.ms
  except:
    discard

proc recomputeFileCacheAsync(self: WorkspaceFolderLocal): Future[void] {.async.} =
  if self.isCacheUpdateInProgress:
    return
  self.isCacheUpdateInProgress = true
  defer:
    self.isCacheUpdateInProgress = false

  log lvlInfo, "[recomputeFileCacheAsync] Start"
  let args = (@[self.path] & self.additionalPaths, self.ignore)
  let res = spawnAsync(collectFilesThread, args).await
  log lvlInfo, fmt"[recomputeFileCacheAsync] Finished in {res.time}ms"

  self.cachedFiles = res.files
  self.onCachedFilesUpdated.invoke()

method recomputeFileCache*(self: WorkspaceFolderLocal) =
  asyncCheck self.recomputeFileCacheAsync()

proc getAbsolutePath(self: WorkspaceFolderLocal, relativePath: string): string =
  if relativePath.isAbsolute:
    relativePath
  else:
    self.path.absolutePath // relativePath

method getRelativePathSync*(self: WorkspaceFolderLocal, absolutePath: string): Option[string] =
  if absolutePath.startsWith(self.path):
    return absolutePath.relativePath(self.path, '/').normalizePathUnix.some

  for path in self.additionalPaths:
    if absolutePath.startsWith(path):
      return absolutePath.relativePath(path, '/').normalizePathUnix.some

  return string.none

method getRelativePath*(self: WorkspaceFolderLocal, absolutePath: string):
    Future[Option[string]] {.async.} =
  return self.getRelativePathSync(absolutePath)

method isReadOnly*(self: WorkspaceFolderLocal): bool = false

method getWorkspacePath*(self: WorkspaceFolderLocal): string = self.path.absolutePath

method setFileReadOnly*(self: WorkspaceFolderLocal, relativePath: string, readOnly: bool): Future[bool] {.
    async.} =

  let path = self.getAbsolutePath(relativePath)
  try:
    var permissions = path.getFilePermissions()

    if readOnly:
      permissions.excl {fpUserWrite, fpGroupWrite, fpOthersWrite}
    else:
      permissions.incl {fpUserWrite, fpGroupWrite, fpOthersWrite}

    log lvlInfo, fmt"Try to change file permissions of '{path}' to {permissions}"
    path.setFilePermissions(permissions)
    return true

  except:
    log lvlError, fmt"Failed to change file permissions of '{path}'"
    return false

method isFileReadOnly*(self: WorkspaceFolderLocal, relativePath: string): Future[bool] {.async.} =
  let path = self.getAbsolutePath(relativePath)
  try:
    let permissions = path.getFilePermissions()
    log lvlInfo, &"[isFileReadOnly] Permissions for '{path}': {permissions}"
    # todo: how to handle other write permissions on unix
    return fpUserWrite notin permissions

  except:
    log lvlError, fmt"Failed to get file permissions of '{path}'"
    return false

method loadFile*(self: WorkspaceFolderLocal, relativePath: string): Future[string] {.async.} =
  return readFile(self.getAbsolutePath(relativePath))

method saveFile*(self: WorkspaceFolderLocal, relativePath: string, content: string):
    Future[void] {.async.} =
  writeFile(self.getAbsolutePath(relativePath), content)

proc loadIgnoreFile(self: WorkspaceFolderLocal, path: string): Option[Globs] =
  try:
    let globLines = readFile(self.getAbsolutePath(path))
    return globLines.parseGlobs.some
  except:
    return Globs.none

proc loadDefaultIgnoreFile(self: WorkspaceFolderLocal) =
  if self.loadIgnoreFile(".absytree-ignore").getSome(ignore):
    self.ignore = ignore
    log lvlInfo, &"Using ignore file '.absytree-ignore' for workpace {self.name}"
  elif self.loadIgnoreFile(".gitignore").getSome(ignore):
    self.ignore = ignore
    log lvlInfo, &"Using ignore file '.gitignore' for workpace {self.name}"
  else:
    log lvlInfo, &"No ignore file for workpace {self.name}"

proc fillDirectoryListing(directoryListing: var DirectoryListing, path: string) =
  for (kind, file) in walkDir(path, relative=false):
    case kind
    of pcFile:
      directoryListing.files.add file.normalizePathUnix
    of pcDir:
      directoryListing.folders.add file.normalizePathUnix
    else:
      log lvlError, fmt"getDirectoryListing: Unhandled file type {kind} for {file}"

method getDirectoryListing*(self: WorkspaceFolderLocal, relativePath: string):
    Future[DirectoryListing] {.async.} =
  when not defined(js):
    var res = DirectoryListing()

    if relativePath == "":
      self.loadDefaultIgnoreFile()
      res.fillDirectoryListing(self.path)
      for path in self.additionalPaths:
        res.fillDirectoryListing(path)

    else:
      res.fillDirectoryListing(self.getAbsolutePath(relativePath))

    return res

proc searchWorkspaceFolder(self: WorkspaceFolderLocal, query: string, root: string, maxResults: int):
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

method searchWorkspace*(self: WorkspaceFolderLocal, query: string, maxResults: int): Future[seq[SearchResult]] {.async.} =
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

method getVcsForFile*(self: WorkspaceFolderLocal, file: string): Option[VersionControlSystem] =
  let absolutePath = self.getAbsolutePath(file)
  for vcs in self.versionControlSystems:
    if file.startsWith(vcs.root):
      return vcs.some

method getAllVersionControlSystems*(self: WorkspaceFolderLocal): seq[VersionControlSystem] =
  return self.versionControlSystems

proc createInfo(path: string, additionalPaths: seq[string]): Future[WorkspaceInfo] {.async.} =
  let additionalPaths = additionalPaths.mapIt((it.absolutePath, it.some))
  return WorkspaceInfo(name: path, folders: @[(path.absolutePath, path.some)] & additionalPaths)

proc detectVersionControlSystemIn(path: string): Option[VersionControlSystem] =
  if dirExists(path // ".git"):
    log lvlInfo, fmt"Found git repository in {path}"
    let vcs = newVersionControlSystemGit(path)
    return vcs.VersionControlSystem.some

  if fileExists(path // ".p4ignore"):
    log lvlInfo, fmt"Found perforce repository in {path}"
    let vcs = newVersionControlSystemPerforce(path)
    return vcs.VersionControlSystem.some

proc newWorkspaceFolderLocal*(path: string, additionalPaths: seq[string] = @[]): WorkspaceFolderLocal =
  new result
  result.path = path
  result.name = fmt"Local:{path.absolutePath}"
  result.info = createInfo(path, additionalPaths)
  result.additionalPaths = additionalPaths

  result.loadDefaultIgnoreFile()

  if detectVersionControlSystemIn(result.path).getSome(vcs):
    result.versionControlSystems.add vcs

  for path in result.additionalPaths:
    if detectVersionControlSystemIn(path).getSome(vcs):
      result.versionControlSystems.add vcs

  result.recomputeFileCache()

proc newWorkspaceFolderLocal*(settings: JsonNode): WorkspaceFolderLocal =
  let path = settings["path"].getStr
  let additionalPaths = settings["additionalPaths"].elems.mapIt(it.getStr)
  return newWorkspaceFolderLocal(path, additionalPaths)
