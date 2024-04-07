import "../src/scripting_api"
export scripting_api

## This file is auto generated, don't modify.

when defined(wasm):
  import editor_api_wasm
  export editor_api_wasm
else:
  import editor_api
  export editor_api
when defined(wasm):
  import editor_text_api_wasm
  export editor_text_api_wasm
else:
  import editor_text_api
  export editor_text_api
when defined(wasm):
  import lsp_api_wasm
  export lsp_api_wasm
else:
  import lsp_api
  export lsp_api
when defined(wasm):
  import popup_selector_api_wasm
  export popup_selector_api_wasm
else:
  import popup_selector_api
  export popup_selector_api

const enableAst* = false
