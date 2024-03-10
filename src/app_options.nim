import std/options

type AppOptions* = object
  disableNimScriptPlugins*: bool
  disableWasmPlugins*: bool
  dontRestoreOptions*: bool
  dontRestoreConfig*: bool
  fileToOpen*: Option[string]
  sessionOverride*: Option[string]