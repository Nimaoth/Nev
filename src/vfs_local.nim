import std/[os, options, unicode, strutils, streams, atomics, sequtils, pathnorm, tables]
import nimsumtree/[rope, static_array]
import malebolgia
import misc/[custom_async, custom_logger, util, timer, regex, id]
import vfs
import fsnotify

when defined(windows):
  import winim/lean

{.push gcsafe.}
{.push raises: [].}

logCategory "vfs-local"

type
  CachedFile = object
    fut: Future[string]

  Directory* = object
    path*: string
    totalFiles*: int
    children*: seq[Directory]
    files*: seq[string]

  VFSLocal* = ref object of VFS
    watcher: Watcher
    updateRate: int
    cache: Table[string, CachedFile]

proc process(self: VFSLocal) {.async.}

proc new*(_: typedesc[VFSLocal]): VFSLocal =
  new(result)
  result.watcher = initWatcher()
  result.updateRate = 200

  asyncSpawn result.process()

proc cacheFile*(self: VFSLocal, path: string) =
  self.cache[path] = CachedFile(fut: self.readImpl(path, {ReadFlag.Binary}))

proc cacheDir*(self: VFSLocal, path: string, ignore: Globs) =
  try:
    for (kind, name) in walkDir(path, relative=true):
      case kind
      of pcFile:
        let filePath = path // name
        if ignore.ignorePath(filePath):
          continue
        self.cacheFile(filePath)
      # of pcLinkToFile:
      #   directoryListing.files.add name
      else:
        discard

  except OSError:
    discard

proc process(self: VFSLocal) {.async.} =
  while true:
    await sleepAsync(self.updateRate.milliseconds)
    try:
      process(self.watcher)
    except Exception as e:
      log lvlError, &"Failed to process file watcher: {e.msg}"

proc subscribe*(self: VFSLocal, path: string, cb: proc(events: seq[PathEvent]) {.gcsafe, raises: [].}): Id =
  try:
    proc cbWrapper(events: seq[PathEvent]) {.gcsafe, raises: [].} = cb(events.deduplicate(isSorted = true))
    register(self.watcher, path, cbWrapper)
    # todo
    return newId()
  except OSError as e:
    log lvlError, &"Failed to register file watcher for '{path}': {e.msg}"
    return idNone()

method normalizeImpl*(self: VFSLocal, path: string): string =
  return path.normalizePath.normalizeNativePath

method watchImpl*(self: VFSLocal, path: string, cb: proc(events: seq[PathEvent]) {.gcsafe, raises: [].}): Id =
  log lvlInfo, &"Register watcher for local file system at '{path}'"
  return self.subscribe(path, cb)

# todo: unwatch

proc loadFileThread(args: tuple[path: string, data: ptr string, invalidUtf8Error: ptr bool, flags: set[ReadFlag]]): bool =
  try:
    args.data[] = readFile(args.path)

    if ReadFlag.Binary notin args.flags:
      let invalidUtf8Index = args.data[].validateUtf8
      if invalidUtf8Index >= 0:
        args.data[] = &"Invalid utf-8 byte at {invalidUtf8Index}"
        args.invalidUtf8Error[] = true
        return false

    return true

  except:
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

method name*(self: VFSLocal): string = &"VFSLocal({self.prefix})"

method readImpl*(self: VFSLocal, path: string, flags: set[ReadFlag]): Future[string] {.async: (raises: [IOError]).} =
  if not path.isAbsolute:
    raise newException(IOError, &"Path not absolute '{path}'")
  if self.cache.contains(path):
    let fut = self.cache[path].fut
    self.cache.del(path)
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

proc loadFileRopeThread(args: tuple[path: string, data: ptr Rope, err: ptr ref CatchableError, cancel: ptr Atomic[bool], threadDone: ptr Atomic[bool]]) =
  try:
    let s = newFileStream(args.path, fmRead, 1024)
    if s.isNil:
      args.err[] = newException(IOError, &"Failed to open file for reading: {args.path}")
      args.threadDone[].store(true)
      return

    defer:
      s.close()

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

method readRopeImpl*(self: VFSLocal, path: string, rope: ptr Rope): Future[void] {.async: (raises: [IOError]).} =
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

method writeImpl*(self: VFSLocal, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  if not path.isAbsolute:
    raise newException(IOError, &"Path not absolute '{path}'")

  try:
    logScope lvlInfo, &"[saveFile] '{path}'"
    let (ok, err) = await spawnAsync(writeFileThread, (path, content))
    if not ok:
      raise newException(IOError, err)
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

method writeImpl*(self: VFSLocal, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  if not path.isAbsolute:
    raise newException(IOError, &"Path not absolute '{path}'")

  try:
    logScope lvlInfo, &"[saveFile (rope)] '{path}'"
    let (ok, err) = await spawnAsync(writeRopeThread, (path, content))
    if not ok:
      raise newException(IOError, err)

  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

method deleteImpl*(self: VFSLocal, path: string): Future[bool] {.async: (raises: []).} =
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

method createDirImpl*(self: VFSLocal, path: string): Future[void] {.async: (raises: [IOError]).} =
  if not path.isAbsolute:
    raise newException(IOError, &"Path not absolute '{path}'")

  try:
    createDir(path)
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

method getFileKindImpl*(self: VFSLocal, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  if fileExists(path):
    return FileKind.File.some
  if dirExists(path):
    return FileKind.Directory.some

  return FileKind.none

method getFileAttributesImpl*(self: VFSLocal, path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
  try:
    let permissions = path.getFilePermissions()
    # log lvlInfo, &"[isFileReadOnly] Permissions for '{path}': {permissions}"
    return FileAttributes(writable: fpUserWrite in permissions, readable: fpUserRead in permissions).some
  except:
    return FileAttributes.none

method setFileAttributesImpl*(self: VFSLocal, path: string, attributes: FileAttributes): Future[void] {.async: (raises: [IOError]).} =
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

method getDirectoryListingImpl*(self: VFSLocal, path: string): Future[DirectoryListing] {.async: (raises: []).} =
  if path.len == 0:
    when defined(windows):
      var chars: array[1024, char]
      let len = GetLogicalDriveStringsA(chars.len.DWORD, cast[LPSTR](chars[0].addr)).int
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

method copyFileImpl*(self: VFSLocal, src: string, dest: string): Future[void] {.async: (raises: [IOError]).} =
  try:
    let dir = dest.splitPath.head
    createDir(dir)
    copyFileWithPermissions(src, dest)
  except Exception as e:
    raise newException(IOError, &"Failed to copy file '{src}' to '{dest}': {e.msg}", e)

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

method findFilesImpl*(self: VFSLocal, root: string, filenameRegex: string, maxResults: int = int.high, options: FindFilesOptions = FindFilesOptions()): Future[seq[string]] {.async: (raises: []).} =
  var res = newSeq[string]()
  try:
    var options = options
    await spawnAsync(findFileThread, (root, filenameRegex, maxResults, res.addr, options.addr))
  except Exception as e:
    log lvlError, &"Failed to find files in {self.name}/{root}: {e.msg}"
  return res


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
    UNI_SUR_HIGH_END = 0xDBFF
    UNI_SUR_LOW_START = 0xDC00
    UNI_SUR_LOW_END = 0xDFFF
    UNI_REPL = 0xFFFD

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

    template ones(n: untyped): untyped = ((1 shl n)-1)
    iterator `$`(w: WideCString, estimate: int, replacement: int = 0xFFFD): char =
      var i = 0
      while w[i].int16 != 0'i16:
        var ch = ord(w[i])
        inc i
        if ch >= UNI_SUR_HIGH_START and ch <= UNI_SUR_HIGH_END:
          # If the 16 bits following the high surrogate are in the source buffer...
          let ch2 = ord(w[i])

          # If it's a low surrogate, convert to UTF32:
          if ch2 >= UNI_SUR_LOW_START and ch2 <= UNI_SUR_LOW_END:
            ch = (((ch and halfMask) shl halfShift) + (ch2 and halfMask)) + halfBase
            inc i
          else:
            #invalid UTF-16
            ch = replacement
        elif ch >= UNI_SUR_LOW_START and ch <= UNI_SUR_LOW_END:
          #invalid UTF-16
          ch = replacement

        if ch < 0x80:
          yield chr(ch)
        elif ch < 0x800:
          yield chr((ch shr 6) or 0xc0)
          yield chr((ch and 0x3f) or 0x80)
        elif ch < 0x10000:
          yield chr((ch shr 12) or 0xe0)
          yield chr(((ch shr 6) and 0x3f) or 0x80)
          yield chr((ch and 0x3f) or 0x80)
        elif ch <= 0x10FFFF:
          yield chr((ch shr 18) or 0xf0)
          yield chr(((ch shr 12) and 0x3f) or 0x80)
          yield chr(((ch shr 6) and 0x3f) or 0x80)
          yield chr((ch and 0x3f) or 0x80)
        else:
          # replacement char(in case user give very large number):
          yield chr(0xFFFD shr 12 or 0b1110_0000)
          yield chr(0xFFFD shr 6 and ones(6) or 0b10_0000_00)
          yield chr(0xFFFD and ones(6) or 0b10_0000_00)
else:
  import std/posix
  import std/private/oscommon

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
    # echo "scan '", res.name, "'"
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

