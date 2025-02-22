import misc/timer

## Timer which can be used to check how much async processing has already happened this frame.
## Generally used `gAsyncFrameTimer.elapsed.ms` to get the time in milliseconds.
var gAsyncFrameTimer*: Timer

{.push warning[Deprecated]:off.}
import std/[threadpool]
{.pop.}

# Prevent bs warnings on builtin types (e.g bool) because `=destroy(bool)` raises `Exception` when using `spawn`
type NoExceptionDestroy* = object
func `=destroy`*(x: NoExceptionDestroy) {.raises: [].} = discard

import chronos except asyncDiscard
export chronos except asyncDiscard

proc runAsyncVoid[A](f: proc(options: A) {.gcsafe, raises: [].}, options: A): NoExceptionDestroy {.raises: [].} =
  f(options)

proc runAsync[T, A](f: proc(options: A): T {.gcsafe, raises: [].}, options: A, res: ptr T): NoExceptionDestroy {.raises: [].} =
  res[] = f(options)

proc runAsyncVoid(f: proc() {.gcsafe, raises: [].}): NoExceptionDestroy {.raises: [].} =
  f()

proc runAsync[T](f: proc(): T {.gcsafe, raises: [].}, res: ptr T): NoExceptionDestroy {.raises: [].} =
  res[] = f()

proc spawnAsync*[A](f: proc(options: A) {.gcsafe, raises: [].}, options: A): Future[void] {.async: (raises: [CancelledError]).} =
  let flowVar: FlowVar[NoExceptionDestroy] = spawn runAsyncVoid(f, options)
  while not flowVar.isReady:
    await sleepAsync(10.milliseconds)

proc spawnAsync*[T, A](f: proc(options: A): T {.gcsafe, raises: [], .}, options: A): Future[T] {.async: (raises: [CancelledError]).} =
  var res: T
  let flowVar: FlowVar[NoExceptionDestroy] = spawn runAsync(f, options, res.addr)
  while not flowVar.isReady:
    await sleepAsync(10.milliseconds)

  return res

proc spawnAsync*(f: proc() {.gcsafe, raises: [], .}): Future[void] {.async: (raises: [CancelledError]).} =
  let flowVar: FlowVar[NoExceptionDestroy] = spawn runAsyncVoid(f)
  while not flowVar.isReady:
    await sleepAsync(10.milliseconds)

proc spawnAsync*[T](f: proc(): T {.gcsafe, raises: [], .}): Future[T] {.async: (raises: [CancelledError]).} =
  var res: T
  let flowVar: FlowVar[NoExceptionDestroy] = spawn runAsync(f, res.addr)
  while not flowVar.isReady:
    await sleepAsync(10.milliseconds)

  return res

proc toFuture*[T](value: sink T): Future[T] =
  try:
    result = newFuture[T]()
    result.complete(value)
  except:
    assert false

proc doneFuture*(): Future[void] =
  try:
    result = newFuture[void]()
    result.complete()
  except:
    assert false

proc asyncDiscard*[T](f: Future[T]): Future[void] {.async.} =
  discard await f

template readFinished*[T: not void](fut: Future[T]): lent T =
  try:
    fut.read
  except:
    raiseAssert("Failed to read unfinished future")

proc thenAsync*[T](f: Future[T], cb: proc(f: Future[T]) {.gcsafe, raises: [].}) {.async.} =
  await f
  cb(f)

proc then*[T](f: Future[T], cb: proc(f: Future[T]) {.gcsafe, raises: [].}) =
  asyncSpawn f.thenAsync(cb)

template thenIt*[T](f: Future[T], body: untyped): untyped =
  proc cb(ff: Future[T]) {.gcsafe, raises: [].} =
    when T isnot void:
      let it {.inject.} = ff.read
    body

  f.then(cb)
