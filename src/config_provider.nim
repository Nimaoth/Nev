import std/[json, options, strutils, tables]
import misc/[traits, util, event, custom_async, custom_logger, myjsonutils]
import scripting/expose
import platform/platform
import service, platform_service, dispatch_tables

{.push gcsafe.}
{.push raises: [].}

logCategory "previewer"

traitRef ConfigProvider:
  method getConfigValue(self: ConfigProvider, path: string): Option[JsonNode] {.gcsafe, raises: [].}
  method setConfigValue(self: ConfigProvider, path: string, value: JsonNode) {.gcsafe, raises: [].}
  method onConfigChanged*(self: ConfigProvider): ptr Event[void] {.gcsafe, raises: [].}

proc setValue*[T](self: ConfigProvider, path: string, value: T) =
  template createSetOption(self, path, value, constructor: untyped): untyped {.used.} =
    block:
      self.setConfigValue(path, constructor(value))

  try:
    when T is bool:
      self.createSetOption(path, value, newJBool)
    elif T is Ordinal:
      self.createSetOption(path, value, newJInt)
    elif T is float32 | float64:
      self.createSetOption(path, value, newJFloat)
    elif T is string:
      self.createSetOption(path, value, newJString)
    elif T is JsonNode:
      self.setConfigValue(path, value)
    else:
      {.fatal: ("Can't set option with type " & $T).}
  except KeyError:
    discard

proc getValue*[T](self: ConfigProvider, path: string, default: T = T.default): T =
  template createGetOption(self, path, defaultValue, accessor: untyped): untyped {.used.} =
    block:
      let value = self.getConfigValue(path)
      if value.isSome:
        accessor(value.get, defaultValue)
      else:
        self.setValue(path, defaultValue)
        defaultValue

  try:
    when T is bool:
      return createGetOption(self, path, default, getBool)
    elif T is enum:
      return parseEnum[T](createGetOption(self, path, "", getStr), default)
    elif T is Ordinal:
      return createGetOption(self, path, default, getInt)
    elif T is float32 | float64:
      return createGetOption(self, path, default, getFloat)
    elif T is string:
      return createGetOption(self, path, default, getStr)
    elif T is JsonNode:
      return self.getConfigValue(path).get(default)
    else:
      {.fatal: ("Can't get option with type " & $T).}
  except KeyError:
    return default

proc getFlag*(self: ConfigProvider, flag: string, default: bool): bool =
  return self.getValue(flag, default)

proc setFlag*(self: ConfigProvider, flag: string, value: bool) =
  self.setValue(flag, value)

proc toggleFlag*(self: ConfigProvider, flag: string) =
  if self.getConfigValue(flag).isSome:
    self.setFlag(flag, not self.getFlag(flag, false))

proc decodeRegex*(value: JsonNode, default: string = ""): string =
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

proc getRegexValue*(self: ConfigProvider, path: string, default: string = ""): string =
  let value = self.getValue(path, newJNull())
  return value.decodeRegex(default)

type
  ConfigService* = ref object of Service
    settings*: JsonNode
    onConfigChanged*: Event[void]

func serviceName*(_: typedesc[ConfigService]): string = "ConfigService"

addBuiltinService(ConfigService)

method init*(self: ConfigService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"ConfigService.init"
  self.settings = newJObject()
  return ok()

implTrait ConfigProvider, ConfigService:
  proc getConfigValue(self: ConfigService, path: string): Option[JsonNode] =
    let node = self.settings{path.split(".")}
    if node.isNil:
      return JsonNode.none
    return node.some

  proc setConfigValue(self: ConfigService, path: string, value: JsonNode) =
    try:
      let pathItems = path.split(".")
      var node = self.settings
      for key in pathItems[0..^2]:
        if node.kind != JObject:
          return
        if not node.contains(key):
          node[key] = newJObject()
        node = node[key]
      if node.isNil or node.kind != JObject:
        return
      node[pathItems[^1]] = value
    except KeyError:
      discard

  proc onConfigChanged*(self: ConfigService): ptr Event[void] = self.onConfigChanged.addr

proc setOption*[T](self: ConfigService, path: string, value: T) =
  template createSetOption(self, path, value, constructor: untyped): untyped =
    block:
      if self.isNil:
        return
      let pathItems = path.split(".")
      var node = self.settings
      for key in pathItems[0..^2]:
        if node.kind != JObject:
          return
        if not node.contains(key):
          node[key] = newJObject()
        node = node[key]
      if node.isNil or node.kind != JObject:
        return
      node[pathItems[^1]] = constructor(value)

  try:
    when T is bool:
      self.createSetOption(path, value, newJBool)
    elif T is Ordinal:
      self.createSetOption(path, value, newJInt)
    elif T is float32 | float64:
      self.createSetOption(path, value, newJFloat)
    elif T is string:
      self.createSetOption(path, value, newJString)
    else:
      {.fatal: ("Can't set option with type " & $T).}

    self.onConfigChanged.invoke()
    self.services.getService(PlatformService).get.platform.requestRender(true)

  except:
    discard

proc getOption*[T](self: ConfigService, path: string, default: Option[T] = T.none): Option[T] =
  try:
    template createGetOption(self, path, defaultValue, accessor: untyped): untyped {.used.} =
      block:
        if self.isNil:
          return default
        let node = self.settings{path.split(".")}
        if node.isNil:
          self.setOption(path, defaultValue)
          return default
        accessor(node, defaultValue)

    when T is bool:
      return createGetOption(self, path, T.default, getBool).some
    elif T is enum:
      return parseEnum[T](createGetOption(self, path, "", getStr)).some.catch(default)
    elif T is Ordinal:
      return createGetOption(self, path, T.default.int, getInt).T.some
    elif T is float32 | float64:
      return createGetOption(self, path, T.default, getFloat).some
    elif T is string:
      return createGetOption(self, path, T.default, getStr).some
    elif T is JsonNode:
      if self.isNil:
        return default
      let node = self.settings{path.split(".")}
      if node.isNil:
        return default
      return node.some
    else:
      {.fatal: ("Can't get option with type " & $T).}

  except:
    return T.none

proc getOption*[T](self: ConfigService, path: string, default: T = T.default): T =
  try:
    template createGetOption(self, path, defaultValue, accessor: untyped): untyped {.used.} =
      block:
        if self.isNil:
          return default
        let node = self.settings{path.split(".")}
        if node.isNil:
          self.setOption(path, defaultValue)
          return default
        accessor(node, defaultValue)

    when T is bool:
      return createGetOption(self, path, default, getBool)
    elif T is enum:
      return parseEnum[T](createGetOption(self, path, "", getStr), default)
    elif T is Ordinal:
      return createGetOption(self, path, default, getInt)
    elif T is float32 | float64:
      return createGetOption(self, path, default, getFloat)
    elif T is string:
      return createGetOption(self, path, default, getStr)
    elif T is JsonNode:
      if self.isNil:
        return default
      let node = self.settings{path.split(".")}
      if node.isNil:
        return default
      return node
    else:
      {.fatal: ("Can't get option with type " & $T).}

  except:
    return default

###########################################################################

proc getConfigService(): Option[ConfigService] =
  {.gcsafe.}:
    if gServices.isNil: return ConfigService.none
    return gServices.getService(ConfigService)

static:
  addInjector(ConfigService, getConfigService)

proc logOptions*(self: ConfigService) {.expose("config").} =
  log(lvlInfo, self.settings.pretty)

proc setOption*(self: ConfigService, option: string, value: JsonNode, override: bool = true) {.expose("config").} =
  if self.isNil:
    return

  self.services.getService(PlatformService).get.platform.requestRender(true)

  try:
    if option == "":
      if not override:
        self.settings.extendJson(value, true)
      else:
        self.settings = value
      self.onConfigChanged.invoke()
      return

    let pathItems = option.split(".")
    var node = self.settings
    for key in pathItems[0..^2]:
      if node.kind != JObject:
        return
      if not node.contains(key):
        node[key] = newJObject()
      node = node[key]
    if node.isNil or node.kind != JObject:
      return

    let key = pathItems[^1]
    if not override and node.hasKey(key):
      node.fields[key].extendJson(value, true)
    else:
      node[key] = value

    self.onConfigChanged.invoke()
  except:
    discard

proc getOptionJson*(self: ConfigService, path: string, default: JsonNode = newJNull()): JsonNode {.expose("editor").} =
  return self.getOption[:JsonNode](path, default)

proc getFlag*(self: ConfigService, flag: string, default: bool = false): bool {.expose("config").} =
  return self.getOption[:bool](flag, default)

proc setFlag*(self: ConfigService, flag: string, value: bool) {.expose("config").} =
  self.setOption[:bool](flag, value)

proc toggleFlag*(self: ConfigService, flag: string) {.expose("config").} =
  let newValue = not self.getFlag(flag)
  log lvlInfo, fmt"toggleFlag '{flag}' -> {newValue}"
  self.setFlag(flag, newValue)

proc getAllConfigKeys*(node: JsonNode, prefix: string, res: var seq[tuple[key: string, value: JsonNode]]) =
  case node.kind
  of JObject:
    if prefix.len > 0:
      res.add (prefix, node)
    for key, value in node.fields.pairs:
      let key = if prefix.len > 0: prefix & "." & key else: key
      value.getAllConfigKeys(key, res)
  else:
    res.add (prefix, node)

proc getAllConfigKeys*(self: ConfigService): seq[tuple[key: string, value: JsonNode]] =
  self.settings.getAllConfigKeys("", result)

addGlobalDispatchTable "config", genDispatchTable("config")
