#use terminal log:MemChannels

const currentSourcePath2 = currentSourcePath()
include module_base

# Implementation
when implModule:
  import std/[tables]
  import nimsumtree/[arc]
  import misc/[util, custom_async]
  import dynamic_view, terminal/terminal, service, layout
  from scripting_api import CreateTerminalOptions
  import channel
  import log

  type
    LogChannels = ref object
      channels: Table[string, View]

  proc createTerminal(self: LogChannels, name: string, stdin: Arc[BaseChannel], stdout: Arc[BaseChannel]) =
    let terminals = getService(TerminalService)
    let layout = getService(LayoutService)
    if terminals.isSome and layout.isSome:
      let options = CreateTerminalOptions()
      let view = terminals.get.createTerminalView(stdin, stdout, options)
      layout.get.registerView(view, last = false)
      layout.get.addView(view, slot = "#small-left", focus = false)
      self.channels[name] = view

  proc handleNewChannelsMain(self: LogChannels) {.async.} =
    while true:
      try:
        await sleepAsync(500.milliseconds)
      except CatchableError:
        discard

      try:
        let channels = getMemChannels()
        for c in channels:
          if c.name notin self.channels:
            self.createTerminal(c.name, c.stdin, c.stdout)
      except CatchableError:
        discard

  proc init_module_log_terminal*() {.cdecl, exportc, dynlib.} =
    let channels = LogChannels()
    # asyncSpawn handleNewChannelsMain(channels)
