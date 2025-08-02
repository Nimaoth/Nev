
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
import
  types

type
  View* = object
    handle*: int32
proc renderViewDrop(a: int32): void {.wasmimport("[resource-drop]view",
    "nev:plugins/render").}
proc `=copy`*(a: var View; b: View) {.error.}
proc `=destroy`*(a: View) =
  if a.handle != 0:
    renderViewDrop(a.handle - 1)

proc renderNewViewImported(): int32 {.wasmimport("[constructor]view",
    "nev:plugins/render").}
proc newView*(): View {.nodestroy.} =
  let res = renderNewViewImported()
  result.handle = res + 1

proc renderIdImported(a0: int32): int32 {.
    wasmimport("[method]view.id", "nev:plugins/render").}
proc id*(self: View): int32 {.nodestroy.} =
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = renderIdImported(arg0)
  result = convert(res, int32)

proc renderSizeImported(a0: int32; a1: int32): void {.
    wasmimport("[method]view.size", "nev:plugins/render").}
proc size*(self: View): Vec2f {.nodestroy.} =
  var
    retArea: array[8, uint8]
    arg0: int32
  arg0 = cast[int32](self.handle - 1)
  renderSizeImported(arg0, cast[int32](retArea[0].addr))
  result.x = convert(cast[ptr float32](retArea[0].addr)[], float32)
  result.y = convert(cast[ptr float32](retArea[4].addr)[], float32)

proc renderSetRenderIntervalImported(a0: int32; a1: int32): void {.
    wasmimport("[method]view.set-render-interval", "nev:plugins/render").}
proc setRenderInterval*(self: View; ms: int32): void {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
  arg0 = cast[int32](self.handle - 1)
  arg1 = ms
  renderSetRenderIntervalImported(arg0, arg1)

proc renderSetRenderCommandsRawImported(a0: int32; a1: uint32; a2: uint32): void {.
    wasmimport("[method]view.set-render-commands-raw", "nev:plugins/render").}
proc setRenderCommandsRaw*(self: View; buffer: uint32; len: uint32): void {.
    nodestroy.} =
  var
    arg0: int32
    arg1: uint32
    arg2: uint32
  arg0 = cast[int32](self.handle - 1)
  arg1 = buffer
  arg2 = len
  renderSetRenderCommandsRawImported(arg0, arg1, arg2)

proc renderSetRenderCommandsImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[method]view.set-render-commands", "nev:plugins/render").}
proc setRenderCommands*(self: View; data: WitList[uint8]): void {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
    arg2: int32
  arg0 = cast[int32](self.handle - 1)
  if data.len > 0:
    arg1 = cast[int32](data[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](data.len)
  renderSetRenderCommandsImported(arg0, arg1, arg2)

proc renderSetRenderWhenInactiveImported(a0: int32; a1: bool): void {.
    wasmimport("[method]view.set-render-when-inactive", "nev:plugins/render").}
proc setRenderWhenInactive*(self: View; enabled: bool): void {.nodestroy.} =
  var
    arg0: int32
    arg1: bool
  arg0 = cast[int32](self.handle - 1)
  arg1 = enabled
  renderSetRenderWhenInactiveImported(arg0, arg1)

proc renderSetPreventThrottlingImported(a0: int32; a1: bool): void {.
    wasmimport("[method]view.set-prevent-throttling", "nev:plugins/render").}
proc setPreventThrottling*(self: View; enabled: bool): void {.nodestroy.} =
  var
    arg0: int32
    arg1: bool
  arg0 = cast[int32](self.handle - 1)
  arg1 = enabled
  renderSetPreventThrottlingImported(arg0, arg1)

proc renderMarkDirtyImported(a0: int32): void {.
    wasmimport("[method]view.mark-dirty", "nev:plugins/render").}
proc markDirty*(self: View): void {.nodestroy.} =
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  renderMarkDirtyImported(arg0)

proc renderSetRenderCallbackImported(a0: int32; a1: uint32; a2: uint32): void {.
    wasmimport("[method]view.set-render-callback", "nev:plugins/render").}
proc setRenderCallback*(self: View; fun: uint32; data: uint32): void {.nodestroy.} =
  var
    arg0: int32
    arg1: uint32
    arg2: uint32
  arg0 = cast[int32](self.handle - 1)
  arg1 = fun
  arg2 = data
  renderSetRenderCallbackImported(arg0, arg1, arg2)

proc renderViewCreateImported(): int32 {.
    wasmimport("[static]view.create", "nev:plugins/render").}
proc viewCreate*(): View {.nodestroy.} =
  let res = renderViewCreateImported()
  result.handle = res + 1

proc renderViewFromIdImported(a0: int32): int32 {.
    wasmimport("[static]view.from-id", "nev:plugins/render").}
proc viewFromId*(id: int32): View {.nodestroy.} =
  var arg0: int32
  arg0 = id
  let res = renderViewFromIdImported(arg0)
  result.handle = res + 1
