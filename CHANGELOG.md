# Changelog

## [0.x.x](https://github.com/Nimaoth/Nev/compare/v0.2.1...main) (2024-08-18)

- Removed NimScript plugins, for now only wasm plugins are supported (Lua plugins might be added later)
- File content is now stored as a rope CRDT instead of a string array. This allows a bunch of improvements:
  - Better performance for big files
  - Treesitter parsing is now done on a background thread
  - File loading is now completely asynchronous, so no freezes when opening large files.
- Customizable language detection
- Basic harpoon plugin port
- Added command for browsing docs (`explore-help`)
- Support WASM treesitter parsers
- Integrate wasmtime as new WASM engine, for now only for treesitter parsers
- Added command for installing treesitter parsers (`install-treesitter-parser`, requires `tree-sitter-cli` and `git`)
- Support file previewer for `choose-open` and `choose-file`
- Open split view in new view instead of current
- Added command for dumping key map as graphviz file
- Better performance overall
- Switched to chronos instead of std/asyncdispatch
- And many small fixes and improvements

### Vim
- Fixed ctrl+w and ctrl+u in insert mode
- Escape now needs to be pressed twice to cancel the command line or popups, pressing it once goes to normal mode instead

## [0.2.1](https://github.com/Nimaoth/Nev/compare/v0.2.0...v0.2.1)

- More LSP support
- Basic DAP support
