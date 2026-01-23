import std/[json, options, tables, macros, genasts, sets, typetraits, strformat, strutils]
import misc/[util, event, custom_async, custom_logger, myjsonutils, jsonex, id, custom_unicode]
import service
from scripting_api import LineNumbers

include dynlib_export

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

    settingDescriptions: seq[SettingDescription]
    settingDescriptionsIndices: Table[string, int]

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
    parentChangedHandle: Id
    prefix*: string

  Setting*[T] = ref object
    store*: ConfigStore
    cache*: Option[T]
    revision*: int
    key*: string

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

  RegexSetting* = object
    impl: JsonNodeEx

  RuneSetSetting* = distinct HashSet[Rune]

func serviceName*(_: typedesc[ConfigService]): string = "ConfigService"

const defaultToJsonOptions = ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef)

proc `$`*(self: RuneSetSetting): string {.borrow.}

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

proc toJsonExHook*[T](a: Setting[T]): JsonNodeEx {.raises: [].} =
  let v = a.get()
  return v.toJsonEx(defaultToJsonOptions)

proc fromJsonExHook*(t: var RegexSetting, jsonNode: JsonNodeEx) =
  t = RegexSetting(impl: jsonNode)

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

proc decodeRegex*(value: RegexSetting, default: string = ""): string =
  return value.impl.decodeRegex(default)

proc setting*(self: ConfigStore, key: string, T: typedesc): Setting[T] =
  return Setting[T](store: self, key: key)

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

proc configStoreGet(self: ConfigStore, key: string): JsonNodeEx {.apprtl, gcsafe, raises: [].}

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
      let t = $T
      let p = value.pretty
      log lvlError, &"[{self.name}] Failed to get setting '{key}' as type {t}: {e.msg}\n{p}"
      return defaultValue
  else:
    return defaultValue

proc get*(self: ConfigStore, key: string, T: typedesc): T {.inline.} =
  self.get(key, T, T.default)

proc get*[T](self: ConfigStore, key: string, defaultValue: T): T {.inline.} =
  self.get(key, T, defaultValue)

proc get*[T](self: Setting[T], default: T): lent T =
  if self.cache.isSome and self.revision == self.store.revision:
    return self.cache.get
  self.cache = self.store.get(self.key, default).some
  self.revision = self.store.revision
  return self.cache.get

proc get*[T](self: Setting[T]): lent T =
  return self.get(T.default)

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

var settingGroupDescriptions {.compileTime.} = initTable[string, SettingGroupDescription]()
var settingDescriptionsIndices {.compileTime.} = initTable[string, int]()
var settingToJsonTypeNames {.compileTime.} = initTable[string, string]()
var settingDescriptions* {.compileTime.} = newSeq[SettingDescription]()
var getSettingDescriptions*: proc(): seq[SettingDescription] {.gcsafe, raises: [].}

template setSettingDefault(index: int, defaultValue: untyped) =
  static:
    settingDescriptions[index].default = $defaultValue.toJsonEx(defaultToJsonOptions)

proc camelCaseToHyphenCase(str: string): string =
  for c in str:
    if c.isUpperAscii:
      result.add "-"
      result.add c.toLowerAscii
    else:
      result.add c

proc joinSettingKey*(a, b: string): string =
  if a.len > 0 and b.len > 0:
    return a & "." & b
  elif a.len > 0:
    return a
  else:
    return b

proc typeNameToJson*(T: typedesc): string =
  return $T

proc typeNameToJson*(T: typedesc[JsonNode]): string =
  return "any"

proc typeNameToJson*(T: typedesc[RegexSetting]): string =
  return "regex"

proc typeNameToJson*(T: typedesc[RuneSetSetting]): string =
  return "(string | string[])[]"

proc typeNameToJson*[K](T: typedesc[seq[K]]): string =
  let subTypeName = typeNameToJson(K)
  if subTypeName.find(" ") != -1 and not subTypeName.endsWith(")") and not subTypeName.endsWith("]") and not subTypeName.endsWith("}"):
    return "(" & subTypeName & ")[]"
  else:
    return subTypeName & "[]"

proc typeNameToJson*[K](T: typedesc[Option[K]]): string =
  return typeNameToJson(K) & " | null"

proc typeNameToJson*[K](T: typedesc[Table[string, K]]): string =
  return "{ [key: string]: " & typeNameToJson(K) & " }"

proc typeNameToJson*(T: typedesc[LineNumbers]): string =
  return "\"none\" | \"absolute\" | \"relative\""

macro addJsonTypeName(key: static[string], name: static[string]) =
  settingToJsonTypeNames[key] = name

proc declareSettingsImpl(name: NimNode, prefix: string, noInit: static[bool], body: NimNode): NimNode {.compileTime.} =
  if name.repr in settingGroupDescriptions:
    error "Duplicate setting group " & name.repr, name

  let declare = ident"declare"
  let use = ident"use"
  let store = genSym(nskParam, "store")
  let prefixArg = genSym(nskParam, "prefix")
  let res = genSym(nskVar, "res")

  var typeNode = genAst(name):
    type name* = object
      x: int

  typeNode[0][2][2] = nnkRecList.newTree()

  var newNode = genAst(name, store, res, prefix = prefixArg, defaultPrefix = prefix):
    proc new*(_: typedesc[name], store: ConfigStore, prefix: string = defaultPrefix): name =
      var res = name()
      # result.foo = store.setting("foo", int)

  var setDefaultNodes = nnkStmtList.newTree()

  template withPrefix(s: string): string =
    block:
      if prefix.len > 0:
        prefix & "." & s
      else:
        s

  var desc = SettingGroupDescription()

  var docs: NimNode = nil
  for node in body:
    if node.kind == nnkCommentStmt:
      docs = node
      continue

    if node.kind == nnkCommand and node[0] == declare:
      let name = node[1]
      let fullName = name.repr.camelCaseToHyphenCase.withPrefix()
      let settingName = name.repr.camelCaseToHyphenCase
      let typ = node[2]
      let default = node[3]

      var s = SettingDescription(name: settingName, prefix: prefix, fullName: fullName, typ: typ.repr, default: "null", noInit: noInit)

      if docs != nil:
        s.docs = docs.strVal

      settingDescriptions.add(s)
      desc.settings.add settingDescriptions.high

      if prefix != "":
        settingDescriptionsIndices[fullName] = settingDescriptions.high

      typeNode[0][2][2].add nnkIdentDefs.newTree(name.postfix("*"), nnkBracketExpr.newTree(bindSym"Setting", typ), newEmptyNode())

      newNode[6].add block:
        genAst(fieldName = name, settingName, typ, store, res, prefixArg):
          res.fieldName = store.setting(joinSettingKey(prefixArg, settingName), typ)

      if default.repr != "nil":
        setDefaultNodes.add block:
          genAst(index = settingDescriptions.high, default):
            setSettingDefault(index, default)

      setDefaultNodes.add block:
        genAst(index = settingDescriptions.high, fullName, typ):
          addJsonTypeName(fullName, typeNameToJson(typ))
          static:
            settingDescriptions[index].typeName = typeNameToJson(typ)

      docs = nil
      continue

    if node.kind == nnkCommand and node[0] == use:
      let name = node[1]
      let fullName = name.repr.camelCaseToHyphenCase.withPrefix()
      let typ = node[2]

      if typ.repr notin settingGroupDescriptions:
        error "Unknown setting type " & typ.repr, typ

      for i in settingGroupDescriptions[typ.repr].settings:
        let p = settingDescriptions[i]
        var s = SettingDescription(
          name: p.name,
          prefix: fullName,
          fullName: fullName & "." & p.name,
          typ: p.typ,
          default: p.default,
          docs: p.docs,
          noInit: noInit,
        )

        settingDescriptions.add(s)
        desc.settings.add settingDescriptions.high
        settingDescriptionsIndices[s.name] = settingDescriptions.high

        setDefaultNodes.add block:
          genAst(fullName2 = s.fullName, subName = p.name, index = settingDescriptions.high):
            static:
              if settingToJsonTypeNames.contains(subName):
                settingToJsonTypeNames[fullName2] = settingToJsonTypeNames[subName]
                settingDescriptions[index].typeName = settingToJsonTypeNames[subName]

      typeNode[0][2][2].add nnkIdentDefs.newTree(name.postfix("*"), typ, newEmptyNode())

      let settingName = name.repr.camelCaseToHyphenCase
      newNode[6].add block:
        genAst(fieldName = name, typ, store, res, prefixArg, settingName):
          res.fieldName = typ.new(store, joinSettingKey(prefixArg, settingName))

      continue

    if node.kind == nnkIdent:
      discard

    error "Invalid setting, expected 'declare name, type, default'", node

  settingGroupDescriptions[name.repr] = desc

  newNode[6].add block:
    genAst(res):
      return res

  result = nnkStmtList.newTree(typeNode, newNode, setDefaultNodes)

macro declareSettings*(name: untyped, prefix: static string, body: untyped) =
  return declareSettingsImpl(name, prefix, false, body)

macro declareSettingsTemplate*(name: untyped, prefix: static string, body: untyped) =
  return declareSettingsImpl(name, prefix, true, body)

when implModule:
  import std/[algorithm, macrocache]
  import misc/[timer]
  import scripting/expose
  import platform/platform
  import platform_service, dispatch_tables
  var setAllDefaults: proc(store: ConfigStore) {.raises: [].} = nil

  {.push gcsafe.}
  {.push raises: [].}

  proc setUserData(node: JsonNodeEx, userData: int)
  proc evaluateSettingsRec(target: var JsonNodeEx, node: JsonNodeEx)
  proc setParent*(self: ConfigStore, parent: ConfigStore)
  proc setSettings*(self: ConfigStore, settings: JsonNodeEx)

  addBuiltinService(ConfigService)

  var nextConfigStoreId = 1
  proc new*(_: typedesc[ConfigStore], name, filename: string, parent: ConfigStore = nil, settings: JsonNodeEx = newJexObject()): ConfigStore =
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

  method init*(self: ConfigService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    log lvlInfo, &"ConfigService.init"
    {.gcsafe.}:
      for desc in getSettingDescriptions():
        self.settingDescriptions.add desc
        self.settingDescriptionsIndices[desc.fullName] = self.settingDescriptions.high

    self.base = ConfigStore.new("base", "settings://base")
    {.cast(gcsafe).}:
      setAllDefaults(self.base)
    self.runtime = ConfigStore.new("runtime", "settings://runtime")
    self.runtime.setParent(self.base)
    return ok()

  proc getSettingDescription*(self: ConfigService, key: string): Option[SettingDescription] =
    self.settingDescriptionsIndices.withValue(key, val):
      return self.settingDescriptions[val[]].some
    for desc in self.settingDescriptions:
      if desc.fullName == key:
        return desc.some
    return SettingDescription.none

  proc removeStore*(self: ConfigService, store: ConfigStore) =
    store.setParent(nil)
    self.stores.del(store.filename)
    self.storesByName.del(store.name)

  proc addStore*(self: ConfigService, name, filename: string, parent: ConfigStore = nil, settings: JsonNodeEx = newJexObject()): ConfigStore =
    let parent = if parent != nil: parent else: self.runtime
    result = ConfigStore.new(name, filename, parent, settings)
    self.stores[filename] = result
    self.storesByName[name] = result

  proc getLanguageStore*(self: ConfigService, languageId: string): ConfigStore =
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

  proc reconnectGroups*(self: ConfigService) =
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

  proc setParent*(self: ConfigStore, parent: ConfigStore) =
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

  proc mergedSettings*(self: ConfigStore): JsonNodeEx =
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

  proc clear*(self: ConfigStore, key: string) =
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

  proc set*[T](self: ConfigStore, key: string, value: T) =
    # log lvlInfo, &"Set setting '{key}' to {value} in {self.desc()}"

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
        let jsonValue = when T is JsonNodeEx: value else: value.toJsonEx(defaultToJsonOptions)
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

  proc getRegexValue*(self: ConfigStore, path: string, default: string = ""): string =
    let value = self.get(path, JsonNodeEx, nil)
    if value == nil:
      return default
    return value.decodeRegex(default)

  proc getAllConfigKeys*(node: JsonNodeEx, prefix: string, res: var seq[tuple[key: string, value: JsonNodeEx]]) =
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

    for storeName in self.storesByName.keys:
      if path.startsWith(storeName & "/"):
        return (self.storesByName[storeName], path[storeName.len..^1].strip(chars = {'/'}).replace("/", "."))
      if path == storeName:
        return (self.storesByName[storeName], "")

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

    self.runtime.set(option, value.toJsonEx(defaultToJsonOptions))
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

  {.pop.} # raises: []
  {.pop.} # gcsafe

  proc setAllDefaultsImpl(store: ConfigStore, descriptions: seq[SettingDescription]) {.raises: [].} =
    for setting in descriptions:
      try:
        if setting.name.contains("*") or setting.prefix == "" or setting.noInit:
          continue
        store.set(setting.fullName, setting.default.parseJsonEx())
      except Exception as e:
        log lvlError, &"Failed to set default for setting '{setting.name}': {e.msg}\n{setting.default}"

  template defineSetAllDefaultSettings*(): untyped =
    const descriptions = settingDescriptions
    setAllDefaults = proc(store: ConfigStore) {.raises: [].} =
      setAllDefaultsImpl(store, descriptions)

    # static:
    #   echo "=========== All settings ==========="
    #   for i, desc in settingDescriptions:
    #     echo i, ": ", desc

    proc getSettingDescriptionsImpl(): seq[SettingDescription] =
      const settingDescriptionsTemp = settingDescriptions
      return settingDescriptionsTemp
    getSettingDescriptions = getSettingDescriptionsImpl

    proc generateDocs() =
      var text = """
  # List of (most) settings

  For examples and default values see [here](../config/settings.json)

  | Key | Type | Default | Description |
  | ----------- | --- | --- | ------ |
  """

      var sortedDescriptions = descriptions
      let typeNames = settingToJsonTypeNames

      proc escape(s: string): string = s.replace("|", "\\|")

      sortedDescriptions.sort(proc(a, b: auto): int = cmp(a.fullName, b.fullName))
      var lastFullName = ""
      for desc in sortedDescriptions:
        if desc.name.contains("*") or desc.prefix == "" or desc.noInit or desc.fullName == lastFullName:
          continue
        lastFullName = desc.fullName

        let docs = desc.docs.replace("\n", " ")
        var typeName = desc.typ
        if typeNames.contains(desc.fullName):
          typeName = typeNames[desc.fullName]

        text.add "| `" & desc.fullName & "` | " & typeName.escape() & " | " & desc.default.escape() & " | " & docs.escape() & " |\n"

      writeFile("docs/settings.gen.md", text)

    static:
      generateDocs()

declareSettings BackgroundSettings, "":
  ## If true the background is transparent.
  declare transparent, bool, false

  ## How much to change the brightness for inactive views.
  declare inactiveBrightnessChange, float, -0.025

declareSettings OpenSessionSettings, "":
  ## If true then Nev will detect if it's running inside a multiplexer like tmux, zellij or wezterm (by using environment variables)
  ## and if so opening a session will use the command `editor.open-session.tmux` or `editor.open-session.zellij` or `editor.open-session.wezterm`
  declare useMultiplexer, bool, true

  ## Command to use when opening a session in a new window.
  declare command, Option[string], nil

  ## Command arguments to use when opening a session in a new window.
  declare args, Option[seq[JsonNodeEx]], nil

declareSettings UiSettings, "ui":
  use background, BackgroundSettings

  ## VFS path of the theme.
  declare theme, string, "app://themes/tokyo-night-color-theme.json"

  ## Full path to regular font file.
  declare fontFamily, string, "app://fonts/DejaVuSansMono.ttf"

  ## Full path to bold font file.
  declare fontFamilyBold, string, "app://fonts/DejaVuSansMono-Bold.ttf"

  ## Full path to italic font file.
  declare fontFamilyItalic, string, "app://fonts/DejaVuSansMono-Oblique.ttf"

  ## Full path to bold italic font file.
  declare fontFamilyBoldItalic, string, "app://fonts/DejaVuSansMono-BoldOblique.ttf"

  ## After how many milliseconds the which key window opens.
  declare whichKeyDelay, int, 250

  ## Show which key window when holding down modifiers.
  declare whichKeyShowWhenMod, bool, false

  ## If true then the window showing next possible inputs will be displayed even when no keybinding is in progress (i.e. it will always be shown).
  declare whichKeyNoProgress, bool, false

  ## How many rows tall the window showing next possible inputs should be.
  declare whichKeyHeight, int, 6

  ## Maximum number of views (files or other UIs) which can be shown.
  declare maxViews, int, 2

  ## Enable syntax highlighting.
  declare syntaxHighlighting, bool, true

  ## Enable indent guides to show the indentation of the current line.
  declare indentGuide, bool, true

  ## Character to use when rendering whitespace. If this is the empty string or not set then spaces are not rendered.
  declare whitespaceChar, string, "·"

  ## Color of rendered whitespace. Can be a theme key or hex color (e.g #ff00ff).
  declare whitespaceColor, string, "comment"

  ## How many pixels (or rows in the terminal) to scroll per scroll wheel tick.
  declare scrollSpeed, float, 50.0

  ## Enable smooth scrolling.
  declare smoothScroll, bool, true

  ## How fast smooth scrolling interpolates.
  declare smoothScrollSpeed, float, 25.0

  ## Percentage of screen height at which the smooth scroll offset will be snapped to the target location.
  ## E.g. if this is 0.5, then if the smooth scroll offset if further from the target scroll offset than 50% of the
  ## screen height then the smooth scroll offset will instantly jump to the target scroll offset (-50% of the screen height).
  ## This means that the smooth scrolling will not take time proportional to the scroll distance for jumps bigger than
  ## the screen height.
  declare smoothScrollSnapThreshold, float, 0.5

  ## How fast to interpolate the cursor trail position when moving the cursor. Higher means faster.
  declare cursorTrailSpeed, float, 100.0

  ## How long the cursor trail is. Set to 0 to disable cursor trail.
  declare cursorTrailLength, int, 2

  ## Enable vertical sync to prevent screen tearing.
  declare vsync, bool, true

  ## How line numbers should be displayed.
  declare lineNumbers, LineNumbers, LineNumbers.Absolute

  ## How long toasts are displayed for, in milliseconds.
  declare toastDuration, int, 8000

  ## Animate toast positions
  declare toastAnimation, bool, true

  # Defines the way views are layed out.
  # declare layout, JsonNodeEx, newJexObject()

  ## Width of tab layout headers in characters
  declare tabHeaderWidth, int, 30

  ## When true then tab layouts don't render a tab bar when they only have one tab.
  declare hideTabBarWhenSingle, bool, false

  # ## How long the cursor trail is. Set to 0 to disable cursor trail.
  # declare inclusiveSelection, int, 2

# declareSettings LanguageSettings, "languages.*":
#   ## Name of the github repository or link to git repository for the treesitter parser.
#   declare treesitter, string, ""

#   ## Name of the sub directory of the git repository where the treesitter queries are located.
#   ## If empty or not specified the editor will search for the queries in the repository.
#   declare treesitterQueries, string, ""

# declareSettings LanguagesSettings, "":
#   ## Map from language id to language config.
#   declare languages, Table[string, LanguageSettings], initTable[string, LanguageSettings]()

declareSettings GeneralSettings, "editor":
  use openSession, OpenSessionSettings

  ## How often the editor will check for unused documents and close them, in seconds.
  declare closeUnusedDocumentsTimer, int, 10

  ## If true the editor prints memory usage statistics when quitting.
  declare printStatisticsOnShutdown, bool, false

  ## Max number of search results returned by global text based search.
  declare maxSearchResults, int, 1000

  ## Max length of each individual search result (search results are cut off after this value).
  declare maxSearchResultDisplayLen, int, 1000

  ## If true then the app mode event handler (if the app mode is not "") will be on top of the event handler stack,
  ## otherwise it will be at the bottom (but still above the "editor" event handler.
  declare customModeOnTop, bool, true

  ## After how many milliseconds of no input the input history is cleared.
  declare clearInputHistoryDelay, int, 3000

  ## After how many milliseconds of no input a pending input gets inserted as text, if you bind a key
  ## which inserts text in e.g. a multi key keybinding aswell.
  ## Say you bind `jj` to exit insert mode, then if you press `j` once and wait for this delay then it will
  ## insert `j` into the document, but if you press `j` again it will will exit insert mode instead.
  ## If you press another key like `k` before the time ends it will immediately insert the `j` and the `k`.
  declare insertInputDelay, int, 150

  ## Whether the editor shows a history of the last few pressed buttons in the status bar.
  declare recordInputHistory, bool, false

  ## Watch the theme directory for changes to the theme.
  declare watchTheme, bool, true

  ## Watch the config files in the app directory and automatically reload them when they change.
  declare watchAppConfig, bool, true

  ## Watch the config files in the user directory and automatically reload them when they change.
  declare watchUserConfig, bool, true

  ## Watch the config files in the workspace directory and automatically reload them when they change.
  declare watchWorkspaceConfig, bool, true

  ## If true then the editor will keep a history of opened sessions in home://.nev/sessions.json,
  ## which enables features like opening a recent session or opening the last session.
  declare keepSessionHistory, bool, true

  ## If true then you will be prompted to confirm quitting even when no unsaved changes exist.
  declare promptBeforeQuit, bool, false

  ## List of input modes which are always active (at the lowest priority).
  declare baseModes, seq[string], @["editor"]

  ## Global mode to apply while the command line is open.
  declare commandLineModeHigh, string, "command-line-high"

  ## Global mode to apply while the command line is open.
  declare commandLineModeLow, string, "command-line-low"

  ## Global mode to apply while the command line is open showing a command result.
  declare commandLineResultModeHigh, string, "command-line-result-high"

  ## Global mode to apply while the command line is open showing a command result.
  declare commandLineResultModeLow, string, "command-line-result-low"

declareSettings DebugSettings, "debug":
  ## Log how long it takes to generate the render commands for a text editor.
  declare logTextRenderTime, bool, false

  ## GUI only: Highlight text chunks
  declare drawTextChunks, bool, false

  ## Write logs to an internal document which can be opened using the `logs` command.
  declare logToInternalDocument, bool, false

when isMainModule:
  defineSetAllDefaultSettings()
