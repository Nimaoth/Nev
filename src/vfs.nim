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

proc getVFS*(self: VFS, path: string, maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string]
proc read*(self: VFS, path: string, flags: set[ReadFlag] = {}): Future[string] {.async: (raises: [IOError]).}
proc write*(self: VFS, path: string, content: string): Future[void] {.async: (raises: [IOError]).}
proc write*(self: VFS, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).}
proc getFileKind*(self: VFS, path: string): Future[Option[FileKind]] {.async: (raises: []).}
proc getFileAttributes*(self: VFS, path: string): Future[Option[FileAttributes]] {.async: (raises: []).}
proc normalize*(self: VFS, path: string): string
proc getDirectoryListing*(self: VFS, path: string): Future[DirectoryListing] {.async: (raises: []).}

proc normalizePathUnix*(path: string): string =
  var stripLeading = false
  if path.startsWith("/") and path.len >= 3 and path[2] == ':':
    # Windows path: /C:/...
    stripLeading = true
  result = path.normalizedPath.replace('\\', '/').strip(leading=stripLeading, chars={'/'})
  if result.len >= 2 and result[1] == ':':
    result[0] = result[0].toUpperAscii

proc normalizeNativePath*(path: string): string =
  var stripLeading = false
  when defined(windows):
    if path.startsWith("/") and path.len >= 3 and path[2] == ':':
      # Windows path: /C:/...
      stripLeading = true
    result = path.replace('\\', '/')
  result = result.strip(leading=stripLeading, chars={'/'})
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

method getVFSImpl*(self: VFS, path: string, maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string] {.base.} =
  (nil, "")

method normalizeImpl*(self: VFS, path: string): string {.base.} =
  path

method getDirectoryListingImpl*(self: VFS, path: string): Future[DirectoryListing] {.base, async: (raises: []).} =
  discard

proc prettyHierarchy*(self: VFS): string =
  result.add self.name
  for m in self.mounts:
    result.add "\n"
    result.add (m.prefix & " -> " & m.vfs.prettyHierarchy()).indent(2)

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
  return self.target.read(self.targetPrefix & path, flags).await

method writeImpl*(self: VFSLink, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  await self.target.write(self.targetPrefix & path, content)

method writeImpl*(self: VFSLink, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  await self.target.write(self.targetPrefix & path, content.move)

method getFileKindImpl*(self: VFSLink, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  return self.target.getFileKind(path).await

method getFileAttributesImpl*(self: VFSLink, path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
  return self.target.getFileAttributes(path).await

method normalizeImpl*(self: VFSLink, path: string): string =
  return self.target.normalize(self.targetPrefix & path)

method getDirectoryListingImpl*(self: VFSLink, path: string): Future[DirectoryListing] {.async: (raises: []).} =
  return self.target.getDirectoryListing(self.targetPrefix & path).await

method getVFSImpl*(self: VFSLink, path: string, maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string] =
  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' getVFSImpl({path}) -> ({self.target.name}, {self.target.prefix}), '{self.targetPrefix & path}'"

  if maxDepth == 0:
    return (self, path)

  return self.target.getVFS(self.targetPrefix & path)

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

proc getVFS*(self: VFS, path: string, maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string] =
  # echo &"getVFS {self.name} '{path}'"
  # defer:
  #   echo &"  -> getVFS {self.name} '{path}' -> {result.vfs.name} '{result.relativePath}'"

  if maxDepth == 0:
    return (self, path)

  for i in countdown(self.mounts.high, 0):
    if path.startsWith(self.mounts[i].prefix):
      when debugLogVfs:
        debugf"[{self.name}] '{self.prefix}' foward({path}) to ({self.mounts[i].vfs.name}, {self.mounts[i].vfs.prefix})"
      return self.mounts[i].vfs.getVFS(path[self.mounts[i].prefix.len..^1], maxDepth - 1)

  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' getVFSImpl({path})"
  result = self.getVFSImpl(path, maxDepth) # todo: maxDepth - 1?
  if result.vfs.isNil:
    result = (self, path)

proc read*(self: VFS, path: string, flags: set[ReadFlag] = {}): Future[string] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' read({path})"
  let (vfs, path) = self.getVFS(path)
  if vfs == self:
    result = await self.readImpl(path, flags)
  else:
    result = await vfs.read(path, flags)

proc write*(self: VFS, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' write({path})"
  let (vfs, path) = self.getVFS(path)
  if vfs == self:
    await self.writeImpl(path, content)
  else:
    await vfs.write(path, content)

proc write*(self: VFS, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' write({path})"
  let (vfs, path) = self.getVFS(path)
  if vfs == self:
    await self.writeImpl(path, content.move)
  else:
    await vfs.write(path, content.move)

proc getFileKind*(self: VFS, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  let (vfs, path) = self.getVFS(path)
  if vfs == self:
    return await self.getFileKindImpl(path)
  else:
    return await vfs.getFileKind(path)

proc getFileAttributes*(self: VFS, path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
  let (vfs, path) = self.getVFS(path)
  if vfs == self:
    return await self.getFileAttributesImpl(path)
  else:
    return await vfs.getFileAttributes(path)

proc normalize*(self: VFS, path: string): string =
  # defer:
  #   echo &"normalize '{path}' -> '{result}'"

  var (vfs, path) = self.getVFS(path)
  while vfs.parent.getSome(parent):
    path = vfs.prefix & path
    vfs = parent

  return path

proc getDirectoryListing*(self: VFS, path: string): Future[DirectoryListing] {.async: (raises: []).} =
  # defer:
  #   echo &"getDirectoryListing '{path}': '{self.prefix}' -> {self.name}\n{result}"
  let (vfs, relativePath) = self.getVFS(path)
  if vfs == self:
    result = await self.getDirectoryListingImpl(relativePath)
  else:
    result = await vfs.getDirectoryListing(relativePath)

  if path.len == 0:
    for m in self.mounts:
      result.folders.add m.prefix

proc mount*(self: VFS, prefix: string, vfs: VFS) =
  assert vfs.parent.isNone
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
