import std/[tables, options, json]
import misc/[jsonex, myjsonutils]
import component
export component

include dynlib_export

type ConfigComponent* = ref object of Component
  discard

# DLL API
var ConfigComponentId* {.apprtl.}: ComponentTypeId

proc getConfigComponent*(self: ComponentOwner): Option[ConfigComponent] {.apprtl, gcsafe, raises: [].}
proc configComponentGetRaw*(self: ConfigComponent, key: string): JsonNodeEx {.apprtl, gcsafe, raises: [].}

# Nice wrappers
proc get*(self: ConfigComponent, key: string, T: typedesc, defaultValue: T): T =
  let value = self.configComponentGetRaw(key)
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
      return defaultValue
  else:
    return defaultValue

proc get*(self: ConfigComponent, key: string, T: typedesc): T {.inline.} =
  self.get(key, T, T.default)

proc get*[T](self: ConfigComponent, key: string, defaultValue: T): T {.inline.} =
  self.get(key, T, defaultValue)

# Implementation
when implModule:
  import misc/[util]
  import config_provider

  ConfigComponentId = componentGenerateTypeId()

  type ConfigComponentImpl* = ref object of ConfigComponent
    config*: ConfigStore

  proc getConfigComponent*(self: ComponentOwner): Option[ConfigComponent] {.gcsafe, raises: [].} =
    return self.getComponent(ConfigComponentId).mapIt(it.ConfigComponent)

  proc newConfigComponent*(config: ConfigStore): ConfigComponent =
    return ConfigComponentImpl(typeId: ConfigComponentId, config: config)

  proc configComponentGetRaw*(self: ConfigComponent, key: string): JsonNodeEx {.gcsafe, raises: [].} =
    let self = self.ConfigComponentImpl
    return self.config.get(key)
