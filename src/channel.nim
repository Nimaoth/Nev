import std/[strformat, hashes, macros, genasts, atomics, locks, tables, options]
import misc/[event, custom_async, id, generational_seq, util]
import nimsumtree/arc

{.push gcsafe.}

type
  ListenId* = distinct uint64
  ChannelListenResponse* = enum Continue, Stop
  ChannelListener* = proc(channel: var BaseChannel, closed: bool): ChannelListenResponse {.gcsafe, raises: [].}

  BaseChannel* = object of RootObj
    listeners*: GenerationalSeq[ChannelListener, ListenId]
    signal*: ThreadSignalPtr
    destroyImpl*: proc(self: ptr BaseChannel) {.gcsafe, raises: [].}
    closeImpl*: proc(self: ptr BaseChannel) {.gcsafe, raises: [].}
    isOpenImpl*: proc(self: ptr BaseChannel): bool {.gcsafe, raises: [].}
    peekImpl*: proc(self: ptr BaseChannel, to: Option[uint8]): int {.gcsafe, raises: [].}
    writeImpl*: proc(self: ptr BaseChannel, data: openArray[uint8]) {.gcsafe, raises: [IOError].}
    writeSinkImpl*: proc(self: ptr BaseChannel, data: sink seq[uint8]) {.gcsafe, raises: [IOError].}
    flushReadImpl*: proc(self: ptr BaseChannel): int {.gcsafe, raises: [IOError].}
    readImpl*: proc(self: ptr BaseChannel, res: var openArray[uint8]): int {.gcsafe, raises: [IOError].}
    listenImpl*: proc(self: Arc[BaseChannel], cb: ChannelListener): ListenId {.gcsafe, raises: [].}

  # todo: make this thread save
  InMemoryBuffer = object
    data: ptr UncheckedArray[uint8]
    len: int
  InMemoryChannel* = object of BaseChannel
    isOpen: bool
    isWaiting: bool
    data: seq[uint8] # todo: use something more efficient which doesn't require moving memory
    dataStart: int
    writeChannelPeekable: Atomic[int]
    channel: ptr Channel[InMemoryBuffer]

  ChannelRegistry* = object
    lock*: Lock
    readChannels*: Table[string, Arc[BaseChannel]]
    writeChannels*: Table[string, Arc[BaseChannel]]

proc `==`*(a, b: ListenId): bool {.borrow.}
proc hash*(vr: ListenId): Hash {.borrow.}
proc `$`*(vr: ListenId): string {.borrow.}

proc `=destroy`*(a {.byref.}: BaseChannel) {.raises: [], noSideEffect, inline, nodestroy, nimcall.} =
  {.cast(noSideEffect).}:
    if a.destroyImpl != nil:
      a.destroyImpl(a.addr)

proc close*(self: var BaseChannel) {.gcsafe, raises: [].} = self.closeImpl(self.addr)
proc isOpen*(self: var BaseChannel): bool {.raises: [].} = self.isOpenImpl(self.addr)
proc peek*(self: var BaseChannel, to: Option[uint8] = uint8.none): int {.raises: [].} = self.peekImpl(self.addr, to)
proc write*(self: var BaseChannel, data: openArray[uint8]) {.raises: [IOError].} = self.writeImpl(self.addr, data)
proc write*(self: var BaseChannel, data: sink seq[uint8]) {.raises: [IOError].} = self.writeSinkImpl(self.addr, data.ensureMove)
proc read*(self: var BaseChannel, res: var openArray[uint8]): int {.raises: [IOError].} = self.readImpl(self.addr, res)
proc flushRead*(self: var BaseChannel): int {.raises: [IOError].} = self.flushReadImpl(self.addr)

proc close*(self: Arc[BaseChannel]) {.gcsafe, raises: [].} = self.getMutUnsafe.close()
proc isOpen*(self: Arc[BaseChannel]): bool {.raises: [].} = self.getMutUnsafe.isOpen()
proc peek*(self: Arc[BaseChannel], to: Option[uint8] = uint8.none): int {.raises: [].} = self.getMutUnsafe.peek(to)
proc write*(self: Arc[BaseChannel], data: openArray[uint8]) {.raises: [IOError].} = self.getMutUnsafe.write(data)
proc write*(self: Arc[BaseChannel], data: openArray[char]) {.raises: [IOError].} = self.getMutUnsafe.write(cast[ptr UncheckedArray[uint8]](data[0].addr).toOpenArray(0, data.high))
proc write*(self: Arc[BaseChannel], data: sink seq[uint8]) {.raises: [IOError].} = self.getMutUnsafe.write(data.ensureMove)
proc read*(self: Arc[BaseChannel], res: var openArray[uint8]): int {.raises: [IOError].} = self.getMutUnsafe.read(res)
proc flushRead*(self: Arc[BaseChannel]): int {.raises: [IOError].} = self.getMutUnsafe.flushRead()
proc listen*(self: Arc[BaseChannel], cb: ChannelListener): ListenId {.gcsafe, raises: [].} = self.get.listenImpl(self, cb)
proc stopListening*(self: Arc[BaseChannel], id: ListenId) {.gcsafe, raises: [].} =
  self.getMutUnsafe.listeners.del(id)

proc atEnd*(self {.byref.}: BaseChannel): bool {.gcsafe, raises: [].} =
  not self.isOpenImpl(self.addr) and self.peekImpl(self.addr, uint8.none) == 0

proc atEnd*(self: Arc[BaseChannel]): bool {.gcsafe, raises: [].} =
  not self.isOpen and self.peek == 0

proc readAsync*(self: Arc[BaseChannel], amount: int): Future[string] {.async: (raises: [IOError]).} =
  if self.isNil or self.atEnd:
    raise newException(IOError, "(readAsync) Channel closed")
  var buffer = newString(amount)
  var i = 0
  while true:
    discard self.flushRead()
    i += self.read(buffer.toOpenArrayByte(i, amount - 1))
    if i >= amount:
      assert i == amount
      break
    if not self.isOpen():
      break
    catch(await self.get.signal.wait()):
      discard
  return buffer

proc readLine*(self: Arc[BaseChannel]): Future[string] {.async: (raises: [IOError]).} =
  if self.isNil or self.atEnd:
    raise newException(IOError, "(readLine) Channel closed")
  while true:
    discard self.flushRead()
    var nl = self.peek('\n'.uint8.some)
    if nl == -1:
      if not self.isOpen:
        nl = self.peek() - 1
        break
      catch(await self.get.signal.wait()):
        discard
      continue

    var buffer = newString(nl + 1)
    if buffer.len > 0:
      let read = self.read(buffer.toOpenArrayByte(0, buffer.high))
      buffer.setLen(read)
    return buffer

proc fireEvent*(self: var BaseChannel, closed: bool) {.gcsafe, raises: [].} =
  for key in self.listeners.keys:
    let cb = self.listeners[key]
    case cb(self, closed)
    of Continue:
      discard
    of Stop:
      # Deleting while iterating is safe because listeners is a genertional seq, so when deleting
      # it doesn't move elements in memory, it just clears the current element
      self.listeners.del(key)

template destroyChannelImpl*(t: untyped): untyped =
  proc(self: ptr BaseChannel) {.gcsafe, raises: [].} =
    when defined(debugChannelDestroy):
      echo "destroyChannelImpl ", t
    self.destroyImpl = nil
    let self = cast[ptr t](self)
    {.gcsafe, cast(noSideEffect).}:
      {.push warning[BareExcept]:off.}
      try:
        `=destroy`(self[])
        `=wasMoved`(self[])
      except Exception:
        discard
      {.pop.}

proc close(self: ptr InMemoryChannel) {.gcsafe, raises: [].} =
  self.isOpen = false
  discard self.signal.fireSync()

proc isOpen(self: ptr InMemoryChannel): bool = self.isOpen
proc peek(self: ptr InMemoryChannel, to: Option[uint8] = uint8.none): int =
  if to.getSome(to):
    self.data.find(to, self.dataStart) - self.dataStart
  else:
    self.data.len - self.dataStart

proc write(self: ptr InMemoryChannel, data: openArray[uint8]) =
  if data.len > 0:
    var buff = InMemoryBuffer(data: cast[ptr UncheckedArray[uint8]](alloc(data.len)), len: data.len)
    copyMem(buff.data[0].addr, data[0].addr, data.len)
    self.channel[].send(buff)
    discard self.signal.fireSync()

proc write(self: ptr InMemoryChannel, data: sink seq[uint8]) =
  if data.len > 0:
    var buff = InMemoryBuffer(data: cast[ptr UncheckedArray[uint8]](alloc(data.len)), len: data.len)
    copyMem(buff.data[0].addr, data[0].addr, data.len)
    self.channel[].send(buff)
    discard self.signal.fireSync()

proc flushRead(self: ptr InMemoryChannel): int =
  try:
    while true:
      var (ok, data) = self.channel[].tryRecv()
      if not ok:
        break
      let oldLen = self.data.len
      self.data.setLen(oldLen + data.len)
      copyMem(self.data[oldLen].addr, data.data, data.len)
      dealloc(data.data)
  except ValueError as e:
    echo "Failed to read memory channel: ", e.msg
  return self.data.len - self.dataStart

proc read(self: ptr InMemoryChannel, res: var openArray[uint8]): int =
  discard self.flushRead()
  if self.data.len > self.dataStart and res.len > 0:
    let toRead = min(self.data.len - self.dataStart, res.len)
    copyMem(res[0].addr, self.data[self.dataStart].addr, toRead)
    self.dataStart += toRead
    if self.dataStart == self.data.len:
      self.data.setLen(0)
      self.dataStart = 0
    elif self.dataStart > (self.data.len - self.dataStart) * 5:
      moveMem(self.data[0].addr, self.data[self.dataStart].addr, self.data.len - self.dataStart)
      self.data.setLen(self.data.len - self.dataStart)
      self.dataStart = 0
    return toRead
  return 0

proc listen(self: Arc[InMemoryChannel]) {.async: (raises: []).} =
  let self = self.getMutUnsafe.addr
  if self.isWaiting:
    return
  self.isWaiting = true
  defer:
    self.isWaiting = false

  while self.isOpen or self.peek() != 0:
    if self.peek() > 0:
      self[].fireEvent(false)

    if self.listeners.len == 0:
      return

    if not self.isOpen:
      break

    try:
      await self.signal.wait()
      discard self.flushRead()
    except AsyncError, CatchableError:
      discard

  self[].fireEvent(true)

proc listenInMemoryChannel(self: Arc[InMemoryChannel], cb: ChannelListener): ListenId =
  result = self.getMutUnsafe.listeners.add(cb)
  if not self.get.isWaiting:
    asyncSpawn self.listen()

proc cloneAs*[B](self: Arc[B], T: typedesc[B]): Arc[T] =
  return cast[ptr Arc[T]](self.addr)[].clone()

proc newInMemoryChannel*(): Arc[BaseChannel] =
  let signal = ThreadSignalPtr.new()

  var channel = create(Channel[InMemoryBuffer])
  channel[].open()

  var res = Arc[InMemoryChannel].new()
  res.getMut() = InMemoryChannel(
    isOpen: true,
    signal: signal.value,
    channel: channel,
    destroyImpl: destroyChannelImpl(InMemoryChannel),
    closeImpl: (proc(self: ptr BaseChannel) {.gcsafe, raises: [].} = close(cast[ptr InMemoryChannel](self))),
    isOpenImpl: proc(self: ptr BaseChannel): bool {.gcsafe, raises: [].} = isOpen(cast[ptr InMemoryChannel](self)),
    peekImpl: proc(self: ptr BaseChannel, to: Option[uint8]): int {.gcsafe, raises: [].} = peek(cast[ptr InMemoryChannel](self), to),
    writeImpl: proc(self: ptr BaseChannel, data: openArray[uint8]) {.gcsafe, raises: [IOError].} = write(cast[ptr InMemoryChannel](self), data),
    writeSinkImpl: proc(self: ptr BaseChannel, data: sink seq[uint8]) {.gcsafe, raises: [IOError].} = write(cast[ptr InMemoryChannel](self), data.ensureMove),
    readImpl: proc(self: ptr BaseChannel, res: var openArray[uint8]): int {.gcsafe, raises: [IOError].} = read(cast[ptr InMemoryChannel](self), res),
    flushReadImpl: proc(self: ptr BaseChannel): int {.gcsafe, raises: [IOError].} = flushRead(cast[ptr InMemoryChannel](self)),
    listenImpl: proc(self: Arc[BaseChannel], cb: ChannelListener): ListenId {.gcsafe, raises: [].} = listenInMemoryChannel(self.cloneAs(InMemoryChannel), cb),
  )
  return cast[ptr Arc[BaseChannel]](res.addr)[].clone()

var gChannelRegistry = ChannelRegistry()
gChannelRegistry.lock.initLock()

proc openGlobalReadChannel*(path: string): Option[Arc[BaseChannel]] {.gcsafe.} =
  let channels = ({.gcsafe.}: gChannelRegistry.addr)
  withLock(channels.lock):
    var chan: Arc[BaseChannel]
    if channels.readChannels.take(path, chan):
      return chan.some

proc openGlobalWriteChannel*(path: string): Option[Arc[BaseChannel]] {.gcsafe.} =
  let channels = ({.gcsafe.}: gChannelRegistry.addr)
  withLock(channels.lock):
    var chan: Arc[BaseChannel]
    if channels.writeChannels.take(path, chan):
      return chan.some

proc mountGlobalReadChannel*(path: string, chan: Arc[BaseChannel], unique: bool): string {.gcsafe.} =
  var path = path
  if unique:
    path.add "-" & $newId()
  let channels = ({.gcsafe.}: gChannelRegistry.addr)
  withLock(channels.lock):
    channels.readChannels[path] = chan
    return path

proc mountGlobalWriteChannel*(path: string, chan: Arc[BaseChannel], unique: bool): string {.gcsafe.} =
  var path = path
  if unique:
    path.add "-" & $newId()
  let channels = ({.gcsafe.}: gChannelRegistry.addr)
  withLock(channels.lock):
    channels.writeChannels[path] = chan
    return path
