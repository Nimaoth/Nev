# Absytree

![Build and tests](https://github.com/Nimaoth/Absytree/actions/workflows/main.yml/badge.svg?event=push)

This is still very early in developement and very experimental!

Written in Nim

## Programming Language + Editor

Absytree is a text editor + programming languange workbench where instead of writing the source code as text in text files,
the abstract syntac tree (AST) is edited directly (or rather through _projections_, which are still trees)
Languages will be extendable with custom AST node types, by either translating those to nodes of other languages or by implementing code generation
for the backend (at the moment only WASM).

The editor is available for the terminal, as a desktop GUI app and in the browser (without some features).
You can try the browser version [here](https://nimaoth.github.io/AbsytreeBrowser/absytree_browser.html?s=default.absytree-session).
There is also a very experimental [Unreal Engine Plugin](https://github.com/Nimaoth/AbsytreeUE).

`ast` is the gui version, `astt` is the terminal version

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

## Building

### Setup
- Requires OpenGL 4.1 for the GUI version
- Install Nim version 2.0.2. (we need some file from the compiler source so you need to install nim using choosenim, the prebuilt binaries from the nim website or build nim from source, because
  some linux package repositories, e.g. arch, don't seem to include the compiler source code, which this editor needs for nimscript)
- Clone the repository
- Run `nimble setup`

By default builds will not include the nimscript plugin api and the ast language framework.
To enable these features pass `-D:enableNimscript=true` and `-D:enableAst=true` respectively.

### Desktop version
- Use `nimble buildDesktop` or `nimble build` to compile the desktop version of the editor.
- The release builds are built with:
  - For the gui version: `nimble buildDesktop --app:gui -D:forceLogToFile -D:enableGui=true -D:enableTerminal=false`
  - For the terminal version: `nimble buildDesktop --app:console -D:forceLogToFile -D:enableGui=false -D:enableTerminal=true`

### Browser version
- Run `nimble buildBrowser`
- Embed the generated file `ast.js`
- See `absytree_browser.html` for an example

### Compiling tree sitter grammars to wasm
- Go into the tree-sitter repositories root directory
- Make sure the cli is built
  - `cargo build`
- Compile the desired language to wasm. The specified directory is the one containing the `src` folder which in turn contains the `grammar.js`
  - `target/release/tree-sitter build-wasm ../dev/nimtreesitter/treesitter_nim/treesitter_nim/nim`

### Compiling tree sitter wasm binding
- Go into the tree-sitter repositories root directory
- Build the binding:
  - `script/build-wasm`
- Copy the generated files to the AbsytreeBrowser directory:
  - `cp lib/binding_web/tree-sitter.js <.../AbsytreeBrowser> && cp lib/binding_web/tree-sitter.wasm <.../AbsytreeBrowser>`

## Configuration and plugins

Configuration is done using JSON files.

Absytree also supports different plugin mechanisms. The editor API is exposed to each one and can be used to create new commands, change options, etc.
- NimScript (optional): Only supported in the desktop version. The editor bundles part of the Nim compiler so it can run NimScript code.
  Allows easy hot reloading of the config file, but right now only one nimscript file is supported. Needs to be enabled with `-d:enableNimscript`.
  Slightly increases startup time of the editor.
- Wasm: Works on the desktop and in the browser. In theory any language can be used to write plugins if it can compile to wasm.
  Probably better performance than NimScript.
- In the future the builtin language framework will be usable as a scripting language as well by compiling to wasm.

More details in [Configuration](docs/configuration.md) and [Getting Started](docs/getting_started.md)

### Compiling Nim config files to wasm
- You need to have Emscripten installed.
- Run `nimble buildNimConfigWasm` from the root folder of the repository

## Screenshots

### Absytree running inside Windows Terminal -> WSL -> Zellij with transparent background
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
