import std/[options, tables]
import nimsumtree/[arc, rope]
import misc/[custom_async, custom_logger, util, jsonex]
import vfs
import config_provider

const currentSourcePath2 = currentSourcePath()
include module_base

{.push gcsafe.}
{.push raises: [].}

logCategory "vfs-config"

type
  VFSConfig2* = object
    config: ConfigService

{.push modrtl, gcsafe, raises: [].}
proc newVFSConfig*(): Arc[VFS2]
{.pop.}

when implModule:
  import service

  proc vfsConfigReadImpl*(vfs: Arc[VFS2], path: string, flags: set[ReadFlag]): Future[string] {.async: (raises: [IOError]).} =
    let self = cast[ptr VFSConfig2](vfs.getMutUnsafe.impl)
    try:
      let value = self.config.getByPath(path)
      if value == nil:
        return ""
      return value.pretty
    except:
      raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

  proc vfsConfigReadRopeImpl*(vfs: Arc[VFS2], path: string, rope: ptr Rope): Future[void] {.async: (raises: [IOError]).} =
    let self = cast[ptr VFSConfig2](vfs.getMutUnsafe.impl)
    try:
      let value = self.config.getByPath(path)
      if value == nil:
        rope[] = Rope.new("")
      else:
        rope[] = Rope.new(value.pretty)
    except:
      raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

  proc vfsConfigWriteImpl*(vfs: Arc[VFS2], path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
    let self = cast[ptr VFSConfig2](vfs.getMutUnsafe.impl)
    try:
      let (store, key) = self.config.getStoreForPath(path)
      if store == nil:
        return
      let value = content.parseJsonex()
      store.set(key, value)
    except:
      raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

  proc vfsConfigWriteRopeImpl*(vfs: Arc[VFS2], path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
    let self = cast[ptr VFSConfig2](vfs.getMutUnsafe.impl)
    try:
      let (store, key) = self.config.getStoreForPath(path)
      if store == nil:
        return
      let value = ($content).parseJsonex()
      store.set(key, value)
    except:
      raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

  proc vfsConfigGetFileKindImpl*(vfs: Arc[VFS2], path: string): Future[Option[FileKind]] {.async: (raises: []).} =
    let self = cast[ptr VFSConfig2](vfs.getMutUnsafe.impl)
    let value = self.config.getByPath(path)
    if value == nil:
      return FileKind.none
    if value.kind == JObject:
      return FileKind.Directory.some
    return FileKind.File.some

  proc vfsConfigGetFileAttributesImpl*(vfs: Arc[VFS2], path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
    let self = cast[ptr VFSConfig2](vfs.getMutUnsafe.impl)
    return FileAttributes(writable: true, readable: true).some

  proc vfsConfigGetDirectoryListingImpl*(vfs: Arc[VFS2], path: string): Future[DirectoryListing] {.async: (raises: []).} =
    let self = cast[ptr VFSConfig2](vfs.getMutUnsafe.impl)
    if path == "":
      var res = DirectoryListing()
      for store in self.config.stores.values:
        res.folders.add store.name
      return res

    let (store, key) = self.config.getStoreForPath(path)
    if store == nil:
      return DirectoryListing()

    let value = if key == "":
      store.settings
    else:
      store.get(key, JsonNodeEx, nil)

    var res = DirectoryListing()
    if value != nil and value.kind == JObject:
      for key, value in value.fields.pairs:
        if value.kind == JObject:
          res.folders.add key
        else:
          res.files.add key
    return res

  proc vfsConfigName*(self: Arc[VFS2]): string = &"VFSConfig({self.get.prefix})"

  proc newVFSConfig*(): Arc[VFS2] =
    let vfs = create(VFSConfig2)
    vfs.config = getServiceChecked(ConfigService)
    result = Arc[VFS2].new()
    result.getMutUnsafe.impl = vfs
    result.getMutUnsafe.nameImpl = vfsConfigName
    result.getMutUnsafe.readImpl = vfsConfigReadImpl
    result.getMutUnsafe.readRopeImpl = vfsConfigReadRopeImpl
    result.getMutUnsafe.writeImpl = vfsConfigWriteImpl
    result.getMutUnsafe.writeRopeImpl = vfsConfigWriteRopeImpl
    result.getMutUnsafe.getFileKindImpl = vfsConfigGetFileKindImpl
    result.getMutUnsafe.getFileAttributesImpl = vfsConfigGetFileAttributesImpl
    result.getMutUnsafe.getDirectoryListingImpl = vfsConfigGetDirectoryListingImpl
