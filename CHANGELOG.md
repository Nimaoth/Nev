# Changelog

## [0.x.x](https://github.com/Nimaoth/Nev/compare/v0.2.1...main) (2024-08-18)

- Removed NimScript plugins, for now only wasm plugins are supported (Lua plugins might be added later)
- File content is now stored as a rope CRDT instead of a string array. This allows a bunch of improvements:
  - Better performance for big files (except for long lines)
  - Treesitter parsing is now done on a background thread
  - File loading is now completely asynchronous, so no freezes when opening large files.
- Customizable language detection using regex
- Added command for browsing docs (`explore-help`)
- Support WASM treesitter parsers
- Integrate wasmtime as new WASM engine, for now only for treesitter parsers
- Added command for installing treesitter parsers (`install-treesitter-parser`, requires `tree-sitter-cli` and `git`)
- Support file previewer for `choose-open` and `choose-file`
- Open split view in new view instead of current
- Added command for dumping key map as graphviz file
- Better performance overall
- Switched to chronos from std/asyncdispatch
- Many small fixes and improvements
- Removed filesystem related things from workspace, Nev now uses a virtual file system internally.

- Added smooth scrolling
- Added settings browser
- Added key binding preview while waiting for further input in longer keybindings
- Added regex based goto-definition/goto-references/goto-symbol etc if no language server is available (requires ripgrep). Regexes can be configured per language
- Improved document completions to run mostly on a background thread (except filtering) and cache the entire document
- Added inlay hints to preview colors detected using regex, e.g. "#feabee" can be detected, and an inlay hint in the corresponding color will be shown before the text. Has to be configured per language.
- Git view improvements:
  - Added keybindings to navigate changes without switching focus to the preview
  - Added ability to stage/unstage/revert individual changes, from git view or while diff is open
- Added expression evaluation for basic arithmetic like 1+2, and keybindings that add/subtract from a number at the cursor location

- Added option to disable line wrapping
- Added horizontal scrolling
- Added highlighting of all instances of text matching the current selection
- Added toast messages for errors
- Refactored settings

### Vim
- Fixed ctrl+w and ctrl+u in insert mode
- Escape now needs to be pressed twice to cancel the command line or popups, pressing it once goes to normal mode instead

## [0.2.1](https://github.com/Nimaoth/Nev/compare/v0.2.0...v0.2.1)

- More LSP support
- Basic DAP support
