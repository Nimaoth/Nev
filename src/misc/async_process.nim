import std/[json, strutils, tables, osproc, streams, options, macros]
import custom_logger, custom_async, util, channel, generational_seq
import nimsumtree/arc

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

type OwnedChannel*[T] = object
  init: bool
  name: string
  channel: Channel[T]

proc `=destroy`*[T](c {.byref.}: OwnedChannel[T]) =
  if c.init:
    c.channel.addr[].close()

proc open*[T](c: var OwnedChannel[T], name: string) =
  c.channel.open()
  c.init = true
  c.name = name

type AsyncChannel*[T] = ref object
  chan: Arc[OwnedChannel[T]]
  closed: bool
  buffer: T
  activeAwaits: int = 0

proc close*[T](c: AsyncChannel[T]) =
  c.closed = true

type ProcessInfo* = object
  name: string

proc `=destroy`*(p: ProcessInfo) =
  if p.name != "":
    `=destroy`(p.name)

type AsyncProcess* = ref object
  name: string
  info: ProcessInfo
  args: seq[string]
  onRestarted*: proc(): Future[void] {.gcsafe, raises: [].}
  onRestartFailed*: proc(): Future[void] {.gcsafe, raises: [].}
  dontRestart: bool
  process: Process
  stdin*: Arc[BaseChannel]
  stdout*: Arc[BaseChannel]
  stderr*: Arc[BaseChannel]
  inputStreamChannel: Arc[OwnedChannel[Option[ProcessObj]]]
  outputStreamChannel: Arc[OwnedChannel[Option[ProcessObj]]]
  errorStreamChannel: Arc[OwnedChannel[Option[ProcessObj]]]
  serverDiedNotifications: Arc[OwnedChannel[bool]]
  readerFlowVar: FlowVarBase
  errorReaderFlowVar: FlowVarBase
  writerFlowVar: FlowVarBase
  killOnExit: bool = false
  eval: bool = false
  errToOut: bool = false

proc isAlive*(process: AsyncProcess): bool =
  return process.process.isNotNil and process.process.running

proc newAsyncChannel*[T](name: string = ""): AsyncChannel[T] =
  new result
  result.chan = Arc[OwnedChannel[T]].new()
  result.chan.getMutUnsafe.open(name)

proc destroy*(process: AsyncProcess) =
  log lvlInfo, fmt"Destroying process {process.name}"
  process.dontRestart = true

  if not process.process.isNil:
    process.process.kill()

  process.inputStreamChannel.getMutUnsafe.channel.send ProcessObj.none
  process.outputStreamChannel.getMutUnsafe.channel.send ProcessObj.none
  process.errorStreamChannel.getMutUnsafe.channel.send ProcessObj.none
  process.onRestarted = nil
  process.onRestartFailed = nil
  process.stdin.close()
  process.stdout.close()
  process.stderr.close()

proc peek*[T](achan: AsyncChannel[T]): int =
  return achan.chan.getMutUnsafe.channel.peek

proc send*[T](achan: AsyncChannel[Option[T]], data: T) {.async.} =
  bind milliseconds
  while not achan.closed and not achan.chan.getMutUnsafe.channel.trySend(data.some):
    await sleepAsync 10.milliseconds

proc send*[T](achan: AsyncChannel[T], data: sink T) {.async.} =
  bind milliseconds
  {.push warning[BareExcept]:off.}
  try:
    while not achan.closed and not achan.chan.getMutUnsafe.channel.trySend(data.move):
      await sleepAsync 10.milliseconds
  except Exception:
    discard
  {.pop.}

proc recv*[T](achan: AsyncChannel[T]): Future[Option[T]] {.async.} =
  bind milliseconds

  while not achan.closed:
    let (ok, data) = achan.chan.getMutUnsafe.channel.tryRecv()
    if ok:
      return data.some

    await sleepAsync 50.milliseconds

  return T.none

proc recv*(process: AsyncProcess, amount: int): Future[string] {.async: (raises: [IOError]).} =
  if process.stdout.isNil or process.stdout.atEnd:
    raise newException(IOError, "(peek) Input stream closed")
  var buffer = newString(amount)
  var i = 0
  while i < amount and not process.stdout.atEnd():
    i += process.stdout.read(buffer.toOpenArrayByte(i, amount - 1))
    catch(await sleepAsync 5.milliseconds):
      discard
  return buffer

proc peek*(process: AsyncProcess): int =
  if process.stdout.isNil or process.stdout.atEnd:
    raise newException(IOError, "(peek) Input stream closed")
  discard process.stdout.flushRead()
  return process.stdout.peek()

proc recvLine*(process: AsyncProcess): Future[string] =
  return process.stdout.readLine()

proc recvErrorLine*(process: AsyncProcess): Future[string] =
  return process.stderr.readLine()

proc send*(process: AsyncProcess, data: string): Future[void] =
  if process.stdin.isNil or not process.stdin.isOpen:
    return
  process.stdin.write(data.toOpenArrayByte(0, data.high))
  return doneFuture()

proc readInput(chan: Arc[OwnedChannel[Option[ProcessObj]]], serverDiedNotifications: Arc[OwnedChannel[bool]], stdout: Arc[BaseChannel], output: bool, name: string): NoExceptionDestroy =
  while true:
    var process = Process.new
    if chan.getMutUnsafe.channel.recv.getSome(chan):
      process[] = chan
    else:
      break

    var stream: Stream
    if output:
      stream = process.outputStream()
      process.outStream = nil
    else:
      stream = process.errorStream()
      process.errStream = nil

    var buffer = newString(100 * 1024)
    while true:
      try:
        let read = stream.readData(buffer[0].addr, buffer.len)
        if read > 0:
          stdout.write buffer.toOpenArray(0, read - 1)
        else:
          serverDiedNotifications.getMutUnsafe.channel.send true
          break
      except CatchableError:
        # echo &"readInput: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
        break

    # todo: figure out when to close the stream
    # stream.close()

proc writeOutput(chan: Arc[OwnedChannel[Option[ProcessObj]]], stdin: Arc[BaseChannel]): NoExceptionDestroy =
  var buffer = newString(100 * 1024)
  while true:
    var process = Process.new
    if chan.getMutUnsafe.channel.recv.getSome(chan):
      process[] = chan
    else:
      break

    let stream = process.inputStream()
    process.inStream = nil

    while not stdin.atEnd:
      try:
        let read = stdin.read(buffer.toOpenArrayByte(0, buffer.high))
        if read > 0:
          assert read <= buffer.len
          stream.writeData(buffer[0].addr, read)

        # flush is required on linux
        # todo: Only flush when \n was written? Don't flush on
        stream.flush()

        discard stdin.get.signal.waitSync()

      except CatchableError:
        # echo "ioerror"
        # echo &"writeOutput: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
        break

    stream.close()

proc start*(process: AsyncProcess): bool =
  log(lvlInfo, fmt"start process {process.name} {process.args}")
  try:
    var options: set[ProcessOption] = {poUsePath, poDaemon}
    if process.eval:
      options.incl poEvalCommand
    if process.errToOut:
      options.incl poStdErrToStdOut
    process.process = startProcess(process.name, args=process.args, options=options)
  except CatchableError as e:
    log(lvlError, fmt"Failed to start {process.name}: {e.msg}")
    return false

  when defined(windows):
    if process.killOnExit:
      discard AssignProcessToJobObject(jobObject, process.process.osProcessHandle())

  process.readerFlowVar = spawn(readInput(process.inputStreamChannel, process.serverDiedNotifications, process.stdout, true, process.name & ".output"))
  process.inputStreamChannel.getMutUnsafe.channel.send process.process[].some

  process.errorReaderFlowVar = spawn(readInput(process.errorStreamChannel, process.serverDiedNotifications, process.stderr, false, process.name & ".error"))
  process.errorStreamChannel.getMutUnsafe.channel.send process.process[].some

  process.writerFlowVar = spawn(writeOutput(process.outputStreamChannel, process.stdin))
  process.outputStreamChannel.getMutUnsafe.channel.send process.process[].some

  return true

proc restartServer(process: AsyncProcess) {.async, gcsafe.} =
  var startCounter = 0

  while true:
    while process.serverDiedNotifications.getMutUnsafe.channel.peek == 0:
      # echo "process active"
      await sleepAsync(10.milliseconds)

    # echo "process dead"
    while process.serverDiedNotifications.getMutUnsafe.channel.peek > 0:
      discard process.serverDiedNotifications.getMutUnsafe.channel.recv

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

proc startAsyncProcess*(name: string, args: seq[string] = @[], autoRestart = true, autoStart = true, killOnExit = false, eval: bool = false, errToOut: bool = false): AsyncProcess {.gcsafe.} =
  let process = AsyncProcess()
  process.name = name
  process.info.name = name
  process.args = @args
  process.dontRestart = not autoRestart
  process.stdin = newInMemoryChannel()
  process.stdout = newInMemoryChannel()
  process.stderr = newInMemoryChannel()
  process.killOnExit = killOnExit
  process.eval = eval
  process.errToOut = errToOut

  process.inputStreamChannel = Arc[OwnedChannel[Option[ProcessObj]]].new()
  process.inputStreamChannel.getMutUnsafe.open("inputStreamChannel")

  process.outputStreamChannel = Arc[OwnedChannel[Option[ProcessObj]]].new()
  process.outputStreamChannel.getMutUnsafe.open("outputStreamChannel")

  process.errorStreamChannel = Arc[OwnedChannel[Option[ProcessObj]]].new()
  process.errorStreamChannel.getMutUnsafe.open("errorStreamChannel")

  process.serverDiedNotifications = Arc[OwnedChannel[bool]].new()
  process.serverDiedNotifications.getMutUnsafe.open("serverDiedNotifications")

  if autoStart:
    asyncSpawn process.restartServer()
    process.serverDiedNotifications.getMutUnsafe.channel.send true

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
    except CatchableError:
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

  except CatchableError:
    log lvlError, &"Failed to start process {name}, {args}"
