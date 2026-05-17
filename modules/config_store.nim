#use lisp
import std/[strformat, strutils, tables, json, sets]
import misc/[jsonex, event, id, myjsonutils, util, custom_unicode]

const currentSourcePath2 = currentSourcePath()
include module_base

type
  ConfigStore* = ref object
    id*: int
    parent*: ConfigStore
    revision*: int
    name*: string
    detail*: string
    filename*: string
    originalText*: string
    settings*: JsonNodeEx
    mergedSettingsCache*: tuple[parent: JsonNodeEx, revision: int, settings: JsonNodeEx]
    onConfigChanged*: Event[string]
    parentChangedHandle*: Id
    prefix*: string

  RegexSetting* = object
    impl*: JsonNodeEx

  RuneSetSetting* = distinct HashSet[Rune]

proc `$`*(self: RuneSetSetting): string {.borrow.}

const defaultToJsonOptions = ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef)

var nextConfigStoreId {.modrtlvar.} = 1

{.push modrtl, gcsafe, raises: [].}
proc configStoreGet(self: ConfigStore, key: string): JsonNodeEx
proc configStoreSet(self: ConfigStore, key: string, jsonValue: JsonNodeEx)
proc configStoreSetSettings(self: ConfigStore, settings: JsonNodeEx)
proc configStoreSetParent(self: ConfigStore, parent: ConfigStore)
proc configMergedSettings(self: ConfigStore): JsonNodeEx
proc configClear(self: ConfigStore, key: string)
proc configGetAllKeys(self: JsonNodeEx): seq[tuple[key: string, value: JsonNodeEx]]
proc evaluateSettingsRec(target: var JsonNodeEx, node: JsonNodeEx)
{.pop.}

proc `in`*(r: Rune, set: RuneSetSetting): bool =
  type Base = HashSet[Rune]
  set.Base.contains(r)

proc `in`*(c: char, set: RuneSetSetting): bool =
  c.Rune in set

proc fromJsonExHook*(t: var RuneSetSetting, jsonNode: JsonNodeEx) =
  var runes = initHashSet[Rune]()
  for s in jsonNode:
    if s.kind == JString:
      runes.incl s.str.runeAt(0)
    if s.kind == JArray:
      for r in s[0].str.runeAt(0)..s[1].str.runeAt(0):
        runes.incl r
  t = runes.RuneSetSetting

proc fromJsonExHook*(t: var RegexSetting, jsonNode: JsonNodeEx) =
  t = RegexSetting(impl: jsonNode)

proc decodeRegex*(value: JsonNodeEx, default: string = ""): string =
  if value.kind == JString:
    return value.str
  elif value.kind == JArray:
    var r = ""
    for t in value.elems:
      if t.kind != JString:
        continue
      if r.len > 0:
        r.add "|"
      r.add t.str

    return r
  elif value.kind == JNull:
    return default
  else:
    return default

proc decodeRegex*(value: RegexSetting, default: string = ""): string =
  return value.impl.decodeRegex(default)

proc set*[T](self: ConfigStore, key: string, value: T) =
  let jsonValue = when T is JsonNodeEx: value else: value.toJsonEx(defaultToJsonOptions)
  configStoreSet(self, key, jsonValue)

proc setSettings*(self: ConfigStore, settings: JsonNodeEx) = configStoreSetSettings(self, settings)
proc setParent*(self: ConfigStore, parent: ConfigStore) = configStoreSetParent(self, parent)
proc mergedSettings*(self: ConfigStore): JsonNodeEx = configMergedSettings(self)
proc clear*(self: ConfigStore, key: string) = configClear(self, key)
proc getAllKeys*(self: JsonNodeEx): seq[tuple[key: string, value: JsonNodeEx]] = configGetAllKeys(self)

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

proc `$`*(self: ConfigStore): string =
  result = self.desc
  result.add "\n"
  result.add self.settings.pretty().indent(2)

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

  if (a.kind, b.kind) == (jsonex.JObject, jsonex.JObject):
    for (key, value) in b.fields.pairs:
      if a.hasKey(key):
        a.fields[key].extendJson(value)
      else:
        a[key] = value

  elif (a.kind, b.kind) == (jsonex.JArray, jsonex.JArray):
    for value in b.elems:
      a.elems.add value

  else:
    a = b

proc getValue*(self: ConfigStore, key: string): JsonNodeEx =
  result = self.configStoreGet(key)
  if self.prefix != "":
    let override = self.configStoreGet(self.prefix & "." & key)
    if override != nil and result != nil:
      result.extendJson(override)

proc get*(self: ConfigStore, key: string): JsonNodeEx =
  result = self.configStoreGet(key)
  if self.prefix != "":
    let override = self.configStoreGet(self.prefix & "." & key)
    if override != nil and result != nil:
      result.extendJson(override)

proc get*(self: ConfigStore, key: string, T: typedesc, defaultValue: T): T =
  let value = self.get(key)
  if value != nil:
    try:
      when T is JsonNode:
        return value.toJson
      elif T is JsonNodeEx:
        return value
      else:
        if value.kind == JNull:
          return defaultValue
        return value.jsonTo(T)
    except Exception as e:
      return defaultValue
  else:
    return defaultValue

proc get*(self: ConfigStore, key: string, T: typedesc): T {.inline.} =
  self.get(key, T, T.default)

proc get*[T](self: ConfigStore, key: string, defaultValue: T): T {.inline.} =
  self.get(key, T, defaultValue)

proc setUserData(node: JsonNodeEx, userData: int) =
  node.userData = userData
  if node.kind == JObject:
    for value in node.fields.values:
      value.setUserData(userData)
  elif node.kind == JArray:
    for value in node.elems:
      value.setUserData(userData)

proc new*(_: typedesc[ConfigStore], name, filename: string, parent: ConfigStore = nil, settings: JsonNodeEx = newJexObject()): ConfigStore {.gcsafe.} =
  let id = block:
    {.gcsafe.}:
      let id = nextConfigStoreId
      inc nextConfigStoreId
      id

  result = ConfigStore(id: id, name: name, filename: filename, settings: newJexObject())
  result.settings.setUserData(id)
  settings.setUserData(id)
  result.settings.evaluateSettingsRec(settings)
  result.settings.extend = true
  result.setParent(parent)

when implModule:
  import misc/[custom_logger]

  logCategory "config-store"

  proc configStoreSetParent(self: ConfigStore, parent: ConfigStore) =
    if self.parent != parent:
      if self.parent != nil:
        self.parent.onConfigChanged.unsubscribe(self.parentChangedHandle)

      self.parent = parent
      self.mergedSettingsCache.settings = nil
      inc self.revision

      if self.parent != nil:
        self.parentChangedHandle = self.parent.onConfigChanged.subscribe proc(key: string) =
          inc self.revision
          var val = self.settings
          var extend = val.extend
          for keyRaw in key.splitOpenArray('.'):
            if keyRaw.len == 0:
              break
            if isNil(val) or val.kind != JObject:
              val = nil
              break
            val = val.fields.getOrDefault(keyRaw.p.toOpenArray(0, keyRaw.len - 1))
            if val != nil:
              extend = extend and val.extend

          if val == nil or extend:
            self.onConfigChanged.invoke(key)

      self.onConfigChanged.invoke("")

  proc configStoreSetSettings(self: ConfigStore, settings: JsonNodeEx) =
    self.settings = newJexObject()
    self.settings.setUserData(self.id)
    settings.setUserData(self.id)
    self.settings.evaluateSettingsRec(settings)
    self.settings.extend = true
    self.mergedSettingsCache.settings = nil
    inc self.revision
    self.onConfigChanged.invoke("")

  proc configMergedSettings(self: ConfigStore): JsonNodeEx =
    if self.parent != nil:
      var parentMergedSettings = self.parent.mergedSettings
      let a = cast[ptr JsonNodeEx](parentMergedSettings)
      let b = cast[ptr JsonNodeEx](self.mergedSettingsCache.parent)
      if self.mergedSettingsCache.settings == nil or a != b or self.mergedSettingsCache.revision != self.parent.revision:
        # log lvlInfo, &"Parent changed for ConfigStore {self.desc}, recalculate merged settings"
        var mergedSettings = parentMergedSettings.copy()
        mergedSettings.extendJson(self.settings)
        self.mergedSettingsCache = (parentMergedSettings, self.parent.revision, mergedSettings)

      return self.mergedSettingsCache.settings

    else:
      return self.settings

  proc configClear(self: ConfigStore, key: string) =
    log lvlInfo, &"Clear setting '{key}' in {self.desc()}"

    inc self.revision
    self.mergedSettingsCache.settings = nil

    var prevI = 0
    var i = key.find('.')
    if i == -1:
      i = key.len

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

  proc configStoreSet(self: ConfigStore, key: string, jsonValue: JsonNodeEx) =
    # log lvlInfo, &"Set setting '{key}' to {jsonValue} in {self.desc()}"

    var prevI = 0
    var i = key.find('.')
    if i == -1:
      i = key.len

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

      if node.kind != jsonex.JObject:
        log lvlError, &"Failed to change setting '{key}', '{key[0..<prevI]}' is not an object:\n{node}"
        return

      if i == key.len:
        if subKey in node.fields:
          if node.fields[subKey] == jsonValue:
            return
        node[subKey] = jsonValue
        break
      else:
        if not node.hasKey(subKey):
          var newValue = newJexObject()
          newValue.extend = extend
          newValue.userData = self.id
          node[subKey] = newValue
        node = node[subKey]

    inc self.revision
    self.mergedSettingsCache.settings = nil
    self.onConfigChanged.invoke(key)

  proc configStoreGet(self: ConfigStore, key: string): JsonNodeEx =
    var res = self.settings
    var extend = res.extend
    for keyRaw in key.splitOpenArray('.'):
      if isNil(res) or res.kind != jsonex.JObject:
        res = nil
        break
      res = res.fields.getOrDefault(keyRaw.p.toOpenArray(0, keyRaw.len - 1))
      if res != nil:
        extend = extend and res.extend

    if not extend:
      return res

    if self.parent != nil:
      let parentRes = self.parent.configStoreGet(key)
      if res != nil and parentRes == nil:
        return res
      elif res != nil and parentRes != nil:
        result = parentRes.copy()
        result.extendJson(res)
        return
      else:
        assert res == nil
        return parentRes

    return res

  proc getAllConfigKeys(node: JsonNodeEx, prefix: string, res: var seq[tuple[key: string, value: JsonNodeEx]]) =
    if node == nil:
      return

    case node.kind
    of jsonex.JObject:
      if prefix.len > 0:
        res.add (prefix, node)
      for key, value in node.fields.pairs:
        let key = if prefix.len > 0: prefix & "." & key else: key
        value.getAllConfigKeys(key, res)
    else:
      res.add (prefix, node)

  proc configGetAllKeys(self: JsonNodeEx): seq[tuple[key: string, value: JsonNodeEx]] =
    self.getAllConfigKeys("", result)

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
          var extend = true
          if key[prevI] == '+':
            extend = true
            inc prevI
          elif key[prevI] == '*':
            extend = false
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

        var extend = field.extend
        if prevI < key.len:
          if key[prevI] == '+':
            extend = true
            inc prevI
          elif key[prevI] == '*':
            extend = false
            inc prevI
          let sub = key[prevI..^1].replace("..", ".")

          var evaluatedField: JsonNodeEx
          evaluatedField.evaluateSettingsRec(field)
          evaluatedField.extend = extend
          subTarget[sub] = evaluatedField
        else:
          # empty last key
          var evaluatedField: JsonNodeEx
          evaluatedField.evaluateSettingsRec(field)
          evaluatedField.extend = extend
          subTarget[""] = evaluatedField

    else:
      target = node
