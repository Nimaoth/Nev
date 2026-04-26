#use layout
import misc/[custom_async]
import app_options

const currentSourcePath2 = currentSourcePath()
include module_base

when defined(appCommandServer):
  # DLL API
  proc commandServerTryAttach(options: AppOptions, processId: int) {.rtl, gcsafe, raises: [].}

  # Nice wrappers
  proc tryAttach*(options: AppOptions, processId: int) = commandServerTryAttach(options, processId)

when not defined(appCommandServer):
  static:
    echo "DONT build command server"
  proc tryAttach*(options: AppOptions, processId: int) = discard

# Implementation
when implModule and defined(appCommandServer):
  import std/[json, strformat, options]
  import misc/[custom_logger, util, myjsonutils]
  import asynctools/asyncipc
  import chronos/transports/stream
  import service, command_service, layout/layout, config_provider

  logCategory "command-server"

  proc listenForIpc(id: int) {.async.} =
    try:
      let services = getServices()
      let layout = services.getService(LayoutService).get
      let commands = services.getService(CommandService).get
      let config = services.getService(ConfigService).get

      if not config.runtime.get("ipc-server.enable", true):
        log lvlInfo, &"Don't start ipc server"
        return

      let ipcName = "nev-" & $id
      log lvlInfo, &"Listen for ipc commands through {ipcName}"
      let  ipc = createIpc(ipcName).catch:
        log lvlWarn, &"Ipc port 0 already occupied"
        return

      var inBuffer: array[1024, char]

      defer: ipc.close()

      let readHandle = open(ipcName, sideReader)
      defer: readHandle.close()

      while true:
        let c = await readHandle.readInto(cast[pointer](inBuffer[0].addr), inBuffer.len)
        # todo: handle arbitrary message size
        if c > 0:
          let message = inBuffer[0..<c].join()
          log lvlInfo, &"Run command from client: '{message}'"

          try:
            if message.startsWith("-r:") or message.startsWith("-R:"):
              log lvlDebug, commands.executeCommand(message[3..^1], false)
            elif message.startsWith("-p:"):
              let setting = message[3..^1]
              let i = setting.find("=")
              if i == -1:
                log lvlError, &"Invalid setting '{setting}', expected 'path.to.setting=value'"
                continue

              let path = setting[0..<i]
              let value = setting[(i + 1)..^1].parseJson.catch:
                log lvlError, &"Failed to parse value as json for '{setting}': {getCurrentExceptionMsg()}"
                continue

              log lvlInfo, &"Set {setting}"
              config.runtime.set(path, value)
            else:
              discard layout.openFile(message)

          except:
            log lvlError, &"Failed to run ipc command: {getCurrentExceptionMsg()}"

    except:
      log lvlError, &"Failed to open/read ipc messages: {getCurrentExceptionMsg()}"

  proc commandServerTryAttach(options: AppOptions, processId: int) =
    echo &"commandServerTryAttach {options}, {processId}"
    try:
      if processId == 0:
        # todo: find process by name
        # return
        discard

      let ipcName = "nev-" & $processId
      let writeHandle = open(ipcName, sideWriter).catch:
        if processId == 0:
          echo &"No existing editor, open new"
          return
        else:
          echo &"No existing editor with process id {processId}"
          quit(0)

      echo "opened ipc"
      defer: writeHandle.close()

      proc send(msg: string) =
        echo "Send ", msg
        waitFor writeHandle.write(cast[pointer](msg[0].addr), msg.len)

      # todo: instead of sending -p:... etc, translate the settings to set-option command syntax,
      # pass the commands through as is and traslate fileToOpen to corresponding command.
      for setting in options.settings:
        send("-p:" & setting)

      for command in options.earlyCommands:
        send("-r:" & command)

      for command in options.lateCommands:
        send("-R:" & command)

      if options.fileToOpen.getSome(file):
        send(file)

      quit(0)

    except CatchableError as e:
      echo &"Failed to attach to existing nev instance: {e.msg}"

  proc processClient(server: StreamServer, transp: StreamTransport) {.async: (raises: []).} =
    try:
      log lvlInfo, &"[server] Client connected to collaborative editing session {transp.remoteAddress}"

      let services: Services = ({.gcsafe.}: getServices())
      let commands = services.getService(CommandService).get

      var reader = newAsyncStreamReader(transp)

      while not server.closed:
        debugf"[server] readLine"
        let line = await reader.readLine(sep = "\n")
        if line.len == 0:
          break

        debugf"[server] readLine -> '{line}'"
        log lvlDebug, commands.executeCommand(line, false)

      log lvlInfo, &"[command-server] Client disconnected"
    except:
      log lvlError, &"[command-server] Failed to read data from connection: {getCurrentExceptionMsg()}"

  proc listenForConnection(port: int) {.async.} =
    var server: StreamServer

    try:
      server = createStreamServer(initTAddress("127.0.0.1:" & $port), processClient, {ReuseAddr})
      server.start()
      let localAddress = server.localAddress()
      log lvlInfo, &"[command-server] Listen for connections on port {localAddress}"
    except:
      log lvlError, &"[command-server] Failed to create server on port {port.int}: {getCurrentExceptionMsg()}"
      return

  proc init_module_command_server*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_command_server: no services found"
      return

    let config = services.getService(ConfigService).getOr:
      return

    asyncSpawn listenForIpc(0)
    asyncSpawn listenForIpc(os.getCurrentProcessId())

    if config.runtime.get("command-server.port", int.none).getSome(port):
      asyncSpawn listenForConnection(port)
