## Background PNG writer for SDL screen captures.
##
## The main thread reads pixels back from the GPU (`renderReadPixels`) and hands
## the surface to worker threads which convert and encode it, so recording
## doesn't stall frames on PNG encoding. Files are written to a temp path and
## renamed so readers never see partially written files.

import std/[locks, os, typedthreads]
import nuigi/backend/sdl3/sdl3

{.push gcsafe.}
{.push raises: [].}

type
  CaptureJob = object
    surface: ptr Surface
    path: string
    extraFiles: seq[(string, string)]  ## (path, content), written after the image in order

  CaptureQueue = object
    lock: Lock
    cond: Cond
    jobs: seq[CaptureJob]
    busyPaths: seq[string]  ## Paths currently being written by a worker
    stop: bool
    errors: seq[string]

const workerCount = 3

var captureQueue: CaptureQueue
var captureThreads: array[workerCount, Thread[void]]
var captureThreadStarted = false
var captureThreadCount = 0

proc writeFileAtomic(path, content: string): string =
  ## Returns an error message, or "" on success.
  try:
    createDir(path.parentDir)
    let tempPath = path & ".tmp"
    writeFile(tempPath, content)
    moveFile(tempPath, path)
    ""
  except CatchableError as e:
    "Failed to write '" & path & "': " & e.msg

proc processJob(job: CaptureJob): seq[string] =
  # Drop alpha so the PNG looks like what was presented.
  let converted = convertSurface(job.surface, PIXELFORMAT_RGB24)
  destroySurface(job.surface)
  if converted == nil:
    result.add "Failed to convert screenshot surface: " & $getError()
  else:
    try:
      createDir(job.path.parentDir)
      let tempPath = job.path & ".tmp"
      if savePNG(converted, tempPath.cstring):
        moveFile(tempPath, job.path)
      else:
        result.add "Failed to save '" & job.path & "': " & $getError()
    except CatchableError as e:
      result.add "Failed to save '" & job.path & "': " & e.msg
    destroySurface(converted)

  for (path, content) in job.extraFiles:
    let error = writeFileAtomic(path, content)
    if error.len > 0:
      result.add error

proc nextRunnableJob(): int =
  ## Jobs for a path another worker is writing must wait, so writes to the same
  ## path (e.g. the debug dir's screen.png) stay in order. Requires the lock.
  {.cast(gcsafe).}:
    for i, job in captureQueue.jobs:
      if job.path notin captureQueue.busyPaths:
        return i
  return -1

proc captureWorker() {.thread.} =
  {.cast(gcsafe).}:
    while true:
      var job: CaptureJob
      withLock captureQueue.lock:
        var index = nextRunnableJob()
        while index == -1 and not (captureQueue.stop and captureQueue.jobs.len == 0):
          wait(captureQueue.cond, captureQueue.lock)
          index = nextRunnableJob()
        if index == -1:
          break
        job = move captureQueue.jobs[index]
        captureQueue.jobs.delete(index)
        captureQueue.busyPaths.add job.path

      let errors = processJob(job)

      withLock captureQueue.lock:
        let busyIndex = captureQueue.busyPaths.find(job.path)
        if busyIndex != -1:
          captureQueue.busyPaths.del(busyIndex)
        captureQueue.errors.add errors
        broadcast(captureQueue.cond)

proc startCaptureWorker(): bool =
  if captureThreadStarted:
    return true
  {.cast(gcsafe).}:
    initLock(captureQueue.lock)
    initCond(captureQueue.cond)
    for i in 0..<workerCount:
      try:
        createThread(captureThreads[i], captureWorker)
        captureThreadCount = i + 1
      except ResourceExhaustedError:
        break
    if captureThreadCount == 0:
      deinitCond(captureQueue.cond)
      deinitLock(captureQueue.lock)
      return false
    captureThreadStarted = true
    return true

proc enqueueCapture*(surface: ptr Surface, path: string,
    extraFiles: seq[(string, string)] = @[], maxPending = int.high): bool =
  ## Takes ownership of `surface`. A pending job with the same `path` is replaced
  ## (latest frame wins). Returns false (and frees the surface) when more than
  ## `maxPending` jobs are queued or in progress, or the worker can't start.
  if surface == nil:
    return false
  if not startCaptureWorker():
    destroySurface(surface)
    return false
  {.cast(gcsafe).}:
    withLock captureQueue.lock:
      for job in captureQueue.jobs.mitems:
        if job.path == path:
          destroySurface(job.surface)
          job.surface = surface
          job.extraFiles = extraFiles
          return true
      if captureQueue.jobs.len + captureQueue.busyPaths.len >= maxPending:
        destroySurface(surface)
        return false
      captureQueue.jobs.add CaptureJob(surface: surface, path: path, extraFiles: extraFiles)
      signal(captureQueue.cond)
  return true

proc takeCaptureErrors*(): seq[string] =
  if not captureThreadStarted:
    return
  {.cast(gcsafe).}:
    withLock captureQueue.lock:
      swap(result, captureQueue.errors)

proc stopCaptureWorker*() =
  ## Writes all pending captures, then stops the workers.
  if not captureThreadStarted:
    return
  {.cast(gcsafe).}:
    withLock captureQueue.lock:
      captureQueue.stop = true
      broadcast(captureQueue.cond)
    for i in 0..<captureThreadCount:
      joinThread(captureThreads[i])
    captureThreadCount = 0
    captureThreadStarted = false
    captureQueue.stop = false
    deinitCond(captureQueue.cond)
    deinitLock(captureQueue.lock)
