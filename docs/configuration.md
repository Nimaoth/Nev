# Configuration/Settings and plugins

Configuration is split up into two main parts:

- JSON files containing settings
- WASM plugins

## Settings

The json config files contain simple values like `ui.background.transparent` as well as more complex things
like debugger launch configurations and LSP settings.

Settings can be specified in multiple places. The final settings are computed by loading the following files
in order:

- `{app_dir}/config/settings.json` and `{app_dir}/config/keybindings.json`, where `{app_dir}` is the directory
  where the editor is installed.
- `~/.absytree/settings.json` and `~/.absytree/keybindings.json`, where `~` is the users home directory.
- `{workspace_dir}/config/settings.json` and `{workspace_dir}/config/keybindings.json`, where `{workspace_dir}`
  is the primary directory of the workspace.

Additionally to the `settings.json` and `keybindings.json` files, the editor also tries to load the following files from each of the directories:

- `settings-{platform}.json`
- `settings-{backend}.json`
- `settings-{platform}-{backend}.json`

`{platform}` is one of (`windows`, `linux`, `wasm`, `js`, `other`) and `{backend}` is one of (`gui`, `terminal`, `browser`)

These additional settings files are useful for having different cofiguration on different operating systems
(e.g. different paths to LSP executables)

As these config files just specify plain values and can't contain any logic, more complex configuration has
to be done using WASM or Nimscript plugins.

### How to override/extend configuration

Each configuration file is applied on top of the previous one.
The following example shows how to override and extend values.
Prefixing a property name with `+` will cause the json object/array value of that property to be
extended, without the `+` the property will be overriden. Number, bool and string properties are always overriden.
```json
// ~/.absytree/settings.json
{
    "editor": {
        "text": {
            "lsp": {
                "cpp": {
                    "path": "clangd"
                }
            }
        }
    },
    "ui": {
        "background": {
            "transparent": false
        }
    }
}

// ~/.absytree/settings-terminal.json
{
    "ui": {
        "background": {
            "transparent": true
        }
    }
}

// {workspace_dir}/.absytree/settings-windows.json
{
    "+editor": {
        "+text": {
            "+lsp": {
                "rust": {
                    "path": "rust-analyzer.exe"
                }
            }
        }
    }
}

// Final settings when run on windows in the terminal
{
    "editor": {
        "text": {
            "lsp": {
                "cpp": {
                    "path": "clangd"
                },
                "rust": {
                    "path": "rust-analyzer.exe"
                }
            }
        }
    },
    "ui": {
        "background": {
            "transparent": true
        }
    }
}

// Final settings when run on windows in the gui version
{
    "editor": {
        "text": {
            "lsp": {
                "cpp": {
                    "path": "clangd"
                },
                "rust": {
                    "path": "rust-analyzer.exe"
                }
            }
        }
    },
    "ui": {
        "background": {
            "transparent": false
        }
    }
}

```

Currently there is no complete list of settings yet.

## Plugins

WASM plugins are loaded from `{app_dir}/config/wasm`. The wasm modules have to conform to a certain
API and can only use a subset of WASI right now, so it is recommended not to rely on WASI for now.

In theory WASM plugins can be written in any language that supports compiling to wasm, but there
are currently no C header files for the editor API, so for now the recommended way
to write plugins is to use Nim and Emscripten.

At the moment `config/absytree_config_wasm.wasm` is generated from `config/absytree_config.nim` by compiling it to wasm using `config/config.nims` (uses Emscripten). So `absytree_config.nim` can be used as NimScript or as a wasm plugin.

The editor API is exactly the same in both cases.

Inside `absytree_config.nim` one can check if it's being used in wasm or NimScript using the following check:

    when defined(wasm):
      # Script was compiled to wasm
    else:
      # Script is being interpreted as NimScript

`absytree_config.nim` must import `absytree_runtime`, which contains some utility functions. `absytree_runtime` also exports `absytree_api`,
which contains every function exposed by the editor. `absytree_api` is automatically generated when compiling the editor.

There are a few utility scripts for defining key bindings.
- `import keybindings_normal`: Standard keybindings, like most text editors. (e.g. no modes)
- `import keybindings_vim`: [Vim](https://github.com/neovim/neovim) inspired keybindings, work in progress. Will probably never be 100% compatible.
- `import keybindings_helix`: [Helix](https://github.com/helix-editor/helix) inspired keybindings, work in progress. Will probably never be 100% compatible.

Each of these files defines a `load*Bindings()` function which applies the corresponding key bindings. After calling this function one can still override specific keys.

Here is an example of a basic plugin:

```nim
# This needs to imported to access the editor API.
# It can be imported in any file that's part of the plugin, not just the main file like `absytree_runtime_impl`
import absytree_runtime

# You can import the Nim std lib and other libraries, as long as what you import can be compiled to wasm
# and doesn't rely on currently unsupported WASI APIs.
import std/[strutils, unicode]

proc postInitialize*(): bool {.wasmexport.} =
  # Called after all top level code has been executed
  return true

# Check if you're running the terminal/gui/browser with `getBackend()`
if getBackend() == Terminal:
  # Disable animations in terminal because they don't look great
  changeAnimationSpeed 10000

# Change settings with setOption
setOption "editor.text.triple-click-command", "extend-select-move"

# Get settings with getOption
let transparent = getOption[bool]("ui.background.transparent")
infof"transparent: {transparent}"

# Expose functions as commands using the `expose` pragma, so they can be called from other plugins
# or bound to keys
proc customCommand1(arg1: string, arg2: int) {.expose("custom-command-1").} =
  infof"customCommand1: {arg1}, {arg2}"

proc customCommand2(editor: TextDocumentEditor, arg1: string, arg2: int) {.expose("custom-command-2").} =
  infof"customCommand2: {editor}, {arg1}, {arg2}"

# Create keybindings
addCommand "editor", "<C-a>", "custom-command-1", "hello", 13
addCommand "editor.text", "<C-b>", "custom-command-2", "world", 42
addTextCommand "", "<C-c>", "copy" # addTextCommand "xyz" is equivalent to addCommand "editor.text.xyz"

# These handle* functions will be removed in the future. They have to be declared, but don't use them.
# To create custom commands see the function with {.expose.} below
proc handleAction*(action: string, args: JsonNode): bool {.wasmexport.} = return false
proc handlePopupAction*(popup: EditorId, action: string, args: JsonNode): bool {.wasmexport.} = return false
proc handleDocumentEditorAction*(id: EditorId, action: string, args: JsonNode): bool {.wasmexport.} = return false
proc handleTextEditorAction*(editor: TextDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} = return false
proc handleModelEditorAction*(editor: ModelDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} = return false

# This is required for the main file of the plugin. If you use NimScript this is not required.
when defined(wasm):
  include absytree_runtime_impl
```