# Language servers

## Installation

Language servers currently have to be installed manually. If you already have a language server installed through another editor (e.g. VSCode, NeoVim etc.) then you should be able to use that version as well.

## Usage

The following LSP features are currently supported:

| Feature | Vim | VSCode | Note |
| ----------- | --- | --- | --- |
| `textDocument/definition` | `gd` | `<C-g><C-d>` or `<F12>` |  |
| `textDocument/declaration` | `gD` | `<C-g><CS-d>` |  |
| `textDocument/typeDefinition` | `gT` | `<C-g><CS-t>` |  |
| `textDocument/implementation` | `gi` | `<C-g><C-i>` |  |
| `textDocument/documentSymbol` | `gs` | `<C-g><C-s>` or `<CS-o>` |  |
| `textDocument/references` | `gr` | `<C-g><C-r>` or `<S-F12>` |  |
| `textDocument/hover` | `K` | `<C-g><C-k>` |  |
| `textDocument/diagnostic` | `H` | `<C-g><C-h>` |  |
| `textDocument/codeAction` | `ga` |  | Opens the code action picker for the selected diagnostic. |
| `textDocument/rename` | `gR` |  | Opens a prompt to rename a variable. |
| `textDocument/switchSourceHeader` | `go` | `<C-g><C-o>` | Only for C/C++ with `clangd` |
| `workspace/symbol` | `gw` | `<C-g><C-w>` or `<C-t>` |  |
| `textDocument/inlayHints` |  |  | No keybindings necessary |
| `textDocument/completion` |  |  | See below |

## Configuration

Configuration for language servers should be put in the user settings (`~/.nev/settings.json`) or the workspace settings (`{workspace_dir}/.nev/settings.json`)

Some language servers are already configured in the [app settings](../config/settings.json), so when you add you're own language server configuration make sure to use `"+lsp"` to extend the LSP configurations, unless you want to completely override the defaults:
- `nim`: `nimlangserver`
- `C`: `clangd`
- `C++`: `clangd`
- `Zig`: `zls`
- `Odin`: `ols`
- `Rust`: `rust-analizer`

Nev supports attaching multiple language servers to a document. The merge strategy for merging results from multiple
language servers is not configurable yet.

```json
// ~/.nev/settings.json
{
    // `+` is used to add new lsp configurations instead of overriding all of them with just these two
    "+lsp": {

        "clangd": {
            "languages": ["c", "cpp"], // Which languages to attach to
            "command": ["clangd", "--offset-encoding=utf-8"], // Command and arguments

            // Windows only:
            // Usually an LSP server should terminate itself when the client disconnects unexpectedly (e.g. because of a crash)
            // but some LSP servers don't do that. This setting enables using windows jobs to put LSP subprocesses into the same
            // job as the editor, so that when the editor process terminates in any way the LSP processes will be terminated
            // as well. If you use an LSP server which e.g. caches some things and terminating it forcefully could corrupt those
            // caches then you should disable this.
            // This is enabled by default.
            "kill-on-exit": false,
        },

        "nimlangserver": {
            "languages": ["nim"],
            "command": ["nimlangserver", "--stdio"],
            "settings": { // Settings sent to the language server
                "project": [],
                "projectMapping": [
                    {
                        "projectFile": "test.nim",
                        "fileRegex": ".*test.nim",
                    },
                ],
            },
        },

        "rust-analyzer": {
            "languages": ["rust"],
            "command": ["rust-analyzer"],

            // These properties are already set in {app_dir}/.nev/settings.json, so you just need to set "path" if you want to specifiy the full path to the binary, and the "rust-analyzer" property to
            // specify settings from [here](https://rust-analyzer.github.io/manual.html#configuration)
            // "path": "rust-analyzer",
            // "initialization-options-name": "rust-analyzer", // The name of the property to send as initialization options
            // "workspace-configuration-name": "", // The name of the property to send as initialization options
            // "initial-configuration": "", // Send a workspace/didChangeConfiguration request after initialization with this value. rust-analizer won't send workspace/configuration if this is not set.
            "rust-analyzer": {
                "linkedProjects": "path/to/Cargo.toml",
            },
        },
    },

    // Or use the short form:
    "lsp.zls": {
        "languages": ["zig"],
        "command": ["zls"],
        "settings": { // LSP specific configuration.
            "zls": {
                "enable_snippets": true,
                "enable_argument_placeholders": true,
                "enable_build_on_save": false
            }
        }
    },
}
```

## Inlay hints

Inlay hints are enabled by default, but can be disabled using the setting `text.inlay-hints-enabled`:

```json
// ~/.nev/settings.json
{
    // Disable inlay hints globally (can still be overriden per language)
    "text.inlay-hints-enabled": false,

    // Disable inlay hints for Nim
    "lang.nim.text.inlay-hints-enabled": false,
}

## Path language server

Nev has a builtin language server which provides auto completion and goto definition for paths.
To enable this language server for a language you need to add the language to `lsp-regex.languages` (see example below).

```json
// ~/.nev/settings.json
{
    // List of languages for which the paths language server gets enabled.
    // The `+` in this case means add "nim" to the list instead of setting the list to ["nim"]
    "lsp.paths.+languages": ["nim"],
}
```

## Regex based language features

Nev has a builtin language server which uses regexes defined per language to provide some features.
This allows you get decent support for some LSP features without having to install an LSP, or if no LSP is available for a language.

This feature currently requires [Ripgrep](https://github.com/BurntSushi/ripgrep) to be installed.

To enable this language server for a language you need to add the language to `lsp-regex.languages` (see example below).

Here is an example configuration for Nim which defines two regexes, one for goto definition and one to find symbols in the current file:


```json
// ~/.nev/settings.json
{
    // List of languages for which the regex language server gets enabled.
    // The `+` in this case means add "nim" to the list instead of setting the list to ["nim"]
    "lsp.regex.+languages": ["nim"],

    "lang.nim.text.search-regexes": {
        "symbols": "proc \\b[a-zA-Z0-9_]+\\b",
        "goto-definition": "proc \\b[[0]]\\b", // [[0]] will be replaced by the word under the cursor when searching
        "goto-declaration": "...",
        "goto-type-definition": "...",
        "goto-implementation": "...",
        "goto-references": "...",
        "workspace-symbols": {
            "Class": "...",
            "Function": "..."
            // Other lsp symbol kinds, like Class, Function, Method, Enum, ...
        }
    }
}
```

Given this configuration, when you press `gs` (in normal mode) in a Nim file, the editor will use the regex `languages.nim.search-regexes.symbols` to search the current file and display the results in a popup.

When you press `gd` (in normal mode) in a Nim file, the editor will use the regex `languages.nim.search-regexes.goto-definition` to search all workspaces. If only one result is found, the editor will open it immediately, otherwise all results are displayed in a popup.

For `goto-definition`, `goto-declaration`, `goto-type-definition`, `goto-implementation` and `goto-references` the regex is a template, and any instances of the string `[[0]]` will be replaced by the word under the cursor.

Currently there are some regexes configured for Nim, C and Zig.

### Auto completion

LSP is integrated into the completion engine as just another provider.

Currently the providers are:
- Document: Provides completions based on the content of the current document
- Snippet: Provides snippet completions which can be configured through the settings. VSCode `.code-snippets` files are also supported through the `vscode_config_plugin` which is shipped with the editor.

- LSP (when the document is connected to a language server): Provides completions using the `textDocument/completion` request.
  Language servers can also provide snippets this way.

The completion engine takes possible completions from all providers and sorts/filters them based on their priorities and fuzzy matching.

Currently this is not configurable yet, but later on the providers will be configurable and accessible to plugins.
Plugins will also be able to create new completion providers.
