import std/[json, options]
import misc/[traits, util, event]

traitRef ConfigProvider:
  method getConfigValue(self: ConfigProvider, path: string): Option[JsonNode] {.gcsafe, raises: [].}
  method setConfigValue(self: ConfigProvider, path: string, value: JsonNode) {.gcsafe, raises: [].}
  method onConfigChanged*(self: ConfigProvider): var Event[void] {.gcsafe, raises: [].}

proc getValue*[T](self: ConfigProvider, path: string, default: T = T.default): T =
  template createScriptGetOption(self, path, defaultValue, accessor: untyped): untyped {.used.} =
    block:
      let value = self.getConfigValue(path)
      if value.isSome:
        accessor(value.get, defaultValue)
      else:
        defaultValue

  try:
    when T is bool:
      return createScriptGetOption(self, path, default, getBool)
    elif T is enum:
      return parseEnum[T](createScriptGetOption(self, path, "", getStr), default)
    elif T is Ordinal:
      return createScriptGetOption(self, path, default, getInt)
    elif T is float32 | float64:
      return createScriptGetOption(self, path, default, getFloat)
    elif T is string:
      return createScriptGetOption(self, path, default, getStr)
    elif T is JsonNode:
      return self.getConfigValue(path).get(default)
    else:
      {.fatal: ("Can't get option with type " & $T).}
  except KeyError:
    return default

proc setValue*[T](self: ConfigProvider, path: string, value: T) =
  template createScriptSetOption(self, path, value, constructor: untyped): untyped =
    block:
      self.setConfigValue(path, constructor(value))

  try:
    when T is bool:
      self.createScriptSetOption(path, value, newJBool)
    elif T is Ordinal:
      self.createScriptSetOption(path, value, newJInt)
    elif T is float32 | float64:
      self.createScriptSetOption(path, value, newJFloat)
    elif T is string:
      self.createScriptSetOption(path, value, newJString)
    else:
      {.fatal: ("Can't set option with type " & $T).}
  except KeyError:
    discard

proc getFlag*(self: ConfigProvider, flag: string, default: bool): bool =
  return self.getValue(flag, default)

proc setFlag*(self: ConfigProvider, flag: string, value: bool) =
  self.setValue(flag, value)

proc toggleFlag*(self: ConfigProvider, flag: string) =
  if self.getConfigValue(flag).isSome:
    self.setFlag(flag, not self.getFlag(flag, false))
