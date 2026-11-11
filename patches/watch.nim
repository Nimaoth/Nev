import fsnotify/timers
import std/os
import fsnotify/base
export base

when defined(windows):
  import fsnotify/[windir, filepoll]
  export windir, filepoll
elif defined(linux):
  import fsnotify/linpath
  export linpath
elif defined(macosx):
  import fsnotify/macpath
  export macpath

type
  Watcher* = object
    timer: Timer
    path: seq[PathEventData]

proc initWatcher*(): Watcher =
  discard

proc register*(watcher: var Watcher, path: string, cb: EventCallback,
               treatAsFile = false) =
  let idx = watcher.path.len
  let pathData =
    if fileExists(path):
      initFileEventData(path, cb)
    elif dirExists(path):
      initDirEventData(path, cb)
    elif treatAsFile:
      initFileEventData(path, cb)
    else:
      initDirEventData(path, cb)

  watcher.path.add pathData

  case pathData.kind
  of PathKind.File:
    let event = initTimerEvent(filecb, watcher.path[idx])
    watcher.timer.add(event)
  of PathKind.Dir:
    let event = initTimerEvent(dircb, watcher.path[idx])
    watcher.timer.add(event)

proc register*(watcher: var Watcher, pathList: seq[string], cb: EventCallback,
               treatAsFile = false) =
  for path in pathList:
    watcher.register(path, cb, treatAsFile)

when defined(windows):
  proc close*(data: var PathEventData) =
    case data.kind
    of PathKind.File:
      closeFileEventData(data)
    of PathKind.Dir:
      closeDirEventData(data)

  proc close*(watcher: var Watcher) =
    watcher.timer.queue.setLen(0)
    var firstError = ""
    for path in watcher.path.mitems:
      try:
        path.close()
      except OSError as error:
        if firstError.len == 0:
          firstError = error.msg
    watcher.path.setLen(0)
    if firstError.len != 0:
      raise newException(OSError, firstError)

template process*(watcher: var Watcher, maxDurationMs: int = 1) =
  ## Processes watched paths for at most `maxDurationMs` milliseconds.
  process(watcher.timer, maxDurationMs)

proc poll*(watcher: var Watcher, ms = 100) =
  sleep(ms)
  process(watcher)

when isMainModule:
  block:
    proc hello(event: seq[PathEvent]) =
      echo "Hello: "
      echo event

    var watcher = initWatcher()
    register(watcher, "/root/play", hello)

    while true:
      poll(watcher, 300)
