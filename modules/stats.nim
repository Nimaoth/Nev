import std/[tables]
import service

const currentSourcePath2 = currentSourcePath()
include module_base

type
  StatsService* = ref object of DynamicService
    stats*: Table[string, tuple[value: int, unit: string]]

func serviceName*(_: typedesc[StatsService]): string = "StatsService"

# DLL API
proc set*(self: StatsService, name: string, value: int, unit: string = "") =
  self.stats[name] = (value, unit)

proc add*(self: StatsService, name: string, value: int, unit: string = "") =
  self.stats.mgetOrPut(name, (0, unit)).value += value

proc get*(self: StatsService, name: string): tuple[value: int, unit: string] =
  return self.stats[name]

# Implementation
when implModule:
  proc init_module_stats*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      return
    let service = StatsService()
    services.addService(service)
