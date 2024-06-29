# Building

## Setup
- Requires OpenGL 4.1 for the GUI version
- Install Nim version 2.0.2. (we need some file from the compiler source so you need to install nim using choosenim, the prebuilt binaries from the nim website or build nim from source, because
  some linux package repositories, e.g. arch, don't seem to include the compiler source code, which this editor needs for nimscript)
- Clone the repository
- Run `nimble setup`

By default builds will not include the nimscript plugin api and the ast language framework.
To enable these features pass `-D:enableNimscript=true` and `-D:enableAst=true` respectively.

## Desktop version
- Use `nimble buildDesktop` or `nimble build` to compile the desktop version of the editor.
- The release builds are built with:
  - For the gui version: `nimble buildDesktop --app:gui -D:forceLogToFile -D:enableGui=true -D:enableTerminal=false`
  - For the terminal version: `nimble buildDesktop --app:console -D:forceLogToFile -D:enableGui=false -D:enableTerminal=true`

## Browser version
- Run `nimble buildBrowser`
- Embed the generated file `ast.js`
- See `absytree_browser.html` for an example

## Compiling tree sitter grammars to wasm
- Go into the tree-sitter repositories root directory
- Make sure the cli is built
  - `cargo build`
- Compile the desired language to wasm. The specified directory is the one containing the `src` folder which in turn contains the `grammar.js`
  - `target/release/tree-sitter build-wasm ../dev/nimtreesitter/treesitter_nim/treesitter_nim/nim`

## Compiling tree sitter wasm binding
- Go into the tree-sitter repositories root directory
- Build the binding:
  - `script/build-wasm`
- Copy the generated files to the AbsytreeBrowser directory:
  - `cp lib/binding_web/tree-sitter.js <.../AbsytreeBrowser> && cp lib/binding_web/tree-sitter.wasm <.../AbsytreeBrowser>`

## Compiling Nim config files to wasm
- You need to have Emscripten installed.
- Run `nimble buildNimConfigWasm` from the root folder of the repository
