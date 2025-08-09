import std/[strformat]
import misc/[event, custom_async]

{.push gcsafe.}

type
  BaseChannel* = ref object of RootObj
    event*: Event[void]

  InMemoryChannel* = ref object of BaseChannel
    isOpen: bool
    isWaiting: bool
    data: seq[uint8] # todo: use something more efficient which doesn't require moving memory

method close*(self: BaseChannel) {.base, raises: [].} = discard
method isOpen*(self: BaseChannel): bool {.base, raises: [].} = false
method peek*(self: BaseChannel): int {.base, raises: [].} = 0
method write*(self: BaseChannel, data: openArray[uint8]) {.base, raises: [IOError].} = discard
method readAll*(self: BaseChannel, res: var seq[uint8]) {.base, raises: [IOError].} = discard
method readAll*(self: BaseChannel, res: var string) {.base, raises: [IOError].} = discard
method read*(self: BaseChannel, len: int, res: var seq[uint8]) {.base, raises: [IOError].} = discard
method read*(self: BaseChannel, len: int, res: var string) {.base, raises: [IOError].} = discard
# method wait*(self: BaseChannel) {.base, async: (raises: []).} = discard
method listen*(self: BaseChannel, cb: proc() {.gcsafe, raises: [].}) {.gcsafe, raises: [].} = discard

proc newInMemoryChannel*(): InMemoryChannel =
  return InMemoryChannel(isOpen: true)

method isOpen*(self: InMemoryChannel): bool = self.isOpen
method close*(self: InMemoryChannel) = self.isOpen = false
method peek*(self: InMemoryChannel): int = self.data.len
method write*(self: InMemoryChannel, data: openArray[uint8]) =
  if data.len > 0:
    let prevLen = self.data.len
    self.data.setLen(prevLen + data.len)
    copyMem(self.data[prevLen].addr, data[0].addr, data.len)

method readAll*(self: InMemoryChannel, res: var seq[uint8]) =
  if self.data.len > 0:
    let prevLen = res.len
    res.setLen(prevLen + self.data.len)
    copyMem(res[prevLen].addr, self.data[0].addr, self.data.len)
    self.data.setLen(0)

method readAll*(self: InMemoryChannel, res: var string) =
  if self.data.len > 0:
    let prevLen = res.len
    res.setLen(prevLen + self.data.len)
    copyMem(res[prevLen].addr, self.data[0].addr, self.data.len)
    self.data.setLen(0)

method read*(self: InMemoryChannel, len: int, res: var seq[uint8]) =
  if self.data.len > 0:
    let available = min(self.data.len, len)
    let prevLen = res.len
    res.setLen(prevLen + available)
    copyMem(res[prevLen].addr, self.data[0].addr, available)
    self.data = self.data[available..^1]

method read*(self: InMemoryChannel, len: int, res: var string) =
  if self.data.len > 0:
    let available = min(self.data.len, len)
    let prevLen = res.len
    res.setLen(prevLen + available)
    copyMem(res[prevLen].addr, self.data[0].addr, available)
    self.data = self.data[available..^1]

# method listen(self: InMemoryChannel) {.async: (raises: []).} =
#   while self.isOpen or self.peek > 0:
#     if self.peek > 0:
#       self.event.invoke()

#     try:
#       await sleepAsync(10.milliseconds)
#     except CatchableError:
#       discard

#   log lvlWarn, &"listen done"

method listen*(self: InMemoryChannel, cb: proc() {.gcsafe, raises: [].}) =
  discard

proc write*(self: BaseChannel, data: string) =
  if data.len > 0:
    self.write(cast[ptr UncheckedArray[uint8]](data.cstring).toOpenArray(0, data.high))

proc pollEvents*(channel: BaseChannel, interval: int) {.async: (raises: []).} =
  while channel.isOpen or channel.peek > 0:
    if channel.peek > 0:
      channel.event.invoke()

    try:
      await sleepAsync(interval.milliseconds)
    except CatchableError:
      discard
  channel.event.invoke()
