import std/[options, strutils, tables, os, random, strformat, locks]
import nimsumtree/[rope, arc]
import misc/[custom_async, util, custom_logger, regex, id]
import fsnotify

export fsnotify.PathEvent, fsnotify.FileEventAction

{.push gcsafe.}
{.push raises: [].}

logCategory "VFS"

const debugLogVfs* = false

type
  FileNotFoundError* = object of IOError
  InvalidUtf8Error* = object of IOError

  Directory* = object
    path*: string
    totalFiles*: int
    children*: seq[Directory]
    files*: seq[string]

  DirectoryListing* = object
    files*: seq[string]
    folders*: seq[string]

  FileKind* {.pure.} = enum File, Directory
  FileAttributes* = object
    writable*: bool
    readable*: bool

  ReadFlag* = enum Binary

  VFSInMemoryItemKind* {.pure.} = enum String, Rope
  VFSInMemoryItem* = object
    case kind: VFSInMemoryItemKind
    of VFSInMemoryItemKind.String:
      text: string
    of VFSInMemoryItemKind.Rope:
      rope: Rope

  VFSInMemory2* = object
    lock: Lock
    files: Table[string, VFSInMemoryItem]
    handlers: Table[string, seq[(Id, proc(events: seq[PathEvent]) {.gcsafe, raises: [].})]]

  FindFilesOptions* = object
    maxDepth*: int = int.high
    maxResults*: int = int.high

  VFS2* = object
    impl*: pointer
    mounts*: seq[tuple[prefix: string, vfs: Arc[VFS2]]]  ## Seq because I assume the amount of entries will be very small.
    parent*: Option[Arc[VFS2]]
    prefix*: string
    nameImpl*: proc(self: Arc[VFS2]): string {.nimcall, gcsafe, raises: [].}
    normalizeImpl*: proc(self: Arc[VFS2], path: string): string {.nimcall, gcsafe, raises: [].}
    readImpl*: proc(self: Arc[VFS2], path: string, flags: set[ReadFlag]): Future[string] {.nimcall, async: (raises: [IOError]).}
    readRopeImpl*: proc(self: Arc[VFS2], path: string, rope: ptr Rope): Future[void] {.nimcall, async: (raises: [IOError]).}
    writeImpl*: proc(self: Arc[VFS2], path: string, content: string): Future[void] {.nimcall, async: (raises: [IOError]).}
    writeRopeImpl*: proc(self: Arc[VFS2], path: string, content: sink RopeSlice[int]): Future[void] {.nimcall, async: (raises: [IOError]).}
    deleteImpl*: proc(self: Arc[VFS2], path: string): Future[bool] {.nimcall, async: (raises: []).}
    createDirImpl*: proc(self: Arc[VFS2], path: string): Future[void] {.nimcall, async: (raises: [IOError]).}
    getFileKindImpl*: proc(self: Arc[VFS2], path: string): Future[Option[FileKind]] {.nimcall, async: (raises: []).}
    getFileAttributesImpl*: proc(self: Arc[VFS2], path: string): Future[Option[FileAttributes]] {.nimcall, async: (raises: []).}
    setFileAttributesImpl*: proc(self: Arc[VFS2], path: string, attributes: FileAttributes): Future[void] {.nimcall, async: (raises: [IOError]).}
    watchImpl*: proc(self: Arc[VFS2], path: string, cb: proc(events: seq[PathEvent]) {.gcsafe, raises: [].}): Id {.nimcall, gcsafe, raises: []}
    unwatchImpl*: proc(self: Arc[VFS2], id: Id) {.nimcall, gcsafe, raises: [].}
    getVFSImpl*: proc(self: Arc[VFS2], path: openArray[char], maxDepth: int = int.high): tuple[vfs: Arc[VFS2], relativePath: string] {.nimcall, gcsafe, raises: [].}
    getDirectoryListingImpl*: proc(self: Arc[VFS2], path: string): Future[DirectoryListing] {.nimcall, async: (raises: []).}
    copyFileImpl*: proc(self: Arc[VFS2], src: string, dest: string): Future[void] {.nimcall, async: (raises: [IOError]).}
    findFilesImpl*: proc(self: Arc[VFS2], root: string, filenameRegex: string, maxResults: int = int.high, options: FindFilesOptions = FindFilesOptions()): Future[seq[string]] {.nimcall, async: (raises: []).}

  VFS* = Arc[VFS2]

  VFSLink2* = object
    target*: VFS
    targetPrefix*: string

  VFSWatchHandle* = object
    path*: string
    vfs: VFS
    id: Id

proc isVfsPath*(path: string): bool =
  let index = path.find("://")
  if index == -1:
    return false
  let index2 = path.find(":")
  if index2 != index:
    return
  return true

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

proc `//`*(a: string, b: string): string {.gcsafe, raises: [].} =
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

proc nameImpl*(self: VFS): string {.gcsafe, raises: [].} =
  if self.get.nameImpl != nil:
    self.get.nameImpl(self)
  else:
    &"VFS({self.get.prefix})"

proc name*(self: VFS): string {.gcsafe, raises: [].} = self.nameImpl
proc `$`*(self: VFS): string {.gcsafe, raises: [].} = self.nameImpl

proc normalizeImpl*(self: VFS, path: string): string {.gcsafe, raises: [].} =
  if self.get.normalizeImpl != nil:
    self.get.normalizeImpl(self, path)
  else:
    path

proc readImpl*(self: VFS, path: string, flags: set[ReadFlag]): Future[string] {.async: (raises: [IOError]).} =
  if self.get.readImpl != nil:
    self.get.readImpl(self, path, flags).await
  else:
    ""

proc readRopeImpl*(self: VFS, path: string, rope: ptr Rope): Future[void] {.async: (raises: [IOError]).} =
  if self.get.readRopeImpl != nil:
    self.get.readRopeImpl(self, path, rope).await

proc writeImpl*(self: VFS, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  if self.get.writeImpl != nil:
    self.get.writeImpl(self, path, content).await

proc writeImpl*(self: VFS, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  if self.get.writeRopeImpl != nil:
    self.get.writeRopeImpl(self, path, content).await

proc deleteImpl*(self: VFS, path: string): Future[bool] {.async: (raises: []).} =
  if self.get.deleteImpl != nil:
    self.get.deleteImpl(self, path).await
  else:
    false

proc createDirImpl*(self: VFS, path: string): Future[void] {.async: (raises: [IOError]).} =
  if self.get.createDirImpl != nil:
    self.get.createDirImpl(self, path).await

proc getFileKindImpl*(self: VFS, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  if self.get.getFileKindImpl != nil:
    self.get.getFileKindImpl(self, path).await
  else:
    FileKind.none

proc getFileAttributesImpl*(self: VFS, path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
  if self.get.getFileAttributesImpl != nil:
    self.get.getFileAttributesImpl(self, path).await
  else:
    FileAttributes.none

proc setFileAttributesImpl*(self: VFS, path: string, attributes: FileAttributes): Future[void] {.async: (raises: [IOError]).} =
  if self.get.setFileAttributesImpl != nil:
    self.get.setFileAttributesImpl(self, path, attributes).await

proc watchImpl*(self: VFS, path: string, cb: proc(events: seq[PathEvent]) {.gcsafe, raises: [].}): Id {.gcsafe, raises: []} =
  if self.get.watchImpl != nil:
    self.get.watchImpl(self, path, cb)
  else:
    idNone()

proc unwatchImpl*(self: VFS, id: Id) {.gcsafe, raises: [].} =
  if self.get.unwatchImpl != nil:
    self.get.unwatchImpl(self, id)

proc getVFSImpl*(self: VFS, path: openArray[char], maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string] {.gcsafe, raises: [].} =
  if self.get.getVFSImpl != nil:
    self.get.getVFSImpl(self, path, maxDepth)
  else:
    (self, path.join())

proc getDirectoryListingImpl*(self: VFS, path: string): Future[DirectoryListing] {.async: (raises: []).} =
  if self.get.getDirectoryListingImpl != nil:
    self.get.getDirectoryListingImpl(self, path).await
  else:
    DirectoryListing()

proc copyFileImpl*(self: VFS, src: string, dest: string): Future[void] {.async: (raises: [IOError]).} =
  if self.get.copyFileImpl != nil:
    self.get.copyFileImpl(self, src, dest).await

proc findFilesImpl*(self: VFS, root: string, filenameRegex: string, maxResults: int = int.high, options: FindFilesOptions = FindFilesOptions()): Future[seq[string]] {.async: (raises: []).} =
  if self.get.findFilesImpl != nil:
    self.get.findFilesImpl(self, root, filenameRegex, maxResults, options).await
  else:
    @[]

proc vfsName*(self: VFS): string = &"VFS({self.get.prefix})"

proc vfsRead*(self: VFS, path: string, flags: set[ReadFlag]): Future[string] {.gcsafe, async: (raises: [IOError]).} =
  return ""

proc vfsReadRope*(self: VFS, path: string, rope: ptr Rope): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  discard

proc vfsWrite*(self: VFS, path: string, content: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  discard

proc vfsWrite*(self: VFS, path: string, content: sink RopeSlice[int]): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  discard

proc vfsDelete*(self: VFS, path: string): Future[bool] {.gcsafe, async: (raises: []).} =
  return false

proc vfsCreateDir*(self: VFS, path: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  discard

proc vfsGetFileKind*(self: VFS, path: string): Future[Option[FileKind]] {.gcsafe, async: (raises: []).} =
  return FileKind.none

proc vfsGetFileAttributes*(self: VFS, path: string): Future[Option[FileAttributes]] {.gcsafe, async: (raises: []).} =
  return FileAttributes.none

proc vfsSetFileAttributes*(self: VFS, path: string, attributes: FileAttributes): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  discard

proc vfsGetDirectoryListing*(self: VFS, path: string): Future[DirectoryListing] {.gcsafe, async: (raises: []).} =
  return DirectoryListing()

proc vfsGetVFS*(self: VFS, path: openArray[char], maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string] =
  return (self, path.join())

proc vfsCopyFile*(self: VFS, src: string, dest: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  discard

proc newVFS*(): VFS =
  result = VFS.new()
  result.getMutUnsafe.impl = nil
  result.getMutUnsafe.nameImpl = vfsName
  result.getMutUnsafe.readImpl = vfsRead
  result.getMutUnsafe.readRopeImpl = vfsReadRope
  result.getMutUnsafe.writeImpl = vfsWrite
  result.getMutUnsafe.writeRopeImpl = vfsWrite
  result.getMutUnsafe.deleteImpl = vfsDelete
  result.getMutUnsafe.createDirImpl = vfsCreateDir
  result.getMutUnsafe.getFileKindImpl = vfsGetFileKind
  result.getMutUnsafe.getFileAttributesImpl = vfsGetFileAttributes
  result.getMutUnsafe.setFileAttributesImpl = vfsSetFileAttributes
  result.getMutUnsafe.getDirectoryListingImpl = vfsGetDirectoryListing
  result.getMutUnsafe.getVFSImpl = vfsGetVFS
  result.getMutUnsafe.copyFileImpl = vfsCopyFile

proc vfsLinkName*(self: VFS): string =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  return &"VFS({self.get.prefix}, {link.target.nameImpl}/{link.targetPrefix})"

proc vfsLinkRead*(self: VFS, path: string, flags: set[ReadFlag]): Future[string] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  return link.target.readImpl(link.targetPrefix // path, flags).await

proc vfsLinkReadRope*(self: VFS, path: string, rope: ptr Rope): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  link.target.readRopeImpl(link.targetPrefix // path, rope).await

proc vfsLinkWrite*(self: VFS, path: string, content: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  link.target.writeImpl(link.targetPrefix // path, content).await

proc vfsLinkWrite*(self: VFS, path: string, content: sink RopeSlice[int]): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  link.target.writeImpl(link.targetPrefix // path, content.move).await

proc vfsLinkDelete*(self: VFS, path: string): Future[bool] {.gcsafe, async: (raises: []).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  return link.target.deleteImpl(link.targetPrefix // path).await

proc vfsLinkCreateDir*(self: VFS, path: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  link.target.createDirImpl(link.targetPrefix // path).await

proc vfsLinkGetFileKind*(self: VFS, path: string): Future[Option[FileKind]] {.gcsafe, async: (raises: []).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  return link.target.getFileKindImpl(path).await

proc vfsLinkGetFileAttributes*(self: VFS, path: string): Future[Option[FileAttributes]] {.gcsafe, async: (raises: []).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  return link.target.getFileAttributesImpl(path).await

proc vfsLinkSetFileAttributes*(self: VFS, path: string, attributes: FileAttributes): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  link.target.setFileAttributesImpl(path, attributes).await

proc vfsLinkGetDirectoryListing*(self: VFS, path: string): Future[DirectoryListing] {.gcsafe, async: (raises: []).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  return link.target.getDirectoryListingImpl(link.targetPrefix // path).await

proc getVFS*(self: VFS, path: openArray[char], maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string]

proc vfsLinkGetVFS*(self: VFS, path: openArray[char], maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string] =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  when debugLogVfs:
    debugf"[{sgcsafe, elf.name}] '{self.prefix}' getVFSImpl({path.join()}) -> ({link.target.nameImpl}, {link.target.prefix}), '{link.targetPrefix // path.join()}'"

  if maxDepth == 0:
    return (self, path.join())

  return link.target.getVFS(link.targetPrefix // path.join(), maxDepth - 1)

proc vfsLinkCopyFile*(self: VFS, src: string, dest: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  link.target.copyFileImpl(src, dest).await

proc newVFSLink*(target: VFS, prefix: string): VFS =
  let link = create(VFSLink2)
  link.target = target
  link.targetPrefix = prefix

  result = VFS.new()
  result.getMutUnsafe.impl = link
  result.getMutUnsafe.nameImpl = vfsLinkName
  result.getMutUnsafe.readImpl = vfsLinkRead
  result.getMutUnsafe.readRopeImpl = vfsLinkReadRope
  result.getMutUnsafe.writeImpl = vfsLinkWrite
  result.getMutUnsafe.writeRopeImpl = vfsLinkWrite
  result.getMutUnsafe.deleteImpl = vfsLinkDelete
  result.getMutUnsafe.createDirImpl = vfsLinkCreateDir
  result.getMutUnsafe.getFileKindImpl = vfsLinkGetFileKind
  result.getMutUnsafe.getFileAttributesImpl = vfsLinkGetFileAttributes
  result.getMutUnsafe.setFileAttributesImpl = vfsLinkSetFileAttributes
  result.getMutUnsafe.getDirectoryListingImpl = vfsLinkGetDirectoryListing
  result.getMutUnsafe.getVFSImpl = vfsLinkGetVFS
  result.getMutUnsafe.copyFileImpl = vfsLinkCopyFile

proc vfsInMemoryName*(self: VFS): string =
  return &"VFSInMemory()"

proc vfsInMemoryRead*(self: VFS, path: string, flags: set[ReadFlag]): Future[string] {.gcsafe, async: (raises: [IOError]).} =
  let vfs = cast[ptr VFSInMemory2](self.getMutUnsafe.impl)
  withLock vfs.lock:
    vfs.files.withValue(path, file):
      case file[].kind
      of VFSInMemoryItemKind.String:
        return file[].text
      of VFSInMemoryItemKind.Rope:
        return $file[].rope
    raise newException(IOError, "VFSInMemory: File not found '" & path & "'")

proc vfsInMemoryReadRope*(self: VFS, path: string, rope: ptr Rope): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let vfs = cast[ptr VFSInMemory2](self.getMutUnsafe.impl)
  withLock vfs.lock:
    vfs.files.withValue(path, file):
      case file[].kind
      of VFSInMemoryItemKind.String:
        rope[] = Rope.new(file[].text)
      of VFSInMemoryItemKind.Rope:
        rope[] = file[].rope
      return
    raise newException(IOError, "VFSInMemory: File not found '" & path & "'")

proc vfsInMemoryWrite*(self: VFS, path: string, content: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let vfs = cast[ptr VFSInMemory2](self.getMutUnsafe.impl)
  withLock vfs.lock:
    vfs.files[path] = VFSInMemoryItem(kind: VFSInMemoryItemKind.String, text: content)

proc vfsInMemoryWrite*(self: VFS, path: string, content: sink RopeSlice[int]): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let vfs = cast[ptr VFSInMemory2](self.getMutUnsafe.impl)
  withLock vfs.lock:
    vfs.files[path] = VFSInMemoryItem(kind: VFSInMemoryItemKind.Rope, rope: content.toRope)

proc vfsInMemoryDelete*(self: VFS, path: string): Future[bool] {.gcsafe, async: (raises: []).} =
  let vfs = cast[ptr VFSInMemory2](self.getMutUnsafe.impl)
  withLock vfs.lock:
    if path in vfs.files:
      vfs.files.del(path)
      return true

proc vfsInMemoryCreateDir*(self: VFS, path: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  # let vfs = cast[ptr VFSInMemory2](self.getMutUnsafe.impl)
  discard

proc vfsInMemoryGetFileKind*(self: VFS, path: string): Future[Option[FileKind]] {.gcsafe, async: (raises: []).} =
  let vfs = cast[ptr VFSInMemory2](self.getMutUnsafe.impl)
  withLock vfs.lock:
    if path in vfs.files:
      return FileKind.File.some
    return FileKind.none

proc vfsInMemoryGetFileAttributes*(self: VFS, path: string): Future[Option[FileAttributes]] {.gcsafe, async: (raises: []).} =
  let vfs = cast[ptr VFSInMemory2](self.getMutUnsafe.impl)
  withLock vfs.lock:
    if path in vfs.files:
      return FileAttributes(writable: true, readable: true).some
    return FileAttributes.none

proc vfsInMemorySetFileAttributes*(self: VFS, path: string, attributes: FileAttributes): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  # let vfs = cast[ptr VFSInMemory2](self.getMutUnsafe.impl)
  discard

proc vfsInMemoryGetDirectoryListing*(self: VFS, path: string): Future[DirectoryListing] {.gcsafe, async: (raises: []).} =
  let vfs = cast[ptr VFSInMemory2](self.getMutUnsafe.impl)
  withLock vfs.lock:
    for file in vfs.files.keys:
      if file.startsWith(path):
        result.files.add file

proc newVFSInMemory*(): VFS =
  let vfs = create(VFSInMemory2)
  vfs.lock.initLock()
  vfs.files = Table[string, VFSInMemoryItem].default
  vfs.handlers = Table[string, seq[(Id, proc(events: seq[PathEvent]) {.gcsafe, raises: [].})]].default

  result = VFS.new()
  result.getMutUnsafe.impl = vfs
  result.getMutUnsafe.nameImpl = vfsInMemoryName
  result.getMutUnsafe.readImpl = vfsInMemoryRead
  result.getMutUnsafe.readRopeImpl = vfsInMemoryReadRope
  result.getMutUnsafe.writeImpl = vfsInMemoryWrite
  result.getMutUnsafe.writeRopeImpl = vfsInMemoryWrite
  result.getMutUnsafe.deleteImpl = vfsInMemoryDelete
  result.getMutUnsafe.createDirImpl = vfsInMemoryCreateDir
  result.getMutUnsafe.getFileKindImpl = vfsInMemoryGetFileKind
  result.getMutUnsafe.getFileAttributesImpl = vfsInMemoryGetFileAttributes
  result.getMutUnsafe.setFileAttributesImpl = vfsInMemorySetFileAttributes
  result.getMutUnsafe.getDirectoryListingImpl = vfsInMemoryGetDirectoryListing
  # result.getMutUnsafe.copyFileImpl = vfsInMemoryCopyFile

proc prettyHierarchy*(self: VFS): string =
  result.add self.name
  for m in self.get.mounts:
    result.add "\n"
    result.add ("'" & m.prefix & "' -> " & m.vfs.prettyHierarchy()).indent(2)

########################################################

proc getVFS*(self: VFS, path: openArray[char], maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string] =
  if maxDepth == 0:
    return (self, path.join())

  for i in countdown(self.get.mounts.high, 0):
    template pref(): untyped = self.get.mounts[i].prefix

    if path.startsWith(pref.toOpenArray()) and (pref.len == 0 or path.len == pref.len or pref.endsWith(['/']) or path[pref.len] == '/'):
      var prefixLen = pref.len
      if pref.len > 0 and not pref.endsWith(['/']) and path.len > pref.len:
        inc prefixLen

      return self.get.mounts[i].vfs.getVFS(path[prefixLen..^1], maxDepth - 1)

  result = self.getVFSImpl(path, maxDepth)
  if result.vfs.isNil:
    result = (self, path.join(""))

proc localize*(self: VFS, path: string): string =
  return self.getVFS(path).relativePath.normalizeNativePath

proc normalize*(self: VFS, path: string): string =
  var (vfs, path) = self.getVFS(path)
  path = vfs.normalizeImpl(path)
  while true:
    if vfs.get.parent.isSome:
      path = vfs.get.prefix // path
      vfs = vfs.get.parent.get
    else:
      break

  return path.normalizeNativePath

proc read*(self: VFS, path: string, flags: set[ReadFlag] = {}): Future[string] {.async: (raises: [IOError]).} =
  let (vfs, path) = self.getVFS(path)
  return await vfs.readImpl(path, flags)

proc readRope*(self: VFS, path: string, rope: ptr Rope): Future[void] {.async: (raises: [IOError]).} =
  let (vfs, path) = self.getVFS(path)
  await vfs.readRopeImpl(path, rope)

proc write*(self: VFS, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  let (vfs, path) = self.getVFS(path)
  await vfs.writeImpl(path, content)

proc write*(self: VFS, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  let (vfs, path) = self.getVFS(path)
  await vfs.writeImpl(path, content.move)

proc delete*(self: VFS, path: string): Future[bool] {.async: (raises: [IOError]).} =
  let (vfs, path) = self.getVFS(path)
  await vfs.deleteImpl(path)

proc copyFile*(self: VFS, src: string, dest: string): Future[void] {.async: (raises: [IOError]).} =
  let (srcVfs, srcRelativePath) = self.getVFS(src)
  let (destVfs, destRelativePath) = self.getVFS(dest)
  if srcVfs == destVfs:
    await srcVfs.copyFileImpl(src, dest)
  else:
    # todo: this could be done better with streams
    log lvlWarn, &"Copy file using slow method: '{src}' to '{dest}'"
    let content = srcVfs.read(srcRelativePath, {Binary}).await
    await destVfs.write(destRelativePath, content)

proc findFiles*(self: VFS, root: string, filenameRegex: string, maxResults: int = int.high, options: FindFilesOptions = FindFilesOptions()): Future[seq[string]] {.async: (raises: []).} =
  ## Recursively searches for files in all sub directories of `root` (including `root`).
  ## Returned paths are relative to `root`

  # todo: support root which contains other VFSs
  let (vfs, relativePath) = self.getVFS(root)
  return await vfs.findFilesImpl(relativePath, filenameRegex, maxResults, options)

proc createDir*(self: VFS, path: string): Future[void] {.raises: [].} =
  let (vfs, path) = self.getVFS(path)
  vfs.createDirImpl(path)

proc getFileKind*(self: VFS, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  let (vfs, path) = self.getVFS(path)
  return vfs.getFileKindImpl(path).await

proc getFileAttributes*(self: VFS, path: string): Future[Option[FileAttributes]] {.raises: [].} =
  let (vfs, path) = self.getVFS(path)
  return vfs.getFileAttributesImpl(path)

proc setFileAttributes*(self: VFS, path: string, attributes: FileAttributes): Future[void] {.raises: [].} =
  let (vfs, path) = self.getVFS(path)
  vfs.setFileAttributesImpl(path, attributes)

proc watch*(self: VFS, path: string, cb: proc(events: seq[PathEvent]) {.gcsafe, raises: [].}): VFSWatchHandle =
  let (vfs, path) = self.getVFS(path)
  return VFSWatchHandle(vfs: vfs, id: vfs.watchImpl(path, cb), path: path)

proc unmount*(self: VFS, prefix: string) =
  # todo: make this thread safe
  log lvlInfo, &"{self.nameImpl}: unmount '{prefix}'"
  for i in 0..self.getMutUnsafe.mounts.high:
    if self.getMutUnsafe.mounts[i].prefix == prefix:
      self.getMutUnsafe.mounts[i].vfs.getMutUnsafe.prefix = ""
      self.getMutUnsafe.mounts[i].vfs.getMutUnsafe.parent = VFS.none
      self.getMutUnsafe.mounts.removeShift(i)
      return

proc mount*(self: VFS, prefix: string, vfs: VFS) =
  # todo: make this thread safe
  assert vfs.get.parent.isNone
  log lvlInfo, &"{self.nameImpl}: mount {vfs.nameImpl} under '{prefix}'"
  for i in 0..self.getMutUnsafe.mounts.high:
    if self.getMutUnsafe.mounts[i].prefix == prefix:
      self.getMutUnsafe.mounts[i].vfs.getMutUnsafe.parent = VFS.none
      self.getMutUnsafe.mounts[i].vfs.getMutUnsafe.prefix = ""
      vfs.getMutUnsafe.parent = self.some
      vfs.getMutUnsafe.prefix = prefix
      self.getMutUnsafe.mounts[i] = (prefix, vfs)
      return
  vfs.getMutUnsafe.parent = self.some
  vfs.getMutUnsafe.prefix = prefix
  self.getMutUnsafe.mounts.add (prefix, vfs)

proc getDirectoryListing*(self: VFS, path: string): Future[DirectoryListing] {.async: (raises: []).} =
  let (vfs, relativePath) = self.getVFS(path)
  if vfs == self:
    result = await self.getDirectoryListingImpl(relativePath)
  else:
    result = await vfs.getDirectoryListing(relativePath)

  if path.len == 0:
    for m in self.get.mounts:
      if m.prefix == path:
        continue
      result.folders.add m.prefix

proc isBound*(self: var VFSWatchHandle): bool =
  return self.id != idNone()

proc unwatch*(self: var VFSWatchHandle) =
  if self.id == idNone():
    return
  if not self.vfs.isNil:
    self.vfs.unwatchImpl(self.id)
  else:
    assert false, "Trying to unwatch unbound VFS watch"
  self.id = idNone()

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

type
  NimTempPathState = object
    state: Rand
    isInit: bool

var nimTempPathState {.threadvar.}: NimTempPathState

const
  maxRetry = 10000
  letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

template randomPathName(length: Natural): string =
  var res = newString(length)
  if not nimTempPathState.isInit:
    nimTempPathState.isInit = true
    nimTempPathState.state = initRand()

  for i in 0 ..< length:
    res[i] = nimTempPathState.state.sample(letters)
  res

proc genTempPath*(vfs: VFS, prefix: string, suffix: string, dir: string = "temp://", randLen: int = 8, checkExists: bool = true): Future[string] {.async: (raises: []).} =
  for i in 0..maxRetry:
    result = dir // (prefix & randomPathName(randLen) & suffix)
    if not checkExists or vfs.getFileKind(result).await.isNone:
      break
