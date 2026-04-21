# Nev

![Build](https://github.com/Nimaoth/Nev/actions/workflows/main.yml/badge.svg?event=push)
[![Discord](https://img.shields.io/discord/1379505644704497664?logo=discord&logoColor=fff)](https://discord.gg/eJjBMcgP2V)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Nev is a fast, keyboard-driven text editor written in Nim that runs in the terminal and in a GUI.
It combines ideas from Neovim, Helix, and Zed with builtin developer tools like Git integration, Treesitter syntax highlighting, LSP support, DAP debugging, and WASM plugins.

**I'm developing Nev for fun and only work on it in my free time. Use at your own risk!**

## Table of Contents

- [Features](#features)
- [Why Nev?](#why-nev)
- [Supported Platforms](#supported-platforms)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Docs](#docs)
- [Showcase](#showcase)
- [Contributing](#contributing)
- [License](#license)

## Features

- Vim motions
- [LSP](docs/lsp.md)
- Syntax highlighting using [Treesitter](docs/treesitter.md) with support for nested languages
- Debugging using DAP
- [Fuzzy search for various things](docs/finders.md)
- [Sessions](docs/sessions.md)
- [WASM plugins](docs/plugins.md)
- Basic git integration (list/diff/add/stage/unstage/revert changed files)
- [Builtin terminal emulator](docs/docs.md#Terminal) supporting multiple shells (e.g. `bash`, `powershell`, `wsl`)
- [Flexible layout system](docs/docs.md#Layout)
- [Nice looking markdown](docs/markdown.md)
- [Undo Trees](docs/undo_tree.md)
- And many more features...

## Supported Platforms

- **Windows**
- **Linux**

## Prerequisites

- `ripgrep` to enable global search

## Installation

Download the latest [release](https://github.com/Nimaoth/Nev/releases) or [build from source](docs/building_from_source.md).

## Quick Start

Open a file or directory from the command line:

```bash
nev .            # Open the current directory
nev myfile.py    # Open a specific file
```

Check out the [cheatsheet](docs/cheatsheet.md) and [getting started guide](docs/getting_started.md) for more info.

## Inspirations

- [Neovim](https://github.com/neovim/neovim)
- [Helix](https://github.com/helix-editor/helix)
- [Zed](https://github.com/zed-industries/zed)

## Important notes if you intend to use it

- Nev currently only supports saving files as `UTF-8` and without carriage return in line separators.
- Language servers and debug adapters have to be installed manually at the moment; Treesitter parsers require [Emscripten](https://github.com/emscripten-core/emscripten)

## Docs

- [Getting started](docs/getting_started.md)
- [cheatsheet](docs/cheatsheet.md)
- [General docs](docs/docs.md)
- [Build from source](docs/building_from_source.md)
- [Cheatsheet](docs/cheatsheet.md)
- [Configuration](docs/configuration.md)
- [Keybindings](docs/keybindings.md)
- [Finders](docs/finders.md)
- [Plugin API](https://nimaoth.github.io/AbsytreeDocs/scripting_nim/htmldocs/theindex.html)
- [Virtual filesystem](docs/virtual_file_system.md)
- [Moves](docs/moves.md)
- [Treesitter](docs/treesitter.md)
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

## Contributing

Nev is still relatively new, so many things are still missing or need improvement. If you want to contribute, check out [CONTRIBUTING.md](CONTRIBUTING.md).

There is also a [Discord server](https://discord.gg/eJjBMcgP2V) where you can ask questions.

## License

This project is licensed under the [MIT License](LICENSE).
