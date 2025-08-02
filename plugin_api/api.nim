import std/macros

const pluginApiVersion* {.intdefine.}: int = 0

macro includePluginApi*(version: static int) =
  let dir = ident("v" & $version)
  return quote do:
    include `dir`/api

static:
  hint("Using plugin api version " & $pluginApiVersion)
includePluginApi(pluginApiVersion)
