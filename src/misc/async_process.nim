import std/[asyncnet, json, strutils, tables, os, osproc, streams, threadpool, options, macros]
import custom_logger, custom_async

logCategory "asyncprocess"

type AsyncChannel*[T] = ref object
  chan: ptr Channel[T]
  closed: bool

type AsyncProcess* = ref object
  name: string
  args: seq[string]
  onRestarted*: proc(): Future[void]
  dontRestart: bool
  process: Process
  input: AsyncChannel[char]
  output: AsyncChannel[Option[string]]
  error: AsyncChannel[char]
  inputStreamChannel: ptr Channel[Stream]
  outputStreamChannel: ptr Channel[Stream]
  errorStreamChannel: ptr Channel[Stream]
  serverDiedNotifications: ptr Channel[bool]
  readerFlowVar: FlowVarBase
  errorReaderFlowVar: FlowVarBase
  writerFlowVar: FlowVarBase

proc isAlive*(process: AsyncProcess): bool =
  return process.process.running

proc newAsyncChannel*[T](): AsyncChannel[T] =
  new result
  result.chan = cast[ptr Channel[T]](allocShared0(sizeof(Channel[T])))
  result.chan[].open()

proc destroy*[T](channel: AsyncChannel[T]) =
  channel.chan[].close()
  channel.chan.deallocShared
  channel.chan = nil

proc destroyProcess2(process: ptr AsyncProcess) =
  # todo: probably needs a lock for the process RC
  let process = process[]

  if not process.readerFlowVar.isNil:
    blockUntil process.readerFlowVar[]
  if not process.writerFlowVar.isNil:
    blockUntil process.writerFlowVar[]
  if not process.errorReaderFlowVar.isNil:
    blockUntil process.errorReaderFlowVar[]

  process.inputStreamChannel[].close()
  process.errorStreamChannel[].close()
  process.outputStreamChannel[].close()
  process.serverDiedNotifications[].close()
  process.input.destroy()
  process.error.destroy()
  process.output.destroy()
  process.inputStreamChannel.deallocShared
  process.errorStreamChannel.deallocShared
  process.outputStreamChannel.deallocShared
  process.serverDiedNotifications.deallocShared

proc destroy*(process: AsyncProcess) =
  log lvlInfo, fmt"Destroying process {process.name}"
  process.dontRestart = true

  if not process.process.isNil:
    process.process.terminate()

  process.inputStreamChannel[].send nil
  process.outputStreamChannel[].send nil
  process.errorStreamChannel[].send nil

  spawn destroyProcess2(process.addr)
  # todo: should probably wait for the other thread to increment the process RC

  # if not process.readerFlowVar.isNil:
  #   debugf"wait for reader"
  #   blockUntil process.readerFlowVar[]
  # if not process.writerFlowVar.isNil:
  #   debugf"wait for writer"
  #   blockUntil process.writerFlowVar[]
  # if not process.errorReaderFlowVar.isNil:
  #   debugf"wait for error reader"
  #   blockUntil process.errorReaderFlowVar[]

  # debugf"close channels"
  # process.inputStreamChannel[].close()
  # process.errorStreamChannel[].close()
  # process.outputStreamChannel[].close()
  # process.serverDiedNotifications[].close()
  # debugf"destroy channels"
  # process.input.destroy()
  # process.error.destroy()
  # process.output.destroy()
  # process.inputStreamChannel.deallocShared
  # process.errorStreamChannel.deallocShared
  # process.outputStreamChannel.deallocShared
  # process.serverDiedNotifications.deallocShared

proc recv*[T: char](achan: AsyncChannel[T], amount: int): Future[string] {.async.} =
  var buffer = ""
  while buffer.len < amount:
    while buffer.len < amount and achan.chan[].peek > 0:
      let c = achan.chan[].recv
      if c == '\0':
        # End of input
        return buffer

      buffer.add c

    if buffer.len < amount:
      await sleepAsync 1
  return buffer

proc recvLine*[T: char](achan: AsyncChannel[T]): Future[string] {.async.} =
  var buffer = ""

  var cr = false
  while not achan.chan.isNil:
    while not achan.chan.isNil and achan.chan[].peek > 0:
      let c = achan.chan[].recv
      if c == '\0':
        # End of input
        return buffer

      if c != '\r' and c != '\n':
        cr = false
        buffer.add c
      elif c == '\r':
        cr = true
      elif c == '\n':
        if cr and buffer.len == 0:
          return "\r\n"
        cr = false
        return buffer
    await sleepAsync 1

  return ""

proc tryRecvLine*[T: char](achan: AsyncChannel[T]): Future[Option[string]] {.async.} =
  if achan.closed:
    return string.none

  var buffer = ""

  var cr = false
  while not achan.chan.isNil:
    while not achan.chan.isNil:
      let (hasData, c) = achan.chan[].tryRecv
      if not hasData:
        continue

      if c == '\0':
        achan.closed = true

        if buffer.len > 0:
          return buffer.some
        else:
          return string.none

      if c != '\r' and c != '\n':
        cr = false
        buffer.add c
      elif c == '\r':
        cr = true
      elif c == '\n':
        if cr and buffer.len == 0:
          return "\r\n".some
        cr = false
        return buffer.some

    await sleepAsync 1

  return string.none

proc send*[T](achan: AsyncChannel[Option[T]], data: T) {.async.} =
  while not achan.chan[].trySend(data.some):
    await sleepAsync 1

proc recv*(process: AsyncProcess, amount: int): Future[string] =
  if process.input.isNil or process.input.chan.isNil:
    result = newFuture[string]("recv")
    result.fail(newException(IOError, "(recv) Input stream closed while reading"))
    return result
  return process.input.recv(amount)

proc recvLine*(process: AsyncProcess): Future[string] =
  if process.input.isNil or process.input.chan.isNil:
    result = newFuture[string]("recv")
    result.fail(newException(IOError, "(recvLine) Input stream closed while reading"))
    return result
  return process.input.recvLine()

proc tryRecvLine*(process: AsyncProcess): Future[Option[string]] {.async.} =
  if process.input.isNil or process.input.chan.isNil:
    return string.none
  return process.input.tryRecvLine().await

proc recvErrorLine*(process: AsyncProcess): Future[string] =
  if process.error.isNil or process.error.chan.isNil:
    result = newFuture[string]("recvError")
    result.fail(newException(IOError, "(recvLine) Error stream closed while reading"))
    return result
  return process.error.recvLine()

proc send*(process: AsyncProcess, data: string): Future[void] =
  if process.output.isNil or process.output.chan.isNil:
    return
  return process.output.send(data)

proc readInput(chan: ptr Channel[Stream], serverDiedNotifications: ptr Channel[bool], data: ptr Channel[char], data2: ptr Channel[Option[string]]): bool =
  while true:
    let stream = chan[].recv

    if stream.isNil:
      # Send none to writeOutput to make it abandon the current stream
      # and recheck, causing it to also get a nil stream and stop
      data2[].send string.none
      break

    while true:
      try:
        let c = stream.readChar()

        data[].send c

        if c == '\0':
          # echo "server died"
          data2[].send string.none
          serverDiedNotifications[].send true
          break
      except:
        # echo &"readInput: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
        break

  return true

proc writeOutput(chan: ptr Channel[Stream], data: ptr Channel[Option[string]]): bool =
  var buffer: seq[string]
  while true:
    let stream = chan[].recv

    if stream.isNil:
      break

    while true:
      try:

        let d = data[].recv
        if d.isNone:
          # echo "data none"
          buffer.setLen 0
          break

        # echo "> " & d.get
        buffer.add d.get

        for d in buffer:
          stream.write(d)
        buffer.setLen 0

      except:
        # echo "ioerror"
        # echo &"writeOutput: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
        break

  return true

proc start*(process: AsyncProcess): bool =
  log(lvlInfo, fmt"start process {process.name} {process.args}")
  try:
    process.process = startProcess(process.name, args=process.args, options={poUsePath, poDaemon})
  except CatchableError as e:
    log(lvlError, fmt"Failed to start {process.name}: {e.msg}")
    return false

  process.readerFlowVar = spawn(readInput(process.inputStreamChannel, process.serverDiedNotifications, process.input.chan, process.output.chan))
  process.inputStreamChannel[].send process.process.outputStream()

  process.errorReaderFlowVar = spawn(readInput(process.errorStreamChannel, process.serverDiedNotifications, process.error.chan, process.output.chan))
  process.errorStreamChannel[].send process.process.errorStream()

  process.writerFlowVar = spawn(writeOutput(process.outputStreamChannel, process.output.chan))
  process.outputStreamChannel[].send process.process.inputStream()

  return true

proc restartServer(process: AsyncProcess) {.async.} =
  var startCounter = 0

  while true:
    while process.serverDiedNotifications[].peek == 0:
      # echo "process active"
      await sleepAsync(1)

    # echo "process dead"
    while process.serverDiedNotifications[].peek > 0:
      discard process.serverDiedNotifications[].recv

    if startCounter > 0 and process.dontRestart:
      log(lvlInfo, "Don't restart")
      return

    inc startCounter

    if not process.start():
      break

    if not process.onRestarted.isNil:
      process.onRestarted().await


proc startAsyncProcess*(name: string, args: seq[string] = @[], autoRestart = true, autoStart = true): AsyncProcess =
  let process = AsyncProcess()
  process.name = name
  process.args = @args
  process.dontRestart = not autoRestart
  process.input = newAsyncChannel[char]()
  process.error = newAsyncChannel[char]()
  process.output = newAsyncChannel[Option[string]]()

  process.inputStreamChannel = cast[ptr Channel[Stream]](allocShared0(sizeof(Channel[Stream])))
  process.inputStreamChannel[].open()

  process.errorStreamChannel = cast[ptr Channel[Stream]](allocShared0(sizeof(Channel[Stream])))
  process.errorStreamChannel[].open()

  process.outputStreamChannel = cast[ptr Channel[Stream]](allocShared0(sizeof(Channel[Stream])))
  process.outputStreamChannel[].open()

  process.serverDiedNotifications = cast[ptr Channel[bool]](allocShared0(sizeof(Channel[bool])))
  process.serverDiedNotifications[].open()

  if autoStart:
    asyncCheck process.restartServer()
    process.serverDiedNotifications[].send true

  return process

proc readProcessOutputThread(args: (string, seq[string])): seq[string] {.gcsafe.} =
  try:
    let process = startProcess(args[0], args=args[1], options={poUsePath, poDaemon})
    let (lines, _) = process.readLines()
    return lines
  except CatchableError:
    return @[]

proc runProcessAsync*(name: string, args: seq[string] = @[]): Future[seq[string]] =
  return spawnAsync(readProcessOutputThread, (name, args))
