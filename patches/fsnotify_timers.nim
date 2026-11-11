import std/[monotimes, times]
import fsnotify/base
import nuigi/debug/profiler

type
  Callback* = proc(args: var PathEventData) {.gcsafe.}

  TimerEvent* = object
    userData*: PathEventData
    cb*: Callback

  Timer* = object
    queue*: seq[TimerEvent]
    nextIndex: int

proc initTimerEvent*(cb: Callback, userData: PathEventData): TimerEvent =
  TimerEvent(cb: cb, userData: userData)

proc initTimer*(): Timer =
  discard

proc add*(timer: var Timer, event: TimerEvent) =
  if timer.queue.len == 0:
    timer.nextIndex = 0
  timer.queue.add(event)

proc execute*(t: var TimerEvent) =
  if t.cb != nil:
    t.cb(t.userData)

proc process*(timer: var Timer, maxDurationMs: int = 1) =
  ## Processes timer events for at most `maxDurationMs` milliseconds.
  ## Processing resumes from the next event on the following call.
  if maxDurationMs <= 0:
    return

  if timer.nextIndex >= timer.queue.len:
    timer.nextIndex = 0

  if timer.queue.len == 0:
    return

  let deadline = getMonoTime() + initDuration(milliseconds = maxDurationMs)
  let batchEnd = timer.queue.len
  while timer.nextIndex < min(batchEnd, timer.queue.len):
    block:
      prof("fsnotify.Timer.process")
      let eventIndex = timer.nextIndex
      inc timer.nextIndex
      if timer.queue[eventIndex].cb != nil:
        timer.queue[eventIndex].cb(timer.queue[eventIndex].userData)

    if getMonoTime() >= deadline:
      break

  if timer.nextIndex >= batchEnd or timer.nextIndex >= timer.queue.len:
    timer.nextIndex = 0
