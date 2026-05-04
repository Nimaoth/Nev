import std/[macros, json, strutils, tables, options, os, sugar]
import misc/[custom_logger, custom_async, util, myjsonutils, event]
import scripting/expose
import service, vfs_service, vfs, vfs_local, dispatch_tables, events, config_provider, command_service
import lisp

import "../modules/stats"

include dynlib_export

{.push gcsafe.}
{.push raises: [].}

logCategory "plugins"

type PluginCommandLoadBehaviour* = enum
  DontRun = "dont-run"
  AsyncRun = "async-run"
  WaitAndRun = "wait-and-run"
  AsyncOrWait = "async-or-wait"

declareSettings PluginSettings, "plugins":
  # use openSession, OpenSessionSettings

  ## Whether to watch the plugin directories for changes and load new plugins
  declare watchPluginDirectories, bool, true

  ## Defines if and how to run commands which trigger a plugin to load.
  ## "dont-run": Don't run the command after the plugin is loaded. You have to manually run the command again.
  ## "async-run": Asynchronously load the plugin and run the command afterwards. If the command returns something
  ##              then the return value will not be available if the command is e.g. called from a plugin.
  ## "wait-and-run": Synchronously load the plugin and run the command afterwards. Return values work fine, but the editor
  ##                 will freeze while loading the plugin.
  ## "async-or-wait": Use "async-run" behaviour for commands with no return value and "wait-and-run" for commands with return values.
  declare commandLoadBehaviour, PluginCommandLoadBehaviour, AsyncOrWait

type
  WasiPermissions* = enum None = "none", Reduced = "reduced", Full = "full"

  FilesystemPermissions* = object
    allowAll*: Option[bool]
    disallowAll*: Option[bool]
    allow*: seq[string]
    disallow*: seq[string]

  PluginPermissions* = object
    filesystemRead*: FilesystemPermissions
    filesystemWrite*: FilesystemPermissions
    commands*: CommandPermissions
    wasi*: Option[WasiPermissions]
    wasiPreopenDirs*: seq[tuple[host, guest: string, read, write: bool]]
    time*: bool

  PluginInstanceBase* = ref object of RootObj
    setPermissionsImpl*: proc(self: PluginInstanceBase, permissions: PluginPermissions) {.gcsafe, raises: [].}

  PluginCommandDescription* = object
    parameters*: seq[tuple[name: string, `type`: string]]
    returnType*: string
    description*: string

  PluginManifest* = object
    name*: string
    id*: string
    path*: string
    authors*: seq[string]
    repository*: string
    autoLoad*: bool
    autoReload*: bool = false
    apiVersion*: int = -1
    wasm*: string
    permissions*: JsonNode
    load*: seq[JsonNode]
    commands*: Table[string, PluginCommandDescription]

  PluginState* = enum Unloaded, Loading, Loaded, Disabled, Failed

  Plugin* = ref object
    manifest*: PluginManifest
    state*: PluginState
    pluginSystem*: PluginSystem
    instance*: PluginInstanceBase
    dirty*: bool ## True if there are changes on disk for the plugin
    settings*: ConfigStore
    permissions*: PluginPermissions
    loadOnCommand*: bool = true
    registeredLoadCommands: Table[string, CommandId]

  PluginSystem* = ref object of RootObj
    deinitImpl*: proc(self: PluginSystem) {.gcsafe, raises: [].}
    reloadImpl*: proc(self: PluginSystem): Future[void] {.gcsafe, async: (raises: []).}
    postInitializeImpl*: proc(self: PluginSystem): bool {.gcsafe, raises: [].}
    getCurrentContextImpl*: proc(self: PluginSystem): string {.gcsafe, raises: [].}
    tryLoadPluginImpl*: proc(self: PluginSystem, plugin: Plugin, state: seq[uint8] = @[]): Future[bool] {.async: (raises: [IOError]).}
    unloadPluginImpl*: proc(self: PluginSystem, plugin: Plugin): Future[void] {.async: (raises: []).}
    dispatchDynamicImpl*: proc(self: PluginSystem, name: string, args: LispVal, namedArgs: LispVal): LispVal {.gcsafe, raises: [].}
    savePluginStateImpl*: proc(self: PluginSystem, plugin: Plugin): seq[uint8] {.gcsafe, raises: [].}

  PluginService* = ref object of DynamicService
    pluginSystems*: seq[PluginSystem]
    currentPluginSystem*: Option[PluginSystem] = PluginSystem.none
    plugins*: seq[Plugin]

func serviceName*(_: typedesc[PluginService]): string = "PluginService"

{.push apprtl, gcsafe, raises: [].}
proc pluginsAddPluginSystem(self: PluginService, pluginSystem: PluginSystem)
proc pluginsLoadPlugins(self: PluginService)
proc pluginsUnloadPlugin(self: PluginService, path: string) {.async.}
proc pluginsLoadPlugin(self: PluginService, path: string) {.async.}
proc pluginsReloadPlugin(self: PluginService, path: string) {.async.}
{.pop.}

proc addPluginSystem*(self: PluginService, pluginSystem: PluginSystem) = pluginsAddPluginSystem(self, pluginSystem)
proc loadPlugins*(self: PluginService) = pluginsLoadPlugins(self)
proc unloadPlugin*(self: PluginService, path: string) {.async.} = await pluginsUnloadPlugin(self, path)
proc loadPlugin*(self: PluginService, path: string) {.async.} = await pluginsLoadPlugin(self, path)
proc reloadPlugin*(self: PluginService, path: string) {.async.} = await pluginsReloadPlugin(self, path)

proc deinit*(self: PluginSystem) =
  if self.deinitImpl != nil:
    self.deinitImpl(self)

proc reload*(self: PluginSystem): Future[void] {.async: (raises: []).} =
  if self.reloadImpl != nil:
    await self.reloadImpl(self)

proc postInitialize*(self: PluginSystem): bool =
  if self.postInitializeImpl != nil:
    return self.postInitializeImpl(self)
  return true

proc getCurrentContext*(self: PluginSystem): string =
  if self.getCurrentContextImpl != nil:
    return self.getCurrentContextImpl(self)
  return ""

proc tryLoadPlugin*(self: PluginSystem, plugin: Plugin, state: seq[uint8] = @[]): Future[bool] {.async: (raises: [IOError]).} =
  if self.tryLoadPluginImpl != nil:
    return await self.tryLoadPluginImpl(self, plugin, state)
  return false

proc unloadPlugin*(self: PluginSystem, plugin: Plugin): Future[void] {.async: (raises: []).} =
  if self.unloadPluginImpl != nil:
    await self.unloadPluginImpl(self, plugin)

proc dispatchDynamic*(self: PluginSystem, name: string, args: LispVal, namedArgs: LispVal): LispVal =
  if self.dispatchDynamicImpl != nil:
    return self.dispatchDynamicImpl(self, name, args, namedArgs)
  return newNil()

proc savePluginState*(self: PluginSystem, plugin: Plugin): seq[uint8] =
  if self.savePluginStateImpl != nil:
    return self.savePluginStateImpl(self, plugin)
  return @[]

proc setPermissions*(self: PluginInstanceBase, permissions: PluginPermissions) =
  if self.setPermissionsImpl != nil:
    self.setPermissionsImpl(self, permissions)

when implModule:
  type

    PluginDirectory* = ref object
      path*: string
      watchHandle*: VFSWatchHandle

    VFSEvent = tuple
      pluginFolder: PluginDirectory
      path: string
      newPath: string
      action: FileEventAction

    PluginServiceImpl* = ref object of PluginService
      events: EventHandlerService
      vfs: VFS
      commands*: CommandService
      configService*: ConfigService
      settings*: ConfigStore

      pluginFolders*: seq[PluginDirectory]
      pathToPlugin*: Table[string, Plugin]
      idToPlugin*: Table[string, Plugin]

      autoLoadPlugins: bool = false

      pluginSettings*: PluginSettings

      isHandlingVFSEvents: bool
      vfsEvents: seq[VFSEvent]

  func serviceName*(_: typedesc[PluginServiceImpl]): string = "PluginService"

  proc addPluginFolder(self: PluginServiceImpl, path: string) {.async.}
  proc registerPluginCommands(self: PluginServiceImpl, plugin: Plugin)

  proc desc*(self: Plugin): string = &"'{self.manifest.name}' ({self.manifest.path})"

  proc initPluginService(self: PluginServiceImpl): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    self.events = self.services.getService(EventHandlerService).get
    self.vfs = self.services.getService(VFSService).get.vfs
    self.commands = self.services.getService(CommandService).get
    self.configService = self.services.getService(ConfigService).get
    self.settings = self.configService.runtime
    self.pluginSettings = PluginSettings.new(self.settings)

    asyncSpawn self.addPluginFolder("app://plugins")
    asyncSpawn self.addPluginFolder("home://.nev/plugins")
    return ok()

  proc updatePermissions(self: PluginServiceImpl, plugin: Plugin) =
    try:
      plugin.settings.set("permissions", plugin.manifest.permissions)
      let permissionsJson = plugin.settings.get("permissions", newJObject())
      plugin.permissions = permissionsJson.jsonTo(PluginPermissions, Joptions(allowExtraKeys: true, allowMissingKeys: true))
      if plugin.instance != nil:
        plugin.instance.setPermissions(plugin.permissions)
    except CatchableError as e:
      log lvlError, &"Failed to parse permissions for {plugin.desc}: {e.msg}"

  proc updateLoadedPluginCount(self: PluginServiceImpl) =
    if getService(StatsService).getSome(stats):
      var num = 0
      for plugin in self.plugins:
        if plugin.state == Loaded:
          inc num
      stats.set("Loaded Plugins", num)

  proc loadPlugin*(self: PluginServiceImpl, plugin: Plugin, state: seq[uint8] = @[]) {.async.} =
    if plugin.state notin {PluginState.Unloaded, PluginState.Failed}:
      return

    defer:
      self.updateLoadedPluginCount()

    log lvlInfo, &"Load plugin {plugin.desc}"
    plugin.state = Loading
    self.updatePermissions(plugin)
    for ps in self.pluginSystems:
      try:
        if ps.tryLoadPlugin(plugin, state).await:
          plugin.state = Loaded
          plugin.dirty = false
          return
      except IOError as e:
        plugin.state = Failed
        log lvlWarn, &"Plugin {plugin.desc} could not be loaded: {e.msg}"

    plugin.state = Failed
    log lvlWarn, &"Plugin {plugin.desc} could not be loaded."

  proc unloadPlugin*(self: PluginServiceImpl, plugin: Plugin) {.async.} =
    if plugin.state != PluginState.Loaded:
      return

    defer:
      self.updateLoadedPluginCount()

    for id in plugin.registeredLoadCommands.values:
      self.commands.unregisterCommand(id)
    plugin.registeredLoadCommands.clear()

    if plugin.pluginSystem != nil:
      log lvlInfo, &"Unload plugin {plugin.desc}"
      await plugin.pluginSystem.unloadPlugin(plugin)
      plugin.pluginSystem = nil
      plugin.instance = nil

      # Register these commands again so the plugin can get loaded again when running one of these commands
      self.registerPluginCommands(plugin)

    plugin.state = PluginState.Unloaded

  proc reloadPlugin*(self: PluginServiceImpl, plugin: Plugin) {.async.} =
    if plugin.state == PluginState.Disabled:
      return

    var state = newSeq[uint8]()
    if plugin.state == PluginState.Loaded and plugin.pluginSystem != nil:
      log lvlInfo, &"Save plugin state {plugin.desc}"
      state = plugin.pluginSystem.savePluginState(plugin)

    await self.unloadPlugin(plugin)
    await self.loadPlugin(plugin, state)

  proc pluginsUnloadPlugin(self: PluginService, path: string) {.async.} =
    let self = self.PluginServiceImpl
    for p in self.plugins:
      if p.manifest.path == path:
        await self.unloadPlugin(p)
        return

  proc pluginsLoadPlugin(self: PluginService, path: string) {.async.} =
    let self = self.PluginServiceImpl
    for p in self.plugins:
      if p.manifest.path == path:
        await self.loadPlugin(p)
        return

  proc pluginsReloadPlugin(self: PluginService, path: string) {.async.} =
    let self = self.PluginServiceImpl
    for p in self.plugins:
      if p.manifest.path == path:
        await self.reloadPlugin(p)
        return

  proc pluginsLoadPlugins(self: PluginService) =
    let self = self.PluginServiceImpl
    self.autoLoadPlugins = true
    for p in self.plugins:
      if not p.manifest.autoLoad:
        continue
      if p.state == PluginState.Unloaded:
        asyncSpawn self.loadPlugin(p)

  proc registerPluginCommands(self: PluginServiceImpl, plugin: Plugin) =
    for (name, desc) in plugin.manifest.commands.pairs:
      let name = plugin.manifest.id & "." & name
      capture name, desc:
        let id = self.commands.registerCommand(command_service.Command(
          name: name,
          parameters: desc.parameters,
          description: desc.description,
          execute: (proc(args: string): string =
            if plugin.state == PluginState.Unloaded and plugin.loadOnCommand:
              var commandLoadBehaviour = self.pluginSettings.commandLoadBehaviour.get()
              if commandLoadBehaviour == AsyncOrWait:
                if desc.returnType == "":
                  commandLoadBehaviour = AsyncRun
                else:
                  commandLoadBehaviour = WaitAndRun

              let fut = self.loadPlugin(plugin)
              case commandLoadBehaviour
              of DontRun:
                asyncSpawn fut

              of AsyncRun:
                fut.thenIt:
                  if plugin.state == Loaded:
                    discard self.commands.executeCommand(name & " " & args)

              of WaitAndRun:
                try:
                  waitFor fut
                  if plugin.state == Loaded:
                    return self.commands.executeCommand(name & " " & args).get("")
                  return ""
                except CatchableError as e:
                  log lvlWarn, &"Failed to wait for plugin to load: {e.msg}"
                  return ""

              of AsyncOrWait:
                assert false
          )
        ), override = true)
        plugin.registeredLoadCommands[name] = id

  proc createPlugin(self: PluginServiceImpl, manifest: sink PluginManifest) =
    log lvlInfo, &"Register plugin {manifest}"
    if self.idToPlugin.contains(manifest.id):
      log lvlWarn, &"Failed to register plugin manifest\n{manifest}\nPlugin with same id already exists:\n{self.idToPlugin[manifest.id].manifest}"
      return

    let plugin = Plugin(
      manifest: manifest.ensureMove,
    )
    if plugin.manifest.permissions == nil:
      plugin.manifest.permissions = newJObject()

    plugin.settings = self.configService.addStore("plugin-" & plugin.manifest.id, &"settings://plugin/{plugin.manifest.id}")
    plugin.settings.prefix = "plugin." & plugin.manifest.id
    self.updatePermissions(plugin)
    self.plugins.add(plugin)
    self.pathToPlugin[plugin.manifest.path] = plugin
    self.idToPlugin[plugin.manifest.id] = plugin
    self.registerPluginCommands(plugin)

    if plugin.manifest.autoLoad:
      self.services.getService(VFSService).get.localVfs.cacheFile(self.vfs.localize(plugin.manifest.wasm))

    # todo: maybe this should be just subscribed once when the service starts and then loop over all loaded plugins
    discard self.settings.onConfigChanged.subscribe proc(key: string) =
      if key == "" or key == "permissions" or key.startsWith("permissions"):
        self.updatePermissions(plugin)

    if self.autoLoadPlugins and plugin.manifest.autoLoad:
      asyncSpawn self.loadPlugin(plugin)

  proc addManifestFromFile(self: PluginServiceImpl, pluginFolder: PluginDirectory, file: string) {.async.} =
    if file.endsWith(".m.wasm"):
      var name = file.splitPath.tail
      name.removeSuffix(".m.wasm")
      self.createPlugin(PluginManifest(
        name: name,
        id: name,
        path: pluginFolder.path // file,
        wasm: pluginFolder.path // file,
        permissions: newJObject(),
      ))

  proc addManifestFromFolder(self: PluginServiceImpl, pluginFolder: PluginDirectory, folder: string) {.async.} =
    try:
      let manifestJson = self.vfs.read(pluginFolder.path // folder // "manifest.json").await
      var manifest = manifestJson.parseJson().jsonTo(PluginManifest, Joptions(allowExtraKeys: true, allowMissingKeys: true))
      manifest.path = pluginFolder.path // folder
      manifest.id = folder
      if manifest.wasm != "":
        manifest.wasm = pluginFolder.path // folder // manifest.wasm
      if manifest.permissions == nil:
        manifest.permissions = newJObject()
      self.createPlugin(manifest)
    except IOError as e:
      log lvlError, &"Failed to find manifest.json in '{folder}': {e.msg}"
    except ValueError as e:
      log lvlError, &"Failed to parse manifest.json in '{folder}': {e.msg}"
    except CatchableError as e:
      log lvlError, &"Failed to load manifest.json in '{folder}': {e.msg}"

  proc getPlugin(self: PluginServiceImpl, path: string): Option[Plugin] =
    if self.pathToPlugin.contains(path):
      return self.pathToPlugin[path].some
    return Plugin.none

  proc handleVFSEvents(self: PluginServiceImpl) {.async.} =
    boolLock(self.isHandlingVFSEvents)
    var i = 0
    while i < self.vfsEvents.len:
      defer:
        inc i

      let e = self.vfsEvents[i]
      case e.action
      of FileEventAction.Modify:
        let fullPath = e.pluginFolder.path // e.path
        let isDir = self.vfs.getFileKind(fullPath).await
        let (container, _) = e.path.splitPath
        if isDir.getSome(isDir):
          let pluginPathRelative = if container == "":
            e.path
          else:
            container
          let pluginPath = e.pluginFolder.path // pluginPathRelative

          if self.getPlugin(pluginPath).getSome(existingPlugin):
            log lvlInfo, &"Plugin file '{fullPath}' changed"
            existingPlugin.dirty = true
            if existingPlugin.manifest.autoReload and isDir == FileKind.Directory:
              asyncSpawn self.reloadPlugin(existingPlugin)
          else:
            log lvlInfo, "New plugin ", pluginPath
            if container != "" or isDir == FileKind.Directory:
              await self.addManifestFromFolder(e.pluginFolder, pluginPathRelative)
            else:
              await self.addManifestFromFile(e.pluginFolder, pluginPathRelative)


      else:
        discard

    self.vfsEvents.setLen(0)

  proc loadPluginManifests(self: PluginServiceImpl, pluginFolder: PluginDirectory) {.async.} =
    log lvlInfo, &"Load plugin manifests from '{pluginFolder.path}'"
    let root = pluginFolder.path
    let listing = await self.vfs.getDirectoryListing(root)

    for path in listing.files:
      await self.addManifestFromFile(pluginFolder, path)

    for path in listing.folders:
      await self.addManifestFromFolder(pluginFolder, path)

    if self.pluginSettings.watchPluginDirectories.get():
      log lvlInfo, &"Watch plugin pluginFolder: {pluginFolder.path}"
      pluginFolder.watchHandle = self.vfs.watch(pluginFolder.path, proc(events: seq[PathEvent]) =
        var vfsEvents = newSeq[VFSEvent]()
        for event in events:
          vfsEvents.add (pluginFolder, event.name.normalizeNativePath, event.newName.normalizeNativePath, event.action)
        self.vfsEvents.add vfsEvents
        asyncSpawn self.handleVFSEvents()
      )

  proc addPluginFolder(self: PluginServiceImpl, path: string) {.async.} =
    for it in self.pluginFolders:
      if it.path == path:
        return

    log lvlInfo, &"Add plugin folder '{path}'"
    self.pluginFolders.add PluginDirectory(path: path)
    await self.loadPluginManifests(self.pluginFolders.last)

  {.pop.} # raises

  template withPluginSystem*(self: PluginServiceImpl, pluginSystem: untyped, body: untyped): untyped =
    if pluginSystem.isNotNil:
      let oldScriptContext = self.currentPluginSystem
      {.push hint[ConvFromXtoItselfNotNeeded]:off.}
      self.currentPluginSystem = pluginSystem.PluginSystem.some
      {.pop.}
      defer:
        self.currentPluginSystem = oldScriptContext
      body

  proc getPluginService(): Option[PluginServiceImpl] =
    {.gcsafe.}:
      if getServices().isNil: return PluginServiceImpl.none
      return getServices().getService(PluginServiceImpl)

  static:
    addInjector(PluginServiceImpl, getPluginService)

  proc bindKeys*(self: PluginServiceImpl, context: string, subContext: string, keys: string, action: string, arg: string = "", description: string = "", source: tuple[filename: string, line: int, column: int] = ("", 0, 0)) {.expose("plugins").} =
    let command = if arg.len == 0: action else: action & " " & arg
    log(lvlInfo, fmt"Adding command to '{context}': ('{subContext}', '{keys}', '{command}')")

    let (context, subContext) = if (let i = context.find('#'); i != -1):
      (context[0..<i], context[i+1..^1] & subContext)
    else:
      (context, subContext)

    if description.len > 0:
      self.events.commandDescriptions[context & subContext & keys] = description

    var source = source
    if self.currentPluginSystem.getSome(pluginSystem):
      source.filename = pluginSystem.getCurrentContext() & source.filename

    self.events.getEventHandlerConfig(context).addCommand(subContext, keys, command, source)
    self.events.invalidateCommandToKeysMap()

  addGlobalDispatchTable "plugins", genDispatchTable("plugins")

  proc pluginsAddPluginSystem(self: PluginService, pluginSystem: PluginSystem) =
    self.PluginServiceImpl.pluginSystems.add pluginSystem

  proc init_module_plugin_service*() {.cdecl, exportc, dynlib.} =
    getServices().addService(PluginServiceImpl(
      initImpl: proc(self: Service): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
        return await self.PluginServiceImpl.initPluginService()
    ), @[EventHandlerService.serviceName, VFSService.serviceName, CommandService.serviceName, ConfigService.serviceName])
