import std/[os, json, options, sequtils, strutils]
import misc/[custom_async, custom_logger, async_process, util]
import platform/filesystem
import workspace

logCategory "ws-local"

type
  WorkspaceFolderLocal* = ref object of WorkspaceFolder
    path*: string
    additionalPaths: seq[string]

method settings*(self: WorkspaceFolderLocal): JsonNode =
  result = newJObject()
  result["path"] = newJString(self.path.absolutePath)
  result["additionalPaths"] = %self.additionalPaths

proc getAbsolutePath(self: WorkspaceFolderLocal, relativePath: string): string =
  if relativePath.isAbsolute:
    relativePath
  else:
    self.path.absolutePath / relativePath

method getRelativePath*(self: WorkspaceFolderLocal, absolutePath: string): Future[Option[string]] {.async.} =
  return absolutePath.relativePath(self.path, '/').some

method isReadOnly*(self: WorkspaceFolderLocal): bool = false

method getWorkspacePath*(self: WorkspaceFolderLocal): string = self.path.absolutePath

method loadFile*(self: WorkspaceFolderLocal, relativePath: string): Future[string] {.async.} =
  return readFile(self.getAbsolutePath(relativePath))

method saveFile*(self: WorkspaceFolderLocal, relativePath: string, content: string): Future[void] {.async.} =
  writeFile(self.getAbsolutePath(relativePath), content)

proc fillDirectoryListing(directoryListing: var DirectoryListing, path: string) =
  for (kind, file) in walkDir(path, relative=false):
    case kind
    of pcFile:
      directoryListing.files.add file.normalizePathUnix
    of pcDir:
      directoryListing.folders.add file.normalizePathUnix
    else:
      log lvlError, fmt"getDirectoryListing: Unhandled file type {kind} for {file}"

method getDirectoryListing*(self: WorkspaceFolderLocal, relativePath: string): Future[DirectoryListing] {.async.} =
  when not defined(js):
    var res = DirectoryListing()
    res.fillDirectoryListing(self.getAbsolutePath(relativePath))

    if relativePath == "":
      for path in self.additionalPaths:
        res.fillDirectoryListing(path)

    return res

proc searchWorkspaceFolder(self: WorkspaceFolderLocal, query: string, root: string): Future[seq[SearchResult]] {.async.} =
  let output = runProcessAsync("rg", @["--line-number", "--column", "--heading", query, root]).await
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

  return res

method searchWorkspace*(self: WorkspaceFolderLocal, query: string): Future[seq[SearchResult]] {.async.} =
  var futs: seq[Future[seq[SearchResult]]]
  futs.add self.searchWorkspaceFolder(query, self.path)
  for path in self.additionalPaths:
    futs.add self.searchWorkspaceFolder(query, path)

  var res: seq[SearchResult]
  for fut in futs:
    res.add fut.await

  return res

proc createInfo(path: string, additionalPaths: seq[string]): Future[WorkspaceInfo] {.async.} =
  let additionalPaths = additionalPaths.mapIt((it.absolutePath, it.some))
  return WorkspaceInfo(name: path, folders: @[(path.absolutePath, path.some)] & additionalPaths)

proc newWorkspaceFolderLocal*(path: string, additionalPaths: seq[string] = @[]): WorkspaceFolderLocal =
  new result
  result.path = path
  result.name = fmt"Local:{path.absolutePath}"
  result.info = createInfo(path, additionalPaths)
  result.additionalPaths = additionalPaths

proc newWorkspaceFolderLocal*(settings: JsonNode): WorkspaceFolderLocal =
  let path = settings["path"].getStr
  let additionalPaths = settings["additionalPaths"].elems.mapIt(it.getStr)
  return newWorkspaceFolderLocal(path, additionalPaths)