# Nev

![Build](https://github.com/Nimaoth/Nev/actions/workflows/main.yml/badge.svg?event=push)

Nev is a text editor focused on keyboard usage, customizability and speed which runs in the terminal and in a GUI.
It also aims to provide tools for writing code out of the box, like Git integration, syntax highlighting using [Treesitter](https://tree-sitter.github.io/tree-sitter/), language integration using [LSP](https://microsoft.github.io/language-server-protocol) and debugging using [DAP](https://microsoft.github.io/debug-adapter-protocol/).

I'm also experimenting with a programming language system where instead of writing the source code as plain text,
the abstract syntax tree (AST) is edited directly (or rather through _projections_, which are still trees).
This feature is not included in release builds, and has to enabled by compiling with `-D:enableAst=true` (note that it doesn't compile with the latest version, I will continue work on this at a later stage, for now the focus is on making this a good text editor for "normal" programming languages).

Nev is still relatively new, so many things are still missing or need improvement. If you want to contribute check out [this](CONTRIBUTING.md).

## Features
- Vim motions (incomplete)
- [LSP](docs/lsp.md) (incomplete)
- [Syntax highlighting](docs/treesitter.md) using treesitter (no support for nested languages yet)
- Basic debugging using DAP
- [Fuzzy search for various things](docs/finders.md)
- [Sessions](docs/sessions.md)
- [WASM plugins](docs/configuration.md)
- Basic git integration (list/diff/add/stage/unstage/revert changed files)
- [Builtin terminal emulator](docs/docs.md#Terminal) support multiple shells (e.g `bash`, `powershell`, `wsl`)
- [Flexible layout system](docs/docs.md#Layout)
- And many more smaller features...

## Planned features
- Collaborative editing (the foundation exists already, the editor is using CRDTs based on [Zeds](https://github.com/zed-industries/zed) implementation)
- Create custom UI in plugins
- Fine grained permissions for plugins
- Builtin terminal
- Generic tree/table view with fuzzy searching, collapsing nodes, support for large trees. This will be used for e.g. file tree, document symbol outlines, type hierarchies, etc.
- Helix motions

## Installation
Download latest [release](https://github.com/Nimaoth/Nev/releases) or [build from source](docs/building_from_source.md)

## Inspirations
- [Neovim](https://github.com/neovim/neovim)
- [Helix](https://github.com/helix-editor/helix)
- [Zed](https://github.com/zed-industries/zed)
- [JetBrains MPS](https://github.com/JetBrains/MPS)

## Important notes if you intend to use it
- Currently only UTF-8 encoded files are supported
- Carriage return (`0xD`) will be removed when loading, and not added back when saving.
- Language servers and debug adapters have to installed manually at the moment, treesitter parsers require [emscripten](https://github.com/emscripten-core/emscripten)
- Read the [docs](docs/getting_started.md)

## Docs
- [General docs, contains things that don't fit into other files](docs/docs.md)
- [Build from source](docs/building_from_source.md)
- [Getting started](docs/getting_started.md)
- [Cheatsheet](docs/cheatsheet.md)
- [Configuration](docs/configuration.md)
- [Keybindings](docs/keybindings.md)
- [Finders](docs/finders.md)
- [Plugin API](https://nimaoth.github.io/AbsytreeDocs/scripting_nim/htmldocs/theindex.html).
- [Virtual filesystem](docs/virtual_file_system.md)

## Screenshots

Some of these screenshots and GIFs are quite old and things might look different.

### Nev running inside Windows Terminal -> WSL -> Zellij with transparent background
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/transparent_background.png)

---

### LSP integration
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/lsp.gif)

---

### Git integration
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/git.gif)

---

### Debugging support (breakpoints aren't rendered correctly in the GIF because of recording with asciinema and they use unicode symbols, see screenshot above)
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/debug.gif)

---

### Global and open file finders (and more)
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/finders.gif)

---

### Global search
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/search.gif)

---

### Themes
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/themes.gif)

---

### LSP completions
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/lsp_completions.png)

---

### Diagnostics, inlay hints and hover information
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/lsp_diagnostics_inlay_hints_hover.png)

---

### Fuzzy search for document symbols
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/lsp_document_symbols.png)

---

### View changed/added files in git, and open the diff for files directly, or stage/unstage/revert them
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/git_changed_files.png)

---

### View the git diff in the editor
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/git_diff.png)

---
