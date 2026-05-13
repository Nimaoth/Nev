import std/[options, sequtils, os]
import misc/[custom_async, id, util, regex, custom_logger, event]
import nimsumtree/arc
import vfs, vfs_service, service
import finder/finder

include dynlib_export

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
    cachedFiles*: Option[ItemList]

    onCachedFilesUpdated*: Event[void]
    onWorkspaceFolderAdded*: Event[string]
    onWorkspaceFolderRemoved*: Event[string]
    isCacheUpdateInProgress: bool = false
    vfs*: VFS

func serviceName*(_: typedesc[Workspace]): string = "Workspace"

# DLL API
{.push apprtl, gcsafe, raises: [].}
proc workspaceSearchPaths*(self: Workspace, paths: seq[string], query: string, maxResults: int, customArgs: seq[string] = @[]): Future[seq[SearchResult]]
proc workspaceSearch*(self: Workspace, query: string, maxResults: int, customArgs: seq[string] = @[], additionalPaths: seq[string] = @[]): Future[seq[SearchResult]]
proc workspaceSetWorkspaceFolder*(self: Workspace, path: string)
proc workspaceAddWorkspaceFolder(self: Workspace, path: string, recomputeFileCache: bool = true)
proc workspaceGetAbsolutePath(self: Workspace, path: string): string
proc getRelativePathAndWorkspaceSync*(self: Workspace, absolutePath: string): Option[tuple[root, path: string]]
proc workspaceGetRelativePathSync(self: Workspace, absolutePath: string): Option[string]
{.pop.}

# Nice wrappers

proc search*(self: Workspace, paths: seq[string], query: string, maxResults: int, customArgs: seq[string] = @[]): Future[seq[SearchResult]] {.inline.} = workspaceSearchPaths(self, paths, query, maxResults, customArgs)
proc search*(self: Workspace, query: string, maxResults: int, customArgs: seq[string] = @[], additionalPaths: seq[string] = @[]): Future[seq[SearchResult]] {.inline.} = workspaceSearch(self, query, maxResults, customArgs, additionalPaths)
proc setWorkspaceFolder*(self: Workspace, path: string) {.inline.} = workspaceSetWorkspaceFolder(self, path)
proc addWorkspaceFolder*(self: Workspace, path: string, recomputeFileCache: bool = true) = workspaceAddWorkspaceFolder(self, path, recomputeFileCache)
proc getAbsolutePath*(self: Workspace, path: string): string = workspaceGetAbsolutePath(self, path)
proc getRelativePathSync*(self: Workspace, absolutePath: string): Option[string] = workspaceGetRelativePathSync(self, absolutePath)

proc info*(self: Workspace): WorkspaceInfo =
  try:
    let additionalPaths = self.additionalPaths.mapIt((it.absolutePath, it.some))
    return WorkspaceInfo(name: self.path, folders: @[(self.path.absolutePath, self.path.some)] & additionalPaths)
  except ValueError, OSError:
    return WorkspaceInfo()

proc getWorkspacePath*(self: Workspace): string =
  try:
    self.path.absolutePath
  except ValueError, OSError:
    return ""

# Implementation
when implModule:
  import std/[json, strutils, unicode]
  import malebolgia
  import misc/[timer, async_process, static_array]
  import compilation_config, event_service

  when defined(windows):
    import winlean
    const
      UNI_REPLACEMENT_CHAR = Utf16Char(0xFFFD'i16)
      UNI_MAX_BMP = 0x0000FFFF
      UNI_MAX_UTF16 = 0x0010FFFF
      # UNI_MAX_UTF32 = 0x7FFFFFFF
      # UNI_MAX_LEGAL_UTF32 = 0x0010FFFF

      halfShift = 10
      halfBase = 0x0010000
      halfMask = 0x3FF

      UNI_SUR_HIGH_START = 0xD800
      UNI_SUR_LOW_START = 0xDC00
      UNI_SUR_LOW_END = 0xDFFF

    proc skipFindData(f: winlean.WIN32_FIND_DATA): bool {.inline.} =
      # Note - takes advantage of null delimiter in the cstring
      const dot = ord('.')
      result = f.cFileName[0].int == dot and (f.cFileName[1].int == 0 or
               f.cFileName[1].int == dot and f.cFileName[2].int == 0)

    template getFilename*(f: untyped): untyped =
      $cast[WideCString](addr(f.cFileName[0]))

    iterator toWideChars(str: openArray[char]): Utf16Char =
      var d = 0
      for r in str.runes:
        let ch = r.int
        if ch <= UNI_MAX_BMP:
          if ch >= UNI_SUR_HIGH_START and ch <= UNI_SUR_LOW_END:
            yield UNI_REPLACEMENT_CHAR
          else:
            yield cast[Utf16Char](uint16(ch))
        elif ch > UNI_MAX_UTF16:
          yield UNI_REPLACEMENT_CHAR
        else:
          let ch = ch - halfBase
          yield cast[Utf16Char](uint16((ch shr halfShift) + UNI_SUR_HIGH_START))
          inc d
          yield cast[Utf16Char](uint16((ch and halfMask) + UNI_SUR_LOW_START))
        inc d
  else:
    import std/posix
    import std/private/oscommon

  addBuiltinService(Workspace, VFSService)

  method init*(self: Workspace): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    log lvlInfo, &"Workspace.init"
    self.vfs = self.services.getServiceChecked(VFSService).vfs

    return ok()

  proc ignorePath*(workspace: Workspace, path: string): bool =
    if workspace.ignore.excludePath(path) or workspace.ignore.excludePath(path.extractFilename):
      if workspace.ignore.includePath(path) or workspace.ignore.includePath(path.extractFilename):
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

  iterator walkDirCustom(dir: string, relative = false, checkDir = false, skipSpecial = false): tuple[kind: PathComponent, path: string] {.tags: [ReadDirEffect], raises: [OSError].} =
    when defined(windows):
      var buffer = initArray(Utf16Char, 300)
      for c in dir.toWideChars:
        buffer.add c
      for c in "/*".toWideChars:
        buffer.add c
      var f: winlean.WIN32_FIND_DATA
      var h = findFirstFileW(buffer.toOpenArray().data, f)
      if h == -1:
        if checkDir:
          raiseOSError(osLastError(), dir)
      else:
        defer: findClose(h)
        while true:
          var k = pcFile
          if not skipFindData(f):
            if (f.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) != 0'i32:
              k = pcDir
            if (f.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) != 0'i32:
              k = succ(k)
            var filename = cast[WideCString](addr(f.cFileName[0]))
            yield (k, $filename)
          if findNextFileW(h, f) == 0'i32:
            let errCode = getLastError()
            if errCode == winlean.ERROR_NO_MORE_FILES: break
            else: raiseOSError(errCode.OSErrorCode)
    else:
      var d = opendir(dir.cstring)
      if d == nil:
        if checkDir:
          raiseOSError(osLastError(), dir)
      else:
        defer: discard closedir(d)
        while true:
          var x = readdir(d)
          if x == nil: break
          var y = $cast[cstring](addr x.d_name)
          if y != "." and y != "..":
            var s: Stat
            let path = dir / y
            var k = pcFile

            template resolveSymlink() =
              var isSpecial: bool
              (k, isSpecial) = getSymlinkFileKind(path)
              if skipSpecial and isSpecial: continue

            template kSetGeneric() =  # pure Posix component `k` resolution
              if lstat(path.cstring, s) < 0'i32: continue  # don't yield
              elif S_ISDIR(s.st_mode):
                k = pcDir
              elif S_ISLNK(s.st_mode):
                resolveSymlink()
              elif skipSpecial and not S_ISREG(s.st_mode): continue

            when defined(linux) or defined(macosx) or
                 defined(bsd) or defined(genode) or defined(nintendoswitch):
              case x.d_type
              of DT_DIR: k = pcDir
              of DT_LNK:
                resolveSymlink()
              of DT_UNKNOWN:
                kSetGeneric()
              else: # DT_REG or special "files" like FIFOs
                if skipSpecial and x.d_type != DT_REG: continue
                else: discard # leave it as pcFile
            else:  # assuming that field `d_type` is not present
              kSetGeneric()

            yield (k, y)

  proc scanDirectoryImpl(ignore: ptr Globs, res: ptr Directory) {.gcsafe, raises: [].} =
    try:
      var m = createMaster()
      for kind, fileName in walkDirCustom(res.path, relative = true):
        if ignore[].ignorePath(res.path.toOpenArray(), fileName):
          continue

        if kind == pcFile:
          res.files.add(fileName)
          res.totalFiles += 1
        elif kind == pcDir:

          var path = newStringOfCap(res.path.len + fileName.len + 1)
          path.add res.path
          path.add "/"
          path.add fileName
          res.children.add(Directory(path: path.ensureMove))

      m.awaitAll:
        for i in 0..res.children.high:
          m.spawn scanDirectoryImpl(ignore, res.children[i].addr)

      for c in res.children:
        res.totalFiles += c.totalFiles
    except CatchableError:
      discard

  proc scanDirectory*(path: string, ignore: ptr Globs): Directory =
    result.path = path
    scanDirectoryImpl(ignore, result.addr)

  proc collectFiles(dir: Directory, files: var openArray[FinderItem], startIndex: int) =
    for i, fileName in dir.files:
      var path = dir.path & "/" & fileName
      files[startIndex + i] = FinderItem(
        displayName: fileName,
        details: @[dir.path],
        data: path.ensureMove,
      )

    var startIndex = startIndex + dir.files.len
    for c in dir.children:
      c.collectFiles(files, startIndex)
      startIndex += c.totalFiles

  proc collectFilesThread(args: tuple[roots: seq[string], ignore: Globs]):
      tuple[files: ItemList, time: float] =
    try:
      let t = startTimer()

      var m = createMaster()
      var dirs = newSeq[Directory](args.roots.len)
      m.awaitAll:
        for i in 0..args.roots.high:
          m.spawn scanDirectory(args.roots[i], args.ignore.addr) -> dirs[i]

      var totalFiles = 0
      for d in dirs:
        totalFiles += d.totalFiles
      var files = newSeq[FinderItem](totalFiles)
      var startIndex = 0
      for d in dirs:
        d.collectFiles(files, startIndex)
        startIndex += d.totalFiles

      result.files = newItemList(files.ensureMove)
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

      self.cachedFiles = res.files.some
      self.onCachedFilesUpdated.invoke()
    except CancelledError:
      discard

  proc recomputeFileCache*(self: Workspace) =
    logScope lvlInfo, &"recomputeFileCache"
    asyncSpawn self.recomputeFileCacheAsync()


  proc searchWorkspaceFolder(self: Workspace, query: string, root: string, maxResults: int, customArgs: seq[string]):
      Future[seq[SearchResult]] {.async: (raises: []).} =
    try:
      let args = @["--line-number", "--column", "--heading"] & customArgs & @[query, root]
      let output = runProcessAsync("rg", args, maxLines=maxResults).await
      var res: seq[SearchResult]

      var currentFile = ""
      if self.vfs.getFileKind(root).await == FileKind.File.some:
        currentFile = root
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

  proc searchWorkspace*(self: Workspace, paths: seq[string], query: string, maxResults: int, customArgs: seq[string] = @[]): Future[seq[SearchResult]] {.async: (raises: []).} =
    var futs: seq[InternalRaisesFuture[seq[SearchResult], void]]
    for path in paths:
      futs.add self.searchWorkspaceFolder(query, path, maxResults, customArgs)

    var res: seq[SearchResult]
    for fut in futs:
      res.add fut.await

      if res.len >= maxResults:
        break

    return res

  proc searchWorkspace*(self: Workspace, query: string, maxResults: int, customArgs: seq[string] = @[], additionalPaths: seq[string] = @[]): Future[seq[SearchResult]] {.async: (raises: []).} =
    var futs: seq[InternalRaisesFuture[seq[SearchResult], void]]
    futs.add self.searchWorkspaceFolder(query, self.path, maxResults, customArgs)
    for path in self.additionalPaths:
      futs.add self.searchWorkspaceFolder(query, path, maxResults, customArgs)
    for path in additionalPaths:
      futs.add self.searchWorkspaceFolder(query, path, maxResults, customArgs)

    var res: seq[SearchResult]
    for fut in futs:
      res.add fut.await

      if res.len >= maxResults:
        break

    return res

  proc workspaceSearchPaths*(self: Workspace, paths: seq[string], query: string, maxResults: int, customArgs: seq[string] = @[]): Future[seq[SearchResult]] {.gcsafe, raises: [].} =
    searchWorkspace(self, paths, query, maxResults, customArgs)

  proc workspaceSearch*(self: Workspace, query: string, maxResults: int, customArgs: seq[string] = @[], additionalPaths: seq[string] = @[]): Future[seq[SearchResult]] {.gcsafe, raises: [].} =
    searchWorkspace(self, query, maxResults, customArgs, additionalPaths)

  proc workspaceGetAbsolutePath(self: Workspace, path: string): string =
    if path.isAbsolute:
      return path.normalizeNativePath
    else:
      self.getWorkspacePath() // path

  proc workspaceGetRelativePathSync(self: Workspace, absolutePath: string): Option[string] =
    result = string.none
    try:
      var longestMatch = 0
      if absolutePath.startsWith(self.path):
        result = absolutePath.relativePath(self.path, '/').some
        longestMatch = self.path.len

      for path in self.additionalPaths:
        if path.len > longestMatch and absolutePath.startsWith(path):
          result = absolutePath.relativePath(path, '/').some
          longestMatch = path.len

    except:
      discard

  proc getRelativePathAndWorkspaceSync*(self: Workspace, absolutePath: string): Option[tuple[root, path: string]] =
    try:
      if absolutePath.startsWith(self.path):
        return ("ws0://", absolutePath.relativePath(self.path, '/')).some

      for i, path in self.additionalPaths:
        if absolutePath.startsWith(path):
          return (&"ws{i + 1}://", absolutePath.relativePath(path, '/')).some
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

  proc loadDefaultIgnoreFile*(self: Workspace) =
    if self.loadIgnoreFile(&".{appName}-ignore").getSome(ignore):
      self.ignore = ignore
      log lvlInfo, &"Using ignore file '.{appName}-ignore' for workspace {self.name}"
    elif self.loadIgnoreFile(".gitignore").getSome(ignore):
      self.ignore = ignore
      log lvlInfo, &"Using ignore file '.gitignore' for workspace {self.name}"
    else:
      log lvlInfo, &"No ignore file for workspace {self.name}"

    # todo: make this configurable
    self.ignore.original.add ".git"

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

    let (wsVfs2, _) = self.vfs.getVFS("ws://")
    self.vfs.unmount(&"ws{self.additionalPaths.len + 1}://")
    wsVfs2.unmount(&"{self.additionalPaths.len + 1}")

    # rebuild vfs
    for i, path in @[self.path] & self.additionalPaths:
      self.vfs.mount(&"ws{i}://", newVFSLink(self.vfs.getVFS("").vfs, path & "/"))
      wsVfs2.mount($i, newVFSLink(self.vfs.getVFS("").vfs, path & "/"))

    self.onWorkspaceFolderRemoved.invoke(path)
    getServiceChecked(EventService).emit("workspace/removed", path)

    if recomputeFileCache:
      self.recomputeFileCache()

  proc workspaceAddWorkspaceFolder(self: Workspace, path: string, recomputeFileCache: bool = true) =
    if self.path.len == 0:
      self.path = path
      self.loadDefaultIgnoreFile()
    else:
      self.additionalPaths.add path

    self.vfs.mount(&"ws{self.additionalPaths.len}://", newVFSLink(self.vfs.getVFS("").vfs, path & "/"))

    let index = $self.additionalPaths.len

    let (wsVfs2, _) = self.vfs.getVFS("ws://")
    wsVfs2.mount($index, newVFSLink(self.vfs.getVFS("").vfs, path & "/"))

    self.onWorkspaceFolderAdded.invoke(path)
    getServiceChecked(EventService).emit("workspace/added", path)
    if recomputeFileCache:
      self.recomputeFileCache()

  proc workspaceSetWorkspaceFolder(self: Workspace, path: string) =
    let allPaths = @[self.path] & self.additionalPaths
    let (wsVfs2, _) = self.vfs.getVFS("ws://")
    for i, p in allPaths:
      self.onWorkspaceFolderRemoved.invoke(p)
      self.vfs.unmount(&"ws{i}://")
      wsVfs2.unmount(&"{i}")

    self.additionalPaths = @[]
    self.path = ""

    self.addWorkspaceFolder(path)

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
