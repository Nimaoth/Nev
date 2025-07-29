import std/[json, strutils, tables, os, osproc, streams, options, macros]
import custom_logger, custom_async, util, timer

{.push warning[Deprecated]:off.}
import std/[threadpool]
{.pop.}

logCategory "asyncprocess"

# Create a job which is used to kill assigned sub processes when the editor is closed.
when defined(windows):
  import winim/[lean]
  const JobObjectExtendedLimitInformation: DWORD = 9
  let jobObject = CreateJobObjectA(nil, nil)
  var limitInformation: JOBOBJECT_EXTENDED_LIMIT_INFORMATION
  limitInformation.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
  const length = sizeof(limitInformation)
  discard SetInformationJobObject(jobObject, JobObjectExtendedLimitInformation, limitInformation.addr, length.DWORD)

type AsyncChannel*[T] = ref object
  chan: ptr Channel[T]
  closed: bool
  buffer: T

type AsyncProcess* = ref object
  name: string
  args: seq[string]
  onRestarted*: proc(): Future[void] {.gcsafe, raises: [].}
  onRestartFailed*: proc(): Future[void] {.gcsafe, raises: [].}
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
  killOnExit: bool = false
  eval: bool = false

proc isAlive*(process: AsyncProcess): bool =
  return process.process.isNotNil and process.process.running

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
    process.process.kill()

  process.inputStreamChannel[].send nil
  process.outputStreamChannel[].send nil
  process.errorStreamChannel[].send nil

  spawn destroyProcess2(process.addr)
  # todo: should probably wait for the other thread to increment the process RC

proc recv*[T: char](achan: AsyncChannel[T], amount: int): Future[string] {.async.} =
  bind milliseconds

  var buffer = ""
  while buffer.len < amount:
    var timer = startTimer()

    while buffer.len < amount:
      let (ok, c) = achan.chan[].tryRecv
      if not ok:
        await sleepAsync 10.milliseconds
        timer = startTimer()
        continue

      if c == '\0':
        # End of input
        return buffer

      buffer.add c

      if timer.elapsed.ms > 2:
        await sleepAsync 10.milliseconds
        timer = startTimer()

    if buffer.len < amount:
      await sleepAsync 10.milliseconds

  return buffer

proc recv*[T: string](achan: AsyncChannel[T], amount: int): Future[string] {.async.} =
  bind milliseconds

  while achan.buffer.len < amount:
    var timer = startTimer()

    while achan.buffer.len < amount:
      let (ok, str) = achan.chan[].tryRecv
      if not ok:
        await sleepAsync 10.milliseconds
        timer = startTimer()
        continue

      if str == "":
        # End of input
        break

      if achan.buffer.len == 0 and str.len == amount:
        return str

      achan.buffer.add str

      if timer.elapsed.ms > 2:
        await sleepAsync 10.milliseconds
        timer = startTimer()

    if achan.buffer.len < amount:
      await sleepAsync 10.milliseconds

  if achan.buffer.len < amount:
    return ""

  let res = achan.buffer[0..<amount]
  achan.buffer = achan.buffer[amount..^1]
  return res

proc recvLine*[T: char](achan: AsyncChannel[T]): Future[string] {.async.} =
  bind milliseconds

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
    await sleepAsync 10.milliseconds

  return ""

proc tryRecvLine*[T: char](achan: AsyncChannel[T]): Future[Option[string]] {.async.} =
  bind milliseconds

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

    await sleepAsync 10.milliseconds

  return string.none

proc send*[T](achan: AsyncChannel[Option[T]], data: T) {.async.} =
  bind milliseconds
  while not achan.closed and not achan.chan[].trySend(data.some):
    await sleepAsync 10.milliseconds

proc send*[T](achan: AsyncChannel[T], data: sink T) {.async.} =
  bind milliseconds
  while not achan.closed and not achan.chan[].trySend(data.move):
    await sleepAsync 10.milliseconds

proc recv*[T](achan: AsyncChannel[T]): Future[Option[T]] {.async.} =
  bind milliseconds

  while not achan.closed:
    let (ok, data) = achan.chan[].tryRecv()
    if ok:
      return data.some

    await sleepAsync 50.milliseconds

  return T.none

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

proc readInput(chan: ptr Channel[Stream], serverDiedNotifications: ptr Channel[bool], data: ptr Channel[char], data2: ptr Channel[Option[string]]): NoExceptionDestroy =
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

proc writeOutput(chan: ptr Channel[Stream], data: ptr Channel[Option[string]]): NoExceptionDestroy =
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

        # flush is required on linux
        # todo: Only flush when \n was written? Don't flush on
        stream.flush()

      except:
        # echo "ioerror"
        # echo &"writeOutput: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
        break

proc start*(process: AsyncProcess): bool =
  log(lvlInfo, fmt"start process {process.name} {process.args}")
  try:
    var options: set[ProcessOption] = {poUsePath, poDaemon}
    if process.eval:
      options.incl poEvalCommand
    process.process = startProcess(process.name, args=process.args, options=options)
  except CatchableError as e:
    log(lvlError, fmt"Failed to start {process.name}: {e.msg}")
    return false

  when defined(windows):
    if process.killOnExit:
      discard AssignProcessToJobObject(jobObject, process.process.osProcessHandle())

  process.readerFlowVar = spawn(readInput(process.inputStreamChannel, process.serverDiedNotifications, process.input.chan, process.output.chan))
  process.inputStreamChannel[].send process.process.outputStream()

  process.errorReaderFlowVar = spawn(readInput(process.errorStreamChannel, process.serverDiedNotifications, process.error.chan, process.output.chan))
  process.errorStreamChannel[].send process.process.errorStream()

  process.writerFlowVar = spawn(writeOutput(process.outputStreamChannel, process.output.chan))
  process.outputStreamChannel[].send process.process.inputStream()

  return true

proc restartServer(process: AsyncProcess) {.async, gcsafe.} =
  var startCounter = 0

  while true:
    while process.serverDiedNotifications[].peek == 0:
      # echo "process active"
      await sleepAsync(10.milliseconds)

    # echo "process dead"
    while process.serverDiedNotifications[].peek > 0:
      discard process.serverDiedNotifications[].recv

    if startCounter > 0 and process.dontRestart:
      # log(lvlInfo, "Don't restart")
      return

    inc startCounter

    if not process.start():
      if process.onRestartFailed.isNotNil:
        process.onRestartFailed().await
      break

    startCounter = 0

    if not process.onRestarted.isNil:
      process.onRestarted().await

proc startAsyncProcess*(name: string, args: seq[string] = @[], autoRestart = true, autoStart = true, killOnExit = false, eval: bool = false): AsyncProcess {.gcsafe.} =
  let process = AsyncProcess()
  process.name = name
  process.args = @args
  process.dontRestart = not autoRestart
  process.input = newAsyncChannel[char]()
  process.error = newAsyncChannel[char]()
  process.output = newAsyncChannel[Option[string]]()
  process.killOnExit = killOnExit
  process.eval = eval

  process.inputStreamChannel = cast[ptr Channel[Stream]](allocShared0(sizeof(Channel[Stream])))
  process.inputStreamChannel[].open()

  process.errorStreamChannel = cast[ptr Channel[Stream]](allocShared0(sizeof(Channel[Stream])))
  process.errorStreamChannel[].open()

  process.outputStreamChannel = cast[ptr Channel[Stream]](allocShared0(sizeof(Channel[Stream])))
  process.outputStreamChannel[].open()

  process.serverDiedNotifications = cast[ptr Channel[bool]](allocShared0(sizeof(Channel[bool])))
  process.serverDiedNotifications[].open()

  if autoStart:
    asyncSpawn process.restartServer()
    process.serverDiedNotifications[].send true

  return process

const debugAsyncProcess = false

when debugAsyncProcess:
  var asyncProcessDebugOutput: Channel[string]
  asyncProcessDebugOutput.open()

  proc readAsyncProcessDebugOutput() {.async.} =
    while true:
      while asyncProcessDebugOutput.peek > 0:
         let line = asyncProcessDebugOutput.recv
         debugf"> {line}"
      await sleepAsync 10.milliseconds

  asyncSpawn readAsyncProcessDebugOutput()

type RunProcessThreadArgs = tuple
  processName: string
  args: seq[string]
  maxLines: int
  workingDir: string
  captureOut: bool = true
  captureErr: bool = true
  evalCommand: bool = false

proc readLineIncludingLast*(s: Stream, line: var string, last: char): tuple[eof: bool, last: char] =
  ## Like streams.readLine, but also returns an empty string for the last line if the last line is empty,
  ## which streams.readLine doesn't.
  line.setLen(0)
  while true:
    var c = readChar(s)
    if c == '\c':
      c = readChar(s)
      result.last = c
      break
    elif c == '\L':
      result.last = c
      break
    elif c == '\0':
      result.last = c
      if line.len > 0 or last == '\L': break
      else: return (true, c)
    line.add(c)
  result.eof = false

proc readProcessOutputThread(args: RunProcessThreadArgs): (seq[string], seq[string], ref Exception) {.gcsafe.} =
  try:
    when debugAsyncProcess:
      asyncProcessDebugOutput.send(fmt"Start process {args}")

    var options: set[ProcessOption] = {poUsePath, poDaemon}
    if args.evalCommand:
      options.incl poEvalCommand

    let process = startProcess(args.processName, workingDir=args.workingDir, args=args.args,
      options=options)

    if args.captureOut:
      var outp = process.outputStream
      var line = newStringOfCap(120)
      var last = '\n'
      var eof = false
      while ((eof, last) = outp.readLineIncludingLast(line, last); not eof):
        result[0].add(line)
        if result[0].len >= args.maxLines:
          when debugAsyncProcess:
            asyncProcessDebugOutput.send("{args}: Stop, max lines reached")
          break

    if args.captureErr:
      var errp = process.errorStream
      var line = newStringOfCap(120)
      var last = '\n'
      var eof = false
      while ((eof, last) = errp.readLineIncludingLast(line, last); not eof):
        result[1].add(line)
        if result[1].len >= args.maxLines:
          when debugAsyncProcess:
            asyncProcessDebugOutput.send("{args}: Stop, max lines reached")
          break

    try:
      process.kill()
    except:
      discard

  except CatchableError:
    when debugAsyncProcess:
      asyncProcessDebugOutput.send fmt"Failed to run {args}: {getCurrentExceptionMsg()}"
    result[2] = getCurrentException()

proc runProcessAsync*(name: string, args: seq[string] = @[], workingDir: string = "",
    maxLines: int = int.high, eval: bool = false): Future[seq[string]] {.async.} =

  log lvlInfo, fmt"[runProcessAsync] {name}, {args}, '{workingDir}', {maxLines}"
  let (lines, _, err) = await spawnAsync(readProcessOutputThread, (name, args, maxLines, workingDir, true, false, eval))
  if err != nil:
    raise newException(IOError, err.msg, err)
  return lines

proc runProcessAsyncOutput*(name: string, args: seq[string] = @[], workingDir: string = "",
    maxLines: int = int.high, eval: bool = false): Future[tuple[output: string, err: string]] {.async.} =

  log lvlInfo, fmt"[runProcessAsync] {name}, {args}, '{workingDir}', {maxLines}"
  let (outLines, errLines, err) = await spawnAsync(readProcessOutputThread, (name, args, maxLines, workingDir, true, true, eval))
  if err != nil:
    raise newException(IOError, err.msg, err)
  return (outLines.join("\n"), errLines.join("\n"))

proc readProcessOutputCallback(process: AsyncProcess,
    handleOutput: proc(line: string) {.closure, gcsafe, raises: [].} = nil) {.async.} =
  while process.isAlive:
    let line = await process.recvLine()
    handleOutput(line)

proc readProcessErrorCallback(process: AsyncProcess,
    handleError: proc(line: string) {.closure, gcsafe, raises: [].} = nil) {.async.} =
  while process.isAlive:
    let line = await process.recvErrorLine()
    handleError(line)

proc runProcessAsyncCallback*(name: string, args: seq[string] = @[], workingDir: string = "",
    handleOutput: proc(line: string) {.closure, gcsafe, raises: [].} = nil,
    handleError: proc(line: string) {.closure, gcsafe, raises: [].} = nil,
    maxLines: int = int.high, eval: bool = false) {.async.} =

  var process: AsyncProcess = nil
  try:
    process = startAsyncProcess(name, args, autoRestart = false, autoStart = false, eval = eval)
    if not process.start():
      log lvlError, &"Failed to start process {name}, {args}"
      return

    asyncSpawn readProcessOutputCallback(process, handleOutput)
    asyncSpawn readProcessErrorCallback(process, handleError)
    while process.isAlive:
      await sleepAsync 10.milliseconds
    log lvlInfo, &"Command {name}, {args} finished."

  except:
    log lvlError, &"Failed to start process {name}, {args}"
