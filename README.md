# Nev

![Build and tests](https://github.com/Nimaoth/Nev/actions/workflows/main.yml/badge.svg?event=push)

This is still very early in developement and very experimental. Use at your own risk!

## Programming Language + Editor

Nev is a text editor + programming languange workbench where instead of writing the source code as text in text files,
the abstract syntac tree (AST) is edited directly (or rather through _projections_, which are still trees)
Languages will be extendable with custom AST node types, by either translating those to nodes of other languages or by implementing code generation
for the backend (at the moment only WASM).

The editor is available for the terminal, as a desktop GUI app.
You can an old browser version [here](https://nimaoth.github.io/AbsytreeBrowser/nev_browser.html?s=default.nev-session), but this is not representative of the current state and will not be updated in the near future (only works in Chrome).
There is also a very experimental [Unreal Engine Plugin](https://github.com/Nimaoth/AbsytreeUE) which integrates Nev into the Unreal editor.

## Goals
- For the text editor:
  - Sit somewhere inbetween Vim and VS Code
  - The most important tools are built in (e.g. syntax highlighting with tree-sitter, LSP support)
  - Can be used purely as a text editor (ignoring the AST language framework)
  - Little to no configuration needed to get nice experience out of the box
  - Support Vim motions
- General goals:
  - Keyboard focused (only basic mouse support)
  - Easily extendable with scripting
  - Good performance

## Inspirations
- [JetBrains MPS](https://github.com/JetBrains/MPS)
- [Dion Systems Editor](https://dion.systems/gallery.html)
- [NeoVim](https://github.com/neovim/neovim)
- [Helix](https://github.com/helix-editor/helix)

## Important notes if you intend to use it

- Current only UTF-8 encoded files are supported
- Language servers, Treesitter parsers and debug adapters have to installed manually at the moment
- Read the [docs](docs/getting_started.md)

## Docs
- [Build from source](docs/building_from_source.md)
- [Getting started](docs/getting_started.md)
- [Cheatsheet](docs/cheatsheet.md)
- [Configuration](docs/configuration.md)
- [Finders](docs/finders.md)
- [Plugin API](https://nimaoth.github.io/AbsytreeDocs/scripting_nim/htmldocs/theindex.html).

## Screenshots

### Nev running inside Windows Terminal -> WSL -> Zellij with transparent background
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/transparent_background.png)

---

### LSP integration
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/lsp.gif)

---

### Git integration
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/git.gif)

---

### Debugging support (breakpoints aren't rendered correctly in the gif because of recording with asciinema and they use unicode symbols, see screenshot above)
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/debug.gif)

---

### Global and open file finders (and more)
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/finders.gif)

---

### Global search
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/search.gif)

---

### Themes
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/themes.gif)

---

### LSP completions
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/lsp_completions.png)

---

### Diagnostics, inlay hints and hover information
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/lsp_diagnostics_inlay_hints_hover.png)

---

### Fuzzy search for document symbols
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/lsp_document_symbols.png)

---

### View changed/added files in git, and open the diff for files directly, or stage/unstage/revert them
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/git_changed_files.png)

---

### View the git diff in the editor
![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/git_diff.png)

---
