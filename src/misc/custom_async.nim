
when defined(js):
  import std/asyncjs
  export asyncjs

  template asyncCheck*(body: untyped): untyped = discard body
  proc sleepAsync*(ms: int): Future[void] {.importjs: "(new Promise(resolve => setTimeout(resolve, #)))".}

  proc toFuture*[T](value: sink T): Future[T] {.importjs: "(Promise.resolve(#))".}

else:
  import std/[asyncdispatch, asyncfile, asyncfutures, threadpool]
  export asyncdispatch, asyncfile, asyncfutures

  proc runAsyncVoid[A](f: proc(options: A) {.gcsafe.}, options: A): bool =
    f(options)
    return true

  proc runAsync[T, A](f: proc(options: A): T {.gcsafe.}, options: A): T =
    return f(options)

  proc runAsyncVoid(f: proc() {.gcsafe.}): bool =
    f()
    return true

  proc runAsync[T](f: proc(): T {.gcsafe.}): T =
    return f()

  proc spawnAsync*[A](f: proc(options: A) {.gcsafe.}, options: A): Future[void] {.async.} =
    let flowVar: FlowVarBase = spawn runAsyncVoid(f, options)
    while not flowVar.isReady:
      await sleepAsync(1)

  proc spawnAsync*[T, A](f: proc(options: A): T {.gcsafe.}, options: A): Future[T] {.async.} =
    let flowVar: FlowVar[T] = spawn runAsync(f, options)
    while not flowVar.isReady:
      await sleepAsync(1)

    return ^flowVar

  proc spawnAsync*(f: proc() {.gcsafe.}): Future[void] {.async.} =
    let flowVar: FlowVarBase = spawn runAsyncVoid(f)
    while not flowVar.isReady:
      await sleepAsync(1)

  proc spawnAsync*[T](f: proc(): T {.gcsafe.}): Future[T] {.async.} =
    let flowVar: FlowVar[T] = spawn runAsync(f)
    while not flowVar.isReady:
      await sleepAsync(1)

    return ^flowVar

  proc toFuture*[T](value: sink T): Future[T] =
    result = newFuture[T]()
    result.complete(value)

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

proc newResolvableFuture*[T](name: string): ResolvableFuture[T] =
  when defined(js):
    var resolveFunc: proc(value: T) = nil
    var requestFuture = newPromise[T](proc(resolve: proc(value: T)) =
      resolveFunc = resolve
    )
    result = ResolvableFuture[T](future: requestFuture, resolve: resolveFunc)

  else:
    var requestFuture = newFuture[T](name)
    result = ResolvableFuture[T](future: requestFuture)