import std/[os, json, options, sequtils, strutils, unicode]
import misc/[custom_async, custom_logger, async_process, util, regex, timer, event]
import platform/filesystem
import workspace
import compilation_config

import nimsumtree/[rope]

{.push gcsafe.}
{.push raises: [].}

logCategory "ws-local"

type
  WorkspaceFolderLocal* = ref object of Workspace
    path*: string
    additionalPaths: seq[string]
    isCacheUpdateInProgress: bool = false

method settings*(self: WorkspaceFolderLocal): JsonNode =
  try:
    result = newJObject()
    result["path"] = newJString(self.path.absolutePath)
    result["additionalPaths"] = %self.additionalPaths
  except ValueError, OSError:
    discard

proc ignorePath*(ignore: Globs, path: string): bool =
  if ignore.excludePath(path) or ignore.excludePath(path.extractFilename):
    if ignore.includePath(path) or ignore.includePath(path.extractFilename):
      return false

    return true
  return false

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

proc recomputeFileCacheAsync(self: WorkspaceFolderLocal): Future[void] {.async.} =
  if self.isCacheUpdateInProgress:
    return
  self.isCacheUpdateInProgress = true
  defer:
    self.isCacheUpdateInProgress = false

  log lvlInfo, "[recomputeFileCacheAsync] Start"
  let args = (@[self.path] & self.additionalPaths, self.ignore)
  try:
    let res = spawnAsync(collectFilesThread, args).await
    log lvlInfo, fmt"[recomputeFileCacheAsync] Finished in {res.time}ms"

    self.cachedFiles = res.files
    self.onCachedFilesUpdated.invoke()
  except CancelledError:
    discard

method recomputeFileCache*(self: WorkspaceFolderLocal) =
  asyncSpawn self.recomputeFileCacheAsync()

proc getAbsolutePath(self: WorkspaceFolderLocal, relativePath: string): string =
  try:
    if relativePath.isAbsolute:
      relativePath
    else:
      self.path.absolutePath // relativePath
  except ValueError, OSError:
    relativePath

method getRelativePathSync*(self: WorkspaceFolderLocal, absolutePath: string): Option[string] =
  try:
    if absolutePath.startsWith(self.path):
      return absolutePath.relativePath(self.path, '/').normalizePathUnix.some

    for path in self.additionalPaths:
      if absolutePath.startsWith(path):
        return absolutePath.relativePath(path, '/').normalizePathUnix.some

    return string.none
  except:
    return string.none

method getRelativePath*(self: WorkspaceFolderLocal, absolutePath: string):
    Future[Option[string]] {.async.} =
  return self.getRelativePathSync(absolutePath)

method isReadOnly*(self: WorkspaceFolderLocal): bool = false

method getWorkspacePath*(self: WorkspaceFolderLocal): string =
  try:
    self.path.absolutePath
  except ValueError, OSError:
    return ""

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

method fileExists*(self: WorkspaceFolderLocal, path: string): Future[bool] {.async.} =
  let path = self.getAbsolutePath(path)
  return path.fileExists

proc loadFileThread(args: tuple[path: string, data: ptr string]): bool =
  try:
    args.data[] = readFile(args.path)

    let invalidUtf8Index = args.data[].validateUtf8
    if invalidUtf8Index >= 0:
      args.data[] = &"Invalid utf-8 byte at {invalidUtf8Index}"
      return false
    else:
      return true

  except:
    return false

method loadFile*(self: WorkspaceFolderLocal, relativePath: string): Future[string] {.async.} =
  let path = self.getAbsolutePath(relativePath)
  logScope lvlInfo, &"[loadFile] '{path}'"
  try:
    var data = ""
    let ok = await spawnAsync(loadFileThread, (path, data.addr))
    if not ok:
      log lvlError, &"Failed to load file '{path}'"

    return data.move
  except:
    log lvlError, &"Failed to load file '{path}'"
    return ""

method loadFile*(self: WorkspaceFolderLocal, relativePath: string, data: ptr string): Future[void] {.async.} =
  let path = self.getAbsolutePath(relativePath)
  logScope lvlInfo, &"[loadFile] '{path}'"
  try:
    let ok = await spawnAsync(loadFileThread, (path, data))
    if not ok:
      log lvlError, &"Failed to load file '{path}'"
      return

  except:
    log lvlError, &"Failed to load file '{path}'"

method saveFile*(self: WorkspaceFolderLocal, relativePath: string, content: string): Future[void] {.async.} =
  let path = self.getAbsolutePath(relativePath)
  logScope lvlInfo, &"[saveFile] '{path}'"
  try:
    # todo: reimplement async
    writeFile(path, content)
    # var file = openAsync(path, fmWrite)
    # await file.write(content)
    # file.close()
  except:
    log lvlError, &"Failed to write file '{path}'"

method saveFile*(self: WorkspaceFolderLocal, relativePath: string, content: sink Rope): Future[void] {.async.} =
  let path = self.getAbsolutePath(relativePath)
  logScope lvlInfo, &"[saveFile] '{path}'"
  try:
    # todo: reimplement async
    writeFile(path, $content)
    # var file = openAsync(path, fmWrite)
    # for chunk in content.iterateChunks:
    #   await file.writeBuffer(chunk.chars[0].addr, chunk.chars.len)
    # file.close()
  except:
    log lvlError, &"Failed to write file '{path}'"

proc loadIgnoreFile(self: WorkspaceFolderLocal, path: string): Option[Globs] =
  try:
    let globLines = readFile(self.getAbsolutePath(path))
    return globLines.parseGlobs.some
  except:
    return Globs.none

proc loadDefaultIgnoreFile(self: WorkspaceFolderLocal) =
  if self.loadIgnoreFile(&".{appName}-ignore").getSome(ignore):
    self.ignore = ignore
    log lvlInfo, &"Using ignore file '.{appName}-ignore' for workpace {self.name}"
  elif self.loadIgnoreFile(".gitignore").getSome(ignore):
    self.ignore = ignore
    log lvlInfo, &"Using ignore file '.gitignore' for workpace {self.name}"
  else:
    log lvlInfo, &"No ignore file for workpace {self.name}"

proc fillDirectoryListing(directoryListing: var DirectoryListing, path: string) =
  try:
    for (kind, file) in walkDir(path, relative=false):
      case kind
      of pcFile:
        directoryListing.files.add file.normalizePathUnix
      of pcDir:
        directoryListing.folders.add file.normalizePathUnix
      else:
        log lvlError, fmt"getDirectoryListing: Unhandled file type {kind} for {file}"

  except OSError:
    discard

method getDirectoryListing*(self: WorkspaceFolderLocal, relativePath: string):
    Future[DirectoryListing] {.async.} =
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

proc createInfo(path: string, additionalPaths: seq[string]): Future[WorkspaceInfo] {.async.} =
  let additionalPaths = additionalPaths.mapIt((it.absolutePath, it.some))
  return WorkspaceInfo(name: path, folders: @[(path.absolutePath, path.some)] & additionalPaths)

proc newWorkspaceFolderLocal*(path: string, additionalPaths: seq[string] = @[]): WorkspaceFolderLocal =
  new result
  result.path = path.absolutePath.catch(path).normalizePathUnix
  result.name = fmt"Local:{result.path}"
  result.additionalPaths = additionalPaths.mapIt(it.absolutePath.catch(path).normalizePathUnix)
  result.info = createInfo(path, result.additionalPaths)

  result.loadDefaultIgnoreFile()

  result.recomputeFileCache()

proc newWorkspaceFolderLocal*(settings: JsonNode): WorkspaceFolderLocal =
  try:
    let path = settings["path"].getStr
    let additionalPaths = settings["additionalPaths"].elems.mapIt(it.getStr)
    return newWorkspaceFolderLocal(path, additionalPaths)
  except:
    return nil
