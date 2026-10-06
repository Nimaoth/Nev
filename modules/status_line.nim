#use theme
import std/[tables, options]
import service
from nuigi import UiBuilder

const currentSourcePath2 = currentSourcePath()
include module_base

type
  StatusLineRenderNui* = proc(nui: var UiBuilder) {.gcsafe, raises: [].}
  StatusLineService* = ref object of DynamicService
    entriesNui*: Table[string, StatusLineRenderNui]

func serviceName*(_: typedesc[StatusLineService]): string = "StatusLine"

# DLL API
{.push rtl, gcsafe, raises: [].}
proc statusLineAddRendererNui(self: StatusLineService, name: string, render: StatusLineRenderNui) =
  self.entriesNui[name] = render
proc statusLineGetRendererNui(self: StatusLineService, name: string): Option[StatusLineRenderNui] =
  if name in self.entriesNui:
    return self.entriesNui[name].some
  return StatusLineRenderNui.none
{.pop.}

{.push inline}
proc addRendererNui*(self: StatusLineService, name: string, render: StatusLineRenderNui) = statusLineAddRendererNui(self, name, render)
proc getRendererNui*(self: StatusLineService, name: string): Option[StatusLineRenderNui] = statusLineGetRendererNui(self, name)
{.pop.}

when implModule:
  proc init_module_status_line*() {.cdecl, exportc, dynlib.} =
    let self = StatusLineService()
    getServices().addService(self)
