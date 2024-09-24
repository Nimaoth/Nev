import std/[options, strutils, tables]
import misc/[custom_async, util, custom_logger]
import platform/filesystem

logCategory "VFS"

var debugLogVfs* = false

type
  VFS* = ref object of RootObj
    mounts: seq[tuple[prefix: string, vfs: VFS]]  ## Seq because I assume the amount of entries will be very small.
    parent: Option[VFS]
    prefix*: string

  VFSNull* = ref object of VFS
    discard

  VFSDynamic* = ref object of VFS
    readFunc: proc(self: VFS, path: string): Future[Option[string]]
    writeFunc: proc(self: VFS, path: string, content: string): Future[void]

  VFSInMemory* = ref object of VFS
    files: Table[string, string]

  VFSLink* = ref object of VFS
    target*: VFS
    targetPrefix*: string

proc getVFS*(self: VFS, path: string): tuple[vfs: VFS, relativePath: string]
proc read*(self: VFS, path: string): Future[Option[string]]
proc write*(self: VFS, path: string, content: string): Future[void]
proc normalize*(self: VFS, path: string): string

proc newInMemoryVFS*(): VFSInMemory = VFSInMemory(files: initTable[string, string]())

method name*(self: VFS): string {.base.} = "VFS"

method readImpl*(self: VFS, path: string): Future[Option[string]] {.base.} =
  discard

method writeImpl*(self: VFS, path: string, content: string): Future[void] {.base.} =
  doneFuture()

method getVFSImpl*(self: VFS, path: string): tuple[vfs: VFS, relativePath: string] {.base.} =
  (nil, "")

method normalizeImpl*(self: VFS, path: string): string {.base.} =
  path

method name*(self: VFSNull): string = "VFSNull"

method readImpl*(self: VFSNull, path: string): Future[Option[string]] {.async.} =
  return string.none

method writeImpl*(self: VFSNull, path: string, content: string): Future[void] =
  doneFuture()

method name*(self: VFSDynamic): string = "VFSDynamic"

method readImpl*(self: VFSDynamic, path: string): Future[Option[string]] =
  return self.readFunc(self, path)

method writeImpl*(self: VFSDynamic, path: string, content: string): Future[void] =
  return self.writeFunc(self, path, content)

method name*(self: VFSLink): string = "VFSLink"

method readImpl*(self: VFSLink, path: string): Future[Option[string]] =
  return self.target.read(self.targetPrefix & path)

method writeImpl*(self: VFSLink, path: string, content: string): Future[void] =
  return self.target.write(self.targetPrefix & path, content)

method normalizeImpl*(self: VFSLink, path: string): string =
  return self.target.normalize(self.targetPrefix & path)

method getVFSImpl*(self: VFSLink, path: string): tuple[vfs: VFS, relativePath: string] =
  if debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' getVFSImpl({path}) -> ({self.target.name}, {self.target.prefix}), '{self.targetPrefix & path}'"
  return self.target.getVFS(self.targetPrefix & path)

method name*(self: VFSInMemory): string = "VFSInMemory"

method readImpl*(self: VFSInMemory, path: string): Future[Option[string]] =
  if debugLogVfs:
    debugf"VFSInMemory.read({path})"
  if self.files.contains(path):
    return self.files[path].some.toFuture
  return string.none.toFuture

method writeImpl*(self: VFSInMemory, path: string, content: string): Future[void] =
  if debugLogVfs:
    debugf"VFSInMemory.write({path})"
  self.files[path] = content
  doneFuture()

proc getVFS*(self: VFS, path: string): tuple[vfs: VFS, relativePath: string] =
  for i in countdown(self.mounts.high, 0):
    if path.startsWith(self.mounts[i].prefix):
      if debugLogVfs:
        debugf"[{self.name}] '{self.prefix}' foward({path}) to ({self.mounts[i].vfs.name}, {self.mounts[i].vfs.prefix})"
      return self.mounts[i].vfs.getVFS(path[self.mounts[i].prefix.len..^1])

  result = self.getVFSImpl(path)
  if result.vfs.isNil:
    result = (self, path)

proc read*(self: VFS, path: string): Future[Option[string]] =
  if debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' read({path})"
  let (vfs, path) = self.getVFS(path)
  if vfs == self:
    result = self.readImpl(path)
  else:
    result = vfs.read(path)
  if result.isNil:
    result = string.none.toFuture

proc write*(self: VFS, path: string, content: string): Future[void] =
  if debugLogVfs:
    debugf"[{self.name}] '{self.prefix}' write({path})"
  let (vfs, path) = self.getVFS(path)
  if vfs == self:
    result = self.writeImpl(path, content)
  else:
    result = vfs.write(path, content)
  if result.isNil:
    result = doneFuture()

proc normalize*(self: VFS, path: string): string =
  var (vfs, path) = self.getVFS(path)
  while vfs.parent.getSome(parent):
    path = vfs.prefix & path
    vfs = parent

  return path

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
