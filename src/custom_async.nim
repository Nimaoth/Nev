
when defined(js):
  import std/asyncjs
  export asyncjs

  template asyncCheck*(body: untyped): untyped = discard body
  proc sleepAsync*(ms: int): Future[void] {.importjs: "(new Promise(resolve => setTimeout(resolve, #)))".}
else:
  import std/[asyncdispatch, asyncfile, asyncfutures, threadpool]
  export asyncdispatch, asyncfile, asyncfutures

  proc runAsync[T, A](f: proc(options: A): T {.gcsafe.}, options: A): T =
    return f(options)

  proc spawnAsync*[T, A](f: proc(options: A): T {.gcsafe.}, options: A): Future[T] {.async.} =
    let flowVar: FlowVar[T] = spawn runAsync(f, options)
    while not flowVar.isReady:
      await sleepAsync(1)

    return ^flowVar
