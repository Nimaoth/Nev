import std/[os, options, unicode, strutils, streams, atomics, sequtils, pathnorm, tables]
import nimsumtree/[rope, static_array, arc]
import malebolgia
import misc/[custom_async, custom_logger, util, timer, regex, id]
import vfs
import fsnotify

when not defined(musl):
  import encodings

when defined(windows):
  import winim/lean

{.push gcsafe.}
{.push raises: [].}

logCategory "vfs-local"

type
  CachedFile = object
    fut: Future[string]

  VFSLocal2* = object
    watcher: Watcher
    updateRate: int
    cache: Table[string, CachedFile]

proc cacheFile*(self: Arc[VFS2], path: string) =
  let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  local.cache[path] = CachedFile(fut: self.readImpl(path, {ReadFlag.Binary}))

proc cacheDir*(self: Arc[VFS2], path: string, ignore: Globs) =
  try:
    for (kind, name) in walkDir(path, relative=true):
      case kind
      of pcFile:
        let filePath = path // name
        if ignore.ignorePath(filePath):
          continue
        self.cacheFile(filePath)
      else:
        discard

  except OSError:
    discard

proc process(self: Arc[VFS2]) {.async.} =
  let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  while true:
    await sleepAsync(local.updateRate.milliseconds)
    try:
      process(local.watcher)
    except Exception as e:
      log lvlError, &"Failed to process file watcher: {e.msg}"

type
  BomKind = enum
    bomNone
    bomUtf8
    bomUtf16Le
    bomUtf16Be

proc checkBom(s: Stream): tuple[bom: BomKind, bomLen: int] =
  try:
    var header: array[3, char]
    let pos = s.getPosition
    let bytesRead = s.readData(header[0].addr, 3)
    s.setPosition(pos)

    if bytesRead >= 3 and header[0] == '\xEF' and header[1] == '\xBB' and header[2] == '\xBF':
      return (bomUtf8, 3)
    if bytesRead >= 2 and header[0] == '\xFF' and header[1] == '\xFE':
      return (bomUtf16Le, 2)
    if bytesRead >= 2 and header[0] == '\xFE' and header[1] == '\xFF':
      return (bomUtf16Be, 2)
    return (bomNone, 0)
  except IOError, OSError:
    return (bomNone, 0)

proc loadFileFromStream(s: Stream, flags: set[ReadFlag]): tuple[data: string, invalidUtf8Error: bool] {.raises: [IOError, OSError, ValueError].} =
  if ReadFlag.Binary in flags:
    return (s.readAll(), false)

  let (bom, bomLen) = checkBom(s)

  if bom in {bomUtf16Le, bomUtf16Be}:
    # Read all and convert to UTF-8
    s.setPosition(bomLen)
    var raw = s.readAll
    if bom == bomUtf16Be:
      # Swap bytes for big endian
      for i in countup(0, raw.len - 2, 2):
        swap(raw[i], raw[i + 1])
    when not defined(musl):
      return (convert(raw, "UTF-8", "UTF-16"), false)
    else:
      return (&"Invalid utf-8", true)

  if bom == bomUtf8:
    s.setPosition(bomLen)

  # Read all as UTF-8 (or binary)
  var data = s.readAll
  if data.len == 0:
    return (data.ensureMove, false)

  # Validate UTF-8
  let invalidUtf8Index = data.validateUtf8
  if invalidUtf8Index < 0:
    return (data.ensureMove, false)

  # Try converting from CP1252
  when not defined(musl):
    var converted = convert(data, "UTF-8", "CP1252")
    if converted.validateUtf8 < 0:
      return (converted.ensureMove, false)

  return (&"Invalid utf-8 byte at {invalidUtf8Index}", true)

proc loadFileThread(args: tuple[path: string, data: ptr string, invalidUtf8Error: ptr bool, flags: set[ReadFlag]]): bool =
  try:
    let fileSize = getFileSize(args.path).int
    let s = newFileStream(args.path, fmRead, max(1024, fileSize))
    if s.isNil:
      args.data[] = &"Failed to open file for reading: {args.path}"
      return false

    defer:
      s.close()

    var (data, invalidUtf8) = loadFileFromStream(s, args.flags)
    if invalidUtf8:
      args.data[] = data.ensureMove
      args.invalidUtf8Error[] = true
      return false

    args.data[] = data.ensureMove
    return true

  except CatchableError:
    args.data[] = getCurrentExceptionMsg()
    return false

proc writeFileThread(args: tuple[path: string, data: string]): (bool, string) =
  try:
    let dir = args.path.splitPath.head
    if not dirExists(dir):
      createDir(dir)
    writeFile(args.path, args.data)
    return (true, "")
  except:
    return (false, getCurrentExceptionMsg())

proc writeRopeThread(args: tuple[path: string, data: sink RopeSlice[int]]): (bool, string) =
  try:
    let dir = args.path.splitPath.head
    if not dirExists(dir):
      createDir(dir)

    let s = openFileStream(args.path, fmWrite, 64 * 1024)
    defer:
      s.close()

    for chunk in args.data.iterateChunks:
      s.writeData(chunk.startPtr, chunk.chars.len)
    return (true, "")
  except:
    return (false, getCurrentExceptionMsg())

proc loadFileRopeThread(args: tuple[path: string, data: ptr Rope, err: ptr ref CatchableError, cancel: ptr Atomic[bool], threadDone: ptr Atomic[bool]]) =
  try:
    let s = newFileStream(args.path, fmRead, 1024 * 1024)
    if s.isNil:
      args.err[] = newException(IOError, &"Failed to open file for reading: {args.path}")
      args.threadDone[].store(true)
      return

    defer:
      s.close()

    let (bom, bomLen) = checkBom(s)

    if bom in {bomUtf16Le, bomUtf16Be}:
      # Non-UTF-8 BOM: use helper to load and convert, then create rope from string
      var (data, invalidUtf8) = loadFileFromStream(s, {})
      if invalidUtf8:
        args.err[] = newException(IOError, data)
      else:
        args.data[] = Rope.new(data.ensureMove)
      args.threadDone[].store(true)
      return

    # UTF-8 BOM or no BOM: use existing stream-based rope loading
    if bom == bomUtf8:
      s.setPosition(bomLen)

    proc readImpl(buffer: var string, bytesToRead: int) {.gcsafe, raises: [].} =
      if args.cancel[].load:
        return

      var localBuffer = array[chunkBase, char].default

      let len = buffer.len
      buffer.setLen(len + bytesToRead)
      try:
        var totalBytesRead = 0
        while totalBytesRead < bytesToRead:
          let bytesToReadLocal = min(localBuffer.len, bytesToRead - totalBytesRead)
          let bytesRead = s.readData(localBuffer[0].addr, bytesToReadLocal)
          for i in 0..<bytesRead:
            if localBuffer[i] != '\r':
              buffer[len + totalBytesRead] = localBuffer[i]
              inc totalBytesRead

          if bytesRead < bytesToReadLocal:
            break

        buffer.setLen(len + totalBytesRead)
      except CatchableError as e:
        args.err[] = e
        buffer.setLen(len)

    var errorIndex = -1
    var res = Rope.new(readImpl, errorIndex)
    if res.isSome:
      args.data[] = res.take
    else:
      args.err[] = newException(InvalidUtf8Error, &"Invalid utf-8 byte at {errorIndex}")

    args.threadDone[].store(true)

  except CatchableError as e:
    args.err[] = e

proc fillDirectoryListing(directoryListing: var DirectoryListing, path: string, relative: bool = true) =
  try:
    for (kind, name) in walkDir(path, relative=relative):
      case kind
      of pcFile:
        directoryListing.files.add name
      of pcDir:
        directoryListing.folders.add name
      of pcLinkToFile:
        directoryListing.files.add name
      of pcLinkToDir:
        directoryListing.folders.add name

  except OSError:
    discard

proc findFilesRec(dir: string, relDir: string, filename: Regex, maxResults: int, res: var seq[string], maxDepth: int, depth: int = 0) =
  try:
    if depth > maxDepth:
      return

    for (kind, name) in walkDir(dir, relative=true):
      case kind
      of pcFile:
        if name.contains(filename):
          res.add relDir // name
          if res.len >= maxResults:
            return

      of pcDir:
        findFilesRec(dir // name, relDir // name, filename, maxResults, res, maxDepth, depth + 1)
        if res.len >= maxResults:
          return
      else:
        discard

  except:
    discard

proc findFileThread(args: tuple[root: string, filename: string, maxResults: int, res: ptr seq[string], options: ptr FindFilesOptions]) =
  try:
    let filenameRegex = re(args.filename)
    findFilesRec(args.root, "", filenameRegex, args.maxResults, args.res[], args.options[].maxDepth)
  except RegexError:
    discard

when defined(windows):
  import winlean

proc vfsLocalName*(self: Arc[VFS2]): string = &"VFSLocal({self.get.prefix})"

proc vfsLocalRead*(self: Arc[VFS2], path: string, flags: set[ReadFlag]): Future[string] {.gcsafe, async: (raises: [IOError]).} =
  let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  if not path.isAbsolute:
    raise newException(IOError, &"Path not absolute '{path}'")
  if local.cache.contains(path):
    let fut = local.cache[path].fut
    local.cache.del(path)
    try:
      return await fut
    except:
      raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

  if not fileExists(path):
    raise newException(FileNotFoundError, &"Not found '{path}'")

  try:
    # logScope lvlInfo, &"[loadFile] '{path}'"
    var data = ""
    var invalidUtf8Error = false
    let ok = await spawnAsync(loadFileThread, (path, data.addr, invalidUtf8Error.addr, flags))
    if not ok:
      if invalidUtf8Error:
        raise newException(InvalidUtf8Error, data)
      else:
        raise newException(IOError, data)

    return data.move
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

{.push, hint[XCannotRaiseY]: off.}
proc vfsLocalReadRope*(self: Arc[VFS2], path: string, rope: ptr Rope): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  # let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  if not path.isAbsolute:
    raise newException(IOError, &"Path not absolute '{path}'")
  if not fileExists(path):
    raise newException(FileNotFoundError, &"Not found '{path}'")

  try:
    # logScope lvlInfo, &"[loadFileRope] '{path}'"

    var err: ref CatchableError = nil
    var cancel: Atomic[bool]
    var threadDone: Atomic[bool]
    try:
      await spawnAsync(loadFileRopeThread, (path, rope, err.addr, cancel.addr, threadDone.addr))
    except CancelledError:
      cancel.store(true)

      while not threadDone.load:
        try:
          await sleepAsync(10.milliseconds)
        except CancelledError:
          discard

    if err != nil:
      if err of IOError:
        raise err
      else:
        raise newException(IOError, err.msg, err)

  except IOError as e:
    raise e
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

proc vfsLocalWrite*(self: Arc[VFS2], path: string, content: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  # let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  if not path.isAbsolute:
    raise newException(IOError, &"Path not absolute '{path}'")

  try:
    logScope lvlInfo, &"[saveFile] '{path}'"
    let (ok, err) = await spawnAsync(writeFileThread, (path, content))
    if not ok:
      raise newException(IOError, err)
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

proc vfsLocalWrite*(self: Arc[VFS2], path: string, content: sink RopeSlice[int]): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  # let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  if not path.isAbsolute:
    raise newException(IOError, &"Path not absolute '{path}'")

  try:
    logScope lvlInfo, &"[saveFile (rope)] '{path}'"
    let (ok, err) = await spawnAsync(writeRopeThread, (path, content))
    if not ok:
      raise newException(IOError, err)

  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

proc vfsLocalDelete*(self: Arc[VFS2], path: string): Future[bool] {.gcsafe, async: (raises: []).} =
  # let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  if not path.isAbsolute:
    return false

  logScope lvlInfo, &"[deleteFile] '{path}'"
  if dirExists(path):
    try:
      removeDir(path)
      return true
    except:
      return false
  return tryRemoveFile(path)

proc vfsLocalCreateDir*(self: Arc[VFS2], path: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  # let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  if not path.isAbsolute:
    raise newException(IOError, &"Path not absolute '{path}'")

  try:
    createDir(path)
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

proc vfsLocalGetFileKind*(self: Arc[VFS2], path: string): Future[Option[FileKind]] {.gcsafe, async: (raises: []).} =
  # let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  if fileExists(path):
    return FileKind.File.some
  if dirExists(path):
    return FileKind.Directory.some

  return FileKind.none

proc vfsLocalGetFileAttributes*(self: Arc[VFS2], path: string): Future[Option[FileAttributes]] {.gcsafe, async: (raises: []).} =
  # let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  try:
    let permissions = path.getFilePermissions()
    # log lvlInfo, &"[isFileReadOnly] Permissions for '{path}': {permissions}"
    return FileAttributes(writable: fpUserWrite in permissions, readable: fpUserRead in permissions).some
  except:
    return FileAttributes.none

proc vfsLocalSetFileAttributes*(self: Arc[VFS2], path: string, attributes: FileAttributes): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  # let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  try:
    var permissions = path.getFilePermissions()

    if attributes.writable:
      permissions.incl {fpUserWrite}
    else:
      permissions.excl {fpUserWrite}

    if attributes.readable:
      permissions.incl {fpUserRead}
    else:
      permissions.excl {fpUserRead}

    log lvlInfo, fmt"Try to change file permissions of '{path}' to {permissions}"
    path.setFilePermissions(permissions)

  except:
    raise newException(IOError, fmt"Failed to change file permissions of '{path}': " & getCurrentExceptionMsg(), getCurrentException())

{.pop.}

proc vfsLocalGetDirectoryListing*(self: Arc[VFS2], path: string): Future[DirectoryListing] {.gcsafe, async: (raises: []).} =
  if path.len == 0:
    when defined(windows):
      var chars: array[1024, char]
      let len = GetLogicalDriveStringsA(cast[winlean.DWORD](chars.len), cast[LPSTR](chars[0].addr)).int
      if len == 0:
        result.folders.add "C:"
      else:
        var index = 0
        while true:
          let nextIndex = chars.toOpenArray(0, chars.high).find('\0', index)
          if nextIndex == index or nextIndex == -1 or index >= chars.len:
            break

          let colonIndex = chars.find(':', index)
          if colonIndex != -1:
            result.folders.add chars[index..colonIndex].join("")

          index = nextIndex + 1

    else:
      result.fillDirectoryListing("/", relative = false)

  else:
    when defined(posix):
      if path == "/":
        result.fillDirectoryListing("/", relative = false)
        return

    result.fillDirectoryListing(path)

proc vfsLocalGetVFS*(self: Arc[VFS2], path: openArray[char], maxDepth: int = int.high): tuple[vfs: Arc[VFS2], relativePath: string] =
  return (self, path.join())

proc vfsLocalCopyFile*(self: Arc[VFS2], src: string, dest: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  # let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  try:
    let dir = dest.splitPath.head
    createDir(dir)
    copyFileWithPermissions(src, dest)
  except Exception as e:
    raise newException(IOError, &"Failed to copy file '{src}' to '{dest}': {e.msg}", e)

proc vfsLocalNormalize*(self: Arc[VFS2], path: string): string {.gcsafe, raises: [].} =
  # let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  return path.normalizePath.normalizeNativePath

proc vfsLocalWatch*(self: Arc[VFS2], path: string, cb: proc(events: seq[PathEvent]) {.gcsafe, raises: [].}): id.Id {.gcsafe, raises: [].} =
  let local = cast[ptr VFSLocal2](self.getMutUnsafe.impl)
  log lvlInfo, &"Register watcher for local file system at '{path}'"
  try:
    proc cbWrapper(events: seq[PathEvent]) {.gcsafe, raises: [].} = cb(events.deduplicate(isSorted = true))
    register(local.watcher, path, cbWrapper)
    # todo
    return newId()
  except OSError as e:
    log lvlError, &"Failed to register file watcher for '{path}': {e.msg}"
    return idNone()

proc vfsLocalFindFiles*(self: Arc[VFS2], root: string, filenameRegex: string, maxResults: int = int.high, options: FindFilesOptions = FindFilesOptions()): Future[seq[string]] {.async: (raises: []).} =
  var res = newSeq[string]()
  try:
    var options = options
    await spawnAsync(findFileThread, (root, filenameRegex, maxResults, res.addr, options.addr))
  except Exception as e:
    log lvlError, &"Failed to find files in {self.name}/{root}: {e.msg}"
  return res

proc newVFSLocal*(): Arc[VFS2] =
  let local = create(VFSLocal2)
  result = Arc[VFS2].new()
  result.getMutUnsafe.impl = local
  result.getMutUnsafe.nameImpl = vfsLocalName
  result.getMutUnsafe.readImpl = vfsLocalRead
  result.getMutUnsafe.readRopeImpl = vfsLocalReadRope
  result.getMutUnsafe.writeImpl = vfsLocalWrite
  result.getMutUnsafe.writeRopeImpl = vfsLocalWrite
  result.getMutUnsafe.deleteImpl = vfsLocalDelete
  result.getMutUnsafe.createDirImpl = vfsLocalCreateDir
  result.getMutUnsafe.getFileKindImpl = vfsLocalGetFileKind
  result.getMutUnsafe.getFileAttributesImpl = vfsLocalGetFileAttributes
  result.getMutUnsafe.setFileAttributesImpl = vfsLocalSetFileAttributes
  result.getMutUnsafe.getDirectoryListingImpl = vfsLocalGetDirectoryListing
  # result.getMutUnsafe.getVFSImpl = vfsLocalGetVFS
  result.getMutUnsafe.copyFileImpl = vfsLocalCopyFile

  result.getMutUnsafe.normalizeImpl = vfsLocalNormalize
  result.getMutUnsafe.watchImpl = vfsLocalWatch
  # result.getMutUnsafe.unwatchImpl = vfsLocalUnwatch
  result.getMutUnsafe.findFilesImpl = vfsLocalFindFiles

  local.watcher = initWatcher()
  local.updateRate = 200

  asyncSpawn result.process()
