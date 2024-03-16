import std/[json, options]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
elif defined(wasm):
  # import absytree_internal_wasm
  discard
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc lspLogVerbose*(val: bool) =
  lsp_lspLogVerbose_void_bool_impl(val)
proc lspToggleLogServerDebug*() =
  lsp_lspToggleLogServerDebug_void_impl()
proc lspLogServerDebug*(val: bool) =
  lsp_lspLogServerDebug_void_bool_impl(val)
