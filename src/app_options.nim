import std/options

type AppOptions* = object
  disableNimScriptPlugins*: bool
  disableWasmPlugins*: bool
  dontRestoreOptions*: bool
  dontRestoreConfig*: bool
  restoreLastSession*: bool
  fileToOpen*: Option[string]
  sessionOverride*: Option[string]
  settings*: seq[string]
  earlyCommands*: seq[string]
  lateCommands*: seq[string]
