import nimsumtree/[arc]
import service, vfs

export vfs

const currentSourcePath2 = currentSourcePath()
include module_base

{.push gcsafe.}
{.push raises: [].}

type
  VFSService* = ref object of DynamicService
    vfs2*: Arc[VFS2]

func serviceName*(_: typedesc[VFSService]): string = "VFSService"

when implModule:
  import std/[tables, options, json, os]
  import results
  import misc/[custom_async, custom_logger, myjsonutils, util, regex]
  import scripting/expose
  import dispatch_tables, vfs_config, config_provider, app_options
  import fsnotify, vfs_local

  logCategory "vfs-service"

  proc localizePath*(self: VFSService, path: string): string

  proc newVFSService(): VFSService =
    log lvlInfo, &"VFSService.init"
    let self = VFSService()

    let localVfs2 = newVFSLocal()

    self.vfs2 = newVFS()
    self.vfs2.mount("", newVFS())
    self.vfs2.mount("local://", localVfs2)
    self.vfs2.mount("", newVFSLink(localVfs2, ""))
    self.vfs2.mount("app://", newVFSLink(localVfs2, getAppDir().normalizeNativePath))
    self.vfs2.mount("unsaved://", newVFSLink(self.vfs2.getVFS("app://", 1).vfs, "unsaved"))
    self.vfs2.mount("temp://", newVFSLink(localVfs2, getTempDir().normalizeNativePath))
    self.vfs2.mount("settings://", newVFSConfig())
    let edVFs = newVFSInMemory()
    self.vfs2.mount("ed://", edVFs)
    self.vfs2.mount("ws://", newVFS())

    var ignore = parseGlobs """
  *
  !*.json
  """

    localVfs2.cacheDir(self.localizePath("app://config"), ignore)

    let homeDir = getHomeDir().normalizePathUnix.catch:
      log lvlError, &"Failed to get home directory: {getCurrentExceptionMsg()}"
      ""
    if homeDir != "":
      self.vfs2.mount("home://", newVFSLink(localVfs2, homeDir & "/"))
      localVfs2.cacheDir(self.localizePath("home://.nev"), ignore)

    try:
      if getAppOptions().fileToOpen.getSome(file):
        let path = os.absolutePath(file).normalizeNativePath
        localVfs2.cacheFile(path)
        localVfs2.cacheFile(path // ".nev-session")
      localVfs2.cacheFile(getCurrentDir().normalizeNativePath // ".nev-session")
    except CatchableError as e:
      log lvlError, &"Failed to cache some files: {e.msg}"

    return self

  proc createVfs2*(self: VFSService, config: JsonNode): Option[Arc[VFS2]] =
    result = Arc[VFS2].none
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
        self.vfs2.getVFS(t, targetMaxDepth)
      else:
        (self.vfs2, "")

      if sub != "":
        log lvlError, &"Unknown target '{targetName}', unmatched: '{sub}'"
        return Arc[VFS2].none

      let targetPrefix = config.fields.getOrDefault("targetPrefix", newJString("")).getStr.expect("string 'targetPrefix'", $config)

      # log lvlInfo, &"create VFSLink {target.name}, {target.prefix}, {targetPrefix}"
      return newVFSLink(target, targetPrefix).some

    else:
      log lvlError, &"Invalid VFS config, unknown type '{typ}'"
      return Arc[VFS2].none

  ###########################################################################

  proc getVfsService(): Option[VFSService] =
    {.gcsafe.}:
      if getServices().isNil: return VFSService.none
      return getServices().getService(VFSService)

  static:
    addInjector(VFSService, getVfsService)

  proc mountVfs*(self: VFSService, parentPath: Option[string], prefix: string, config: JsonNode) {.expose("vfs").} =
    log lvlInfo, &"Mount VFS '{parentPath}', '{prefix}', {config}"
    let vfs2 = if parentPath.getSome(p):
      self.vfs2.getVFS(p).vfs
    else:
      self.vfs2

    if self.createVfs2(config).getSome(newVFS):
      vfs2.mount(prefix, newVFS)

  proc normalizePath*(self: VFSService, path: string): string {.expose("vfs").} =
    return self.vfs2.normalize(path)

  proc localizePath*(self: VFSService, path: string): string {.expose("vfs").} =
    return self.vfs2.localize(path)

  proc writeFileSync*(self: VFSService, path: string, content: string) {.expose("vfs").} =
    try:
      waitFor self.vfs2.write(path, content)
    except IOError as e:
      log lvlError, &"Failed to write file '{path}': {e.msg}"

  proc readFileSync*(self: VFSService, path: string): string {.expose("vfs").} =
    try:
      return waitFor self.vfs2.read(path)
    except IOError as e:
      log lvlError, &"Failed to read file '{path}': {e.msg}"

  proc deleteFileSync*(self: VFSService, path: string) {.expose("vfs").} =
    try:
      discard waitFor self.vfs2.delete(path)
    except IOError as e:
      log lvlError, &"Failed to delete file '{path}': {e.msg}"

  proc genTempPath*(self: VFSService, prefix: string, suffix: string, dir: string = "temp://", randLen: int = 8, checkExists: bool = true): string {.expose("vfs").} =
    self.vfs2.genTempPath(prefix, suffix, dir, randLen, checkExists).waitFor

  # proc dumpVfsHierarchy*(self: VFSService) {.expose("vfs").} =
  #   log lvlInfo, "\n" & self.vfs2.prettyHierarchy()

  addGlobalDispatchTable "vfs", genDispatchTable("vfs")

  proc init_module_vfs_service*() {.cdecl, exportc, dynlib.} =
    getServices().addService(newVFSService())
