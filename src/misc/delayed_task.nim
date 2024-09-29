import std/times
import custom_async

when defined(debugDelayedTasks):
  import std/strutils

type
  DelayedTask* = ref object
    restartCounter: int
    active: bool
    interval*: int64
    nextTick: Time
    repeat: bool
    callback: proc() {.gcsafe, raises: [].}
    when defined(debugDelayedTasks):
      creationStackTrace: string

func isActive*(task: DelayedTask): bool {.gcsafe, raises: [].} = task.active
proc reschedule*(task: DelayedTask) {.gcsafe, raises: [].}

proc tick(task: DelayedTask): Future[void] {.gcsafe, async.} =
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
        when defined(nevUseChronos):
          await sleepAsync(chronos.milliseconds(timeToNextTick.inMilliseconds.int))
        else:
          await sleepAsync(timeToNextTick.inMilliseconds.int)
      except CancelledError:
        break

    if task.restartCounter != restartCounter:
      return

    task.reschedule()
    task.callback()

    if not task.repeat:
      break

proc reschedule*(task: DelayedTask) {.gcsafe, raises: [].} =
  task.nextTick = getTime() + initDuration(milliseconds=task.interval)
  if not task.isActive:
    asyncSpawn task.tick()

proc schedule*(task: DelayedTask) {.gcsafe, raises: [].} =
  if not task.isActive:
    task.nextTick = getTime() + initDuration(milliseconds=task.interval)
    asyncSpawn task.tick()

proc newDelayedTask*(interval: int, repeat: bool, autoActivate: bool, callback: proc() {.gcsafe, raises: [].}): DelayedTask {.gcsafe, raises: [].} =
  result = DelayedTask(interval: interval.int64, repeat: repeat, callback: callback)
  when defined(debugDelayedTasks):
    result.creationStackTrace = getStackTrace()
  if autoActivate:
    result.reschedule()

proc pause*(task: DelayedTask) {.gcsafe, raises: [].} =
  task.restartCounter.inc
  task.active = false

proc deinit*(task: DelayedTask) {.gcsafe, raises: [].} =
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
