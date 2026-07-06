import std/[json, options, tables, macros, genasts, sets, typetraits, strformat, strutils]
import misc/[util, event, custom_async, custom_logger, myjsonutils, jsonex, id, custom_unicode]
import service, lisp
import config_store
from scripting_api import LineNumbers

export config_store

include misc/dynlib_export

logCategory "config"

type
  ConfigLayerKind* = enum Unchanged, Extend, Override

  ConfigService* = ref object of Service
    onConfigChanged*: Event[void]
    base*: ConfigStore
    runtime*: ConfigStore

    storeGroups*: Table[string, seq[ConfigStore]]
    stores*: Table[string, ConfigStore]
    storesByName*: Table[string, ConfigStore]
    groups*: seq[string]

  Setting*[T] = ref object
    store*: ConfigStore
    cache*: Option[T]
    revision*: int
    key*: string
    defaultValue*: T

  SettingGroupDescription* = object
    settings*: seq[int]

  SettingDescription* = object
    fullName*: string
    prefix*: string
    name*: string
    typ*: string
    typeName*: string
    default*: string
    docs*: string
    noInit*: bool

  DiagnosticsLocation* = enum LineEnd = "line-end", Below = "below", LineEndOrBelow = "line-end-or-below"

  ToastStyle* = enum Minimal = "minimal", Box = "box"

func serviceName*(_: typedesc[ConfigService]): string = "ConfigService"

const defaultToJsonOptions = ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef)

proc toJsonExHook*[T](a: Setting[T]): JsonNodeEx {.raises: [].} =
  let v = a.get()
  return v.toJsonEx(defaultToJsonOptions)

proc setting*(self: ConfigStore, key: string, T: typedesc, def: JsonNodeEx = nil): Setting[T] {.gcsafe.} =
  # if def != nil:
  #   echo &"setting '{key}' with def {def}"
  let def = try:
    if def != nil:
      when T is JsonNodeEx:
        def
      elif T is JsonNode:
        def.toJson()
      else:
        def.jsonTo(T)
    else:
      T.default
  except CatchableError:
    T.default

  return Setting[T](store: self, key: key, defaultValue: def)

{.push apprtl, gcsafe, raises: [].}
proc configServiceGetLanguageStore(self: ConfigService, languageId: string): ConfigStore
proc configServiceAddStore(self: ConfigService, name, filename: string, parent: ConfigStore = nil, settings: JsonNodeEx = newJexObject()): ConfigStore
proc configServiceRemoveStore(self: ConfigService, store: ConfigStore)
proc configServiceGetByPath(self: ConfigService, path: string): JsonNodeEx
proc configServiceGetStoreForPath(self: ConfigService, path: string): (ConfigStore, string)
proc configReconnectGroups(self: ConfigService)
proc configGetStoreForId(self: ConfigService, id: int): ConfigStore
proc configGetSettingDescription(self: ConfigService, key: string): Option[SettingDescription]
{.pop.}

proc getLanguageStore*(self: ConfigService, languageId: string): ConfigStore = configServiceGetLanguageStore(self, languageId)
proc addStore*(self: ConfigService, name, filename: string, parent: ConfigStore = nil, settings: JsonNodeEx = newJexObject()): ConfigStore = configServiceAddStore(self, name, filename, parent, settings)
proc removeStore*(self: ConfigService, store: ConfigStore) = configServiceRemoveStore(self, store)
proc getByPath*(self: ConfigService, path: string): JsonNodeEx = configServiceGetByPath(self, path)
proc getStoreForPath*(self: ConfigService, path: string): (ConfigStore, string) = configServiceGetStoreForPath(self, path)
proc reconnectGroups*(self: ConfigService) = configReconnectGroups(self)
proc getStoreForId*(self: ConfigService, id: int): ConfigStore = configGetStoreForId(self, id)
proc getSettingDescription*(self: ConfigService, key: string): Option[SettingDescription] = configGetSettingDescription(self, key)

proc get*[T](self: Setting[T], default: T): lent T =
  if self.cache.isSome and self.revision == self.store.revision:
    return self.cache.get
  self.cache = self.store.get(self.key, default).some
  self.revision = self.store.revision
  return self.cache.get

proc get*[T](self: Setting[T]): lent T =
  return self.get(self.defaultValue)

proc set*[T](self: Setting[T], value: T) =
  self.store.set(self.key, value)

proc get*[T](self: Setting[Option[T]], default: T): T =
  let v = self.get()
  if v.isSome:
    return v.get
  return default

proc getRegex*(self: Setting[RegexSetting], default: string = ""): string =
  let value = self.get().impl
  if value == nil:
    return default
  return value.decodeRegex(default)

proc getRegex*(self: Setting[Option[RegexSetting]]): Option[string] =
  let value = self.get()
  if value.isNone:
    return string.none
  return value.get.decodeRegex("").some

proc getRegex*(self: Setting[Option[RegexSetting]], default: string): string =
  let value = self.get()
  if value.isNone:
    return default
  return value.get.decodeRegex(default)

when implModule:
  import std/[algorithm, macrocache]
  import platform
  import default_settings

  {.push gcsafe.}
  {.push raises: [].}

  addBuiltinService(ConfigService)

  method init*(self: ConfigService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    log lvlInfo, &"ConfigService.init"
    # {.gcsafe.}:
      # for desc in getSettingDescriptions():
      #   self.settingDescriptions.add desc

    self.base = ConfigStore.new("base", "settings://base")
    fillDefaultSettings(self.base)
    self.runtime = ConfigStore.new("runtime", "settings://runtime")
    self.runtime.setParent(self.base)
    return ok()

  proc configGetSettingDescription(self: ConfigService, key: string): Option[SettingDescription] =
    return SettingDescription.none

  proc configServiceRemoveStore(self: ConfigService, store: ConfigStore) =
    store.setParent(nil)
    self.stores.del(store.filename)
    self.storesByName.del(store.name)

  proc configServiceAddStore(self: ConfigService, name, filename: string, parent: ConfigStore = nil, settings: JsonNodeEx = newJexObject()): ConfigStore =
    let parent = if parent != nil: parent else: self.runtime
    result = ConfigStore.new(name, filename, parent, settings)
    self.stores[filename] = result
    self.storesByName[name] = result

  proc configServiceGetLanguageStore(self: ConfigService, languageId: string): ConfigStore =
    let path = "languages/" & languageId
    if self.stores.contains(path):
      return self.stores[path]

    let prefix = "lang." & languageId
    let store = self.addStore(languageId, path, self.runtime)
    let v = store.parent.get(prefix)
    if v != nil:
      store.setSettings(v)
    store.parent.onConfigChanged.unsubscribe(store.parentChangedHandle)
    store.parentChangedHandle = store.parent.onConfigChanged.subscribe proc(key: string) =
      if key.startsWith(prefix) or key == "lang" or key == "":
        let v = store.parent.get(prefix)
        if v != nil:
          store.setSettings(v)
        else:
          store.setSettings(newJexObject())
      else:
        var val = store.settings
        var extend = val.extend
        for keyRaw in key.splitOpenArray('.'):
          if isNil(val) or val.kind != JObject:
            val = nil
            break
          val = val.fields.getOrDefault(keyRaw.p.toOpenArray(0, keyRaw.len - 1))
          if val != nil:
            extend = extend and val.extend

        if val == nil or extend:
          store.onConfigChanged.invoke(key)

    return store

  proc firstGroupConfigStore*(self: ConfigService): ConfigStore =
    for group in self.groups:
      if group notin self.storeGroups:
        continue
      let stores = self.storeGroups[group]
      if stores.len == 0:
        continue
      return stores[0]

    return nil

  proc lastGroupConfigStore*(self: ConfigService): ConfigStore =
    for i in countdown(self.groups.high, 0):
      let group = self.groups[i]
      if group notin self.storeGroups:
        continue
      let stores = self.storeGroups[group]
      if stores.len == 0:
        continue
      return stores[^1]

    return nil

  proc configReconnectGroups(self: ConfigService) =
    var lastGroup = self.groups[0]
    for i in 1..self.groups.high:
      let childGroup = self.groups[i]

      if childGroup notin self.storeGroups:
        continue

      if lastGroup in self.storeGroups:
        let child = self.storeGroups[childGroup][0]
        let parent = self.storeGroups[lastGroup][^1]
        child.setParent(parent)

      lastGroup = childGroup

    let first = self.firstGroupConfigStore()
    if first != nil:
      first.setParent(self.base)

      let last = self.lastGroupConfigStore()
      assert last != nil
      self.runtime.setParent(last)

    else:
      self.runtime.setParent(self.base)

  proc configGetStoreForId(self: ConfigService, id: int): ConfigStore =
    for store in self.runtime.parentStores:
      if store.id == id:
        return store

    return nil

  proc configServiceGetStoreForPath(self: ConfigService, path: string): (ConfigStore, string) =
    for store in self.runtime.parentStores:
      if path.startsWith(store.name):
        return (store, path[store.name.len..^1].strip(chars = {'/'}).replace("/", "."))

    for storeName in self.storesByName.keys:
      if path.startsWith(storeName & "/"):
        return (self.storesByName[storeName], path[storeName.len..^1].strip(chars = {'/'}).replace("/", "."))
      if path == storeName:
        return (self.storesByName[storeName], "")

    log lvlWarn, &"getStoreForPath '{path}' not found"
    return (nil, "")

  proc configServiceGetByPath(self: ConfigService, path: string): JsonNodeEx =
    let (store, key) = self.getStoreForPath(path)
    if store == nil:
      return nil
    return store.get(key)

  proc getByPath*(self: ConfigService, path: string, T: typedesc, defaultValue: T): T =
    let value = self.getByPath(path)
    if value != nil:
      try:
        return value.jsonTo(T)
      except Exception as e:
        let t = $T
        log lvlError, &"Failed to get setting as type {t}: {e.msg}\n{value.pretty}"
        return defaultValue
    else:
      return defaultValue

  proc getByPath*(self: ConfigService, path: string, T: typedesc): T {.inline.} =
    self.getByPath(path, T, T.default)

  ###########################################################################

  proc logOptions*(self: ConfigService) =
    log lvlInfo, self.runtime.mergedSettings.pretty()

  proc setOption*(self: ConfigService, option: string, value: JsonNode, override: bool = true) =
    if self.isNil:
      return

    self.runtime.set(option, value.toJsonEx(defaultToJsonOptions))
    self.onConfigChanged.invoke()
    self.services.getServiceChecked(PlatformService).platform.requestRender(true)

  proc cycleOption*(self: ConfigService, path: string, values: JsonNode) =
    if self.isNil:
      return

    let current = self.runtime.get(path, newJNull())
    if values.kind == JArray:
      for i, option in values.elems:
        if option == current:
          let nextIndex = (i + 1) mod values.elems.len
          let value = values.elems[nextIndex]
          self.runtime.set(path, value.toJsonEx(defaultToJsonOptions))
          self.onConfigChanged.invoke()
          self.services.getServiceChecked(PlatformService).platform.requestRender(true)
          return
      if values.elems.len > 0:
        let value = values.elems[0]
        self.runtime.set(path, value.toJsonEx(defaultToJsonOptions))
        self.onConfigChanged.invoke()
        self.services.getServiceChecked(PlatformService).platform.requestRender(true)

  proc getOptionJson*(self: ConfigService, path: string, default: JsonNode = newJNull()): JsonNode =
    return self.runtime.get(path, default)

  proc getFlag*(self: ConfigService, flag: string, default: bool = false): bool =
    return self.runtime.get(flag, bool, default)

  proc setFlag*(self: ConfigService, flag: string, value: bool) =
    self.runtime.set(flag, value)

  proc toggleFlag*(self: ConfigService, flag: string) =
    let newValue = not self.getFlag(flag)
    log lvlInfo, fmt"toggleFlag '{flag}' -> {newValue}"
    self.setFlag(flag, newValue)

  {.pop.} # raises: []
  {.pop.} # gcsafe

