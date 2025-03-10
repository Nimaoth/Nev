import std/[options, strutils, json, tables]
import nimsumtree/[rope]
import misc/[custom_async, custom_logger, util, myjsonutils]
import vfs
import config_provider

{.push gcsafe.}
{.push raises: [].}

logCategory "vfs-config"

type
  VFSConfig* = ref object of VFS
    config: ConfigService

proc new*(_: typedesc[VFSConfig], config: ConfigService): VFSConfig =
  new(result)
  result.config = config

method name*(self: VFSConfig): string = &"VFSConfig({self.prefix})"

method readImpl*(self: VFSConfig, path: string, flags: set[ReadFlag]): Future[string] {.async: (raises: [IOError]).} =
  try:
    let key = path.replace("/", ".")
    let value = self.config.getOption[:JsonNode](key, nil)
    if value != nil:
      return value.pretty
    return ""
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

method readRopeImpl*(self: VFSConfig, path: string, rope: ptr Rope): Future[void] {.async: (raises: [IOError]).} =
  try:
    let key = path.replace("/", ".")
    let value = self.config.getOption[:JsonNode](key, nil)
    if value != nil:
      rope[] = Rope.new(value.pretty)
    else:
      rope[] = Rope.new("")
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

method writeImpl*(self: VFSConfig, path: string, content: string): Future[void] {.async: (raises: [IOError]).} =
  try:
    let key = path.replace("/", ".")
    let value = content.parseJson()
    self.config.setOption(key, value)
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

method writeImpl*(self: VFSConfig, path: string, content: sink RopeSlice[int]): Future[void] {.async: (raises: [IOError]).} =
  try:
    let key = path.replace("/", ".")
    let value = ($content).parseJson()
    self.config.setOption(key, value)
  except:
    raise newException(IOError, getCurrentExceptionMsg(), getCurrentException())

method deleteImpl*(self: VFSConfig, path: string): Future[bool] {.async: (raises: []).} =
  discard

method getFileKindImpl*(self: VFSConfig, path: string): Future[Option[FileKind]] {.async: (raises: []).} =
  let key = path.replace("/", ".")
  let value = self.config.getOption[:JsonNode](key, nil)
  if value == nil:
    return FileKind.none
  if value.kind == JObject:
    return FileKind.Directory.some
  return FileKind.File.some

method getFileAttributesImpl*(self: VFSConfig, path: string): Future[Option[FileAttributes]] {.async: (raises: []).} =
  return FileAttributes(writable: true, readable: true).some

method getDirectoryListingImpl*(self: VFSConfig, path: string): Future[DirectoryListing] {.async: (raises: []).} =
  let value = if path == "":
    self.config.settings
  else:
    let key = path.replace("/", ".")
    self.config.getOption[:JsonNode](key, nil)

  var res = DirectoryListing()
  if value != nil and value.kind == JObject:
    for key, value in value.fields.pairs:
      if value.kind == JObject:
        res.folders.add key
      else:
        res.files.add key
  return res

method copyFileImpl*(self: VFSConfig, src: string, dest: string): Future[void] {.async: (raises: [IOError]).} =
  try:
    # todo
    discard
  except Exception as e:
    raise newException(IOError, &"Failed to copy file '{src}' to '{dest}': {e.msg}", e)

method findFilesImpl*(self: VFSConfig, root: string, filenameRegex: string, maxResults: int = int.high): Future[seq[string]] {.async: (raises: []).} =
  var res = newSeq[string]()
  # todo
  return res
