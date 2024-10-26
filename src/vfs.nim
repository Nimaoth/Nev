import std/[options, strutils, tables, os]
import nimsumtree/rope
import misc/[custom_async, util, custom_logger, cancellation_token, regex]

{.push gcsafe.}
{.push raises: [].}

logCategory "VFS"

const debugLogVfs* = false

type
  FileNotFoundError* = object of IOError

  DirectoryListing* = object
    files*: seq[string]
    folders*: seq[string]

  FileKind* = enum File, Directory
  FileAttributes* = object
    writable*: bool
    readable*: bool

  ReadFlag* = enum Binary

  VFS* = ref object of RootObj
    mounts: seq[tuple[prefix: string, vfs: VFS]]  ## Seq because I assume the amount of entries will be very small.
    parent: Option[VFS]
    prefix*: string

  VFSNull* = ref object of VFS
    discard

  VFSInMemory* = ref object of VFS
    files: Table[string, string]

  VFSLink* = ref object of VFS
    target*: VFS
    targetPrefix*: string

proc getVFS*(self: VFS, path: openArray[char], maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string]
proc read*(self: VFS, path: string, flags: set[ReadFlag] = {}): Future[string] {.async: (raises: [IOError]).}
proc write*(self: VFS, path: string, content: string): Future[void] {.async: (raises: [IOError]).}
proc write*(self: VFS, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).}
proc getFileKind*(self: VFS, path: string): Future[Option[FileKind]] {.async: (raises: []).}
proc getFileAttributes*(self: VFS, path: string): Future[Option[FileAttributes]] {.async: (raises: []).}
proc setFileAttributes*(self: VFS, path: string, attributes: FileAttributes): Future[void] {.async: (raises: [IOError]).}
proc normalize*(self: VFS, path: string): string
proc getDirectoryListing*(self: VFS, path: string): Future[DirectoryListing] {.async: (raises: []).}
proc copyFile*(self: VFS, src: string, dest: string): Future[void] {.async: (raises: [IOError]).}
proc findFiles*(self: VFS, root: string, filenameRegex: string, maxResults: int = int.high): Future[seq[string]] {.async: (raises: []).}

proc normalizePathUnix*(path: string): string =
  var stripLeading = false
  var stripTrailing = true
  if path.startsWith("/") and path.len >= 3 and path[2] == ':':
    # Windows path: /C:/...
    stripLeading = true

  if path.endsWith("://"):
    stripTrailing = false

  result = path.normalizedPath.replace('\\', '/').strip(leading=stripLeading, trailing=stripTrailing, chars={'/'})
  if result.len >= 2 and result[1] == ':':
    result[0] = result[0].toUpperAscii

proc normalizeNativePath*(path: string): string =
  var stripLeading = false
  var stripTrailing = true
  when defined(windows):
    if path.startsWith("/") and path.len >= 3 and path[2] == ':':
      # Windows path: /C:/...
      stripLeading = true
    result = path.replace('\\', '/')
  else:
    result = path

  if path.endsWith("://"):
    stripTrailing = false

  result = result.strip(leading=stripLeading, trailing=stripTrailing, chars={'/'})
  when defined(windows):
    if result.len >= 2 and result[1] == ':':
      result[0] = result[0].toUpperAscii

proc parentDirectory*(path: string): string =
  # defer:
  #   debugf"parentDir '{path}' -> '{result}'"
  let index = path.rfind("/")
  if index == -1:
    return ""

  let index2 = path.find("://")
  if index2 >= 0 and index2 + 2 == index:
    if index == path.high:
      return ""
    return path[0..index]

  return path[0..<index]

proc `//`*(a: string, b: string): string =
  # defer:
  #   echo &"'{a}' // '{b}' -> '{result}'"
  if a.endsWith("://"):
    return a & b
  if a.len == 0:
    return b

  let aHasSep = a.endsWith("/")
  let bHasSep = b.startsWith("/")

  result = newStringOfCap(a.len + b.len + 1)
  result.add(a)
  if aHasSep and bHasSep:
    result.setLen(result.len - 1)
    result.add(b)
  elif aHasSep xor bHasSep:
    result.add(b)
  else:
    result.add("/")
    result.add(b)

proc newInMemoryVFS*(): VFSInMemory = VFSInMemory(files: initTable[string, string]())

method name*(self: VFS): string {.base.} = &"VFS({self.prefix})"

method readImpl*(self: VFS, path: string, flags: set[ReadFlag]): Future[string] {.base, async: (raises: [IOError]).} =
  raise newException(IOError, "Not implemented")

method writeImpl*(self: VFS, path: string, content: string): Future[void] {.base, async: (raises: [IOError]).} =
  discard

method writeImpl*(self: VFS, path: string, content: sink RopeSlice[int]): Future[void] {.base, async: (raises: [IOError]).} =
  discard

method getFileKindImpl*(self: VFS, path: string): Future[Option[FileKind]] {.base, async: (raises: []).} =
  return FileKind.none

method getFileAttributesImpl*(self: VFS, path: string): Future[Option[FileAttributes]] {.base, async: (raises: []).} =
  return FileAttributes.none

method setFileAttributesImpl*(self: VFS, path: string, attributes: FileAttributes): Future[void] {.base, async: (raises: [IOError]).} =
  discard

method getVFSImpl*(self: VFS, path: openArray[char], maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string] {.base.} =
  (nil, "")

method getDirectoryListingImpl*(self: VFS, path: string): Future[DirectoryListing] {.base, async: (raises: []).} =
  discard

method copyFileImpl*(self: VFS, src: string, dest: string): Future[void] {.base, async: (raises: [IOError]).} =
  discard

method findFilesImpl*(self: VFS, root: string, filenameRegex: string, maxResults: int = int.high): Future[seq[string]] {.base, async: (raises: []).} =
  return @[]

proc prettyHierarchy*(self: VFS): string =
  result.add self.name
  for m in self.mounts:
    result.add "\n"
    result.add ("'" & m.prefix & "' -> " & m.vfs.prettyHierarchy()).indent(2)

########################################################

method name*(self: VFSNull): string = &"VFSNull({self.prefix})"

method readImpl*(self: VFSNull, path: string, flags: set[ReadFlag]): Future[string] {.async: (raises: [IOError]).} =
  raise newException(IOError, "VFSNull: File not found '" & path & "'")

method writeImpl*(self: VFSNull, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  discard

method writeImpl*(self: VFSNull, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  discard

method getFileKindImpl*(self: VFSNull, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  return FileKind.none

method getFileAttributesImpl*(self: VFSNull, path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
  return FileAttributes.none

method getDirectoryListingImpl*(self: VFSNull, path: string): Future[DirectoryListing] {.async: (raises: []).} =
  discard

method name*(self: VFSLink): string = &"VFSLink({self.prefix}, {self.target.name}/{self.targetPrefix})"

method readImpl*(self: VFSLink, path: string, flags: set[ReadFlag]): Future[string] {.async: (raises: [IOError]).} =
  return self.target.read(self.targetPrefix // path, flags).await

method writeImpl*(self: VFSLink, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  await self.target.write(self.targetPrefix // path, content)

method writeImpl*(self: VFSLink, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  await self.target.write(self.targetPrefix // path, content.move)

method getFileKindImpl*(self: VFSLink, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  return self.target.getFileKind(path).await

method getFileAttributesImpl*(self: VFSLink, path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
  return self.target.getFileAttributes(path).await

method setFileAttributesImpl*(self: VFSLink, path: string, attributes: FileAttributes): Future[void] {.async: (raises: [IOError]).} =
  await self.target.setFileAttributes(path, attributes)

method getDirectoryListingImpl*(self: VFSLink, path: string): Future[DirectoryListing] {.async: (raises: []).} =
  return self.target.getDirectoryListing(self.targetPrefix // path).await

method getVFSImpl*(self: VFSLink, path: openArray[char], maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string] =
  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' getVFSImpl({path.join()}) -> ({self.target.name}, {self.target.prefix}), '{self.targetPrefix // path.join()}'"

  if maxDepth == 0:
    return (self, path.join())

  return self.target.getVFS(self.targetPrefix // path.join(), maxDepth - 1)

method copyFileImpl*(self: VFSLink, src: string, dest: string): Future[void] {.async: (raises: [IOError]).} =
  await self.target.copyFile(src, dest)

method name*(self: VFSInMemory): string = &"VFSInMemory({self.prefix})"

method readImpl*(self: VFSInMemory, path: string, flags: set[ReadFlag]): Future[string] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"VFSInMemory.read({path})"
  self.files.withValue(path, file):
    return file[]
  raise newException(IOError, "VFSInMemory: File not found '" & path & "'")

method writeImpl*(self: VFSInMemory, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"VFSInMemory.write({path})"
  self.files[path] = content

method writeImpl*(self: VFSInMemory, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"VFSInMemory.write({path})"
  self.files[path] = $content

method getFileKindImpl*(self: VFSInMemory, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  if path in self.files:
    return FileKind.File.some
  return FileKind.none

method getFileAttributesImpl*(self: VFSInMemory, path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
  if path in self.files:
    return FileAttributes(writable: true, readable: true).some
  return FileAttributes.none

method getDirectoryListingImpl*(self: VFSInMemory, path: string): Future[DirectoryListing] {.async: (raises: []).} =
  for file in self.files.keys:
    if file.startsWith(path):
      result.files.add file

method copyFileImpl*(self: VFSInMemory, src: string, dest: string): Future[void] {.async: (raises: [IOError]).} =
  if src in self.files:
    self.files[dest] = self.files[src]
  else:
    raise newException(IOError, &"Failed to copy non-existing file '{src}' to '{dest}'")

proc getVFS*(self: VFS, path: openArray[char], maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string] =
  # when debugLogVfs:
  #   echo &"getVFS {self.name} '{path.join()}'"
  #   defer:
  #     echo &"  -> getVFS {self.name} '{path.join()}' -> {result.vfs.name} '{result.relativePath}'"

  if maxDepth == 0:
    return (self, path.join())

  for i in countdown(self.mounts.high, 0):
    template pref(): untyped = self.mounts[i].prefix

    if path.startsWith(pref.toOpenArray()) and (pref.len == 0 or path.len == pref.len or pref.endsWith(['/']) or path[pref.len] == '/'):
      var prefixLen = pref.len
      if pref.len > 0 and not pref.endsWith(['/']) and path.len > pref.len:
        inc prefixLen

      when debugLogVfs:
        debugf"[{self.name}] '{self.prefix}' foward({path.join()}) to ({self.mounts[i].vfs.name}, {self.mounts[i].vfs.prefix})"
      return self.mounts[i].vfs.getVFS(path[prefixLen..^1], maxDepth - 1)

  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' getVFSImpl({path.join()})"
  result = self.getVFSImpl(path, maxDepth) # todo: maxDepth - 1?
  if result.vfs.isNil:
    result = (self, path.join(""))

proc fullPrefix*(self: VFS): string =
  var vfs = self
  while vfs.parent.getSome(parent):
    result = vfs.prefix // result
    vfs = parent

proc localize*(self: VFS, path: string): string =
  return self.getVFS(path).relativePath.normalizeNativePath

proc normalize*(self: VFS, path: string): string =
  var (vfs, path) = self.getVFS(path)
  while vfs.parent.getSome(parent):
    path = vfs.prefix // path
    vfs = parent

  return path.normalizeNativePath

proc read*(self: VFS, path: string, flags: set[ReadFlag] = {}): Future[string] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' read({path})"
  let (vfs, path) = self.getVFS(path)
  return await vfs.readImpl(path, flags)

proc write*(self: VFS, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' write({path})"
  let (vfs, path) = self.getVFS(path)
  await vfs.writeImpl(path, content)

proc write*(self: VFS, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' write({path})"
  let (vfs, path) = self.getVFS(path)
  await vfs.writeImpl(path, content.move)

proc getFileKind*(self: VFS, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  let (vfs, path) = self.getVFS(path)
  return await vfs.getFileKindImpl(path)

proc getFileAttributes*(self: VFS, path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
  let (vfs, path) = self.getVFS(path)
  return await vfs.getFileAttributesImpl(path)

proc setFileAttributes*(self: VFS, path: string, attributes: FileAttributes): Future[void] {.async: (raises: [IOError]).} =
  let (vfs, path) = self.getVFS(path)
  await vfs.setFileAttributesImpl(path, attributes)

proc getDirectoryListing*(self: VFS, path: string): Future[DirectoryListing] {.async: (raises: []).} =
  let (vfs, relativePath) = self.getVFS(path)
  if vfs == self:
    result = await self.getDirectoryListingImpl(relativePath)
  else:
    result = await vfs.getDirectoryListing(relativePath)

  if path.len == 0:
    for m in self.mounts:
      if m.prefix == path:
        continue
      result.folders.add m.prefix

proc copyFile*(self: VFS, src: string, dest: string): Future[void] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' copyFile('{src}', '{dest}')"
  let (srcVfs, srcRelativePath) = self.getVFS(src)
  let (destVfs, destRelativePath) = self.getVFS(dest)
  if srcVfs == destVfs:
    await srcVfs.copyFileImpl(src, dest)
  else:
    # todo: this could be done better with streams
    log lvlWarn, &"Copy file using slow method: '{src}' to '{dest}'"
    let content = srcVfs.read(srcRelativePath, {Binary}).await
    await destVfs.write(destRelativePath, content)

proc findFiles*(self: VFS, root: string, filenameRegex: string, maxResults: int = int.high): Future[seq[string]] {.async: (raises: []).} =
  ## Recursively searches for files in all sub directories of `root` (including `root`).
  ## Returned paths are relative to `root`

  # todo: support root which contains other VFSs
  let (vfs, relativePath) = self.getVFS(root)
  return await vfs.findFilesImpl(relativePath, filenameRegex, maxResults)

proc unmount*(self: VFS, prefix: string) =
  log lvlInfo, &"{self.name}: unmount '{prefix}'"
  for i in 0..self.mounts.high:
    if self.mounts[i].prefix == prefix:
      self.mounts[i].vfs.prefix = ""
      self.mounts[i].vfs.parent = VFS.none
      self.mounts.removeShift(i)
      return

proc mount*(self: VFS, prefix: string, vfs: VFS) =
  assert vfs.parent.isNone
  log lvlInfo, &"{self.name}: mount {vfs.name} under '{prefix}'"
  for i in 0..self.mounts.high:
    if self.mounts[i].prefix == prefix:
      self.mounts[i].vfs.parent = VFS.none
      self.mounts[i].vfs.prefix = ""
      vfs.parent = self.some
      vfs.prefix = prefix
      self.mounts[i] = (prefix, vfs)
      return
  vfs.parent = self.some
  vfs.prefix = prefix
  self.mounts.add (prefix, vfs)

proc ignorePath*(ignore: Globs, path: string): bool =
  if ignore.excludePath(path) or ignore.excludePath(path.extractFilename):
    if ignore.includePath(path) or ignore.includePath(path.extractFilename):
      return false

    return true
  return false

proc getDirectoryListingRec*(vfs: VFS, ignore: Globs, path: string): Future[seq[string]] {.async.} =
  var resultItems: seq[string]

  let items = await vfs.getDirectoryListing(path)
  for file in items.files:
    let fullPath = path // file

    if ignore.ignorePath(fullPath):
      continue

    resultItems.add(fullPath)

  var futs: seq[Future[seq[string]]]

  for dir in items.folders:
    let fullPath = path // dir

    if ignore.ignorePath(fullPath):
      continue

    futs.add getDirectoryListingRec(vfs, ignore, fullPath)

  for fut in futs:
    let children = await fut
    resultItems.add children

  return resultItems

proc iterateDirectoryRec*(vfs: VFS, path: string, cancellationToken: CancellationToken, ignore: Globs, callback: proc(files: seq[string]): Future[void] {.raises: [CancelledError]}): Future[void] {.async.} =
  let path = path
  var resultItems: seq[string]
  var folders: seq[string]

  if cancellationToken.canceled:
    return

  try:
    let items = await vfs.getDirectoryListing(path)

    if cancellationToken.canceled:
      return

    for file in items.files:
      let fullPath = path // file
      if ignore.ignorePath(fullPath):
        continue
      resultItems.add(fullPath)

    for dir in items.folders:
      let fullPath = path // dir
      if ignore.ignorePath(fullPath):
        continue
      folders.add(fullPath)
  except CatchableError:
    discard

  await sleepAsync(10.milliseconds)

  try:
    await callback(resultItems)
  except CatchableError:
    discard

  if cancellationToken.canceled:
    return

  var futs: seq[Future[void]]

  for dir in folders:
    futs.add iterateDirectoryRec(vfs, dir, cancellationToken, ignore, callback)

  for fut in futs:
    try:
      await fut
    except CatchableError:
      discard

  return
