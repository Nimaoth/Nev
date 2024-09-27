import misc/timer

## Timer which can be used to check how much async processing has already happened this frame.
## Generally used `gAsyncFrameTimer.elapsed.ms` to get the time in milliseconds.
var gAsyncFrameTimer*: Timer

when defined(js):
  import std/asyncjs
  export asyncjs

  template asyncCheck*(body: untyped): untyped = discard body
  proc sleepAsync*(ms: int): Future[void] {.importjs: "(new Promise(resolve => setTimeout(resolve, #)))".}

  proc toFuture*[T](value: sink T): Future[T] {.importjs: "(Promise.resolve(#))".}

  # todo: untested
  proc all*(futs: varargs[Future[void]]): Future[void] {.importjs: "Promise.all(#)".}
  proc all*[T](futs: varargs[Future[T]]): Future[seq[T]] {.importjs: "Promise.all(#)".}

else:
  import std/[threadpool]
  import chronos
  export chronos
  # import std/[asyncdispatch, asyncfile, asyncfutures, threadpool]
  # export asyncdispatch, asyncfile, asyncfutures

  proc runAsyncVoid[A](f: proc(options: A) {.gcsafe, raises: [].}, options: A): bool {.raises: [].} =
    f(options)
    return true

  proc runAsync[T, A](f: proc(options: A): T {.gcsafe, raises: [].}, options: A): T {.raises: [].} =
    return f(options)

  proc runAsyncVoid(f: proc() {.gcsafe, raises: [].}): bool {.raises: [].} =
    f()
    return true

  proc runAsync[T](f: proc(): T {.gcsafe, raises: [].}): T {.raises: [].} =
    return f()

  proc spawnAsync*[A](f: proc(options: A) {.gcsafe, raises: [].}, options: A): Future[void] {.async: (raises: [CancelledError]).} =
    let flowVar: FlowVarBase = spawn runAsyncVoid(f, options)
    while not flowVar.isReady:
      await sleepAsync(10.milliseconds)

  proc spawnAsync*[T, A](f: proc(options: A): T {.gcsafe, raises: [], .}, options: A): Future[T] {.async: (raises: [CancelledError]).} =
    let flowVar: FlowVar[T] = spawn runAsync(f, options)
    while not flowVar.isReady:
      await sleepAsync(10.milliseconds)

    return ^flowVar

  proc spawnAsync*(f: proc() {.gcsafe, raises: [], .}): Future[void] {.async: (raises: [CancelledError]).} =
    let flowVar: FlowVarBase = spawn runAsyncVoid(f)
    while not flowVar.isReady:
      await sleepAsync(10.milliseconds)

  proc spawnAsync*[T](f: proc(): T {.gcsafe, raises: [], .}): Future[T] {.async: (raises: [CancelledError]).} =
    let flowVar: FlowVar[T] = spawn runAsync(f)
    while not flowVar.isReady:
      await sleepAsync(10.milliseconds)

    return ^flowVar

  proc toFuture*[T](value: sink T): Future[T] =
    result = newFuture[T]()
    result.complete(value)

  proc doneFuture*(): Future[void] =
    result = newFuture[void]()
    result.complete()

template thenIt*[T](f: Future[T], body: untyped): untyped =
  when defined(js):
    discard f.then(proc(a: T) =
      let it {.inject.} = a
      body
    )
  else:
    f.addCallback(proc(a: Future[T]) =
      let it {.inject.} = a.read
      body
    )

type
  ResolvableFuture*[T] = object
    future*: Future[T]
    when defined(js):
      resolve: proc(result: T)

proc complete*[T](future: ResolvableFuture[T], result: sink T) =
  when defined(js):
    future.resolve(result)
  else:
    future.future.complete(result)

proc complete*(future: ResolvableFuture[void]) =
  when defined(js):
    future.resolve()
  else:
    future.future.complete()

proc newResolvableFuture*[T](name: static string): ResolvableFuture[T] =
  when defined(js):
    var resolveFunc: proc(value: T) = nil
    var requestFuture = newPromise[T](proc(resolve: proc(value: T)) =
      resolveFunc = resolve
    )
    result = ResolvableFuture[T](future: requestFuture, resolve: resolveFunc)

  else:
    var requestFuture = newFuture[T](name)
    result = ResolvableFuture[T](future: requestFuture)

# proc all*[T](futs: varargs[Future[T]]): auto =
#   ## Returns a future which will complete once
#   ## all futures in `futs` complete.
#   ## If the argument is empty, the returned future completes immediately.
#   ##
#   ## If the awaited futures are not `Future[void]`, the returned future
#   ## will hold the values of all awaited futures in a sequence.
#   ##
#   ## If the awaited futures *are* `Future[void]`,
#   ## this proc returns `Future[void]`.

#   when T is void:
#     var
#       retFuture = newFuture[void]("asyncdispatch.all")
#       completedFutures = 0

#     let totalFutures = len(futs)

#     for fut in futs:
#       fut.addCallback proc (f: Future[T]) =
#         inc(completedFutures)
#         if not retFuture.finished:
#           if f.failed:
#             retFuture.fail(f.error)
#           else:
#             if completedFutures == totalFutures:
#               retFuture.complete()

#     if totalFutures == 0:
#       retFuture.complete()

#     return retFuture

#   else:
#     var
#       retFuture = newFuture[seq[T]]("asyncdispatch.all")
#       retValues = newSeq[T](len(futs))
#       completedFutures = 0

#     for i, fut in futs:
#       proc setCallback(i: int) =
#         fut.addCallback proc (f: Future[T]) =
#           inc(completedFutures)
#           if not retFuture.finished:
#             if f.failed:
#               retFuture.fail(f.error)
#             else:
#               retValues[i] = f.read()

#               if completedFutures == len(retValues):
#                 retFuture.complete(retValues)

#       setCallback(i)

#     if retValues.len == 0:
#       retFuture.complete(retValues)

#     return retFuture