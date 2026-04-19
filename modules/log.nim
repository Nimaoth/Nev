#use terminal
const currentSourcePath2 = currentSourcePath()
include module_base

type
  LogLevel* = enum
    lvlDebug
    lvlInfo
    lvlWarn
    lvlError

  LogChannelObj* = object of RootObj
  LogChannel* = ptr LogChannelObj
  LogCategory* = distinct int

  LogChannelFlag* = enum LogColor, LogStdout, LogStderr, LogFile, LogInMemory

# DLL API
{.push rtl, gcsafe, raises: [].}
proc logImpl(channel: LogChannel, level: LogLevel, category: LogCategory, message: string)
proc logAddCategory(name: string): LogCategory
proc logAddChannel(name: string, flags: set[LogChannelFlag]): LogChannel
{.pop.}

when defined(featMemChannels):
  static:
    echo "with feature featMemChannels"
  import nimsumtree/[arc]
  import channel

  {.push rtl, gcsafe, raises: [].}
  proc getMemChannels*(): seq[tuple[name: string, stdin: Arc[BaseChannel], stdout: Arc[BaseChannel]]]
  {.pop.}

# Nice wrappers
proc newLogChannel*(name: string, flags: set[LogChannelFlag] = {LogColor, LogStderr, LogInMemory}): LogChannel =
  logAddChannel(name, flags)

template log*(level: LogLevel, channel: LogChannel, category: LogCategory, message: string) =
  logImpl(level, channel, category, message)

template logCategory*(name: string) =
  let category = logAddCategory(name)

  template log(level: LogLevel, message: string) =
    logImpl(defaultChannel, level, category, message)

  template log(channel: LogChannel, level: LogLevel, message: string) =
    logImpl(channel, level, category, message)

template logCategory2*(name: string) =
  let category = logAddCategory(name)

  template log2(level: LogLevel, message: string) =
    logImpl(defaultChannel, level, category, message)

  template log(channel: LogChannel, level: LogLevel, message: string) =
    logImpl(channel, level, category, message)

# Implementation
when implModule:
  import std/[atomics, strformat, typedthreads, terminal, colors, locks]
  import nimsumtree/[arc]
  import misc/[util, custom_async]
  import channel

  type
    LogDrainThreadMessageKind = enum
      AddCategory
      AddChannel

    LogDrainThreadMessage = object
      case kind: LogDrainThreadMessageKind
      of AddCategory:
        id: int
        name: string
      of AddChannel:
        channel: LogChannelImpl

    LogMessage = object
      level: LogLevel
      category: LogCategory
      message: string

    LogChannelObjImpl* = object of LogChannelObj
      name: string
      channel: Channel[LogMessage]
      file: File
      stdin: Arc[BaseChannel]
      stdout: Arc[BaseChannel]
      createdTerminal: bool = false
      flags: set[LogChannelFlag]
      flushThreshold: LogLevel = lvlDebug

    LogChannelImpl = ptr LogChannelObjImpl

  var categoryCounter: Atomic[int]
  categoryCounter.store(0)

  var logDrainThreadChannel: Channel[LogDrainThreadMessage]
  logDrainThreadChannel.open()
  var logDrainThread: Thread[int]

  var categories: seq[string] = @[]
  var channels: seq[LogChannelImpl] = @[]
  var channelsLock: Lock
  channelsLock.initLock()

  proc logImpl(channel: LogChannel, level: LogLevel, category: LogCategory, message: string) =
    let channel = cast[ptr LogChannelObjImpl](channel)
    channel.channel.send(LogMessage(level: level, category: category, message: message))

  proc logAddCategory(name: string): LogCategory =
    let category = categoryCounter.fetchAdd(1)
    logDrainThreadChannel.send(LogDrainThreadMessage(kind: AddCategory, id: category, name: name))
    return category.LogCategory

  proc logAddChannel(name: string, flags: set[LogChannelFlag]): LogChannel =
    let channel = create(LogChannelObjImpl)
    channel[] = LogChannelObjImpl(
      name: name,
      flags: flags,
      stdout: newInMemoryChannel(),
      stdin: newInMemoryChannel(),
    )
    channel.channel.open()

    if LogFile in flags:
      try:
        createDir(getAppDir() / "logs")
        let logFileName = getAppDir() / &"/logs/{name}.log"
        channel.file = open(logFileName, fmWrite)
      except OSError, IOError:
        channel.flags.excl LogFile

    logDrainThreadChannel.send(LogDrainThreadMessage(kind: AddChannel, channel: channel))
    return cast[LogChannel](channel)

  proc logConsole(channel: LogChannelImpl, level: LogLevel, category: string, message: string) =
    let color = case level
    of lvlDebug: rgb(100, 100, 200)
    of lvlInfo: rgb(200, 200, 200)
    of lvlWarn: rgb(200, 200, 100)
    of lvlError: rgb(255, 150, 150)
    let levelStr = case level
    of lvlDebug: "DEB"
    of lvlInfo: "INF"
    of lvlWarn: "WRN"
    of lvlError: "ERR"
    try:
      {.gcsafe.}:
        if LogStdout in channel.flags:
          if LogColor in channel.flags:
            stdout.write(ansiForegroundColorCode(color))
          stdout.write("[")
          stdout.write(levelStr)
          stdout.write("] [")
          stdout.write(category)
          stdout.write("] ")
          stdout.write(message)
          stdout.write("\n")
          if LogColor in channel.flags:
            stdout.write(ansiForegroundColorCode(rgb(255, 255, 255)))

        if LogStderr in channel.flags:
          if LogColor in channel.flags:
            stderr.write(ansiForegroundColorCode(color))
          stderr.write("[")
          stderr.write(levelStr)
          stderr.write("] [")
          stderr.write(category)
          stderr.write("] ")
          stderr.write(message)
          stderr.write("\n")
          if LogColor in channel.flags:
            stderr.write(ansiForegroundColorCode(rgb(255, 255, 255)))

        if LogFile in channel.flags:
          channel.file.write("[")
          channel.file.write(levelStr)
          channel.file.write("] [")
          channel.file.write(category)
          channel.file.write("] ")
          channel.file.write(message)
          channel.file.write("\n")
          if level >= channel.flushThreshold: flushFile(channel.file)

        if LogInMemory in channel.flags:
          if LogColor in channel.flags:
            channel.stdout.write(ansiForegroundColorCode(color))
          channel.stdout.write("[")
          channel.stdout.write(levelStr)
          channel.stdout.write("] [")
          channel.stdout.write(category)
          channel.stdout.write("] ")
          channel.stdout.write(message)
          channel.stdout.write("\r\n")
          if LogColor in channel.flags:
            channel.stdout.write(ansiForegroundColorCode(rgb(255, 255, 255)))
    except IOError:
      discard

  proc threadMain(i: int) {.thread.} =
    {.gcsafe.}:
      var localChannels: seq[LogChannelImpl] = @[]
      while true:
        var any = false

        for c in localChannels:
          for i in 0..2:
            let (ok, msg) = c.channel.tryRecv()
            if ok:
              any = true
              let category = if msg.category.int in 0..categories.high:
                categories[msg.category.int]
              else:
                "unknown"
              logConsole(c, msg.level, category & " " & c.name, msg.message)
            else:
              break

        while true:
          let (ok, msg) = logDrainThreadChannel.tryRecv()
          if ok:
            any = true
            case msg.kind
            of AddCategory:
              if categories.len <= msg.id:
                categories.setLen(msg.id + 1)
              categories[msg.id] = msg.name
            of AddChannel:
              localChannels.add msg.channel
              withLock(channelsLock):
                channels.add msg.channel
              logConsole(msg.channel, lvlInfo, "channel", msg.channel.name)
          else:
            break

        if not any:
          sleep(10)

  let defaultChannel = newLogChannel("main-channel")

  proc getMemChannels*(): seq[tuple[name: string, stdin: Arc[BaseChannel], stdout: Arc[BaseChannel]]] =
    {.gcsafe.}:
      withLock(channelsLock):
        for c in channels:
          result.add (c.name, c.stdin, c.stdout)

  proc init_module_log*() {.cdecl, exportc, dynlib.} =
    logDrainThread.createThread(threadMain, 0)

  proc shutdown_module_log*() {.cdecl, exportc, dynlib.} =
    {.gcsafe.}:
      withLock(channelsLock):
        for c in channels:
          if LogFile in c.flags:
            c.file.close()
            c.flags.excl LogFile
