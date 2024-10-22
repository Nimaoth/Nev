import std/[tables, options, json, os]
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


  self.vfs = VFS()
  self.vfs.mount("", VFSLocal())
  self.vfs.mount("app://", VFSLink(target: self.vfs.getVFS("").vfs, targetPrefix: getAppDir().normalizeNativePath & "/"))
  self.vfs.mount("plugs://", VFSNull())
  self.vfs.mount("ws://", VFS())

  let homeDir = getHomeDir().normalizePathUnix.catch:
    log lvlError, &"Failed to get home directory: {getCurrentExceptionMsg()}"
    ""
  if homeDir != "":
    self.vfs.mount("home://", VFSLink(target: self.vfs.getVFS("").vfs, targetPrefix: homeDir & "/"))

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
    let targetName = config.fields.getOrDefault("target", newJNull()).getStr.expect("string 'target'", $config)
    let (target, sub) = self.vfs.getVFS(targetName, targetMaxDepth)
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

proc mountVfs*(self: VFSService, parentPath: string, prefix: string, config: JsonNode) {.expose("vfs").} =
  log lvlInfo, &"Mount VFS '{parentPath}', '{prefix}', {config}"
  let (vfs, _) = self.vfs.getVFS(parentPath)
  if self.createVfs(config).getSome(newVFS):
    vfs.mount(prefix, newVFS)

proc normalizePath*(self: VFSService, path: string): string {.expose("vfs").} =
  return self.vfs.normalize(path)

proc dumpVfsHierarchy*(self: VFSService) {.expose("vfs").} =
  log lvlInfo, "\n" & self.vfs.prettyHierarchy()

addGlobalDispatchTable "vfs", genDispatchTable("vfs")
