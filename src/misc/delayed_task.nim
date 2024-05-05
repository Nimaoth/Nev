import std/times
import custom_async

type
  DelayedTask* = ref object
    restartCounter: int
    active: bool
    interval*: int64
    nextTick: Time
    repeat: bool
    callback: proc()

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
      await sleepAsync(timeToNextTick.inMilliseconds.int)

    if task.restartCounter != restartCounter:
      return

    task.reschedule()
    task.callback()

    if not task.repeat:
      break

proc reschedule*(task: DelayedTask) =
  task.nextTick = getTime() + initDuration(milliseconds=task.interval)
  if not task.isActive:
    asyncCheck task.tick()

proc newDelayedTask*(interval: int, repeat: bool, autoActivate: bool, callback: proc()): DelayedTask =
  result = DelayedTask(interval: interval.int64, repeat: repeat, callback: callback)
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
