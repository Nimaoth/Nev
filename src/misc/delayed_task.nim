import std/times
import custom_async

when defined(debugDelayedTasks):
  import std/strutils

{.push gcsafe.}
{.push raises: [].}

type
  DelayedTask* = ref object
    restartCounter: int
    active: bool
    interval*: int64
    nextTick: Time
    repeat: bool
    callback: proc() {.gcsafe, raises: [].}
    callbackAsync: proc(): Future[void] {.gcsafe, async: (raises: []).}
    when defined(debugDelayedTasks):
      creationStackTrace: string

func isActive*(task: DelayedTask): bool = task.active
proc reschedule*(task: DelayedTask)

proc tick(task: DelayedTask): Future[void] {.async.} =
  let restartCounter = task.restartCounter

  defer:
    if task.restartCounter == restartCounter:
      task.active = false

  task.active = true

  while true:
    while true:
      let now = getTime()
      if now >= task.nextTick:
        break

      let timeToNextTick = task.nextTick - now
      assert timeToNextTick > initDuration()
      when defined(debugDelayedTasks):
        echo "====================== Tick DelayedTask"
        echo task.creationStackTrace.indent(2)

      try:
        await sleepAsync(chronos.milliseconds(timeToNextTick.inMilliseconds.int))
      except CancelledError:
        break

    if task.restartCounter != restartCounter:
      return

    task.reschedule()
    if task.callback != nil:
      task.callback()
    else:
      await task.callbackAsync()

    if not task.repeat:
      break

proc reschedule*(task: DelayedTask) =
  task.nextTick = getTime() + initDuration(milliseconds=task.interval)
  if not task.isActive:
    asyncSpawn task.tick()

proc schedule*(task: DelayedTask) =
  if not task.isActive:
    task.nextTick = getTime() + initDuration(milliseconds=task.interval)
    asyncSpawn task.tick()

proc newDelayedTask*(interval: int, repeat: bool, autoActivate: bool, callback: proc() {.gcsafe, raises: [].}): DelayedTask =
  result = DelayedTask(interval: interval.int64, repeat: repeat, callback: callback)
  when defined(debugDelayedTasks):
    result.creationStackTrace = getStackTrace()
  if autoActivate:
    result.reschedule()

proc newDelayedTask*(interval: int, repeat: bool, autoActivate: bool, callback: proc(): Future[void] {.gcsafe, async: (raises: []).}): DelayedTask =
  result = DelayedTask(interval: interval.int64, repeat: repeat, callbackAsync: callback)
  when defined(debugDelayedTasks):
    result.creationStackTrace = getStackTrace()
  if autoActivate:
    result.reschedule()

proc pause*(task: DelayedTask) =
  task.restartCounter.inc
  task.active = false

proc deinit*(task: DelayedTask) =
  task.pause()
  task.callback = nil

template startDelayed*(interval: int, repeat: bool = false, body: untyped): untyped =
  newDelayedTask(interval, repeat, true, proc() =
    body
  )

template startDelayedPaused*(interval: int, repeat: bool = false, body: untyped): untyped =
  newDelayedTask(interval, repeat, false, proc() =
    body
  )

template startDelayedAsync*(interval: int, repeat: bool = false, body: untyped): untyped =
  newDelayedTask(interval, repeat, true, proc() {.async: (raises: []).} =
    body
  )
