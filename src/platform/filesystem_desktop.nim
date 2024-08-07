import std/[os]
import misc/[custom_logger, custom_async, regex]
import filesystem

logCategory "fs-desktop"

type FileSystemDesktop* = ref object of FileSystem
  appDir*: string

method init*(self: FileSystemDesktop, appDir: string) =
  self.appDir = appDir

method loadFile*(self: FileSystemDesktop, path: string): string =
  return readFile(path)

method saveFile*(self: FileSystemDesktop, path: string, content: string) =
  writeFile(path, content)

proc getApplicationDirectoryListingSync*(self: FileSystemDesktop, path: string):
    tuple[files: seq[string], folders: seq[string]] =
  let path = self.getApplicationFilePath path
  for (kind, file) in walkDir(path, relative=true):
    case kind
    of pcFile:
      result.files.add path // file
    of pcDir:
      result.folders.add path // file
    else:
      log lvlError, fmt"getApplicationDirectoryListing: Unhandled file type {kind} for {file}"

method getApplicationDirectoryListing*(self: FileSystemDesktop, path: string):
    Future[tuple[files: seq[string], folders: seq[string]]] {.async.} =
  return self.getApplicationDirectoryListingSync(path)

method getApplicationFilePath*(self: FileSystemDesktop, name: string): string =
  when defined(js):
    return name
  else:
    if isAbsolute(name):
      return name
    else:
      return self.appDir / name

method loadApplicationFile*(self: FileSystemDesktop, name: string): string =
  let path = self.getApplicationFilePath name
  log lvlInfo, fmt"loadApplicationFile1 {name} -> {path}"
  try:
    return readFile(path)
  except:
    log lvlError, &"Failed to load application file {path}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
    return ""

proc loadFileThread(args: tuple[path: string, data: ptr string]):
    tuple[ok: bool] {.gcsafe.} =

  try:
    args.data[] = readFile(args.path)
    result.ok = true
  except:
    result.ok = false

method loadFileAsync*(self: FileSystemDesktop, path: string): Future[string] {.async.} =
  log lvlInfo, fmt"loadFile '{path}'"
  try:
    var data = ""
    let res = await spawnAsync(loadFileThread, (path, data.addr))
    if not res.ok:
      log lvlError, &"Failed to load file '{path}'"
      return ""

    return data.move
  except:
    log lvlError, &"Failed to load application file {path}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
    return ""

method loadApplicationFileAsync*(self: FileSystemDesktop, name: string): Future[string] {.async.} =
  let path = self.getApplicationFilePath name
  log lvlInfo, fmt"loadApplicationFile2 {name} -> {path}"
  try:
    var data = ""
    let res = await spawnAsync(loadFileThread, (path, data.addr))
    if not res.ok:
      log lvlError, &"Failed to load file '{path}'"
      return ""

    return data.move
  except:
    log lvlError, &"Failed to load application file {path}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
    return ""

method saveApplicationFile*(self: FileSystemDesktop, name: string, content: string) =
  let path = self.getApplicationFilePath name
  log lvlInfo, fmt"saveApplicationFile {name} -> {path}"
  try:
    writeFile(path, content)
  except:
    log lvlError, &"Failed to save application file {path}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc findFilesRec(dir: string, filename: Regex, maxResults: int, res: var seq[string]) =
  for (kind, path) in walkDir(dir, relative=false):
    case kind
    of pcFile:
      if path.contains(filename):
        res.add path
        if res.len >= maxResults:
          return

    of pcDir:
      findFilesRec(path, filename, maxResults, res)
      if res.len >= maxResults:
        return
    else:
      discard

proc findFileThread(args: tuple[root: string, filename: string, maxResults: int]): seq[string] {.gcsafe.} =
  try:
    let filenameRegex = re(args.filename)
    findFilesRec(args.root, filenameRegex, args.maxResults, result)
  except:
    discard

method findFile*(self: FileSystemDesktop, root: string, filenameRegex: string, maxResults: int = int.high): Future[seq[string]] {.async.} =
  let res = await spawnAsync(findFileThread, (root, filenameRegex, maxResults))
  return res

method copyFile*(self: FileSystemDesktop, source: string, dest: string): Future[bool] {.async.} =
  try:
    let dir = dest.splitPath.head
    createDir(dir)
    copyFileWithPermissions(source, dest)
    return true
  except:
    log lvlError, &"Failed to copy file '{source}' to '{dest}': {getCurrentExceptionMsg()}"
    return false
