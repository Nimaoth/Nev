
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime

{.pop.}
type
  Cursor* = object
    line*: int32
    column*: int32
  Selection* = object
    first*: Cursor
    last*: Cursor
  Vec2f* = object
    x*: float32
    y*: float32
  View* = object
    handle*: int32
  Rope* = object
    handle*: int32
proc renderViewDrop(a: int32): void {.wasmimport("[resource-drop]view",
    "nev:plugins/render").}
proc `=copy`*(a: var View; b: View) {.error.}
proc `=destroy`*(a: View) =
  if a.handle != 0:
    renderViewDrop(a.handle - 1)

proc textRopeDrop(a: int32): void {.wasmimport("[resource-drop]rope",
    "nev:plugins/text").}
proc `=copy`*(a: var Rope; b: Rope) {.error.}
proc `=destroy`*(a: Rope) =
  if a.handle != 0:
    textRopeDrop(a.handle - 1)

proc textEditorGetSelectionImported(a0: int32): void {.
    wasmimport("get-selection", "nev:plugins/text-editor").}
proc getSelection*(): Selection {.nodestroy.} =
  var retArea: array[16, uint8]
  textEditorGetSelectionImported(cast[int32](retArea[0].addr))
  result.first.line = convert(cast[ptr int32](retArea[0].addr)[], int32)
  result.first.column = convert(cast[ptr int32](retArea[4].addr)[], int32)
  result.last.line = convert(cast[ptr int32](retArea[8].addr)[], int32)
  result.last.column = convert(cast[ptr int32](retArea[12].addr)[], int32)

proc textEditorAddModeChangedHandlerImported(a0: uint32): int32 {.
    wasmimport("add-mode-changed-handler", "nev:plugins/text-editor").}
proc addModeChangedHandler*(fun: uint32): int32 {.nodestroy.} =
  var arg0: uint32
  arg0 = fun
  let res = textEditorAddModeChangedHandlerImported(arg0)
  result = convert(res, int32)

proc textNewRopeImported(a0: int32; a1: int32): int32 {.
    wasmimport("[constructor]rope", "nev:plugins/text").}
proc newRope*(content: WitString): Rope {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
  if content.len > 0:
    arg0 = cast[int32](content[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](content.len)
  let res = textNewRopeImported(arg0, arg1)
  result.handle = res + 1

proc textCloneImported(a0: int32): int32 {.
    wasmimport("[method]rope.clone", "nev:plugins/text").}
proc clone*(self: Rope): Rope {.nodestroy.} =
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = textCloneImported(arg0)
  result.handle = res + 1

proc textTextImported(a0: int32; a1: int32): void {.
    wasmimport("[method]rope.text", "nev:plugins/text").}
proc text*(self: Rope): WitString {.nodestroy.} =
  var
    retArea: array[8, uint8]
    arg0: int32
  arg0 = cast[int32](self.handle - 1)
  textTextImported(arg0, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textDebugImported(a0: int32; a1: int32): void {.
    wasmimport("[method]rope.debug", "nev:plugins/text").}
proc debug*(self: Rope): WitString {.nodestroy.} =
  var
    retArea: array[8, uint8]
    arg0: int32
  arg0 = cast[int32](self.handle - 1)
  textDebugImported(arg0, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textSliceImported(a0: int32; a1: int64; a2: int64): int32 {.
    wasmimport("[method]rope.slice", "nev:plugins/text").}
proc slice*(self: Rope; a: int64; b: int64): Rope {.nodestroy.} =
  var
    arg0: int32
    arg1: int64
    arg2: int64
  arg0 = cast[int32](self.handle - 1)
  arg1 = a
  arg2 = b
  let res = textSliceImported(arg0, arg1, arg2)
  result.handle = res + 1

proc textSlicePointsImported(a0: int32; a1: int32; a2: int32; a3: int32;
                             a4: int32): int32 {.
    wasmimport("[method]rope.slice-points", "nev:plugins/text").}
proc slicePoints*(self: Rope; a: Cursor; b: Cursor): Rope {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
    arg4: int32
  arg0 = cast[int32](self.handle - 1)
  arg1 = a.line
  arg2 = a.column
  arg3 = b.line
  arg4 = b.column
  let res = textSlicePointsImported(arg0, arg1, arg2, arg3, arg4)
  result.handle = res + 1

proc textGetCurrentEditorRopeImported(): int32 {.
    wasmimport("[static]rope.get-current-editor-rope", "nev:plugins/text").}
proc getCurrentEditorRope*(): Rope {.nodestroy.} =
  let res = textGetCurrentEditorRopeImported()
  result.handle = res + 1

proc coreApiVersionImported(): int32 {.wasmimport("api-version",
    "nev:plugins/core").}
proc apiVersion*(): int32 {.nodestroy.} =
  let res = coreApiVersionImported()
  result = convert(res, int32)

proc coreGetTimeImported(): float64 {.wasmimport("get-time", "nev:plugins/core").}
proc getTime*(): float64 {.nodestroy.} =
  let res = coreGetTimeImported()
  result = convert(res, float64)

proc coreBindKeysImported(a0: int32; a1: int32; a2: int32; a3: int32; a4: int32;
                          a5: int32; a6: int32; a7: int32; a8: int32; a9: int32;
                          a10: int32; a11: int32; a12: int32; a13: int32;
                          a14: int32; a15: int32): void {.
    wasmimport("bind-keys", "nev:plugins/core").}
proc bindKeys*(context: WitString; subcontext: WitString; keys: WitString;
               action: WitString; arg: WitString; description: WitString;
               source: (WitString, int32, int32)): void {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
    arg4: int32
    arg5: int32
    arg6: int32
    arg7: int32
    arg8: int32
    arg9: int32
    arg10: int32
    arg11: int32
    arg12: int32
    arg13: int32
    arg14: int32
    arg15: int32
  if context.len > 0:
    arg0 = cast[int32](context[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](context.len)
  if subcontext.len > 0:
    arg2 = cast[int32](subcontext[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](subcontext.len)
  if keys.len > 0:
    arg4 = cast[int32](keys[0].addr)
  else:
    arg4 = 0.int32
  arg5 = cast[int32](keys.len)
  if action.len > 0:
    arg6 = cast[int32](action[0].addr)
  else:
    arg6 = 0.int32
  arg7 = cast[int32](action.len)
  if arg.len > 0:
    arg8 = cast[int32](arg[0].addr)
  else:
    arg8 = 0.int32
  arg9 = cast[int32](arg.len)
  if description.len > 0:
    arg10 = cast[int32](description[0].addr)
  else:
    arg10 = 0.int32
  arg11 = cast[int32](description.len)
  if source[0].len > 0:
    arg12 = cast[int32](source[0][0].addr)
  else:
    arg12 = 0.int32
  arg13 = cast[int32](source[0].len)
  arg14 = source[1]
  arg15 = source[2]
  coreBindKeysImported(arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8,
                       arg9, arg10, arg11, arg12, arg13, arg14, arg15)

proc coreDefineCommandImported(a0: int32; a1: int32; a2: bool; a3: int32;
                               a4: int32; a5: int32; a6: int32; a7: int32;
                               a8: int32; a9: int32; a10: int32): void {.
    wasmimport("define-command", "nev:plugins/core").}
proc defineCommand*(name: WitString; active: bool; docs: WitString;
                    params: WitList[(WitString, WitString)];
                    returntype: WitString; context: WitString): void {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
    arg2: bool
    arg3: int32
    arg4: int32
    arg5: int32
    arg6: int32
    arg7: int32
    arg8: int32
    arg9: int32
    arg10: int32
  if name.len > 0:
    arg0 = cast[int32](name[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](name.len)
  arg2 = active
  if docs.len > 0:
    arg3 = cast[int32](docs[0].addr)
  else:
    arg3 = 0.int32
  arg4 = cast[int32](docs.len)
  if params.len > 0:
    arg5 = cast[int32](params[0].addr)
  else:
    arg5 = 0.int32
  arg6 = cast[int32](params.len)
  if returntype.len > 0:
    arg7 = cast[int32](returntype[0].addr)
  else:
    arg7 = 0.int32
  arg8 = cast[int32](returntype.len)
  if context.len > 0:
    arg9 = cast[int32](context[0].addr)
  else:
    arg9 = 0.int32
  arg10 = cast[int32](context.len)
  coreDefineCommandImported(arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7,
                            arg8, arg9, arg10)

proc coreRunCommandImported(a0: int32; a1: int32; a2: int32; a3: int32): void {.
    wasmimport("run-command", "nev:plugins/core").}
proc runCommand*(name: WitString; args: WitString): void {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
  if name.len > 0:
    arg0 = cast[int32](name[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](name.len)
  if args.len > 0:
    arg2 = cast[int32](args[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](args.len)
  coreRunCommandImported(arg0, arg1, arg2, arg3)

proc coreGetSettingRawImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("get-setting-raw", "nev:plugins/core").}
proc getSettingRaw*(name: WitString): WitString {.nodestroy.} =
  var
    retArea: array[8, uint8]
    arg0: int32
    arg1: int32
  if name.len > 0:
    arg0 = cast[int32](name[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](name.len)
  coreGetSettingRawImported(arg0, arg1, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc coreSetSettingRawImported(a0: int32; a1: int32; a2: int32; a3: int32): void {.
    wasmimport("set-setting-raw", "nev:plugins/core").}
proc setSettingRaw*(name: WitString; value: WitString): void {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
  if name.len > 0:
    arg0 = cast[int32](name[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](name.len)
  if value.len > 0:
    arg2 = cast[int32](value[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](value.len)
  coreSetSettingRawImported(arg0, arg1, arg2, arg3)

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

proc renderCreateImported(): int32 {.wasmimport("[static]view.create",
    "nev:plugins/render").}
proc create*(): View {.nodestroy.} =
  let res = renderCreateImported()
  result.handle = res + 1

proc renderFromIdImported(a0: int32): int32 {.
    wasmimport("[static]view.from-id", "nev:plugins/render").}
proc fromId*(id: int32): View {.nodestroy.} =
  var arg0: int32
  arg0 = id
  let res = renderFromIdImported(arg0)
  result.handle = res + 1

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
