import std/[json, strutils, tables, os, osproc, streams, options, macros]
import custom_logger, custom_async, util, timer, channel, event, generational_seq
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

proc `=destroy`*[T](c: var OwnedChannel[T]) =
  if c.init:
    c.channel.close()

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
  input: AsyncChannel[char]
  output: AsyncChannel[Option[string]]
  error: AsyncChannel[char]
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
  process.input.close()
  process.output.close()
  process.error.close()

proc peek*[T](achan: AsyncChannel[T]): int =
  return achan.chan.getMutUnsafe.channel.peek

proc recv*[T: char](achan: AsyncChannel[T], amount: int): Future[string] {.async.} =
  bind milliseconds
  achan.activeAwaits.inc
  defer:
    achan.activeAwaits.dec

  var buffer = ""
  while buffer.len < amount and not achan.closed:
    var timer = startTimer()

    while buffer.len < amount and not achan.closed:
      let (ok, c) = achan.chan.getMutUnsafe.channel.tryRecv
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
  achan.activeAwaits.inc
  defer:
    achan.activeAwaits.dec

  while achan.buffer.len < amount and not achan.closed:
    var timer = startTimer()

    while achan.buffer.len < amount and not achan.closed:
      let (ok, str) = achan.chan.getMutUnsafe.channel.tryRecv
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
  achan.activeAwaits.inc
  defer:
    achan.activeAwaits.dec

  var buffer = ""

  var cr = false
  while not achan.chan.isNil and not achan.closed:
    while not achan.chan.isNil and achan.chan.getMutUnsafe.channel.peek > 0 and not achan.closed:
      let c = achan.chan.getMutUnsafe.channel.recv
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
  achan.activeAwaits.inc
  defer:
    achan.activeAwaits.dec

  if achan.closed:
    return string.none

  var buffer = ""

  var cr = false
  while not achan.chan.isNil and not achan.closed:
    while not achan.chan.isNil and not achan.closed:
      let (hasData, c) = achan.chan.getMutUnsafe.channel.tryRecv
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
  while not achan.closed and not achan.chan.getMutUnsafe.channel.trySend(data.some):
    await sleepAsync 10.milliseconds

proc send*[T](achan: AsyncChannel[T], data: sink T) {.async.} =
  bind milliseconds
  while not achan.closed and not achan.chan.getMutUnsafe.channel.trySend(data.move):
    await sleepAsync 10.milliseconds

proc sendSync*[T](achan: AsyncChannel[T], data: sink T) =
  if not achan.closed:
    achan.chan.getMutUnsafe.channel.send(data.move)

proc recv*[T](achan: AsyncChannel[T]): Future[Option[T]] {.async.} =
  bind milliseconds

  while not achan.closed:
    let (ok, data) = achan.chan.getMutUnsafe.channel.tryRecv()
    if ok:
      return data.some

    await sleepAsync 50.milliseconds

  return T.none

proc recvAvailable*[char](achan: AsyncChannel[char], res: var seq[uint8]) =
  while not achan.closed:
    let (ok, data) = achan.chan.getMutUnsafe.channel.tryRecv()
    if not ok:
      return

    res.add(data.uint8)

proc recvAvailable*[char](achan: AsyncChannel[char], res: var string) =
  while not achan.closed:
    let (ok, data) = achan.chan.getMutUnsafe.channel.tryRecv()
    if not ok:
      return

    res.add(data)

proc recvAvailable*[char](achan: AsyncChannel[char], res: var openArray[uint8]): int =
  result = 0
  while not achan.closed and result < res.len:
    let (ok, data) = achan.chan.getMutUnsafe.channel.tryRecv()
    if not ok:
      return

    res[result] = data.uint8
    # res[result].addr[] = data.uint8
    inc result

proc recv*(process: AsyncProcess, amount: int): Future[string] =
  if process.input.isNil or process.input.chan.isNil:
    result = newFuture[string]("recv")
    result.fail(newException(IOError, "(recv) Input stream closed while reading"))
    return result
  return process.input.recv(amount)

proc peek*(process: AsyncProcess): int =
  if process.input.isNil or process.input.chan.isNil:
    raise newException(IOError, "(peek) Input stream closed")
  return process.input.peek()

proc recvAvailable*(process: AsyncProcess, res: var seq[uint8]) {.raises: [IOError].} =
  if process.input.isNil or process.input.chan.isNil:
    raise newException(IOError, "(recvLine) Input stream closed while reading")
  try:
    process.input.recvAvailable(res)
  except ValueError as e:
    raise newException(IOError, "(recvAvailable) Error while reading", e)

proc recvAvailable*(process: AsyncProcess, res: var string) {.raises: [IOError].} =
  if process.input.isNil or process.input.chan.isNil:
    raise newException(IOError, "(recvLine) Input stream closed while reading")
  try:
    process.input.recvAvailable(res)
  except ValueError as e:
    raise newException(IOError, "(recvAvailable) Error while reading", e)

proc recvAvailable*(process: AsyncProcess, res: var openArray[uint8]): int {.raises: [IOError].} =
  if process.input.isNil or process.input.chan.isNil:
    raise newException(IOError, "(recvLine) Input stream closed while reading")
  try:
    process.input.recvAvailable(res)
  except ValueError as e:
    raise newException(IOError, "(recvAvailable) Error while reading", e)

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

proc sendSync*(process: AsyncProcess, data: sink string) =
  if process.output.isNil or process.output.chan.isNil:
    return
  process.output.sendSync(data.some)

proc send*(process: AsyncProcess, data: string): Future[void] =
  if process.output.isNil or process.output.chan.isNil:
    return
  return process.output.send(data)

proc readInput(chan: Arc[OwnedChannel[Option[ProcessObj]]], serverDiedNotifications: Arc[OwnedChannel[bool]], data: Arc[OwnedChannel[char]], data2: Arc[OwnedChannel[Option[string]]], output: bool, name: string): NoExceptionDestroy =
  while true:
    var process = Process.new
    if chan.getMutUnsafe.channel.recv.getSome(chan):
      process[] = chan
    else:
      # Send none to writeOutput to make it abandon the current stream
      # and recheck, causing it to also get a nil stream and stop
      data2.getMutUnsafe.channel.send string.none
      break

    var stream: Stream
    if output:
      stream = process.outputStream()
      process.outStream = nil
    else:
      stream = process.errorStream()
      process.errStream = nil

    while true:
      try:
        let c = stream.readChar()

        data.getMutUnsafe.channel.send c

        if c == '\0':
          # echo "server died"
          data2.getMutUnsafe.channel.send string.none
          serverDiedNotifications.getMutUnsafe.channel.send true
          break
      except CatchableError:
        # echo &"readInput: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
        break

    # todo: figure out when to close the stream
    # stream.close()

proc writeOutput(chan: Arc[OwnedChannel[Option[ProcessObj]]], data: Arc[OwnedChannel[Option[string]]]): NoExceptionDestroy =
  var buffer: seq[string]
  while true:
    var process = Process.new
    if chan.getMutUnsafe.channel.recv.getSome(chan):
      process[] = chan
    else:
      break

    let stream = process.inputStream()
    process.inStream = nil

    while true:
      try:

        let d = data.getMutUnsafe.channel.recv
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

      except CatchableError:
        # echo "ioerror"
        # echo &"writeOutput: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
        break

    # todo: figure out when to close the stream
    # stream.close()

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

  process.readerFlowVar = spawn(readInput(process.inputStreamChannel, process.serverDiedNotifications, process.input.chan, process.output.chan, true, process.name & ".output"))
  process.inputStreamChannel.getMutUnsafe.channel.send process.process[].some

  process.errorReaderFlowVar = spawn(readInput(process.errorStreamChannel, process.serverDiedNotifications, process.error.chan, process.output.chan, false, process.name & ".error"))
  process.errorStreamChannel.getMutUnsafe.channel.send process.process[].some

  process.writerFlowVar = spawn(writeOutput(process.outputStreamChannel, process.output.chan))
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
  process.input = newAsyncChannel[char]("input")
  process.error = newAsyncChannel[char]("error")
  process.output = newAsyncChannel[Option[string]]("output")
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

type
  ProcessOutputChannel* = object of BaseChannel
    process*: AsyncProcess
    isPolling: bool

  ProcessInputChannel* = object of BaseChannel
    process*: AsyncProcess

proc isOpen*(self: ptr ProcessOutputChannel): bool = self.process != nil and self.process.isAlive.catch(false)
proc close*(self: ptr ProcessOutputChannel) = discard
proc peek*(self: ptr ProcessOutputChannel): int = self.process.peek.catch(0)
proc read*(self: ptr ProcessOutputChannel, res: var openArray[uint8]): int {.raises: [IOError].} = self.process.recvAvailable(res)
proc flushRead*(self: ptr ProcessOutputChannel): int {.raises: [IOError].} = self.peek()

proc listenPoll*(self: Arc[ProcessOutputChannel]) {.async: (raises: []).} =
  let self = self.getMutUnsafe.addr
  if self.isPolling:
    return
  self.isPolling = true
  defer:
    self.isPolling = false

  while self.isOpen or self.peek > 0:
    if self.peek > 0:
      self[].fireEvent(false)

    if self.listeners.len == 0:
      return

    if not self.isOpen:
      break

    try:
      await sleepAsync(10.milliseconds)
    except CatchableError:
      discard

  self[].fireEvent(true)

proc listen*(self: Arc[ProcessOutputChannel], cb: ChannelListener): ListenId {.gcsafe, raises: [].} =
  result = self.getMutUnsafe.listeners.add(cb)
  if not self.get.isPolling:
    asyncSpawn self.listenPoll()

proc newProcessOutputChannel*(process: AsyncProcess): Arc[BaseChannel] =
  let signal = ThreadSignalPtr.new()
  var res = Arc[ProcessOutputChannel].new()
  res.getMut() = ProcessOutputChannel(
    process: process,
    signal: signal.value,
    destroyImpl: destroyChannelImpl(ProcessOutputChannel),
    closeImpl: (proc(self: ptr BaseChannel) {.gcsafe, raises: [].} = close(cast[ptr ProcessOutputChannel](self))),
    isOpenImpl: proc(self: ptr BaseChannel): bool {.gcsafe, raises: [].} = isOpen(cast[ptr ProcessOutputChannel](self)),
    peekImpl: proc(self: ptr BaseChannel): int {.gcsafe, raises: [].} = peek(cast[ptr ProcessOutputChannel](self)),
    writeImpl: proc(self: ptr BaseChannel, data: openArray[uint8]) {.gcsafe, raises: [IOError].} = discard,
    readImpl: proc(self: ptr BaseChannel, res: var openArray[uint8]): int {.gcsafe, raises: [IOError].} = read(cast[ptr ProcessOutputChannel](self), res),
    flushReadImpl: proc(self: ptr BaseChannel): int {.gcsafe, raises: [IOError].} = flushRead(cast[ptr ProcessOutputChannel](self)),
    listenImpl: proc(self: Arc[BaseChannel], cb: ChannelListener): ListenId {.gcsafe, raises: [].} = listen(self.cloneAs(ProcessOutputChannel), cb),
  )
  return cast[ptr Arc[BaseChannel]](res.addr)[].clone()

proc isOpen*(self: ptr ProcessInputChannel): bool = self.process != nil and self.process.isAlive.catch(false)
proc close*(self: ptr ProcessInputChannel) = discard
proc write*(self: ptr ProcessInputChannel, data: openArray[uint8]) {.raises: [IOError].} =
  var str = newString(data.len)
  if data.len > 0:
    copyMem(str[0].addr, data[0].addr, data.len)
  self.process.sendSync(str.ensureMove)

proc newProcessInputChannel*(process: AsyncProcess): Arc[BaseChannel] =
  let signal = ThreadSignalPtr.new()
  var res = Arc[ProcessInputChannel].new()
  res.getMut() = ProcessInputChannel(
    process: process,
    signal: signal.value,
    destroyImpl: destroyChannelImpl(ProcessInputChannel),
    closeImpl: (proc(self: ptr BaseChannel) {.gcsafe, raises: [].} = close(cast[ptr ProcessInputChannel](self))),
    isOpenImpl: proc(self: ptr BaseChannel): bool {.gcsafe, raises: [].} = isOpen(cast[ptr ProcessInputChannel](self)),
    peekImpl: proc(self: ptr BaseChannel): int {.gcsafe, raises: [].} = 0,
    writeImpl: proc(self: ptr BaseChannel, data: openArray[uint8]) {.gcsafe, raises: [IOError].} = write(cast[ptr ProcessInputChannel](self), data),
    readImpl: proc(self: ptr BaseChannel, res: var openArray[uint8]): int {.gcsafe, raises: [IOError].} = 0,
    flushReadImpl: proc(self: ptr BaseChannel): int {.gcsafe, raises: [IOError].} = 0,
    listenImpl: proc(self: Arc[BaseChannel], cb: ChannelListener): ListenId {.gcsafe, raises: [].} = 0.ListenId,
  )
  return cast[ptr Arc[BaseChannel]](res.addr)[].clone()
