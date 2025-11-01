import std/options

type AppOptions* = object
  disableNimScriptPlugins*: bool
  disableOldWasmPlugins*: bool
  disableWasmPlugins*: bool
  dontRestoreOptions*: bool
  dontRestoreConfig*: bool
  skipUserSettings*: bool
  restoreLastSession*: bool
  fileToOpen*: Option[string]
  sessionOverride*: Option[string]
  settings*: seq[string]
  earlyCommands*: seq[string]
  lateCommands*: seq[string]
  monitor*: Option[int]
  noPty*: bool
  noUI*: bool
  kittyKeyboardFlags*: string

var gAppOptions*: AppOptions = AppOptions()

proc getAppOptions*(): AppOptions =
  return ({.gcsafe.}: gAppOptions)
