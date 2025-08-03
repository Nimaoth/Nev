
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
import
  types

export
  types

import
  text

export
  text

import
  text_editor

export
  text_editor

import
  layout

export
  layout

import
  render

export
  render

import
  core

export
  core

proc initPlugin(): void
proc initPluginExported(): void {.wasmexport("init-plugin", "nev:plugins/guest").} =
  initPlugin()

proc handleCommand(name: WitString; arg: WitString): WitString
var handleCommandRetArea: array[16, uint8]
proc handleCommandExported(a0: int32; a1: int32; a2: int32; a3: int32): int32 {.
    wasmexport("handle-command", "nev:plugins/guest").} =
  var
    name: WitString
    arg: WitString
  name = ws(cast[ptr char](a0), a1)
  arg = ws(cast[ptr char](a2), a3)
  let res = handleCommand(name, arg)
  if res.len > 0:
    cast[ptr int32](handleCommandRetArea[0].addr)[] = cast[int32](res[0].addr)
  else:
    cast[ptr int32](handleCommandRetArea[0].addr)[] = 0.int32
  cast[ptr int32](handleCommandRetArea[4].addr)[] = cast[int32](res.len)
  cast[int32](handleCommandRetArea[0].addr)

proc handleModeChanged(fun: uint32; old: WitString; new: WitString): void
proc handleModeChangedExported(a0: uint32; a1: int32; a2: int32; a3: int32;
                               a4: int32): void {.
    wasmexport("handle-mode-changed", "nev:plugins/guest").} =
  var
    fun: uint32
    old: WitString
    new: WitString
  fun = convert(a0, uint32)
  old = ws(cast[ptr char](a1), a2)
  new = ws(cast[ptr char](a3), a4)
  handleModeChanged(fun, old, new)

proc handleViewRenderCallback(id: int32; fun: uint32; data: uint32): void
proc handleViewRenderCallbackExported(a0: int32; a1: uint32; a2: uint32): void {.
    wasmexport("handle-view-render-callback", "nev:plugins/guest").} =
  var
    id: int32
    fun: uint32
    data: uint32
  id = convert(a0, int32)
  fun = convert(a1, uint32)
  data = convert(a2, uint32)
  handleViewRenderCallback(id, fun, data)
