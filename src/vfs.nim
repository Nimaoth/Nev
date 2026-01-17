import std/[options, strutils, tables, os, random, strformat]
import nimsumtree/[rope, arc]
import misc/[custom_async, util, custom_logger, cancellation_token, regex, id]
import fsnotify

export fsnotify.PathEvent, fsnotify.FileEventAction

{.push gcsafe.}
{.push raises: [].}

logCategory "VFS"

const debugLogVfs* = false

type
  FileNotFoundError* = object of IOError
  InvalidUtf8Error* = object of IOError

  DirectoryListing* = object
    files*: seq[string]
    folders*: seq[string]

  FileKind* = enum File, Directory
  FileAttributes* = object
    writable*: bool
    readable*: bool

  ReadFlag* = enum Binary

  VFS* = ref object of RootObj
    mounts*: seq[tuple[prefix: string, vfs: VFS]]  ## Seq because I assume the amount of entries will be very small.
    parent*: Option[VFS]
    prefix*: string

  VFSNull* = ref object of VFS
    discard

  VFSInMemoryItemKind* {.pure.} = enum String, Rope
  VFSInMemoryItem* = object
    case kind: VFSInMemoryItemKind
    of VFSInMemoryItemKind.String:
      text: string
    of VFSInMemoryItemKind.Rope:
      rope: Rope

  VFSInMemory* = ref object of VFS
    files: Table[string, VFSInMemoryItem]
    handlers: Table[string, seq[(Id, proc(events: seq[PathEvent]) {.gcsafe, raises: [].})]]

  VFSLink* = ref object of VFS
    target*: VFS
    targetPrefix*: string

  VFSWatchHandle* = object
    path*: string
    vfs: VFS
    vfs2: Arc[VFS2]
    id: Id

  FindFilesOptions* = object
    maxDepth*: int = int.high
    maxResults*: int = int.high

  VFSDynamic* = ref object of VFS
    vfs: Arc[VFS2]

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

  VFSLink2* = object
    target*: Arc[VFS2]
    targetPrefix*: string

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

proc nameImpl*(self: Arc[VFS2]): string {.gcsafe, raises: [].} =
  if self.get.nameImpl != nil:
    self.get.nameImpl(self)
  else:
    &"VFS({self.get.prefix})"

proc normalizeImpl*(self: Arc[VFS2], path: string): string {.gcsafe, raises: [].} =
  if self.get.normalizeImpl != nil:
    self.get.normalizeImpl(self, path)
  else:
    path

proc readImpl*(self: Arc[VFS2], path: string, flags: set[ReadFlag]): Future[string] {.async: (raises: [IOError]).} =
  if self.get.readImpl != nil:
    self.get.readImpl(self, path, flags).await
  else:
    ""

proc readRopeImpl*(self: Arc[VFS2], path: string, rope: ptr Rope): Future[void] {.async: (raises: [IOError]).} =
  if self.get.readRopeImpl != nil:
    self.get.readRopeImpl(self, path, rope).await

proc writeImpl*(self: Arc[VFS2], path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  if self.get.writeImpl != nil:
    self.get.writeImpl(self, path, content).await

proc writeImpl*(self: Arc[VFS2], path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  if self.get.writeRopeImpl != nil:
    self.get.writeRopeImpl(self, path, content).await

proc deleteImpl*(self: Arc[VFS2], path: string): Future[bool] {.async: (raises: []).} =
  if self.get.deleteImpl != nil:
    self.get.deleteImpl(self, path).await
  else:
    false

proc createDirImpl*(self: Arc[VFS2], path: string): Future[void] {.async: (raises: [IOError]).} =
  if self.get.createDirImpl != nil:
    self.get.createDirImpl(self, path).await

proc getFileKindImpl*(self: Arc[VFS2], path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  if self.get.getFileKindImpl != nil:
    self.get.getFileKindImpl(self, path).await
  else:
    FileKind.none

proc getFileAttributesImpl*(self: Arc[VFS2], path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
  if self.get.getFileAttributesImpl != nil:
    self.get.getFileAttributesImpl(self, path).await
  else:
    FileAttributes.none

proc setFileAttributesImpl*(self: Arc[VFS2], path: string, attributes: FileAttributes): Future[void] {.async: (raises: [IOError]).} =
  if self.get.setFileAttributesImpl != nil:
    self.get.setFileAttributesImpl(self, path, attributes).await

proc watchImpl*(self: Arc[VFS2], path: string, cb: proc(events: seq[PathEvent]) {.gcsafe, raises: [].}): Id {.gcsafe, raises: []} =
  if self.get.watchImpl != nil:
    self.get.watchImpl(self, path, cb)
  else:
    idNone()

proc unwatchImpl*(self: Arc[VFS2], id: Id) {.gcsafe, raises: [].} =
  if self.get.unwatchImpl != nil:
    self.get.unwatchImpl(self, id)

proc getVFSImpl*(self: Arc[VFS2], path: openArray[char], maxDepth: int = int.high): tuple[vfs: Arc[VFS2], relativePath: string] {.gcsafe, raises: [].} =
  if self.get.getVFSImpl != nil:
    self.get.getVFSImpl(self, path, maxDepth)
  else:
    (self, path.join())

proc getDirectoryListingImpl*(self: Arc[VFS2], path: string): Future[DirectoryListing] {.async: (raises: []).} =
  if self.get.getDirectoryListingImpl != nil:
    self.get.getDirectoryListingImpl(self, path).await
  else:
    DirectoryListing()

proc copyFileImpl*(self: Arc[VFS2], src: string, dest: string): Future[void] {.async: (raises: [IOError]).} =
  if self.get.copyFileImpl != nil:
    self.get.copyFileImpl(self, src, dest).await

proc findFilesImpl*(self: Arc[VFS2], root: string, filenameRegex: string, maxResults: int = int.high, options: FindFilesOptions = FindFilesOptions()): Future[seq[string]] {.async: (raises: []).} =
  if self.get.findFilesImpl != nil:
    self.get.findFilesImpl(self, root, filenameRegex, maxResults, options).await
  else:
    @[]

proc getVFS*(self: VFS, path: openArray[char], maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string]
proc read*(self: VFS, path: string, flags: set[ReadFlag] = {}): Future[string] {.async: (raises: [IOError]).}
proc readRope*(self: VFS, path: string, rope: ptr Rope): Future[void] {.async: (raises: [IOError]).}
proc write*(self: VFS, path: string, content: string): Future[void] {.async: (raises: [IOError]).}
proc write*(self: VFS, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).}
proc delete*(self: VFS, path: string): Future[bool] {.async: (raises: []).}
proc createDir*(self: VFS, path: string): Future[void] {.async: (raises: [IOError]).}
proc getFileKind*(self: VFS, path: string): Future[Option[FileKind]] {.async: (raises: []).}
proc getFileAttributes*(self: VFS, path: string): Future[Option[FileAttributes]] {.async: (raises: []).}
proc setFileAttributes*(self: VFS, path: string, attributes: FileAttributes): Future[void] {.async: (raises: [IOError]).}
proc normalize*(self: VFS, path: string): string
proc getDirectoryListing*(self: VFS, path: string): Future[DirectoryListing] {.async: (raises: []).}
proc copyFile*(self: VFS, src: string, dest: string): Future[void] {.async: (raises: [IOError]).}
proc findFiles*(self: VFS, root: string, filenameRegex: string, maxResults: int = int.high, options: FindFilesOptions = FindFilesOptions()): Future[seq[string]] {.async: (raises: []).}

proc vfsName*(self: Arc[VFS2]): string = &"VFS({self.get.prefix})"

proc vfsRead*(self: Arc[VFS2], path: string, flags: set[ReadFlag]): Future[string] {.gcsafe, async: (raises: [IOError]).} =
  return ""

proc vfsReadRope*(self: Arc[VFS2], path: string, rope: ptr Rope): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  discard

proc vfsWrite*(self: Arc[VFS2], path: string, content: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  discard

proc vfsWrite*(self: Arc[VFS2], path: string, content: sink RopeSlice[int]): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  discard

proc vfsDelete*(self: Arc[VFS2], path: string): Future[bool] {.gcsafe, async: (raises: []).} =
  return false

proc vfsCreateDir*(self: Arc[VFS2], path: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  discard

proc vfsGetFileKind*(self: Arc[VFS2], path: string): Future[Option[FileKind]] {.gcsafe, async: (raises: []).} =
  return FileKind.none

proc vfsGetFileAttributes*(self: Arc[VFS2], path: string): Future[Option[FileAttributes]] {.gcsafe, async: (raises: []).} =
  return FileAttributes.none

proc vfsSetFileAttributes*(self: Arc[VFS2], path: string, attributes: FileAttributes): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  discard

proc vfsGetDirectoryListing*(self: Arc[VFS2], path: string): Future[DirectoryListing] {.gcsafe, async: (raises: []).} =
  return DirectoryListing()

proc vfsGetVFS*(self: Arc[VFS2], path: openArray[char], maxDepth: int = int.high): tuple[vfs: Arc[VFS2], relativePath: string] =
  return (self, path.join())

proc vfsCopyFile*(self: Arc[VFS2], src: string, dest: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  discard

proc newVFS*(): Arc[VFS2] =
  result = Arc[VFS2].new()
  result.getMutUnsafe.impl = nil
  result.getMutUnsafe.nameImpl = vfsName
  result.getMutUnsafe.readImpl = vfsRead
  result.getMutUnsafe.readRopeImpl = vfsReadRope
  result.getMutUnsafe.writeImpl = vfsWrite
  result.getMutUnsafe.writeImpl = vfsWrite
  result.getMutUnsafe.deleteImpl = vfsDelete
  result.getMutUnsafe.createDirImpl = vfsCreateDir
  result.getMutUnsafe.getFileKindImpl = vfsGetFileKind
  result.getMutUnsafe.getFileAttributesImpl = vfsGetFileAttributes
  result.getMutUnsafe.setFileAttributesImpl = vfsSetFileAttributes
  result.getMutUnsafe.getDirectoryListingImpl = vfsGetDirectoryListing
  result.getMutUnsafe.getVFSImpl = vfsGetVFS
  result.getMutUnsafe.copyFileImpl = vfsCopyFile

proc vfsLinkName*(self: Arc[VFS2]): string =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  return &"Arc[VFS2]({self.get.prefix}, {link.target.nameImpl}/{link.targetPrefix})"

proc vfsLinkRead*(self: Arc[VFS2], path: string, flags: set[ReadFlag]): Future[string] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  return link.target.readImpl(link.targetPrefix // path, flags).await

proc vfsLinkReadRope*(self: Arc[VFS2], path: string, rope: ptr Rope): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  link.target.readRopeImpl(link.targetPrefix // path, rope).await

proc vfsLinkWrite*(self: Arc[VFS2], path: string, content: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  link.target.writeImpl(link.targetPrefix // path, content).await

proc vfsLinkWrite*(self: Arc[VFS2], path: string, content: sink RopeSlice[int]): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  link.target.writeImpl(link.targetPrefix // path, content.move).await

proc vfsLinkDelete*(self: Arc[VFS2], path: string): Future[bool] {.gcsafe, async: (raises: []).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  return link.target.deleteImpl(link.targetPrefix // path).await

proc vfsLinkCreateDir*(self: Arc[VFS2], path: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  link.target.createDirImpl(link.targetPrefix // path).await

proc vfsLinkGetFileKind*(self: Arc[VFS2], path: string): Future[Option[FileKind]] {.gcsafe, async: (raises: []).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  return link.target.getFileKindImpl(path).await

proc vfsLinkGetFileAttributes*(self: Arc[VFS2], path: string): Future[Option[FileAttributes]] {.gcsafe, async: (raises: []).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  return link.target.getFileAttributesImpl(path).await

proc vfsLinkSetFileAttributes*(self: Arc[VFS2], path: string, attributes: FileAttributes): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  link.target.setFileAttributesImpl(path, attributes).await

proc vfsLinkGetDirectoryListing*(self: Arc[VFS2], path: string): Future[DirectoryListing] {.gcsafe, async: (raises: []).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  return link.target.getDirectoryListingImpl(link.targetPrefix // path).await

proc getVFS*(self: Arc[VFS2], path: openArray[char], maxDepth: int = int.high): tuple[vfs: Arc[VFS2], relativePath: string]

proc vfsLinkGetVFS*(self: Arc[VFS2], path: openArray[char], maxDepth: int = int.high): tuple[vfs: Arc[VFS2], relativePath: string] =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  when debugLogVfs:
    debugf"[{sgcsafe, elf.name}] '{self.prefix}' getVFSImpl({path.join()}) -> ({link.target.nameImpl}, {link.target.prefix}), '{link.targetPrefix // path.join()}'"

  if maxDepth == 0:
    return (self, path.join())

  return link.target.getVFS(link.targetPrefix // path.join(), maxDepth - 1)

proc vfsLinkCopyFile*(self: Arc[VFS2], src: string, dest: string): Future[void] {.gcsafe, async: (raises: [IOError]).} =
  let link = cast[ptr VFSLink2](self.getMutUnsafe.impl)
  link.target.copyFileImpl(src, dest).await

proc newVFSLink*(target: Arc[VFS2], prefix: string): Arc[VFS2] =
  let link = create(VFSLink2)
  link.target = target
  link.targetPrefix = prefix

  result = Arc[VFS2].new()
  result.getMutUnsafe.impl = link
  result.getMutUnsafe.nameImpl = vfsLinkName
  result.getMutUnsafe.readImpl = vfsLinkRead
  result.getMutUnsafe.readRopeImpl = vfsLinkReadRope
  result.getMutUnsafe.writeImpl = vfsLinkWrite
  result.getMutUnsafe.writeImpl = vfsLinkWrite
  result.getMutUnsafe.deleteImpl = vfsLinkDelete
  result.getMutUnsafe.createDirImpl = vfsLinkCreateDir
  result.getMutUnsafe.getFileKindImpl = vfsLinkGetFileKind
  result.getMutUnsafe.getFileAttributesImpl = vfsLinkGetFileAttributes
  result.getMutUnsafe.setFileAttributesImpl = vfsLinkSetFileAttributes
  result.getMutUnsafe.getDirectoryListingImpl = vfsLinkGetDirectoryListing
  result.getMutUnsafe.getVFSImpl = vfsLinkGetVFS
  result.getMutUnsafe.copyFileImpl = vfsLinkCopyFile

proc newInMemoryVFS*(): VFSInMemory = VFSInMemory(files: initTable[string, VFSInMemoryItem]())

method clone*(self: VFS): VFS {.base.} =
  result = VFS(prefix: self.prefix)
  for m in self.mounts:
    result.mounts.add (m.prefix, m.vfs.clone())
    result.mounts[^1].vfs.parent = result.some

method clone*(self: VFSNull): VFS =
  result = VFSNull(prefix: self.prefix)
  for m in self.mounts:
    result.mounts.add (m.prefix, m.vfs.clone())
    result.mounts[^1].vfs.parent = result.some

method clone*(self: VFSLink): VFS =
  result = VFSLink(prefix: self.prefix, target: self.target, targetPrefix: self.targetPrefix)
  for m in self.mounts:
    result.mounts.add (m.prefix, m.vfs.clone())
    result.mounts[^1].vfs.parent = result.some

method name*(self: VFS): string {.base.} = &"VFS({self.prefix})"

method normalizeImpl*(self: VFS, path: string): string {.base.} = path

method readImpl*(self: VFS, path: string, flags: set[ReadFlag]): Future[string] {.base, async: (raises: [IOError]).} =
  raise newException(IOError, "Not implemented")

method readRopeImpl*(self: VFS, path: string, rope: ptr Rope): Future[void] {.base, async: (raises: [IOError]).} =
  raise newException(IOError, "Not implemented")

method writeImpl*(self: VFS, path: string, content: string): Future[void] {.base, async: (raises: [IOError]).} =
  discard

method writeImpl*(self: VFS, path: string, content: sink RopeSlice[int]): Future[void] {.base, async: (raises: [IOError]).} =
  discard

method deleteImpl*(self: VFS, path: string): Future[bool] {.base, async: (raises: []).} =
  return false

method createDirImpl*(self: VFS, path: string): Future[void] {.base, async: (raises: [IOError]).} =
  discard

method getFileKindImpl*(self: VFS, path: string): Future[Option[FileKind]] {.base, async: (raises: []).} =
  return FileKind.none

method getFileAttributesImpl*(self: VFS, path: string): Future[Option[FileAttributes]] {.base, async: (raises: []).} =
  return FileAttributes.none

method setFileAttributesImpl*(self: VFS, path: string, attributes: FileAttributes): Future[void] {.base, async: (raises: [IOError]).} =
  discard

method watchImpl*(self: VFS, path: string, cb: proc(events: seq[PathEvent]) {.gcsafe, raises: [].}): Id {.base.} =
  idNone()

method unwatchImpl*(self: VFS, id: Id) {.base.} =
  discard

method getVFSImpl*(self: VFS, path: openArray[char], maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string] {.base.} =
  (nil, "")

method getDirectoryListingImpl*(self: VFS, path: string): Future[DirectoryListing] {.base, async: (raises: []).} =
  discard

method copyFileImpl*(self: VFS, src: string, dest: string): Future[void] {.base, async: (raises: [IOError]).} =
  discard

method findFilesImpl*(self: VFS, root: string, filenameRegex: string, maxResults: int = int.high, options: FindFilesOptions = FindFilesOptions()): Future[seq[string]] {.base, async: (raises: []).} =
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

method readRopeImpl*(self: VFSLink, path: string, rope: ptr Rope): Future[void] {.async: (raises: [IOError]).} =
  self.target.readRope(self.targetPrefix // path, rope).await

method writeImpl*(self: VFSLink, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  await self.target.write(self.targetPrefix // path, content)

method writeImpl*(self: VFSLink, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  await self.target.write(self.targetPrefix // path, content.move)

method deleteImpl*(self: VFSLink, path: string): Future[bool] {.async: (raises: []).} =
  await self.target.delete(self.targetPrefix // path)

method createDirImpl*(self: VFSLink, path: string): Future[void] {.async: (raises: [IOError]).} =
  await self.target.createDir(self.targetPrefix // path)

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
    case file[].kind
    of VFSInMemoryItemKind.String:
      return file[].text
    of VFSInMemoryItemKind.Rope:
      return $file[].rope
  raise newException(IOError, "VFSInMemory: File not found '" & path & "'")

method readRopeImpl*(self: VFSInMemory, path: string, rope: ptr Rope): Future[void] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"VFSInMemory.read({path})"
  self.files.withValue(path, file):
    case file[].kind
    of VFSInMemoryItemKind.String:
      rope[] = Rope.new(file[].text)
    of VFSInMemoryItemKind.Rope:
      rope[] = file[].rope
    return
  raise newException(IOError, "VFSInMemory: File not found '" & path & "'")

proc handleFileChanged(self: VFSInMemory, path: string, existedBefore: bool) =
  if path in self.handlers:
    let action = if existedBefore:
      FileEventAction.Modify
    else:
      FileEventAction.Create
    let events = @[(path, action, "")]
    let handlers = self.handlers[path]
    for (_, handler) in handlers:
      handler(events)

method writeImpl*(self: VFSInMemory, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"VFSInMemory.write({path})"
  let existedBefore = path in self.files
  self.files[path] = VFSInMemoryItem(kind: VFSInMemoryItemKind.String, text: content)
  self.handleFileChanged(path, existedBefore)

method writeImpl*(self: VFSInMemory, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"VFSInMemory.write({path})"
  let existedBefore = path in self.files
  self.files[path] = VFSInMemoryItem(kind: VFSInMemoryItemKind.Rope, rope: content.toRope)
  self.handleFileChanged(path, existedBefore)

method deleteImpl*(self: VFSInMemory, path: string): Future[bool] {.async: (raises: []).} =
  if path in self.files:
    self.files.del(path)
    return true

method createDirImpl*(self: VFSInMemory, path: string): Future[void] {.async: (raises: [IOError]).} =
  discard

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

method watchImpl*(self: VFSInMemory, path: string, cb: proc(events: seq[PathEvent]) {.gcsafe, raises: [].}): Id =
  if not self.handlers.contains(path):
    self.handlers[path] = @[]

  let id = newId()
  self.handlers[path].add((id, cb))
  return id

method unwatchImpl*(self: VFSInMemory, id: Id) =
  for entry in self.handlers.mpairs:
    var i = 0
    for handlerId, handler in entry[1].mitems:
      if handlerId == id:
        entry[1].removeShift(i)
        return
      inc i

method copyFileImpl*(self: VFSInMemory, src: string, dest: string): Future[void] {.async: (raises: [IOError]).} =
  if src in self.files:
    self.files[dest] = self.files[src]
  else:
    raise newException(IOError, &"Failed to copy non-existing file '{src}' to '{dest}'")

method name*(self: VFSDynamic): string {.gcsafe, raises: [].} = self.vfs.nameImpl()
method normalize*(self: VFSDynamic, path: string): string {.gcsafe, raises: [].} = self.vfs.normalizeImpl(path)
method read*(self: VFSDynamic, path: string, flags: set[ReadFlag]): Future[string] {.raises: [IOError].} = self.vfs.readImpl(path, flags)
method readRope*(self: VFSDynamic, path: string, rope: ptr Rope): Future[void] {.raises: [IOError].} = self.vfs.readRopeImpl(path, rope)
method write*(self: VFSDynamic, path: string, content: string): Future[void] {.raises: [IOError].} = self.vfs.writeImpl(path, content)
method write*(self: VFSDynamic, path: string, content: sink RopeSlice[int]): Future[void] {.raises: [IOError].} = self.vfs.writeImpl(path, content)
method delete*(self: VFSDynamic, path: string): Future[bool] {.raises: [].} = self.vfs.deleteImpl(path)
method createDir*(self: VFSDynamic, path: string): Future[void] {.raises: [IOError].} = self.vfs.createDirImpl(path)
method getFileKind*(self: VFSDynamic, path: string): Future[Option[FileKind]] {.raises: [].} = self.vfs.getFileKindImpl(path)
method getFileAttributes*(self: VFSDynamic, path: string): Future[Option[FileAttributes]] {.raises: [].} = self.vfs.getFileAttributesImpl(path)
method setFileAttributes*(self: VFSDynamic, path: string, attributes: FileAttributes): Future[void] {.raises: [IOError].} = self.vfs.setFileAttributesImpl(path, attributes)
method watch*(self: VFSDynamic, path: string, cb: proc(events: seq[PathEvent]) {.gcsafe, raises: [].}): Id {.gcsafe, raises: []} = self.vfs.watchImpl(path, cb)
method unwatch*(self: VFSDynamic, id: Id) {.gcsafe, raises: [].} = self.vfs.unwatchImpl(id)
method getVFS*(self: VFSDynamic, path: openArray[char], maxDepth: int = int.high): tuple[vfs: VFS, relativePath: string] {.gcsafe, raises: [].} = (let (vfs, p) = self.vfs.getVFSImpl(path, maxDepth); (VFSDynamic(vfs: vfs), p))
method getDirectoryListing*(self: VFSDynamic, path: string): Future[DirectoryListing] {.raises: [].} = self.vfs.getDirectoryListingImpl(path)
method copyFile*(self: VFSDynamic, src: string, dest: string): Future[void] {.raises: [IOError].} = self.vfs.copyFileImpl(src, dest)
method findFiles*(self: VFSDynamic, root: string, filenameRegex: string, maxResults: int = int.high, options: FindFilesOptions = FindFilesOptions()): Future[seq[string]] {.raises: [].} = self.vfs.findFilesImpl(root, filenameRegex, maxResults, options)

proc getVFS*(self: Arc[VFS2], path: openArray[char], maxDepth: int = int.high): tuple[vfs: Arc[VFS2], relativePath: string] =
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

proc localize*(self: Arc[VFS2], path: string): string =
  return self.getVFS(path).relativePath.normalizeNativePath

proc normalize*(self: Arc[VFS2], path: string): string =
  var (vfs, path) = self.getVFS(path)
  path = vfs.normalizeImpl(path)
  while vfs.get.parent.getSome(parent):
    path = vfs.get.prefix // path
    vfs = parent

  return path.normalizeNativePath

proc read*(self: Arc[VFS2], path: string, flags: set[ReadFlag] = {}): Future[string] {.raises: [IOError].} =
  let (vfs, path) = self.getVFS(path)
  return vfs.readImpl(path, flags)

proc readRope*(self: Arc[VFS2], path: string, rope: ptr Rope): Future[void] {.raises: [IOError].} =
  let (vfs, path) = self.getVFS(path)
  vfs.readRopeImpl(path, rope)

proc write*(self: Arc[VFS2], path: string, content: string): Future[void] {.raises: [IOError].} =
  let (vfs, path) = self.getVFS(path)
  vfs.writeImpl(path, content)

proc write*(self: Arc[VFS2], path: string, content: sink RopeSlice[int]): Future[void] {.raises: [IOError].} =
  let (vfs, path) = self.getVFS(path)
  vfs.writeImpl(path, content.move)

proc delete*(self: Arc[VFS2], path: string): Future[bool] {.raises: [].} =
  let (vfs, path) = self.getVFS(path)
  vfs.deleteImpl(path)

proc createDir*(self: Arc[VFS2], path: string): Future[void] {.raises: [IOError].} =
  let (vfs, path) = self.getVFS(path)
  vfs.createDirImpl(path)

proc getFileKind*(self: Arc[VFS2], path: string): Future[Option[FileKind]] {.raises: [].} =
  let (vfs, path) = self.getVFS(path)
  return vfs.getFileKindImpl(path)

proc getFileAttributes*(self: Arc[VFS2], path: string): Future[Option[FileAttributes]] {.raises: [].} =
  let (vfs, path) = self.getVFS(path)
  return vfs.getFileAttributesImpl(path)

proc setFileAttributes*(self: Arc[VFS2], path: string, attributes: FileAttributes): Future[void] {.raises: [IOError].} =
  let (vfs, path) = self.getVFS(path)
  vfs.setFileAttributesImpl(path, attributes)

proc watch*(self: Arc[VFS2], path: string, cb: proc(events: seq[PathEvent]) {.gcsafe, raises: [].}): VFSWatchHandle =
  let (vfs, path) = self.getVFS(path)
  return VFSWatchHandle(vfs2: vfs, id: vfs.watchImpl(path, cb), path: path)

proc unmount*(self: Arc[VFS2], prefix: string) =
  # todo: make this thread safe
  log lvlInfo, &"{self.nameImpl}: unmount '{prefix}'"
  for i in 0..self.getMutUnsafe.mounts.high:
    if self.getMutUnsafe.mounts[i].prefix == prefix:
      self.getMutUnsafe.mounts[i].vfs.getMutUnsafe.prefix = ""
      self.getMutUnsafe.mounts[i].vfs.getMutUnsafe.parent = Arc[VFS2].none
      self.getMutUnsafe.mounts.removeShift(i)
      return

proc mount*(self: Arc[VFS2], prefix: string, vfs: Arc[VFS2]) =
  # todo: make this thread safe
  assert vfs.get.parent.isNone
  log lvlInfo, &"{self.nameImpl}: mount {vfs.nameImpl} under '{prefix}'"
  for i in 0..self.getMutUnsafe.mounts.high:
    if self.getMutUnsafe.mounts[i].prefix == prefix:
      self.getMutUnsafe.mounts[i].vfs.getMutUnsafe.parent = Arc[VFS2].none
      self.getMutUnsafe.mounts[i].vfs.getMutUnsafe.prefix = ""
      vfs.getMutUnsafe.parent = self.some
      vfs.getMutUnsafe.prefix = prefix
      self.getMutUnsafe.mounts[i] = (prefix, vfs)
      return
  vfs.getMutUnsafe.parent = self.some
  vfs.getMutUnsafe.prefix = prefix
  self.getMutUnsafe.mounts.add (prefix, vfs)

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
        debugf"[{self.name}] '{self.prefix}' forward({path.join()}) to ({self.mounts[i].vfs.name}, {self.mounts[i].vfs.prefix})"
      return self.mounts[i].vfs.getVFS(path[prefixLen..^1], maxDepth - 1)

  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' getVFSImpl({path.join()})"
  result = self.getVFSImpl(path, maxDepth) # todo: maxDepth - 1?
  if result.vfs.isNil:
    result = (self, path.join(""))

proc localize*(self: VFS, path: string): string =
  return self.getVFS(path).relativePath.normalizeNativePath

proc normalize*(self: VFS, path: string): string =
  var (vfs, path) = self.getVFS(path)
  path = vfs.normalizeImpl(path)
  while vfs.parent.getSome(parent):
    path = vfs.prefix // path
    vfs = parent

  return path.normalizeNativePath

proc read*(self: VFS, path: string, flags: set[ReadFlag] = {}): Future[string] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' read({path})"
  let (vfs, path) = self.getVFS(path)
  return await vfs.readImpl(path, flags)

proc readRope*(self: VFS, path: string, rope: ptr Rope): Future[void] {.async: (raises: [IOError]).} =
  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' readRope({path})"
  let (vfs, path) = self.getVFS(path)
  await vfs.readRopeImpl(path, rope)

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

proc delete*(self: VFS, path: string): Future[bool] {.async: (raises: []).} =
  when debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' delete({path})"
  let (vfs, path) = self.getVFS(path)
  await vfs.deleteImpl(path)

proc createDir*(self: VFS, path: string): Future[void] {.async: (raises: [IOError]).} =
  let (vfs, path) = self.getVFS(path)
  await vfs.createDirImpl(path)

proc getFileKind*(self: VFS, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  let (vfs, path) = self.getVFS(path)
  return await vfs.getFileKindImpl(path)

proc getFileAttributes*(self: VFS, path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
  let (vfs, path) = self.getVFS(path)
  return await vfs.getFileAttributesImpl(path)

proc setFileAttributes*(self: VFS, path: string, attributes: FileAttributes): Future[void] {.async: (raises: [IOError]).} =
  let (vfs, path) = self.getVFS(path)
  await vfs.setFileAttributesImpl(path, attributes)

proc watch*(self: VFS, path: string, cb: proc(events: seq[PathEvent]) {.gcsafe, raises: [].}): VFSWatchHandle =
  let (vfs, path) = self.getVFS(path)
  return VFSWatchHandle(vfs: vfs, id: vfs.watchImpl(path, cb), path: path)

proc isBound*(self: var VFSWatchHandle): bool =
  return self.id != idNone()

proc unwatch*(self: var VFSWatchHandle) =
  if self.id == idNone():
    return
  if self.vfs != nil:
    self.vfs.unwatchImpl(self.id)
  elif not self.vfs2.isNil:
    self.vfs2.unwatchImpl(self.id)
  else:
    assert false, "Trying to unwatch unbound VFS watch"
  self.vfs = nil
  self.id = idNone()

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

proc findFiles*(self: VFS, root: string, filenameRegex: string, maxResults: int = int.high, options: FindFilesOptions = FindFilesOptions()): Future[seq[string]] {.async: (raises: []).} =
  ## Recursively searches for files in all sub directories of `root` (including `root`).
  ## Returned paths are relative to `root`

  # todo: support root which contains other VFSs
  let (vfs, relativePath) = self.getVFS(root)
  return await vfs.findFilesImpl(relativePath, filenameRegex, maxResults, options)

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

proc genTempPath*(vfs: VFS, prefix: string, suffix: string, dir: string = "temp://", randLen: int = 8, checkExists: bool = true): string =
  for i in 0..maxRetry:
    result = dir // (prefix & randomPathName(randLen) & suffix)
    if not checkExists or vfs.getFileKind(result).waitFor.isNone:
      break
