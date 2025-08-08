# Nev Internals

This describes how Nev works under the hood, and is mainly useful for contributors

# Basic overview

- Compilation and execution starts in [desktop_main.nim](../src/desktop_main.nim), which:
  - Reads command line args
  - Creates the `Platform` (either `GuiPlatform` or `TerminalPlatform`)
  - Starts `services`
  - Creates the `App`
  - Initializes `App`

- App is the central hub which connects everything. There is a bunch of stuff in there which should be moved out over time (e.g. most commands defined in app.nim)

- Services are used to separate features so that not everything has to import `app`
  - Services can use each other, but cyclic dependencies should be avoided because Nim doesn't support that very well
  - Services are currently only usable on the main thread
  - Services are singletons, so only one service of each type exists
  - The `Services` type stores all services and allows access to any service

- The `Document` type represents a document (not necessarily text) which is usually backed by a file on disk.
- `TextDocument` is a subtype of `Document` and represents a text document.
  - It stores the file content (`Buffer`, a CRDT using a Rope)
  - It stores which language servers are connected
- `Editor` is the abstract base type for editors
- `TextDocumentEditor` is an `Editor` for a text document
  - Multiple editors can edit the same document
  - Stores things like scroll offset, selections, etc
  - Provides a bunch of commands for editing and using the text editor in general

```

                                    App
                                     |
                   ---------------- uses -------------
                   |                 |               |
                   v                 v               v
     Services: LayoutService, CommandService, PluginService, ...


                  Editor                     Document
                    ^                           ^
                    |                           |----------------------
                    |                           |                     |
         TextDocumentEditor ---- edits ---> TextDocument         (ModelDocument, but this is not working right now)


  The layout tree contains Views:     View
                                        ^
                                        |
                     --------------------------------------------------------------------...
                     |                  |                      |                 |
                EditorView          TerminalView          DebuggerView         Layout
    (contains TextDocumentEditor)  (draws a terminal)                            ^
                                                                                 |
                                                           --------------------------------------------...
                                                           |                    |              |
                 each of these contains views --->   HorizontalLayout     VerticalLayout    TabLayout



                      Platform
                         ^
                         |
               --------------------
               |                  |
          GuiPlatform       TerminalPlatform

```

## Plugins

Important terms: `Host` refers to the editor (native code), `guest` or `plugin` refers to the wasm side

Important files and types:
- [plugin_service.nim](../src/plugin_service.nim)
  - `PluginService`: `Service` which handles loading of plugin manifests, deciding which plugins to load and when
  - `PluginManifest`: Plain data containing some meta data about the plugin.
  - `PluginSystem`: Base type for the plugin system (at the moment only wasm)
- [plugin_system_wasm.nim](../src/plugin_system_wasm.nim)
  - `PluginSystemWasm`: `PluginSystem` subtype which handles wasm engine setup and manages multiple versions of the plugin api
- [plugin_api_base.nim](../src/plugin_api/plugin_api_base.nim)
  - `PluginApiBase`: Base type for a version of the plugin api
- [plugin_api.nim](../src/plugin_api/plugin_api.nim), [plugin_api_1.nim](../src/plugin_api/plugin_api_1.nim) etc
  - `PluginApi`: `PluginApiBase` subtype which implements a specific version of the plugin api and handles instantiation of wasm modules
- [src/generated/plugin_api_host.nim](../src/generated/plugin_api_host.nim), [src/generated/plugin_api_host_1.nim](../src/generated/plugin_api_host_1.nim)
  - Generated files based on [wit/v0/api.wit](../wit/v0/api.wit) and [wit/v1/api.wit](../wit/v1/api.wit)
  - These contain bindings for the host side
- [plugin_api/v0/api.nim](../plugin_api/v0/api.nim), [plugin_api/v1/api.nim](../plugin_api/v1/api.nim)
  - This is what you import in the plugin
  - Includes generated bindings for the plugin API using `nimwasmtime` and the API defined in the `.wit` file
  - Also adds some nicer wrappers around some APIs
- [plugin_api/v0/plugin_api_guest.nim](../plugin_api/v0/plugin_api_guest.nim) and the files it imports:
  - Generated files based on [wit/v0/api.wit](../wit/v0/api.wit) and [wit/v1/api.wit](../wit/v1/api.wit)
  - These contain bindings for the guest side

