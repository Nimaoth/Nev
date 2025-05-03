# Changelog

## [0.4.0](https://github.com/Nimaoth/Nev/compare/v0.3.0...v0.4.0) (2025-05-01)

- You can now define an alias for commands, with the ability to run multiple commands in one alias and forward arguments or
  supply default arguments.

## [0.3.0](https://github.com/Nimaoth/Nev/compare/v0.2.1...v0.3.0) (2025-05-01)

- Removed NimScript plugins, for now only wasm plugins are supported (Lua plugins might be added later)
- File content is now stored as a rope CRDT instead of a string array. This allows a bunch of improvements:
  - Better performance for big files and long lines
  - Treesitter parsing is now done on a background thread
  - File loading is now completely asynchronous, so no freezes when opening large files.
- Customizable language detection using regex
- Support WASM treesitter parsers
- Integrate wasmtime as new WASM engine, for now only for treesitter parsers
- Added command for installing treesitter parsers (`install-treesitter-parser`, requires `tree-sitter-cli` and `git`)
- Added smooth scrolling
- Added command for browsing docs (`explore-help`)
- Added settings browser (`browse-settings`)
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
- Added commands to create/delete files/directories in file explorer.
- Reworked settings
- Recent sessions, finders to open recent sessions or find sessions
- Open session in new pane in tmux or zellij
- Shell command line: Run shell commands and show the output in a text editor. Not a full terminal, but good enough for some things.
- Many small fixes and improvements

### Vim
- Fixed ctrl+w and ctrl+u in insert mode
- Escape now needs to be pressed twice to cancel the command line or popups, pressing it once goes to normal mode instead

## [0.2.1](https://github.com/Nimaoth/Nev/compare/v0.2.0...v0.2.1)

- More LSP support
- Basic DAP support
