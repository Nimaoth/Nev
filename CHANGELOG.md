# Changelog

## [0.4.0](https://github.com/Nimaoth/Nev/compare/v0.3.0...v0.4.0) (2025-05-01)

- You can now define an alias for commands, with the ability to run multiple commands in one alias and forward arguments or
  supply default arguments.
- You can now define multi key keybindings with keys which produce characters (like `w`) in modes that consume input (like insert mode) while still being able to insert the original key by waiting or pressing another key which is not in the bound sequence.
  - Example: when you bind `jj` in insert mode to exit to normal mode, three things can happen:
    - You press `j` once then after a configured delay the `j` will be inserted as text
    - You press `j` twice in a row, faster than the configured delay, then it will exit to normal mode
    - You press `j` once followed by another key (e.g `k`) faster than the configured delay. `j` will be inserted and
      the next key press will be handled as usual.
- Added the ability to show signs on each line in a sign column, to show breakpoints, errors, code actions, etc.
- Added support LSP for code actions and rename
- Added support for multiple language servers attached to one document
- Added builtin language server to provide auto completion and goto definition for paths
- Changed how language servers are configured.

### Bug fixes

- Fixed clicking on text being off by one line in the terminal sometimes

## [0.3.0](https://github.com/Nimaoth/Nev/compare/v0.2.1...v0.3.0) (2025-05-01)

- Removed NimScript plugins, for now only WASM plugins are supported (Lua plugins might be added later)
- File content is now stored as a rope CRDT instead of a string array. This allows a bunch of improvements:
  - Better performance for big files and long lines
  - Treesitter parsing is now done on a background thread
  - File loading is now completely asynchronous, so no freezes when opening large files.
- Customizable language detection using regex
- Support WASM treesitter parsers
- Integrate Wasmtime as new WASM engine, for now only for treesitter parsers
- Added command for installing treesitter parsers (`install-treesitter-parser`, requires `tree-sitter-cli` and `git`)
- Added smooth scrolling
- Added command for browsing docs (`explore-help`)
- Added settings browser (`browse-settings`)
- Added key binding preview while waiting for further input in longer keybindings
- Added regex based goto-definition/goto-references/goto-symbol etc if no language server is available (requires Ripgrep). Regexes can be configured per language
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
