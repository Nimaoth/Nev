# Language servers

## Installation

Language servers currently have to be installed manually. If you already have a language server installed through another editor (e.g. VSCode, NeoVim etc.) then you should be able to use that version aswell.

## Configuration

Configuration for language servers should be put in the user settings (`~/.absytree/settings.json`) or the workspace settings (`{workspace_dir}/.absytree/settings.json`)

Some language servers are already configured in the [app settings](../config/settings.json), so when you add you're own language server configuration make sure to use `"+lsp"` to extend the lsp configurations, unless you want to completely override the defaults.

If you want to use `clangd`, `nimlangserver`, `zls` or `rust-analyzer` and already have the binary in the PATH then you shouldn't need to configure anything (except maybe custom workspace configuration).

```json
// ~/.absytree/settings.json
{
    // `+` is used to add new lsp configurations instead of overriding all of them with just these two
    "+lsp": {

        "cpp": { // Add/override cpp settings
            "path": "clangd", // Absolute path of the language server, or just the name if it's in the PATH
            "args": [ // List of command line arguments passed to the language server
                "--offset-encoding=utf-8"
            ]
        },

        "nim": { // Add/override nim settings
            "path": "nimlangserver",
            "workspace": { // Workspace configuration. The value of this field is language server specific. This example is only valid for nimlangserver
                "project": [],
                "projectMapping": [
                    {
                        "projectFile": "test.nim",
                        "fileRegex": ".*test.nim"
                    }
                ]
            }
        }
    },

    "+editor": { // use `+` because we want to extend this section
        "+text": { // use `+` because we want to extend this section

            // If true then text documents immediately try to connect to or start a language server when opened.
            // If false then text documents will only connect to or start a language server when a command is run
            // which accesses the language server (e.g. goto-definition or goto-symbol)
            "auto-start-language-server": false, // Default: true
        }
    }
}
```

## Usage

The following LSP features are currently supported:

| Feature | Vim | VSCode | Note |
| ----------- | --- | --- | --- |
| textDocument/definition | `gd` | `<C-g><C-d>` or `<F12>` |  |
| textDocument/declaration | `gD` | `<C-g><CS-d>` |  |
| textDocument/typeDefinition | `gT` | `<C-g><CS-t>` |  |
| textDocument/implementation | `gi` | `<C-g><C-i>` |  |
| textDocument/documentSymbol | `gs` | `<C-g><C-s>` or `<CS-o>` |  |
| textDocument/references | `gr` | `<C-g><C-r>` or `<S-F12>` |  |
| textDocument/hover | `K` | `<C-g><C-k>` |  |
| textDocument/diagnostic | `H` | `<C-g><C-h>` |  |
| textDocument/switchSourceHeader | `go` | `<C-g><C-o>` | Only for C/C++ with `clangd` |
| workspace/symbol | `gw` | `<C-g><C-w>` or `<C-t>` |  |
| textDocument/inlayHints |  |  | No keybindings necessary |
| textDocument/completion |  |  | See below |

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
