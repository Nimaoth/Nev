
when defined(js):
  import std/asyncjs
  export asyncjs

  template asyncCheck*(body: untyped): untyped = discard body
  proc sleepAsync*(ms: int): Future[void] {.importjs: "(new Promise(resolve => setTimeout(resolve, #)))".}
else:
  import std/[asyncdispatch, asyncfile, asyncfutures, threadpool]
  export asyncdispatch, asyncfile, asyncfutures

  proc runAsyncVoid[A](f: proc(options: A) {.gcsafe.}, options: A): bool =
    f(options)
    return true

  proc runAsync[T, A](f: proc(options: A): T {.gcsafe.}, options: A): T =
    return f(options)

  proc spawnAsync*[A](f: proc(options: A) {.gcsafe.}, options: A): Future[void] {.async.} =
    let flowVar: FlowVarBase = spawn runAsyncVoid(f, options)
    while not flowVar.isReady:
      await sleepAsync(1)

  proc spawnAsync*[T, A](f: proc(options: A): T {.gcsafe.}, options: A): Future[T] {.async.} =
    let flowVar: FlowVar[T] = spawn runAsync(f, options)
    while not flowVar.isReady:
      await sleepAsync(1)

    return ^flowVar
