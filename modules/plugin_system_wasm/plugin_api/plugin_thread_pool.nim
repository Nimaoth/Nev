
import std/[macros, strformat, tables]
import misc/[custom_async, util]
import nimsumtree/[arc]

type
  InstanceThreadState*[T] = object
    handler: proc(instance: sink Arc[T]) {.nimcall, gcsafe, raises: [].}
    instance: Arc[T]

  WorkerThreadState*[T] = object
    thread: Arc[Thread[WorkerThreadState[T]]]
    channel: Arc[Channel[InstanceThreadState[T]]]
    handler: proc(instance: sink Arc[T]) {.nimcall, gcsafe, raises: [].}

  PluginThreadPool*[T] = object
    threads: seq[Arc[Thread[WorkerThreadState[T]]]]
    channel: Arc[Channel[InstanceThreadState[T]]]
    handler: proc(instance: sink Arc[T]) {.nimcall, gcsafe, raises: [].}

proc workerThread[T](state: WorkerThreadState[T]) {.thread, nimcall, gcsafe.} =
  chronosDontSkipCallbacksAtStart = true

  while true:
    let s = state.channel.getMutUnsafe.recv()
    if s.instance.isNil:
      break
    if s.handler != nil:
      s.handler(s.instance)
    else:
      state.handler(s.instance)

proc addTask*[T](self: var PluginThreadPool[T], instance: sink Arc[T], handler: proc(instance: sink Arc[T]) {.nimcall, gcsafe, raises: [].} = nil) =
  var data = InstanceThreadState[T](
    instance: instance.ensureMove,
    handler: handler,
  )
  self.channel.getMutUnsafe.send(data.ensureMove)

proc newPluginThreadPool*[T](num: int, handler: proc(instance: sink Arc[T]) {.nimcall, gcsafe, raises: [].}): PluginThreadPool[T] =
  result = PluginThreadPool[T](
    channel: Arc[Channel[InstanceThreadState[T]]].new(),
    handler: handler,
  )
  result.channel.getMut.open()

  try:
    for i in 0..<num:
      var thread = Arc[Thread[WorkerThreadState[T]]].new()
      var state = WorkerThreadState[T](
        thread: thread,
        channel: result.channel,
        handler: handler,
      )
      {.push warning[BareExcept]:off.}
      thread.getMutUnsafe.createThread(workerThread, state)
      {.pop.}
      result.threads.add(thread)
  except ResourceExhaustedError as e:
    echo &"Failed to create plugin thread pool: {e.msg}"
