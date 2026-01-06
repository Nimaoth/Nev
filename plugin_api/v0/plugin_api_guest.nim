
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
import
  editor

export
  editor

import
  vfs

export
  vfs

import
  channel

export
  channel

import
  types

export
  types

import
  layout

export
  layout

import
  registers

export
  registers

import
  events

export
  events

import
  text_document

export
  text_document

import
  session

export
  session

import
  render

export
  render

import
  core

export
  core

import
  process

export
  process

import
  settings

export
  settings

import
  text_editor

export
  text_editor

import
  commands

export
  commands

proc initPlugin(): void
proc initPluginExported(): void {.wasmexport("init-plugin", "nev:plugins/guest").} =
  initPlugin()

proc handleCommand(fun: uint32; data: uint32; arguments: WitString): WitString
var handleCommandRetArea: array[16, uint8]
proc handleCommandExported(a0: uint32; a1: uint32; a2: int32; a3: int32): int32 {.
    wasmexport("handle-command", "nev:plugins/guest").} =
  var
    fun: uint32
    data: uint32
    arguments: WitString
  fun = convert(a0, uint32)
  data = convert(a1, uint32)
  arguments = ws(cast[ptr char](a2), a3)
  let res = handleCommand(fun, data, arguments)
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

proc handleChannelUpdate(fun: uint32; data: uint32; closed: bool): ChannelListenResponse
proc handleChannelUpdateExported(a0: uint32; a1: uint32; a2: bool): int8 {.
    wasmexport("handle-channel-update", "nev:plugins/guest").} =
  var
    fun: uint32
    data: uint32
    closed: bool
  fun = convert(a0, uint32)
  data = convert(a1, uint32)
  closed = a2.bool
  cast[int8](handleChannelUpdate(fun, data, closed))

proc notifyTaskComplete(task: uint64; canceled: bool): void
proc notifyTaskCompleteExported(a0: uint64; a1: bool): void {.
    wasmexport("notify-task-complete", "nev:plugins/guest").} =
  var
    task: uint64
    canceled: bool
  task = convert(a0, uint64)
  canceled = a1.bool
  notifyTaskComplete(task, canceled)

proc handleMove(fun: uint32; data: uint32; text: uint32;
                selections: WitList[Selection]; count: int32; eol: bool): WitList[
    Selection]
var handleMoveRetArea: array[28, uint8]
proc handleMoveExported(a0: uint32; a1: uint32; a2: uint32; a3: int32;
                        a4: int32; a5: int32; a6: bool): int32 {.
    wasmexport("handle-move", "nev:plugins/guest").} =
  var
    fun: uint32
    data: uint32
    text: uint32
    selections: WitList[Selection]
    count: int32
    eol: bool
  fun = convert(a0, uint32)
  data = convert(a1, uint32)
  text = convert(a2, uint32)
  selections = wl(cast[ptr typeof(selections[0])](a3), a4)
  count = convert(a5, int32)
  eol = a6.bool
  let res = handleMove(fun, data, text, selections, count, eol)
  if res.len > 0:
    cast[ptr int32](handleMoveRetArea[0].addr)[] = cast[int32](res[0].addr)
  else:
    cast[ptr int32](handleMoveRetArea[0].addr)[] = 0.int32
  cast[ptr int32](handleMoveRetArea[4].addr)[] = cast[int32](res.len)
  cast[int32](handleMoveRetArea[0].addr)

proc savePluginState(): WitList[uint8]
var savePluginStateRetArea: array[8, uint8]
proc savePluginStateExported(): int32 {.wasmexport("save-plugin-state",
    "nev:plugins/guest").} =
  let res = savePluginState()
  if res.len > 0:
    cast[ptr int32](savePluginStateRetArea[0].addr)[] = cast[int32](res[0].addr)
  else:
    cast[ptr int32](savePluginStateRetArea[0].addr)[] = 0.int32
  cast[ptr int32](savePluginStateRetArea[4].addr)[] = cast[int32](res.len)
  cast[int32](savePluginStateRetArea[0].addr)

proc loadPluginState(state: WitList[uint8]): void
proc loadPluginStateExported(a0: int32; a1: int32): void {.
    wasmexport("load-plugin-state", "nev:plugins/guest").} =
  var state: WitList[uint8]
  state = wl(cast[ptr typeof(state[0])](a0), a1)
  loadPluginState(state)

proc handleEvent(fun: uint32; data: uint32; event: WitString; payload: WitString): void
proc handleEventExported(a0: uint32; a1: uint32; a2: int32; a3: int32;
                         a4: int32; a5: int32): void {.
    wasmexport("handle-event", "nev:plugins/guest").} =
  var
    fun: uint32
    data: uint32
    event: WitString
    payload: WitString
  fun = convert(a0, uint32)
  data = convert(a1, uint32)
  event = ws(cast[ptr char](a2), a3)
  payload = ws(cast[ptr char](a4), a5)
  handleEvent(fun, data, event, payload)

proc handleTextOverlayRender(fun: uint32; data: uint32; id: int64; size: Vec2f;
                             offset: int32): uint64
proc handleTextOverlayRenderExported(a0: uint32; a1: uint32; a2: int64;
                                     a3: float32; a4: float32; a5: int32): uint64 {.
    wasmexport("handle-text-overlay-render", "nev:plugins/guest").} =
  var
    fun: uint32
    data: uint32
    id: int64
    size: Vec2f
    offset: int32
  fun = convert(a0, uint32)
  data = convert(a1, uint32)
  id = convert(a2, int64)
  size.x = convert(a3, float32)
  size.y = convert(a4, float32)
  offset = convert(a5, int32)
  cast[uint64](handleTextOverlayRender(fun, data, id, size, offset))
