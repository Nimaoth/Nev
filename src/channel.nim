import std/[strformat, hashes]
import misc/[event, custom_async, id, generational_seq]
import nimsumtree/arc

{.push gcsafe.}

type
  ListenId* = distinct uint64
  ChannelListenResponse* = enum Continue, Stop
  ChannelListener* = proc(): ChannelListenResponse {.gcsafe, raises: [].}

  BaseChannel* = object of RootObj
    listeners*: GenerationalSeq[ChannelListener, ListenId]
    signal*: ThreadSignalPtr
    destroyImpl*: proc(self: ptr BaseChannel) {.gcsafe, raises: [].}
    closeImpl*: proc(self: ptr BaseChannel) {.gcsafe, raises: [].}
    isOpenImpl*: proc(self: ptr BaseChannel): bool {.gcsafe, raises: [].}
    peekImpl*: proc(self: ptr BaseChannel): int {.gcsafe, raises: [].}
    writeImpl*: proc(self: ptr BaseChannel, data: openArray[uint8]) {.gcsafe, raises: [IOError].}
    readImpl*: proc(self: ptr BaseChannel, res: var openArray[uint8]): int {.gcsafe, raises: [IOError].}
    listenImpl*: proc(self: ptr BaseChannel, cb: proc(): ChannelListenResponse {.gcsafe, raises: [].}): ListenId {.gcsafe, raises: [].}

  # todo: make this thread save
  InMemoryChannel* = object of BaseChannel
    isOpen: bool
    isWaiting: bool
    data: seq[uint8] # todo: use something more efficient which doesn't require moving memory

proc `==`*(a, b: ListenId): bool {.borrow.}
proc hash*(vr: ListenId): Hash {.borrow.}
proc `$`*(vr: ListenId): string {.borrow.}

proc `=destroy`*(a {.byref.}: BaseChannel) {.raises: [], noSideEffect, inline, nodestroy, nimcall.} =
  {.cast(noSideEffect).}:
    if a.destroyImpl != nil:
      a.destroyImpl(a.addr)

proc close*(self: Arc[BaseChannel]) {.gcsafe, raises: [].} =
  self.get.closeImpl(self.getMutUnsafe.addr)
proc isOpen*(self: Arc[BaseChannel]): bool {.raises: [].} =
  self.get.isOpenImpl(self.getMutUnsafe.addr)
proc peek*(self: Arc[BaseChannel]): int {.raises: [].} =
  self.get.peekImpl(self.getMutUnsafe.addr)
proc write*(self: Arc[BaseChannel], data: openArray[uint8]) {.raises: [IOError].} =
  self.get.writeImpl(self.getMutUnsafe.addr, data)
proc read*(self: Arc[BaseChannel], res: var openArray[uint8]): int {.raises: [IOError].} =
  self.get.readImpl(self.getMutUnsafe.addr, res)
proc listen*(self: Arc[BaseChannel], cb: ChannelListener): ListenId {.gcsafe, raises: [].} =
  self.get.listenImpl(self.getMutUnsafe.addr, cb)

proc atEnd*(self {.byref.}: BaseChannel): bool {.gcsafe, raises: [].} =
  not self.isOpenImpl(self.addr) and self.peekImpl(self.addr) == 0

proc atEnd*(self: Arc[BaseChannel]): bool {.gcsafe, raises: [].} =
  not self.isOpen and self.peek == 0

proc fireEvent*(self: var BaseChannel) {.gcsafe, raises: [].} =
  for key, cb in self.listeners.pairs:
    case cb()
    of Continue:
      discard
    of Stop:
      # Deleting while iterating is safe because listeners is a genertional seq, so when deleting
      # it doesn't move elements in memory, it just clears the current element
      self.listeners.del(key)

proc destroyChannelImpl*[T: BaseChannel](self: var T) {.gcsafe, raises: [].} =
  {.cast(noSideEffect).}:
    `=destroy`(self)
    `=wasMoved`(self)

proc destroyInMemoryChannel(self: ptr BaseChannel) {.gcsafe, raises: [].} =
  let self = cast[ptr InMemoryChannel](self)
  self.destroyImpl = nil
  self[].destroyChannelImpl()

proc close(self: ptr InMemoryChannel) {.gcsafe, raises: [].} =
  self.isOpen = false

proc isOpen(self: ptr InMemoryChannel): bool = self.isOpen
proc peek(self: ptr InMemoryChannel): int = self.data.len
proc write(self: ptr InMemoryChannel, data: openArray[uint8]) =
  if data.len > 0:
    let prevLen = self.data.len
    self.data.setLen(prevLen + data.len)
    copyMem(self.data[prevLen].addr, data[0].addr, data.len)
    discard self.signal.fireSync()

proc read(self: ptr InMemoryChannel, res: var openArray[uint8]): int =
  if self.data.len > 0 and res.len > 0:
    let toRead = min(self.data.len, res.len)
    copyMem(res[0].addr, self.data[0].addr, toRead)
    self.data = self.data[toRead..^1]
    return toRead
  return 0

proc listen(self: ptr InMemoryChannel) {.async: (raises: []).} =
  if self.isWaiting:
    return
  self.isWaiting = true
  defer:
    self.isWaiting = false

  while self.isOpen or self.peek > 0:
    if self.peek > 0:
      self[].fireEvent()

    if self.listeners.len == 0:
      return

    try:
      await self.signal.wait()
    except AsyncError, CatchableError:
      discard

  self[].fireEvent()

proc listen(self: ptr InMemoryChannel, cb: ChannelListener): ListenId =
  result = self.listeners.add(cb)
  if not self.isWaiting:
    asyncSpawn self.listen()

proc newInMemoryChannel*(): Arc[BaseChannel] =
  let signal = ThreadSignalPtr.new()
  var res = Arc[InMemoryChannel].new()
  res.getMut() = InMemoryChannel(
    isOpen: true,
    signal: signal.value,
    destroyImpl: destroyInMemoryChannel,
    closeImpl: (proc(self: ptr BaseChannel) {.gcsafe, raises: [].} = close(cast[ptr InMemoryChannel](self))),
    isOpenImpl: proc(self: ptr BaseChannel): bool {.gcsafe, raises: [].} = isOpen(cast[ptr InMemoryChannel](self)),
    peekImpl: proc(self: ptr BaseChannel): int {.gcsafe, raises: [].} = peek(cast[ptr InMemoryChannel](self)),
    writeImpl: proc(self: ptr BaseChannel, data: openArray[uint8]) {.gcsafe, raises: [IOError].} = write(cast[ptr InMemoryChannel](self), data),
    readImpl: proc(self: ptr BaseChannel, res: var openArray[uint8]): int {.gcsafe, raises: [IOError].} = read(cast[ptr InMemoryChannel](self), res),
    listenImpl: proc(self: ptr BaseChannel, cb: ChannelListener): ListenId {.gcsafe, raises: [].} = listen(cast[ptr InMemoryChannel](self), cb),
  )
  return cast[ptr Arc[BaseChannel]](res.addr)[].clone()
