import nimsumtree/[arc]
import service, vfs, vfs_local

export vfs

include dynlib_export

{.push gcsafe.}
{.push raises: [].}

type
  VFSService* = ref object of Service
    vfs*: VFS
    vfs2*: Arc[VFS2]
    localVfs*: VFSLocal
    localVfs2*: Arc[VFS2]

func serviceName*(_: typedesc[VFSService]): string = "VFSService"

when implModule:
  import std/[tables, options, json, os]
  import results
  import misc/[custom_async, custom_logger, myjsonutils, util, regex]
  import scripting/expose
  import dispatch_tables, vfs_config, config_provider, app_options
  import fsnotify

  logCategory "vfs-service"
  addBuiltinService(VFSService, ConfigService)

  proc localizePath*(self: VFSService, path: string): string

  method init*(self: VFSService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    log lvlInfo, &"VFSService.init"

    let localVfs = VFSLocal.new()
    self.localVfs = localVfs

    let localVfs2 = newVFSLocal()
    self.localVfs2 = localVfs2

    self.vfs = VFS()
    self.vfs.mount("", VFS())
    self.vfs.mount("local://", localVfs)
    self.vfs.mount("", VFSLink(target: localVfs, targetPrefix: ""))
    self.vfs.mount("app://", VFSLink(target: localVfs, targetPrefix: getAppDir().normalizeNativePath))
    self.vfs.mount("temp://", VFSLink(target: localVfs, targetPrefix: getTempDir().normalizeNativePath))
    self.vfs.mount("settings://", VFSConfig.new(self.services.getService(ConfigService).get))
    self.vfs.mount("ed://", VFSInMemory())
    self.vfs.mount("ws://", VFS())

    self.vfs2 = newVFS()
    self.vfs2.mount("", newVFS())
    self.vfs2.mount("local://", localVfs2)
    self.vfs2.mount("", newVFSLink(localVfs2, ""))
    self.vfs2.mount("app://", newVFSLink(localVfs2, getAppDir().normalizeNativePath))
    self.vfs2.mount("temp://", newVFSLink(localVfs2, getTempDir().normalizeNativePath))
    # self.vfs2.mount("settings://", VFSConfig.new(self.services.getService(ConfigService).get))
    # self.vfs2.mount("ed://", VFSInMemory())
    self.vfs2.mount("ws://", newVFS())

    var ignore = parseGlobs """
  *
  !*.json
  """

    localVfs.cacheDir(self.localizePath("app://config"), ignore)

    let homeDir = getHomeDir().normalizePathUnix.catch:
      log lvlError, &"Failed to get home directory: {getCurrentExceptionMsg()}"
      ""
    if homeDir != "":
      self.vfs.mount("home://", VFSLink(target: localVfs, targetPrefix: homeDir & "/"))
      self.vfs2.mount("home://", newVFSLink(localVfs2, homeDir & "/"))
      localVfs.cacheDir(self.localizePath("home://.nev"), ignore)

    try:
      if getAppOptions().fileToOpen.getSome(file):
        let path = os.absolutePath(file).normalizeNativePath
        localVfs.cacheFile(path)
        localVfs.cacheFile(path // ".nev-session")
      localVfs.cacheFile(getCurrentDir().normalizeNativePath // ".nev-session")
    except CatchableError as e:
      log lvlError, &"Failed to cache some files: {e.msg}"

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

  proc genTempPath*(self: VFSService, prefix: string, suffix: string, dir: string = "temp://", randLen: int = 8, checkExists: bool = true): string {.expose("vfs").} =
    self.vfs.genTempPath(prefix, suffix, dir, randLen, checkExists)

  proc dumpVfsHierarchy*(self: VFSService) {.expose("vfs").} =
    log lvlInfo, "\n" & self.vfs.prettyHierarchy()

  addGlobalDispatchTable "vfs", genDispatchTable("vfs")
