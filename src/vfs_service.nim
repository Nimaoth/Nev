import std/[tables, options, json, os, random]
import results
import misc/[custom_async, custom_logger, myjsonutils, util]
import scripting/expose
import service, dispatch_tables, vfs, vfs_local

{.push gcsafe.}
{.push raises: [].}

logCategory "vfs-service"

type
  VFSService* = ref object of Service
    vfs*: VFS

func serviceName*(_: typedesc[VFSService]): string = "VFSService"

addBuiltinService(VFSService)

method init*(self: VFSService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"VFSService.init"

  let localVfs = VFSLocal()

  self.vfs = VFS()
  self.vfs.mount("", VFS())
  self.vfs.mount("local://", localVfs)
  self.vfs.mount("", VFSLink(target: localVfs, targetPrefix: ""))
  self.vfs.mount("app://", VFSLink(target: localVfs, targetPrefix: getAppDir().normalizeNativePath))
  self.vfs.mount("temp://", VFSLink(target: localVfs, targetPrefix: getTempDir().normalizeNativePath))
  self.vfs.mount("plugs://", VFSNull())
  self.vfs.mount("ws://", VFS())

  let homeDir = getHomeDir().normalizePathUnix.catch:
    log lvlError, &"Failed to get home directory: {getCurrentExceptionMsg()}"
    ""
  if homeDir != "":
    self.vfs.mount("home://", VFSLink(target: localVfs, targetPrefix: homeDir & "/"))

  return ok()

proc createVfs*(self: VFSService, config: JsonNode): Option[VFS] =
  result = VFS.none
  if config.kind != JObject:
    log lvlError, &"Invalid config, expected object, got {config}"
    return

  let typ = config.fields.getOrDefault("type", newJNull()).getStr.catch:
    log lvlError, &"Invalid config, expected string property 'type', got {config}"
    return

  template expect(value: untyped, msg: untyped, got: untyped): untyped =
    try:
      value
    except:
      log lvlError, "Invalid config, expected " & msg & ", got " & got
      return

  case typ
  of "link":
    let targetMaxDepth = config.fields.getOrDefault("targetMaxDepth", newJInt(1)).getInt.expect("int 'targetMaxDepth'", $config)
    let targetName = config.fields.getOrDefault("target", newJNull()).jsonTo(Option[string]).catch:
      log lvlError, "Invalid config, target must be string or null: " & config.pretty
      return
    let (target, sub) = if targetName.getSome(t):
      self.vfs.getVFS(t, targetMaxDepth)
    else:
      (self.vfs, "")

    if sub != "":
      log lvlError, &"Unknown target '{targetName}', unmatched: '{sub}'"
      return VFS.none

    let targetPrefix = config.fields.getOrDefault("targetPrefix", newJString("")).getStr.expect("string 'targetPrefix'", $config)

    log lvlInfo, &"create VFSLink {target.name}, {target.prefix}, {targetPrefix}"
    result = VFSLink(
      target: target,
      targetPrefix: targetPrefix,
    ).VFS.some

  else:
    log lvlError, &"Invalid VFS config, unknown type '{typ}'"
    return VFS.none

###########################################################################

proc getVfsService(): Option[VFSService] =
  {.gcsafe.}:
    if gServices.isNil: return VFSService.none
    return gServices.getService(VFSService)

static:
  addInjector(VFSService, getVfsService)

proc mountVfs*(self: VFSService, parentPath: Option[string], prefix: string, config: JsonNode) {.expose("vfs").} =
  log lvlInfo, &"Mount VFS '{parentPath}', '{prefix}', {config}"
  let vfs = if parentPath.getSome(p):
    self.vfs.getVFS(p).vfs
  else:
    self.vfs

  if self.createVfs(config).getSome(newVFS):
    vfs.mount(prefix, newVFS)

proc normalizePath*(self: VFSService, path: string): string {.expose("vfs").} =
  return self.vfs.normalize(path)

proc localizePath*(self: VFSService, path: string): string {.expose("vfs").} =
  return self.vfs.localize(path)

proc writeFileSync*(self: VFSService, path: string, content: string) {.expose("vfs").} =
  try:
    waitFor self.vfs.write(path, content)
  except IOError as e:
    log lvlError, &"Failed to write file '{path}': {e.msg}"

proc readFileSync*(self: VFSService, path: string): string {.expose("vfs").} =
  try:
    return waitFor self.vfs.read(path)
  except IOError as e:
    log lvlError, &"Failed to read file '{path}': {e.msg}"

proc deleteFileSync*(self: VFSService, path: string) {.expose("vfs").} =
  try:
    discard waitFor self.vfs.delete(path)
  except IOError as e:
    log lvlError, &"Failed to delete file '{path}': {e.msg}"

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

proc genTempPath*(self: VFSService, prefix: string, suffix: string, dir: string = "temp://", randLen: int = 8, checkExists: bool = true): string {.expose("vfs").} =
  for i in 0..maxRetry:
    result = dir // (prefix & randomPathName(randLen) & suffix)
    if not checkExists or self.vfs.getFileKind(result).waitFor.isNone:
      break

proc dumpVfsHierarchy*(self: VFSService) {.expose("vfs").} =
  log lvlInfo, "\n" & self.vfs.prettyHierarchy()

addGlobalDispatchTable "vfs", genDispatchTable("vfs")
