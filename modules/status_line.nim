import std/[tables, options]
import service
import ui/node

const currentSourcePath2 = currentSourcePath()
include module_base

type
  StatusLineRender* = proc(builder: UINodeBuilder): seq[OverlayFunction] {.gcsafe, raises: [].}
  StatusLineService* = ref object of DynamicService
    entries*: Table[string, StatusLineRender]

func serviceName*(_: typedesc[StatusLineService]): string = "StatusLine"

# DLL API
{.push rtl, gcsafe, raises: [].}
proc statusLineAddRenderer(self: StatusLineService, name: string, render: StatusLineRender) =
  self.entries[name] = render
proc statusLineGetRenderer(self: StatusLineService, name: string): Option[StatusLineRender] =
  if name in self.entries:
    return self.entries[name].some
  return StatusLineRender.none
{.pop.}

{.push inline}
proc addRenderer*(self: StatusLineService, name: string, render: StatusLineRender) = statusLineAddRenderer(self, name, render)
proc getRenderer*(self: StatusLineService, name: string): Option[StatusLineRender] = statusLineGetRenderer(self, name)
{.pop.}

when implModule:
  proc init_module_status_line*() {.cdecl, exportc, dynlib.} =
    let self = StatusLineService()
    getServices().addService(self)
