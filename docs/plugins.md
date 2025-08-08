# Plugins

This describes the new plugin system. For documentation about the old system [go here](./configuration.md#Plugins)

Nev uses wasm for plugins. In theory any language can be used but an auto generated plugin api is only provided for Nim.

Nim is compiled to wasm using Emscripten.

## Installing plugins

Plugins are loaded from `app://plugins` (builtin plugins) and `home://.nev/plugins` (user plugins). You should install plugins into `home://.nev/plugins`.

## Plugin structure

Each plugin consists of at least a `manifest.json` and a wasm binary.

Here is an example of a manifest:

```json
{
    "name": "My plugin",
    "version": "0.0.1",
    "authors": ["Your name"],
    "repository": "https://github.com/abc/xyz",
    "wasm": "plugin.m.wasm",  // You can also use .wat files (wasm in text format)
    "autoLoad": false,        // Set to true to load the plugin automatically when opening the editor
    "commands": {             // Declare which commands are exported by the
        "test-command-1": {},
        "test-command-2": {
            "parameters": [{"name": "a", "type": "string"}],
            "returnType": "string",
            "description": "Does something",
        }
    },
    "permissions": {          // Default permissions. Can be overriden
        "filesystem": {
            "disallowAll": false,
            "allow": ["ws0://"],
        },
        "commands": {
            "allowAll": true,
        },
    }
}
```

## Override plugin permissions

To override the permissions for a plugin you need so set the `plugin.<plugin-id>.permissions` setting.
The `plugin-id` is the name of the folder which contains the plugin manifest.

```json
// In e.g. home://.nev/settings.json
// Override permissions for home://.nev/plugins/my_plugin/manifest.json
{
    "plugin.my_plugin.permissions": {
        "filesystem": {
            "allow": ["ws0://src"],
        },
        "commands": {
            "allowAll": false,
        },
    }
}
