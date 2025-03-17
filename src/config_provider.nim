import std/[json, options, strutils, tables, enumerate, sequtils]
import misc/[traits, util, event, custom_async, custom_logger, myjsonutils, jsonex]
import scripting/expose
import platform/platform
import service, platform_service, dispatch_tables

{.push gcsafe.}
{.push raises: [].}

logCategory "config"

type
  ConfigLayerKind* = enum Unchanged, Extend, Override

  ConfigService* = ref object of Service
    onConfigChanged*: Event[void]
    mainConfig*: ConfigStore
    runtime*: ConfigStore

    storeGroups*: Table[string, seq[ConfigStore]]
    stores*: Table[string, ConfigStore]
    groups*: seq[string]

  ConfigStore* = ref object
    id: int
    parent*: ConfigStore
    revision*: int
    name*: string
    detail*: string
    filename*: string
    originalText*: string
    settings*: JsonNodeEx
    mergedSettingsCache: tuple[parent: JsonNodeEx, revision: int, settings: JsonNodeEx]
    onConfigChanged*: Event[string]

  Setting*[T] = ref object
    store*: ConfigStore
    cache*: Option[T]
    layers*: seq[ConfigStoreLayer]
    key*: string

  ConfigStoreLayer = tuple[revision: int, kind: ConfigLayerKind, store: ConfigStore]

proc setUserData(node: JsonNodeEx, userData: int)
proc evaluateSettingsRec(target: var JsonNodeEx, node: JsonNodeEx)

func serviceName*(_: typedesc[ConfigService]): string = "ConfigService"

addBuiltinService(ConfigService)

var nextConfigStoreId = 1
proc new*(_: typedesc[ConfigStore], parent: ConfigStore, name: string, settings: JsonNodeEx = newJexObject()): ConfigStore =
  let id = block:
    {.gcsafe.}:
      let id = nextConfigStoreId
      inc nextConfigStoreId
      id

  result = ConfigStore(id: id, parent: parent, name: name, filename: name, settings: newJexObject())
  result.settings.setUserData(id)
  settings.setUserData(id)
  result.settings.evaluateSettingsRec(settings)
  result.settings.extend = true

method init*(self: ConfigService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"ConfigService.init"
  self.mainConfig = ConfigStore.new(nil, "runtime")
  self.mainConfig.filename = "settings://runtime"
  self.runtime = self.mainConfig
  return ok()

proc desc*(self: ConfigStore, pretty = false): string =
  result = &"CS({self.name}@{self.revision}"
  if not self.parent.isNil:
    if pretty:
      result.add "\n"
      result.add self.parent.desc(pretty).indent(2)
    else:
      result.add ", "
      result.add self.parent.desc
  result.add ")"

proc lastGroupConfigStore*(self: ConfigService): ConfigStore =
  if self.groups.len > 0:
    let group = self.groups[^1]
    if group notin self.storeGroups:
      return nil
    let stores = self.storeGroups[group]
    if stores.len == 0:
      return nil
    return stores[^1]

  return nil

proc reconnectGroups*(self: ConfigService) =
  for i in 1..self.groups.high:
    let childGroup = self.groups[i]
    let parentGroup = self.groups[i - 1]
    echo &"reconnectGroups {childGroup} -> {parentGroup}"

    let child = self.storeGroups[childGroup][0]
    let parent = self.storeGroups[parentGroup][^1]
    echo &"  {child.desc} -> {parent.desc}"

    if child.parent != parent:
      child.parent = parent
      inc child.revision

  let child = self.runtime
  let parent = self.lastGroupConfigStore()

  if child.parent != parent:
    child.parent = parent
    inc child.revision

proc `$`*(self: ConfigStore): string =
  result = self.desc
  result.add "\n"
  result.add self.settings.pretty().indent(2)

proc setUserData(node: JsonNodeEx, userData: int) =
  node.userData = userData
  if node.kind == JObject:
    for value in node.fields.values:
      value.setUserData(userData)
  elif node.kind == JArray:
    for value in node.elems:
      value.setUserData(userData)

proc evaluateSettingsRec(target: var JsonNodeEx, node: JsonNodeEx) =
  proc findSep(str: string, start: int): int =
    result = str.find('.', start)
    while result != -1 and result + 1 <= str.high and str[result + 1] == '.':
      result = str.find('.', result + 2)

  if node.kind == JObject:
    target = newJexObject()
    target.setUserData(node.userData)
    for (key, field) in node.fields.pairs:
      var prevI = 0
      var i = key.findSep(0)

      var subTarget = target
      while i != -1:
        var extend = false
        if key[prevI] == '+':
          extend = true
          inc prevI

        let sub = key[prevI..<i].replace("..", ".")

        if subTarget.hasKey(sub):
          subTarget = subTarget[sub]
        else:
          var subObject = newJexObject()
          subObject.setUserData(node.userData)
          subObject.extend = extend
          subTarget[sub] = subObject
          subTarget = subObject

        prevI = i + 1
        i = key.findSep(prevI)

      var extend = false
      if key[prevI] == '+':
        extend = true
        inc prevI
      let sub = key[prevI..^1].replace("..", ".")

      var evaluatedField: JsonNodeEx
      evaluatedField.evaluateSettingsRec(field)
      evaluatedField.extend = extend
      subTarget[sub] = evaluatedField

  else:
    target = node

proc setParent*(self: ConfigStore, parent: ConfigStore) =
  if self.parent != parent:
    self.parent = parent
    self.mergedSettingsCache.settings = nil
    inc self.revision
    self.onConfigChanged.invoke("")

proc setSettings*(self: ConfigStore, settings: JsonNodeEx) =
  self.settings = newJexObject()
  self.settings.setUserData(self.id)
  settings.setUserData(self.id)
  self.settings.evaluateSettingsRec(settings)
  self.settings.extend = true
  self.mergedSettingsCache.settings = nil
  inc self.revision
  self.onConfigChanged.invoke("")

iterator parentStores*(self: ConfigStore, includeSelf: bool = true): ConfigStore =
  var it = self
  if not includeSelf:
    it = it.parent
  while not it.isNil:
    yield it
    it = it.parent

proc extendJson*(a: var JsonNodeEx, b: JsonNodeEx) =
  if not b.extend:
    a = b
    return

  if (a.kind, b.kind) == (JObject, JObject):
    for (key, value) in b.fields.pairs:
      if a.hasKey(key):
        a.fields[key].extendJson(value)
      else:
        a[key] = value

  elif (a.kind, b.kind) == (JArray, JArray):
    for value in b.elems:
      a.elems.add value

  else:
    a = b

proc mergedSettings*(self: ConfigStore): JsonNodeEx =
  if self.parent != nil:
    let parentMergedSettings = self.parent.mergedSettings
    if self.mergedSettingsCache.settings == nil or parentMergedSettings != self.mergedSettingsCache.parent or self.mergedSettingsCache.revision != self.parent.revision:
      # log lvlInfo, &"Parent changed for ConfigStore {self.desc}, recalculate merged settings"
      var mergedSettings = parentMergedSettings.copy()
      mergedSettings.extendJson(self.settings)
      self.mergedSettingsCache = (parentMergedSettings, self.parent.revision, mergedSettings)

    return self.mergedSettingsCache.settings

  else:
    return self.settings

proc clear*(self: ConfigStore, key: string) =
  log lvlInfo, &"Clear setting '{key}' in {self.desc()}"

  inc self.revision
  self.mergedSettingsCache.settings = nil

  var prevI = 0
  var i = key.find('.')
  if i == -1:
    i = key.len

  var extended = false

  var node = self.settings
  while prevI < key.len:
    var extend = true
    var subKey = key[prevI..<i]
    if subKey[0] == '+':
      subKey = subKey[1..^1]
      extend = true
    elif subKey[0] == '*':
      subKey = subKey[1..^1]
      extend = false

    defer:
      prevI = i + 1
      i = key.find('.', prevI)
      if i == -1:
        i = key.len

    if i == key.len:
      node.fields.del(subKey)
    else:
      if not node.hasKey(subKey):
        break
      node = node[subKey]

  self.onConfigChanged.invoke(key)

proc set*[T](self: ConfigStore, key: string, value: T) =
  template log(msg: untyped): untyped =
    if logGetValue:
      echo msg

  log lvlInfo, &"Set setting '{key}' to {value} in {self.desc()}"

  inc self.revision
  self.mergedSettingsCache.settings = nil

  var prevI = 0
  var i = key.find('.')
  if i == -1:
    i = key.len

  var extended = false

  var node = self.settings
  while prevI <= key.len:
    var extend = true
    var subKey = key[prevI..<i]
    if subKey.len > 0 and subKey[0] == '+':
      subKey = subKey[1..^1]
      extend = true
    elif subKey.len > 0 and subKey[0] == '*':
      subKey = subKey[1..^1]
      extend = false

    defer:
      prevI = i + 1
      i = key.find('.', prevI)
      if i == -1:
        i = key.len

    if i == key.len:
      when T is JsonNodeEx:
        node[subKey] = value
      else:
        node[subKey] = value.toJsonEx
      break
    else:
      if not node.hasKey(subKey):
        var newValue = newJexObject()
        newValue.extend = extend
        newValue.userData = self.id
        node[subKey] = newValue
      node = node[subKey]

  self.onConfigChanged.invoke(key)

var logGetValue* = false
proc getImpl(self: ConfigStore, key: string, layers: var seq[ConfigStoreLayer], recurse: bool = true): JsonNodeEx =
  result = self.settings

  var prevI = 0
  var i = key.find('.')
  if i == -1:
    i = key.len

  var overrode = false
  var extended = false
  var addedSelf = false

  while prevI <= key.len:
    let subKey = key[prevI..<i]
    defer:
      prevI = i + 1
      i = key.find('.', prevI)
      if i == -1:
        i = key.len

    if prevI == key.len and not key.endsWith("."):
      break

    if result.isNil:
      return
    if result.kind == JObject:
      let val = result.fields.getOrDefault(subKey, nil)
      if val != nil:
        if self.parent != nil and val.extend and not extended and not overrode and recurse:
          if not addedSelf:
            layers.add (self.revision, Extend, self)
            addedSelf = true

          result = self.parent.getImpl(key[0..<i], layers)
          if result != nil:
            result = result.copy()
            result.extendJson(val)
          else:
            result = val
          extended = true
        else:
          if not addedSelf:
            layers.add (self.revision, Override, self)
            addedSelf = true

          overrode = true
          result = val

      else:
        # Key not found in current object
        if self.parent != nil and result.extend and not extended and recurse:
          if not addedSelf:
            layers.add (self.revision, Unchanged, self)
            addedSelf = true
          return self.parent.getImpl(key, layers)
        else:
          if not addedSelf:
            layers.add (self.revision, Unchanged, self)
            addedSelf = true
          return nil

    elif result.kind == JArray:
      try:
        let index = subKey.parseInt
        result = result.elems[index]
        overrode = true

        if not addedSelf:
          layers.add (self.revision, Override, self)
          addedSelf = true

      except:
        return nil

    else:
      return nil

  if not addedSelf:
    layers.add (self.revision, Override, self)
    addedSelf = true

proc getValue*(self: ConfigStore, key: string): JsonNodeEx =
  var layers: seq[ConfigStoreLayer] = @[]
  return self.getImpl(key, layers)

proc get*(self: ConfigStore, key: string): JsonNodeEx =
  var layers: seq[ConfigStoreLayer] = @[]
  result = self.getImpl(key, layers)
  # let mergedResult = self.mergedSettings{key.split('.')}
  # if $result != $mergedResult:
  #   echo &"Different result between result and merged result for '{self.name}.{key}': {result} != {mergedResult}"
  #   let uiae = layers.mapIt(&"{it.revision}, {it.kind}, {it.store.desc}").join("\n")
  #   echo "===================== self desc"
  #   echo self.desc(true)
  #   echo "===================== self"
  #   echo self
  #   echo "===================== settings"
  #   echo self.settings.pretty
  #   echo "===================== merged settings"
  #   echo self.mergedSettings{key.split(".")}
  #   echo "===================== layers"
  #   echo uiae.indent(4)

proc get*(self: ConfigStore, key: string, T: typedesc, defaultValue: T): T =
  let value = self.get(key)
  if value != nil:
    try:
      when T is JsonNode:
        return value.toJson
      elif T is JsonNodeEx:
        return value
      else:
        return value.jsonTo(T)
    except Exception as e:
      let t = $T
      let p = value.pretty
      log lvlError, &"Failed to get setting as type {t}: {e.msg}\n{p}"
      return defaultValue
  else:
    return defaultValue

proc get*(self: ConfigStore, key: string, T: typedesc): T {.inline.} =
  self.get(key, T, T.default)

proc get*[T](self: ConfigStore, key: string, defaultValue: T): T {.inline.} =
  self.get(key, T, defaultValue)

proc decodeRegex*(value: JsonNodeEx, default: string = ""): string =
  if value.kind == JString:
    return value.str
  elif value.kind == JArray:
    var r = ""
    for t in value.elems:
      if t.kind != JString:
        log lvlError, &"Invalid regex value: {value}, expected string, got {t}"
        continue
      if r.len > 0:
        r.add "|"
      r.add t.str

    return r
  elif value.kind == JNull:
    return default
  else:
    log lvlError, &"Invalid regex value: {value}, expected string | array[string]"
    return default

proc getRegexValue*(self: ConfigStore, path: string, default: string = ""): string =
  let value = self.get(path, JsonNodeEx, nil)
  if value == nil:
    return default
  return value.decodeRegex(default)

proc setting*(self: ConfigStore, key: string, T: typedesc): Setting[T] =
  return Setting[T](store: self, key: key)

var logSetting* = false
proc cacheValue[T](self: Setting[T]) =
  self.layers.setLen(0)
  let value = self.store.getImpl(self.key, self.layers)
  if value == nil:
    self.cache = T.default.some
  else:
    try:
      self.cache = value.jsonTo(T).some
    except Exception as e:
      let t = $T
      log lvlError, &"Failed to cache setting '{self.key}' of type {t}: {e.msg} ({value})"

proc get*[T](self: Setting[T], default: T): T =
  defer:
    let rawSetting = self.store.get(self.key, T)
    if rawSetting != result:
      log lvlError, &"Setting {self.store.desc}.{self.key} not invalidated correctly: {rawSetting} != {result}"

  if self.cache.isNone:
    self.cacheValue()
    return self.cache.get(default)

  # Check if cache valid
  for i, store in enumerate(self.store.parentStores(includeSelf = true)):
    if i >= self.layers.len:
      self.cacheValue()
      return self.cache.get(default)

    let layer = self.layers[i]
    if store == layer.store and store.revision == layer.revision and layer.kind == Override:
      return self.cache.get
    elif store != layer.store or (store.revision != layer.revision and layer.kind in {Extend, Override}):
      self.cacheValue()
      return self.cache.get(default)
    elif store != layer.store or (store.revision != layer.revision and layer.kind in {Unchanged}):
      var tempLayers = newSeq[ConfigStoreLayer]()
      if layer.store.getImpl(self.key, tempLayers, recurse = false) != nil:
        self.cacheValue()
        return self.cache.get(default)

  return default

proc getAllConfigKeys*(node: JsonNodeEx, prefix: string, res: var seq[tuple[key: string, value: JsonNodeEx]]) =
  case node.kind
  of JObject:
    if prefix.len > 0:
      res.add (prefix, node)
    for key, value in node.fields.pairs:
      let key = if prefix.len > 0: prefix & "." & key else: key
      value.getAllConfigKeys(key, res)
  else:
    res.add (prefix, node)

proc getAllKeys*(self: JsonNodeEx): seq[tuple[key: string, value: JsonNodeEx]] =
  self.getAllConfigKeys("", result)

proc getAllConfigKeys*(self: ConfigStore): seq[tuple[key: string, value: JsonNodeEx]] =
  self.settings.getAllConfigKeys("", result)

proc getStoreForId*(self: ConfigService, id: int): ConfigStore =
  for store in self.runtime.parentStores:
    if store.id == id:
      return store

  return nil

proc getStoreForPath*(self: ConfigService, path: string): (ConfigStore, string) =
  for store in self.runtime.parentStores:
    if path.startsWith(store.name):
      return (store, path[store.name.len..^1].strip(chars = {'/'}).replace("/", "."))

  log lvlWarn, &"getStoreForPath '{path}' not found"
  return (nil, "")

proc getByPath*(self: ConfigService, path: string): JsonNodeEx =
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

proc getConfigService(): Option[ConfigService] =
  {.gcsafe.}:
    if gServices.isNil: return ConfigService.none
    return gServices.getService(ConfigService)

static:
  addInjector(ConfigService, getConfigService)

proc logOptions*(self: ConfigService) {.expose("config").} =
  log lvlInfo, self.runtime.mergedSettings.pretty()

proc setOption*(self: ConfigService, option: string, value: JsonNode, override: bool = true) {.expose("config").} =
  if self.isNil:
    return

  self.runtime.set(option, value.toJsonEx)
  self.onConfigChanged.invoke()
  self.services.getService(PlatformService).get.platform.requestRender(true)

proc getOptionJson*(self: ConfigService, path: string, default: JsonNode = newJNull()): JsonNode {.expose("editor").} =
  return self.runtime.get(path, default)

proc getFlag*(self: ConfigService, flag: string, default: bool = false): bool {.expose("config").} =
  return self.runtime.get(flag, bool, default)

proc setFlag*(self: ConfigService, flag: string, value: bool) {.expose("config").} =
  self.runtime.set(flag, value)

proc toggleFlag*(self: ConfigService, flag: string) {.expose("config").} =
  let newValue = not self.getFlag(flag)
  log lvlInfo, fmt"toggleFlag '{flag}' -> {newValue}"
  self.setFlag(flag, newValue)

addGlobalDispatchTable "config", genDispatchTable("config")
