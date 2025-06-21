# Configuration and plugins

- Configuration for [language servers](lsp.md#configuration)
- Configuration for [Treesitter](treesitter.md#configuration)

## Settings

[List of (most) settings](settings.gen.md)

Settings are specified using JSON files.
These files contain simple values like `ui.background.transparent` as well as more complex things
like debugger launch configurations and LSP settings.

Settings and basic keybindings can be specified in multiple places:
- `{app_dir}/config/settings.json` and `{app_dir}/config/keybindings.json`, where `{app_dir}` is the directory
  where the editor is installed.
- `~/.nev/settings.json` and `~/.nev/keybindings.json`, where `~` is the users home directory.
- `{workspace_dir}/.nev/settings.json` and `{workspace_dir}/.nev/keybindings.json`, where `{workspace_dir}`
  is the primary directory of the workspace.

Additionally to the `settings.json` and `keybindings.json` files, the editor also tries to load the following files from each of the directories:

- `settings-{platform}.json`
- `settings-{backend}.json`
- `settings-{platform}-{backend}.json`

`{platform}` is one of (`windows`, `linux`, `other`) and `{backend}` is one of (`gui`, `terminal`, `browser`)

These additional settings files are useful for having different configuration on different operating systems
(e.g. different paths to LSP executables)

The `keybindings*.json` files can only bind existing commands (builtin or from plugins).
To create new commands plugins have to be used.

### Overview

Settings are internally stored in stores, where each settings store consists of a JSON object, optionally a reference to a parent store and metadata for each setting (e.g. whether the store overrides or extends a specific setting).

Setting stores can override or extend the settings from the parent. Some stores are loaded from a file, some are only in memory.

Setting stores form a tree, with the base store at the root and individual text editors (for individual files) as leaves.

When the application reads the value of a setting, depending on the context it reads it from either an editor store, document store, language store or the runtime store.

```
              base                                      // Base layer. Settings in here contain the default values for all compiletime known settings.
               ^
               |
    app://config/settings.json                          // Settings files loaded from different locations. They auto reload when the file on disk changes by default.
               ^
               |
    app://config/settings-windows.json                  // Platform specific settings, if they exist.
               ^
               |
    app://config/settings-windows-gui.json
               ^
               |
    home://.nev/settings.json                           // User settings.
               ^
               |
    ws0://.nev/settings.json                            // Workspace settings.
               ^
               |
            runtime                                     // Runtime layer. Not backed by a file, by default changing settings at runtime changes them in here.
               ^
               |-------------------------
               |                        |
              nim                      c++              // Language layer. One settings store per language.
               ^                        ^
               |------------            |
               |           |            |
            a.nim        b.nim        c.cpp             // Document layer. Every document has it's own settings store.
               ^           ^            ^
               |           |            |-----------
               |           |            |          |
            editor1     editor2      editor3    editor4 // Editor layer. Every editor has it's own settings store.
```

### Changing settings
There are a few places where you can change settings:
- `home://.nev/settings.json`: Put settings in here if you want to set something globally (for your user). These settings will always be loaded when you open Nev.
- `{workspace_dir}/.nev/settings.json`: Put settings in here if you only want to change them for a specific project.
- `browse-settings`: This command can be used to change settings in any store, but it defaults to the runtime store. Use this if you want to change settings temporarily, figure out where a setting is overridden [and more](finders.md#browse-settings)
- `set-option`, `set-flag`, `toggle-flag`: These commands can be used to change settings in the runtime store. Use this for temporarily changing settings, or from plugins.

### Config files

When specifying settings in config files there are three ways to set the value of a setting `a.b`:

```json
{
    "a.b": "value"
}
```
or
```json
{
    "+a": {
        "b": "value"
    }
}
```
or
```json
{
    "a": {
        "b": "value"
    }
}
```

The first two are equivalent and extend the object `a` and set/override the key `b` within `a`.

The third variant overrides the entire object `a` with a new one containing only the key `b`.

When a config file is loaded all keys containing a period will be expanded to the full object form.
To escape the period simply use two periods (`..`).

### Changing settings per language

Some settings can be overridden per language. The exact list of settings is not documented (as it depends on how it's used in the editor),
but if in doubt just try overriding it.

To change a setting for e.g. Nim, prefix the setting name with `lang.nim`. So let's say you want to disable line wrapping only for Nim files.
The setting for line wrapping is `text.wrap-lines`. So to change it for Nim, just use:

```json
"lang.nim.text.wrap-lines": false
```

Language specific settings are applied in the language layer (between the runtime and document layer),
so a language settings store for e.g. `nim` behaves as if any setting in `lang.nim` was placed at the root of the language store.

## Keybindings

Keybindings which just map to existing commands can be specified in a `keybindings.json` file alongside the `settings.json` files. They works the same as the settings (i.e. they also support platform/backend variants and can be placed in the app/user/workspace config directories)

For more details [go here](./keybindings.md)

## Plugins

Nev currently only supports WASM plugins. It might support other plugin mechanisms in the future (e.g. native dynamic libraries or Lua)

The editor API is exposed to plugins and can be used to create new commands, change settings, etc.

WASM plugins are loaded from `{app_dir}/config/wasm`. The WASM modules have to conform to a certain
API and can only use a subset of WASI right now, so it is recommended not to rely on WASI for now.

In theory WASM plugins can be written in any language that supports compiling to WASM, but there
are currently no C header files for the editor API, so for now the recommended way
to write plugins is to use Nim and Emscripten.

Here is an example of a basic plugin:

```nim
# This needs to imported to access the editor API.
import plugin_runtime

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

proc customCommand2(editor: TextDocumentEditor, arg1: string, arg2: int) {.exposeActive("editor.text", "custom-command-2").} =
  infof"customCommand2: {editor}, {arg1}, {arg2}"

# Create keybindings
addCommand "editor", "<C-a>", "custom-command-1", "hello", 13
addCommand "editor.text", "<C-b>", "custom-command-2", "world", 42
addTextCommand "", "<C-c>", "copy" # addTextCommand "xyz" is equivalent to addCommand "editor.text.xyz"

# This is required for the main file of the plugin.
include plugin_runtime_impl
```

# Settings
The settings which are loaded from the `settings.json` files can be changed at runtime using `proc setOption*[T](path: string, value: T)` or `proc setOption*(option: string; value: JsonNode)`.

You can get the current value of a setting with `proc getOption*[T](path: string, default: T = T.default): T`

```nim
  setOption "lsp.zig.path", "zls"
  echo getOption[string]("lsp.zig.path") # zls
```

# Mouse settings
To change the behavior of single/double/triple clicking you can specify which command should be executed after clicking:

```nim
# To make triple click select the entire line (this is the default behaviour), use e.g. the command 'extend-select-move "line" true':
# extend-select-move applies the given move to the beginning and end of the current selection and then combines the results
# into a new selection.
setOption "editor.text.triple-click-command", "extend-select-move"
setOption "editor.text.triple-click-command-args", %[%"line", %true]

# To make triple click select a paragraph (as defined by vim), use e.g. the command 'extend-select-move "vim-paragraph-inner" true':
setOption "editor.text.triple-click-command", "extend-select-move"
setOption "editor.text.triple-click-command-args", %[%"vim-paragraph-inner", %true]

# Single and double click can also be overriden using "single-click-command"/"single-click-command-args"
# and "double-click-command"/"double-click-command-args"
```

# Scripting API Documentation
The documentation for the scripting API is in scripting/htmldocs. You can see the current version [here](https://raw.githack.com/Nimaoth/AbsytreeDocs/main/scripting_nim/htmldocs/theindex.html) (using raw.githack.com) or [here](https://nimaoth.github.io/AbsytreeDocs/scripting_nim/htmldocs/theindex.html).

Here is an overview of the modules:
- `plugin_runtime`: Exports everything you need, so you can just include this in your script file.
- `scripting_api`: Part of the editor source, defines types used by both the editor and the script, as well as some utility functions for those types.
- `plugin_api_internal`: Ignore this. You shouldn't need to call these functions directly.
- `editor_api`: Contains general functions like changing font size, manipulating views, opening, and closing files, etc.
- `editor_text_api`: Contains functions for interacting with a text editor (e.g. modifying the content).
- `editor_model_api`: Contains functions for interacting with a model editor (e.g. modifying the content).
- `popup_selector_api`: Contains functions for interacting with a selector popup.
