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

These additional settings files are useful for having different cofiguration on different operating systems
(e.g. different paths to LSP executables)

The `keybindings*.json` files can only bind existing commands (builtin or from plugins).
To create new commands plugins have to be used.

### Overview

Settings are internally stored in stores, where each settings store consists of a json object, optionally a reference to a parent store and metadata for each setting (e.g. whether the store overrides or extends a specific setting).

Setting stores can override or extend the settings from the parent. Some stores are loaded from a file, some are only in memory.

Setting stores form a tree, with the base store at the root and indidual text editors (for individual files) as leaves.

When the application reads the value of a setting, depending on the context it reads it from either an editor store, document store, language store or the runtime store.

```
              base                                      // Base layer. Settings in here contain the default values for all compiletime known settings.
               ^
               |
    app://config/settings.json                          // Settings files loaded from different locations. They auto reload when the file on disk changes by default.
               ^
               |
    app://config/settings-windows.json
               ^
               |
    app://config/settings-windows-gui.json
               ^
               |
    home://.nev/settings.json
               ^
               |
    ws0://.nev/settings.json
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
            a.nim        b.nim        c.cpp             // Document layer. Every document has it's own settings.
               ^           ^            ^
               |           |            |-----------
               |           |            |          |
            editor1     editor2      editor3    editor4 // Editor layer. Every editor has it's own settings.
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

## Keybindings
Keybindings which just map to existing commands can be specified in a `keybindings.json` file alongside the `settings.json` files. They works the same as the settings (i.e. they also support platform/backend variants and can be placed in the app/user/workspace config directories)
```json
// ~/.nev/keybindings.json
{
    "editor": {
        "<C-q>": "quit",
    },
    "editor.text": {
        "<C-a>": "move-cursor-column 1",
        "<C-b>": {
            "command": "move-cursor-column",
            "args": [1]
        }
    }
}
```

For custom commands plugins have to be used.

## Plugins

Nev currently only supports wasm plugins. It might support other plugin mechanisms in the future (e.g. native dynamic libraries or Lua)

The editor API is exposed to plugins and can be used to create new commands, change settings, etc.

WASM plugins are loaded from `{app_dir}/config/wasm`. The wasm modules have to conform to a certain
API and can only use a subset of WASI right now, so it is recommended not to rely on WASI for now.

In theory WASM plugins can be written in any language that supports compiling to wasm, but there
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
To change the behaviour of single/double/triple clicking you can specify which command should be executed after clicking:

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

# Key bindings
You can bind different key combinations to __commands__. Each function exposed by the editor (see `plugin_api.nim`) has a corresponding command,
which has two names. If the function is called `myCommand`, then the command can be executed using either `myCommand` or `my-command`.

Key combinations are bound to a command and arguments for that command. The following binds the command `quit` to the key combination `CTRL-x + x`

```nim
addCommand "editor", "<C-x>x", "quit"
```

Key combinations can be as long as you want, and contain any combination of modifiers, as long as the OS supports that combination.
Most keys can be specified using their ASCII value, i.e. to bind to e.g. the `k` key you would use `addCommand "editor", "k", "command-name"`.
Special keys like the space bar are specified using < and >: `addCommand "editor", "<SPACE>", "command-name"`.
The following special keys are defined:
- ENTER
- ESCAPE
- BACKSPACE
- SPACE
- DELETE
- TAB
- LEFT
- RIGHT
- UP
- DOWN
- HOME
- END
- PAGE_UP
- PAGE_DOWN
- F1, ..., F12

To specify that a modifier should be held down together with another key you need to used `<XXX-YYY>`, where `XXX` is any combination of modifiers
(`S` = shift, `C` = control, `A` = alt) and `YYY` is either a single ascii character for the key, or one of the special keys (e.g. `ENTER`).

If you use a upper case ascii character as key then this automatically means it uses shift, so `A` is equivalent to `<S-a>` and `<S-A>`

Some examples:

```nim
addCommand "editor", "a", "command-name"
addCommand "editor", "<C-a>", "command-name" # CTRL+a
addCommand "editor", "<CS-a>", "command-name" # CTRL+SHIFT+a
addCommand "editor", "<CS-SPACE>", "command-name" # CTRL+SHIFT+SPACE
addCommand "editor", "SPACE<C-g>", "command-name" # SPACE, followed by CTRL+g
```

Be careful not to to this:

```nim
addCommand "editor", "a", "command-name"
addCommand "editor", "aa", "command-name" # Will never be used, because pressing a once will immediately execute the first binding
```

There is one special modifier `*` which means the following keys can be repeated without having to press the first keys again:

```nim
# after pressing "<C-w>F", you can press "+" or "-" multiple times, and the input state machine resets to the <*-F> state instead of
# to the beginning
addCommand "editor", "<C-w><*-F>-", "change-font-size", -1
addCommand "editor", "<C-w><*-F>+", "change-font-size", 1
```


All key bindings in the same scope (e.g. `editor`) will be compiled into a state machine. When you press a key, the state machine will advance,
and if it reaches and end state it will execute the command stored in the state (with the arguments also stored in the state).
Each `addCommand` corresponds to one end state.

# Scopes/Context
The first parameter to `addCommand` is a scope. Different scopes can have different key bindings, even conflicting ones.
Depending on which scopes are active the corresponding commands will be executed.
Which scopes are active depends on which editor view is selected, whether there is e.g. a auto completion window open.
The scope stack looks like this
At the bottom of the scope stack is always `editor`.
- `editor`
- `editor.<MODE>`, if the editor mode is not `""` and `editor.custom-mode-on-top` is false. `<MODE>` is the current editor mode.
- One of the following:
  - `commandLine`, if the editor is in commandLine mode

  - If there is a popup open, then the following scopes:
    - If the popup is a goto popup, then the following scopes:
      - Same as a text editor (i.e. `editor.text`, etc)
    - If the popup is a selector popup, then the following scopes:
      - Same as a text editor (i.e. `editor.text`, etc)
      - `popup.selector`, always

  - If the selected view contains a text document, then the following scopes:
    - `editor.text`, always
    - `editor.text.<MODE>`, if the text editor mode is not `""`
    - `editor.text.completion`, if the text editor has a completion window open.

  - If the selected view contains a model document, then the following scopes:
    - `editor.model`, always
    - `editor.model.<MODE>`, if the model editor mode is not `""`

- `editor.<MODE>`, if the editor mode is not `""` and `editor.custom-mode-on-top` is true. `<MODE>` is the current editor mode.

So if you for example have text editor selected and a completion window is open, and the text editor is in `insert` mode, the scope stack would look like this:

- `editor` (bottom, handled by Editor)
- `editor.text` (handled by TextEditor)
- `editor.text.insert` (handled by TextEditor)
- `editor.text.completion` (top, handled by TextEditor)

If you have no completion window open and no mode selected then it would look like this:

- `editor` (bottom, handled by Editor)
- `editor.text` (top, handled by TextEditor)

When a key is pressed, the editor will advance the state machine for every scope in the stack, from top to bottom (i.e. the `editor` scope will always be last).
The first scope which reaches an end state will execute its' command, which will be handled by the owner of the scope. Then all state machines in the stack are reset.
The owners of the scopes are the following:
- `Editor`: `editor`, `commandLine`, `editor.<MODE>`
- `TextEditor`: `editor.text`, `editor.text.<MODE>`, `editor.text.completion`
- `ModelEditor`: `editor.model`, `editor.model.<MODE>`, `editor.model.completion`
- `SelectorPopup`: `popup.selector`

# Summary
To define keybindings specific for text documents (TextEditor), use:

```nim
addCommand "editor.text", "a", "command-name"
addTextCommand "", "a", "command-name"                  # Same as above

addCommand "editor.text.insert", "a", "command-name"    # Insert mode
addTextCommand "insert", "a", "command-name"            # Same as above

addTextCommand "completion", "a", "command-name"        # Only active while completion window is open

addTextCommandBlock "", "s":                            # First parameter is mode/"completion"
  ## Creates an anonymous action which runs this block. `editor` (automatically defined) is the text editor handling this command
  editor.setMode("insert")
  editor.selections = editor.delete(editor.selections)

addTextCommand "", "a", proc(editor: TextDocumentEditor) =
  ## Creates an anonymous action which runs this lambda. `editor` is the text editor handling this command.
  # ...

proc foo(editor: TextDocumentEditor) =
  # ...

addTextCommand "", "a", foo                                 # Like above, but uses existing function
```

# Scripting API Documentation
The documentation for the scripting API is in scripting/htmldocs. You can see the current version [here](https://raw.githack.com/Nimaoth/AbsytreeDocs/main/scripting_nim/htmldocs/theindex.html) (using raw.githack.com) or [here](https://nimaoth.github.io/AbsytreeDocs/scripting_nim/htmldocs/theindex.html).

Here is an overview of the modules:
- `plugin_runtime`: Exports everything you need, so you can just include this in your script file.
- `scripting_api`: Part of the editor source, defines types used by both the editor and the script, as well as some utility functions for those types.
- `plugin_api_internal`: Ignore this. You shouldn't need to call these functions directly.
- `editor_api`: Contains general functions like changing font size, manipulating views, opening and closing files, etc.
- `editor_text_api`: Contains functions for interacting with a text editor (e.g. modifiying the content).
- `editor_model_api`: Contains functions for interacting with an model editor (e.g. modifying the content).
- `popup_selector_api`: Contains functions for interacting with a selector popup.