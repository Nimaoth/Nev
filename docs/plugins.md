# Plugins

This describes the new plugin system. For documentation about the old system [go here](./configuration.md#Plugins)

Nev uses wasm for plugins. In theory any language can be used but an auto generated plugin api is only provided for Nim.

Nim is compiled to wasm using Emscripten.

## Installing plugins

Plugins are loaded from `app://plugins` (builtin plugins) and `home://.nev/plugins` (user plugins). You should install plugins into `home://.nev/plugins`.

## Plugin API versions

Nev can support multiple versions of the plugin API. For now only two versions will be supported:
- `v0` - The most recent version of the API on the main branch. This can have regular braking changes.
- `v1` - The stable version of the API. This version gets updated to match `v0` before each new release, but then stays stable until the next release.

Once the new plugin API has stabalized somewhat we will probably switch to another model:
- `v0` - The same as before.
- `v1`, `v2`, `v3` ... - The stable version of the API. If the current stable version is `v3` and a new version of Nev gets released, the current state of `v0` is copied and becomes the new stable version `v4`. New developement continues on `v0`, with only bug fixes being applied to stable versions.

In this new model Nev will support some amount of older versions (probably around two or three, depending on how much effort it is to keep supporting them).
Support for older versions might also be dropped when builtin features get changed enough where supporting the old API would be too much work.

The main goal with supporting multiple versions is not backwards compatibility forever, but to provide more time before plugins
have to be updated when the plugin API changes.

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
