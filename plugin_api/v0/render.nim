
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
import
  types

import
  layout

type
  ## Shared handle to a custom render view
  RenderView* = object
    handle*: int32
proc renderRenderViewDrop(a: int32): void {.
    wasmimport("[resource-drop]render-view", "nev:plugins/render").}
proc `=copy`*(a: var RenderView; b: RenderView) {.error.}
proc `=destroy`*(a: RenderView) =
  if a.handle != 0:
    renderRenderViewDrop(a.handle - 1)

proc renderNewRenderViewImported(): int32 {.
    wasmimport("[constructor]render-view", "nev:plugins/render").}
proc newRenderView*(): RenderView {.nodestroy.} =
  let res = renderNewRenderViewImported()
  result.handle = res + 1

proc renderRenderViewFromUserIdImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[static]render-view.from-user-id", "nev:plugins/render").}
proc renderViewFromUserId*(id: WitString): Option[RenderView] {.nodestroy.} =
  ## Try to create a handle to an existing render view with the given user id.
  var
    retArea: array[8, uint8]
    arg0: int32
    arg1: int32
  if id.len > 0:
    arg0 = cast[int32](id[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](id.len)
  renderRenderViewFromUserIdImported(arg0, arg1,
                                     cast[int32](retArea[0].addr))
  if cast[ptr int32](retArea[0].addr)[] != 0:
    var temp: RenderView
    temp.handle = cast[ptr int32](retArea[4].addr)[] + 1
    result = temp.some

proc renderRenderViewFromViewImported(a0: int32; a1: int32): void {.
    wasmimport("[static]render-view.from-view", "nev:plugins/render").}
proc renderViewFromView*(v: View): Option[RenderView] {.nodestroy.} =
  ## Try to create a handle to an existing render view from a 'view'.
  var
    retArea: array[8, uint8]
    arg0: int32
  arg0 = v.id
  renderRenderViewFromViewImported(arg0, cast[int32](retArea[0].addr))
  if cast[ptr int32](retArea[0].addr)[] != 0:
    var temp: RenderView
    temp.handle = cast[ptr int32](retArea[4].addr)[] + 1
    result = temp.some

proc renderViewImported(a0: int32): int32 {.
    wasmimport("[method]render-view.view", "nev:plugins/render").}
proc view*(self: RenderView): View {.nodestroy.} =
  ## Returns the raw view handle.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = renderViewImported(arg0)
  result.id = convert(res, int32)

proc renderIdImported(a0: int32): int32 {.
    wasmimport("[method]render-view.id", "nev:plugins/render").}
proc id*(self: RenderView): int32 {.nodestroy.} =
  ## Returns the unique id of the view. This id is not stable across sessions.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = renderIdImported(arg0)
  result = convert(res, int32)

proc renderSizeImported(a0: int32; a1: int32): void {.
    wasmimport("[method]render-view.size", "nev:plugins/render").}
proc size*(self: RenderView): Vec2f {.nodestroy.} =
  ## Returns the size in pixels the view currently has. In the terminal one pixel is one character.
  var
    retArea: array[8, uint8]
    arg0: int32
  arg0 = cast[int32](self.handle - 1)
  renderSizeImported(arg0, cast[int32](retArea[0].addr))
  result.x = convert(cast[ptr float32](retArea[0].addr)[], float32)
  result.y = convert(cast[ptr float32](retArea[4].addr)[], float32)

proc renderSetRenderIntervalImported(a0: int32; a1: int32): void {.
    wasmimport("[method]render-view.set-render-interval", "nev:plugins/render").}
proc setRenderInterval*(self: RenderView; ms: int32): void {.nodestroy.} =
  ## Specify how often the view should render. -1 means don't render in a timer, 0 means render every frame,
  ## a number bigger than 0 specifies the interval in milliseconds.
  var
    arg0: int32
    arg1: int32
  arg0 = cast[int32](self.handle - 1)
  arg1 = ms
  renderSetRenderIntervalImported(arg0, arg1)

proc renderSetRenderCommandsRawImported(a0: int32; a1: uint32; a2: uint32): void {.wasmimport(
    "[method]render-view.set-render-commands-raw", "nev:plugins/render").}
proc setRenderCommandsRaw*(self: RenderView; buffer: uint32; len: uint32): void {.
    nodestroy.} =
  ## Set the render commands used for the next render. 'buffer' is a pointer to a buffer of encoded render commands,
  ## 'len' is the length of the buffer in bytes.
  var
    arg0: int32
    arg1: uint32
    arg2: uint32
  arg0 = cast[int32](self.handle - 1)
  arg1 = buffer
  arg2 = len
  renderSetRenderCommandsRawImported(arg0, arg1, arg2)

proc renderSetRenderCommandsImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[method]render-view.set-render-commands", "nev:plugins/render").}
proc setRenderCommands*(self: RenderView; data: WitList[uint8]): void {.
    nodestroy.} =
  ## Set the render commands used for the next render. 'data' contains encoded render commands.
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

proc renderSetRenderWhenInactiveImported(a0: int32; a1: bool): void {.wasmimport(
    "[method]render-view.set-render-when-inactive", "nev:plugins/render").}
proc setRenderWhenInactive*(self: RenderView; enabled: bool): void {.nodestroy.} =
  ## Enable rendering while the view is inactive (but still visible).
  var
    arg0: int32
    arg1: bool
  arg0 = cast[int32](self.handle - 1)
  arg1 = enabled
  renderSetRenderWhenInactiveImported(arg0, arg1)

proc renderSetPreventThrottlingImported(a0: int32; a1: bool): void {.wasmimport(
    "[method]render-view.set-prevent-throttling", "nev:plugins/render").}
proc setPreventThrottling*(self: RenderView; enabled: bool): void {.nodestroy.} =
  ## When enabled the view prevents the editor from throttling the frame rate after a few seconds. This requires
  ## the view to also be rendered regularly, using e.g. 'set-render-interval' or but marking it dirty regularly.
  var
    arg0: int32
    arg1: bool
  arg0 = cast[int32](self.handle - 1)
  arg1 = enabled
  renderSetPreventThrottlingImported(arg0, arg1)

proc renderSetUserIdImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[method]render-view.set-user-id", "nev:plugins/render").}
proc setUserId*(self: RenderView; id: WitString): void {.nodestroy.} =
  ## Sets the user id of this view.
  var
    arg0: int32
    arg1: int32
    arg2: int32
  arg0 = cast[int32](self.handle - 1)
  if id.len > 0:
    arg1 = cast[int32](id[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](id.len)
  renderSetUserIdImported(arg0, arg1, arg2)

proc renderGetUserIdImported(a0: int32; a1: int32): void {.
    wasmimport("[method]render-view.get-user-id", "nev:plugins/render").}
proc getUserId*(self: RenderView): WitString {.nodestroy.} =
  ## Returns the user id of this view.
  var
    retArea: array[8, uint8]
    arg0: int32
  arg0 = cast[int32](self.handle - 1)
  renderGetUserIdImported(arg0, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc renderMarkDirtyImported(a0: int32): void {.
    wasmimport("[method]render-view.mark-dirty", "nev:plugins/render").}
proc markDirty*(self: RenderView): void {.nodestroy.} =
  ## Trigger a render for this view.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  renderMarkDirtyImported(arg0)

proc renderSetRenderCallbackImported(a0: int32; a1: uint32; a2: uint32): void {.
    wasmimport("[method]render-view.set-render-callback", "nev:plugins/render").}
proc setRenderCallback*(self: RenderView; fun: uint32; data: uint32): void {.
    nodestroy.} =
  ## Sets the callback which wil be called before rendering. This can be used to set the render commands.
  ## 'fun' is a pointer to a function with signature func(id: s32, data: u32). Data is an arbitrary number
  ## which will be passed to the callback unchanged. It can be used as e.g. a pointer to some data.
  var
    arg0: int32
    arg1: uint32
    arg2: uint32
  arg0 = cast[int32](self.handle - 1)
  arg1 = fun
  arg2 = data
  renderSetRenderCallbackImported(arg0, arg1, arg2)

proc renderSetModesImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[method]render-view.set-modes", "nev:plugins/render").}
proc setModes*(self: RenderView; modes: WitList[WitString]): void {.nodestroy.} =
  ## Set the list of input modes. This controls which keybindings are available while the view is active.
  var
    arg0: int32
    arg1: int32
    arg2: int32
  arg0 = cast[int32](self.handle - 1)
  if modes.len > 0:
    arg1 = cast[int32](modes[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](modes.len)
  renderSetModesImported(arg0, arg1, arg2)

proc renderAddModeImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[method]render-view.add-mode", "nev:plugins/render").}
proc addMode*(self: RenderView; mode: WitString): void {.nodestroy.} =
  ## Add a mode to the input modes. This controls which keybindings are available while the view is active.
  var
    arg0: int32
    arg1: int32
    arg2: int32
  arg0 = cast[int32](self.handle - 1)
  if mode.len > 0:
    arg1 = cast[int32](mode[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](mode.len)
  renderAddModeImported(arg0, arg1, arg2)

proc renderRemoveModeImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("[method]render-view.remove-mode", "nev:plugins/render").}
proc removeMode*(self: RenderView; mode: WitString): void {.nodestroy.} =
  ## Remove a mode from the input modes. This controls which keybindings are available while the view is active.
  var
    arg0: int32
    arg1: int32
    arg2: int32
  arg0 = cast[int32](self.handle - 1)
  if mode.len > 0:
    arg1 = cast[int32](mode[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](mode.len)
  renderRemoveModeImported(arg0, arg1, arg2)
