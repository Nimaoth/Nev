
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wasmtime

{.pop.}
type
  Cursor* = object
    line*: int32
    column*: int32
  Selection* = object
    first*: Cursor
    last*: Cursor
when not declared(RopeResource):
  {.error: "Missing resource type definition for " & "RopeResource" &
      ". Define the type before the importWit statement.".}
proc textEditorGetSelection(host: WasmContext; store: ptr ComponentContextT): Selection
proc textNewRope(host: WasmContext; store: ptr ComponentContextT;
                 content: string): RopeResource
proc textClone(host: WasmContext; store: ptr ComponentContextT;
               self: var RopeResource): RopeResource
proc textText(host: WasmContext; store: ptr ComponentContextT;
              self: var RopeResource): string
proc textDebug(host: WasmContext; store: ptr ComponentContextT;
               self: var RopeResource): string
proc textSlice(host: WasmContext; store: ptr ComponentContextT;
               self: var RopeResource; a: int64; b: int64): RopeResource
proc textSlicePoints(host: WasmContext; store: ptr ComponentContextT;
                     self: var RopeResource; a: Cursor; b: Cursor): RopeResource
proc textGetCurrentEditorRope(host: WasmContext; store: ptr ComponentContextT): RopeResource
proc coreBindKeys(host: WasmContext; store: ptr ComponentContextT;
                  context: string; subContext: string; keys: string;
                  action: string; arg: string; description: string;
                  source: (string, int32, int32)): void
proc coreDefineCommand(host: WasmContext; store: ptr ComponentContextT;
                       name: string; active: bool; docs: string;
                       params: seq[(string, string)]; returnType: string;
                       context: string): void
proc coreRunCommand(host: WasmContext; store: ptr ComponentContextT;
                    name: string; args: string): void
proc defineComponent*(linker: ptr ComponentLinkerT; host: WasmContext): WasmtimeResult[
    void] =
  ?linker.defineResource("nev:plugins/text", "rope", RopeResource)
  linker.defineFunc("nev:plugins/text-editor", "get-selection"):
    let res = textEditorGetSelection(host, store)
    results[0] = res.toVal
  linker.defineFunc("nev:plugins/text", "[constructor]rope"):
    let content = parameters[0].to(string)
    let res = textNewRope(host, store, content)
    results[0] = ?store.resourceNew(res)
  linker.defineFunc("nev:plugins/text", "[method]rope.clone"):
    let self = ?store.resourceHostData(parameters[0].addr, RopeResource)
    let res = textClone(host, store, self[])
    results[0] = ?store.resourceNew(res)
    ?store.resourceDrop(parameters[0].addr)
  linker.defineFunc("nev:plugins/text", "[method]rope.text"):
    let self = ?store.resourceHostData(parameters[0].addr, RopeResource)
    let res = textText(host, store, self[])
    results[0] = res.toVal
    ?store.resourceDrop(parameters[0].addr)
  linker.defineFunc("nev:plugins/text", "[method]rope.debug"):
    let self = ?store.resourceHostData(parameters[0].addr, RopeResource)
    let res = textDebug(host, store, self[])
    results[0] = res.toVal
    ?store.resourceDrop(parameters[0].addr)
  linker.defineFunc("nev:plugins/text", "[method]rope.slice"):
    let self = ?store.resourceHostData(parameters[0].addr, RopeResource)
    let a = parameters[1].to(int64)
    let b = parameters[2].to(int64)
    let res = textSlice(host, store, self[], a, b)
    results[0] = ?store.resourceNew(res)
    ?store.resourceDrop(parameters[0].addr)
  linker.defineFunc("nev:plugins/text", "[method]rope.slice-points"):
    let self = ?store.resourceHostData(parameters[0].addr, RopeResource)
    let a = parameters[1].to(Cursor)
    let b = parameters[2].to(Cursor)
    let res = textSlicePoints(host, store, self[], a, b)
    results[0] = ?store.resourceNew(res)
    ?store.resourceDrop(parameters[0].addr)
  linker.defineFunc("nev:plugins/text", "[static]rope.get-current-editor-rope"):
    let res = textGetCurrentEditorRope(host, store)
    results[0] = ?store.resourceNew(res)
  linker.defineFunc("nev:plugins/core", "bind-keys"):
    let context = parameters[0].to(string)
    let subContext = parameters[1].to(string)
    let keys = parameters[2].to(string)
    let action = parameters[3].to(string)
    let arg = parameters[4].to(string)
    let description = parameters[5].to(string)
    let source = parameters[6].to((string, int32, int32))
    coreBindKeys(host, store, context, subContext, keys, action, arg,
                 description, source)
  linker.defineFunc("nev:plugins/core", "define-command"):
    let name = parameters[0].to(string)
    let active = parameters[1].to(bool)
    let docs = parameters[2].to(string)
    let params = parameters[3].to(seq[(string, string)])
    let returnType = parameters[4].to(string)
    let context = parameters[5].to(string)
    coreDefineCommand(host, store, name, active, docs, params, returnType,
                      context)
  linker.defineFunc("nev:plugins/core", "run-command"):
    let name = parameters[0].to(string)
    let args = parameters[1].to(string)
    coreRunCommand(host, store, name, args)
