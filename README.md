# Nev

![Build](https://github.com/Nimaoth/Nev/actions/workflows/main.yml/badge.svg?event=push)

Nev is a text editor focused on keyboard usage, customizability and speed which runs in the terminal and in a GUI.
It also aims to provide tools for writing code out of the box, like Git integration, syntax highlighting using [Treesitter](https://tree-sitter.github.io/tree-sitter/), language integration using [LSP](https://microsoft.github.io/language-server-protocol) and debugging using [DAP](https://microsoft.github.io/debug-adapter-protocol/).

Nev is still relatively new, so many things are still missing or need improvement. If you want to contribute check out [this](CONTRIBUTING.md).

There is a [Discord server](https://discord.gg/eJjBMcgP2V) where you can ask questions as well.

**I'm doing this for fun and only work on Nev in my free time. Use Nev at your own risk!**

## Features
- Vim motions
- [LSP](docs/lsp.md)
- [Syntax highlighting](docs/treesitter.md) using treesitter with support for nested languages
- Debugging using DAP
- [Fuzzy search for various things](docs/finders.md)
- [Sessions](docs/sessions.md)
- [WASM plugins](docs/configuration.md)
- Basic git integration (list/diff/add/stage/unstage/revert changed files)
- [Builtin terminal emulator](docs/docs.md#Terminal) support multiple shells (e.g `bash`, `powershell`, `wsl`)
- [Flexible layout system](docs/docs.md#Layout)
- [Nice looking markdown](docs/markdown.md)
- [Undo Trees](docs/undo_tree.md)
- And many more features...

## Planned features
- Expand plugin API
- Fine grained permissions for plugins
- Performance and memory usage improvements

## Installation
Download latest [release](https://github.com/Nimaoth/Nev/releases) or [build from source](docs/building_from_source.md)

## Inspirations
- [Neovim](https://github.com/neovim/neovim)
- [Helix](https://github.com/helix-editor/helix)
- [Zed](https://github.com/zed-industries/zed)

## Important notes if you intend to use it
- Nev currently only supports saving files as UTF-8
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
- [Moves](docs/moves.md)
- [Markdown](docs/markdown.md)


## Showcase

![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/dashboard.png)

---

### Debugging
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/debug.gif)

---

### Themes
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/themes.gif)

---

### Diagnostics and inlay hints
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/lsp_diagnostics_inlay_hints_hover.png)

---

### Diff View
![alt](https://raw.githubusercontent.com/Nimaoth/NevScreenshots/main/git_diff.png)
---
