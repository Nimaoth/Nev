# Nev Internals

This describes how Nev works under the hood, and is mainly useful for contributors

# Basic overview

- Compilation and execution starts in [desktop_main.nim](../src/desktop_main.nim), which:
  - Reads command line args
  - Creates the `Platform` (either `GuiPlatform` or `TerminalPlatform`)
  - Starts `services`
  - Creates the `App`
  - Initializes `App`
  - Runs the main loop to handle OS events, poll the async runtime and render using the `Platform`

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

## Modules

Modules allow parts of the editor to be compiled as separate DLLs. This is primarily used for **development speed** -- the CI build is statically linked. Modules can only interact with exposed APIs (with the `apprtl` pragma).

### Architecture

Modules live in the `modules/` directory and can be either:
- **Single-file modules**: e.g. `stats.nim`, `dashboard.nim`
- **Multi-file modules**: a directory with a main file matching the directory name, e.g. `terminal/terminal.nim`

Modules fall into two categories:
- **Core modules**: depended on by the core (`src/`). E.g. `stats` and `terminal`.
- **Extra modules**: the core does not depend on them, but they depend on the core. Examples: `dashboard`, `vcs_git`, `language_server_lsp`, `terminal`, `debugger`, etc.

```
                    (((core) core_modules) extra_modules)

    core (src/) ──depends on──> stats, terminal
          │
          └── loaded via ──> module_imports.nim (static) OR native_plugins/*.dll (dynlib)
                                    │
                                    ├── extra_modules (core doesn't depend on these)
                                    │   ├── dashboard
                                    │   ├── vcs_git, vcs_perforce
                                    │   ├── language_server_lsp, language_server_ctags, ...
                                    │   ├── debugger
                                    │   └── ...
                                    │
                                    └── core_modules (core depends on these)
                                        ├── stats
                                        ├── command_component, hover_component, ...
                                        └── terminal
```

### How Modules Work

The key mechanism is `module_base.nim`, which sets up the `implModule` compile-time constant and the `rtl` pragma:

- When **not** compiled with `-d:useDynlib`: everything is statically linked, `implModule` is always true
- When compiled with `-d:useDynlib`: `implModule` is true only for the module being built as a DLL (matched via `-d:nevModuleName=<name>`)

Dependencies between modules are declared via `#use` comments at the top of the main `.nim` file:
```nim
#use stats
```

### Creating a Module

A minimal module requires:

1. **Include `module_base`** with the `currentSourcePath2` setup
2. **Declare the public API** (types, procs) outside the `implModule` block
3. **Mark exported procs** with the `rtl` pragma
4. **Provide an `init_module_<name>` proc** for initialization
5. **Put implementation** inside `when implModule:`

```nim
# modules/my_module.nim
import service

const currentSourcePath2 = currentSourcePath()
include module_base

type
  MyService* = ref object of DynamicService
    value*: int

func serviceName*(_: typedesc[MyService]): string = "MyService"

# DLL API -- visible to both static and dynlib builds. Make sure name is unique.
{.push rtl, gcsafe, raises: [].}
proc myServiceGetValue(self: MyService): int
{.pop.}

# Wrapper
{.push inline.}
proc getValue*(self: MyService): int = self.myServiceGetValue()
{.pop.}

# Implementation -- only compiled once
when implModule:
  import misc/custom_logger

  logCategory "my-module"

  proc myServiceGetValue(self: MyService): int =
    self.value

  # Required: init function called when the module is loaded
  proc init_module_my_module*() {.cdecl, exportc, dynlib.} =
    log lvlInfo, "Initializing my_module"
    let services = getServices()
    if services == nil:
      return
    services.addService(MyService())

  # Optional: shutdown function called when the editor exits
  proc shutdown_module_my_module*() {.cdecl, exportc, dynlib.} =
    log lvlInfo, "Shutting down my_module"
```

### Building Modules

**Static (default, used by CI):**
All modules are compiled into the main binary. The `build.nim` script generates `src/module_imports.nim` which imports all modules and provides `initModules()` / `shutdownModules()` procs.

**Dynamic (development):**
Run `nim c build.nim && nim c -r build.nim` to build dirty modules as DLLs into `native_plugins/`. Use `-f` to force rebuild, `-s` for single-threaded, `-r` for release mode.

### Module Loading

In `desktop_main.nim`, modules are loaded after services are initialized:

- **Static**: `import module_imports; initModules()` -- calls each module's init function
- **Dynamic**: Walks `native_plugins/` directory, loads each `.dll` with `loadLib()`, resolves and calls `init_module_<name>` by symbol lookup

On shutdown, `shutdown_module_<name>` is called for each loaded module (or `shutdownModules()` for static builds).

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

