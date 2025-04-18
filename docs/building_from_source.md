# Building

## Setup
- Requires OpenGL 4.1 for the GUI version
- Install Rust and cargo (required for wasmtime)
- Install Nim version 2.2.0
- Clone the repository
- Run `nimble setup`

The ast language framework is does not compile on the current main branch, I will continue work on this at some later point.

## Compile errors
If you get a compile error, try building with `--passC:-Wno-incompatible-pointer-types`, e.g:
`nimble buildDesktop --passC:-Wno-incompatible-pointer-types -d:appBuildWasmtime --forceBuild --app:gui -D:forceLogToFile -D:enableGui=true`

## Desktop version
- Use `nimble buildDesktop` or `nimble build` to compile the desktop version of the editor.
- The release builds are built with:
  - For the gui version: `nimble buildDesktop --app:gui -D:forceLogToFile -D:enableGui=true -D:enableTerminal=false`
  - For the terminal version: `nimble buildDesktop --app:console -D:forceLogToFile -D:enableGui=false -D:enableTerminal=true`

## Compiling tree sitter grammars to wasm
- Go into the tree-sitter repositories root directory
- Make sure the cli is built
  - `cargo build`
- Compile the desired language to wasm. The specified directory is the one containing the `src` folder which in turn contains the `grammar.js`
  - `target/release/tree-sitter build-wasm ../dev/nimtreesitter/treesitter_nim/treesitter_nim/nim`

## Compiling Nim config files to wasm
- You need to have Emscripten installed.
- Run `nimble buildNimConfigWasm` from the root folder of the repository
