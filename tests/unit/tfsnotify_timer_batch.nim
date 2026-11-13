import std/[os, unittest]
import fsnotify/[base, timers, watch]

var callbacksRun {.threadvar.}: int

proc countCallback(data: var PathEventData) {.gcsafe.} =
  inc callbacksRun
  sleep(3)

suite "fsnotify timer batches":
  test "processing resumes at the next event":
    callbacksRun = 0
    var timer = initTimer()
    for _ in 0 ..< 3:
      timer.add(initTimerEvent(countCallback, default(PathEventData)))

    timer.process()
    check callbacksRun == 1
    timer.process()
    check callbacksRun == 2
    timer.process()
    check callbacksRun == 3
    timer.process()
    check callbacksRun == 4

  test "watcher process accepts a time budget":
    var watcher = initWatcher()
    process(watcher, 2)
