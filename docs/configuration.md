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
