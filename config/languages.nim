import absytree_runtime

{.used.}

let useLSPWebsocketProxy = getBackend() == Browser

if useLSPWebsocketProxy:
  setOption "editor.text.languages-server.url", "localhost"
  setOption "editor.text.languages-server.port", 3001
else:
  setOption "editor.text.languages-server.url", ""
  setOption "editor.text.languages-server.port", 0

setOption "editor.text.lsp.zig.path", "zls"
setOption "editor.text.lsp.rust.path", "rust-analyzer"
setOption "editor.text.lsp.nim.path", "nimlangserver"
setOption "editor.text.lsp.nim.args", %*["--stdio"]
setOption "editor.text.treesitter.rust.dll", "D:/dev/Nim/nimtreesitter/treesitter_rust/treesitter_rust/rust.dll"
setOption "editor.text.treesitter.zig.dll", "D:/dev/Nim/nimtreesitter/treesitter_zig/treesitter_zig/zig.dll"
setOption "editor.text.treesitter.javascript.dll", "D:/dev/Nim/nimtreesitter/treesitter_javascript/treesitter_javascript/javascript.dll"
setOption "editor.text.treesitter.nim.dll", "D:/dev/Nim/nimtreesitter/treesitter_nim/treesitter_nim/nim.dll"
setOption "editor.text.treesitter.python.dll", "D:/dev/Nim/nimtreesitter/treesitter_python/treesitter_python/python.dll"

setOption "editor.text.language.nim", %*{
  "tabWidth": 2,
  "indent": "spaces",
  "indentAfter": [":", "=", "(", "{", "[", "enum", "object"],
  "lineComment": "#",
}

setOption "editor.text.language.python", %*{
  "tabWidth": 2,
  "indent": "spaces",
  "indentAfter": [":", "=", "(", "{", "["],
  "lineComment": "#",
}

setOption "editor.text.language.javascript", %*{
  "tabWidth": 4,
  "indent": "spaces",
  "indentAfter": [":", "=", "(", "{", "["],
  "lineComment": "//",
  "blockComment": ["/*", "*/"],
  "ignoreContextLinePrefix": "{",
}

setOption "editor.text.language.typescript", %*{
  "tabWidth": 4,
  "indent": "tab",
  "indentAfter": [":", "=", "(", "{", "["],
  "lineComment": "//",
  "blockComment": ["/*", "*/"],
}

setOption "editor.text.language.rust", %*{
  "tabWidth": 4,
  "indent": "spaces",
  "indentAfter": [":", "=", "(", "{", "["],
  "lineComment": "//",
  "blockComment": ["/*", "*/"],
}

setOption "editor.text.language.c", %*{
  "tabWidth": 4,
  "indent": "tab",
  "indentAfter": [":", "=", "(", "{", "["],
  "lineComment": "//",
  "blockComment": ["/*", "*/"],
}

setOption "editor.text.language.cpp", %*{
  "tabWidth": 4,
  "indent": "tab",
  "indentAfter": [":", "=", "(", "{", "["],
  "lineComment": "//",
  "blockComment": ["/*", "*/"],
}

setOption "editor.text.language.java", %*{
  "tabWidth": 4,
  "indent": "tab",
  "indentAfter": [":", "=", "(", "{", "["],
  "lineComment": "//",
  "blockComment": ["/*", "*/"],
}

setOption "editor.text.language.zig", %*{
  "tabWidth": 4,
  "indent": "tab",
  "indentAfter": [":", "=", "(", "{", "["],
  "lineComment": "//",
}