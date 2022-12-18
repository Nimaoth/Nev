import asyncdispatch, asyncnet, json, strutils, tables, os, osproc, streams, threadpool, options, macros

type AsyncChannel*[T] = ref object
  chan: ptr Channel[T]

type AsyncProcess* = ref object
  name: string
  onRestarted*: proc(): Future[void]
  process: Process
  input: AsyncChannel[char]
  output: AsyncChannel[Option[string]]
  inputStreamChannel: ptr Channel[Stream]
  outputStreamChannel: ptr Channel[Stream]
  serverDiedNotifications: ptr Channel[bool]

proc newAsyncChannel*[T](): AsyncChannel[T] =
  new result
  result.chan = cast[ptr Channel[T]](allocShared0(sizeof(Channel[T])))
  result.chan[].open()

proc destroy*[T](channel: AsyncChannel[T]) =
  channel.chan.deallocShared
  channel.chan = nil

proc destroy*(process: AsyncProcess) =
  process.process.terminate()
  process.input.destroy()
  process.output.destroy()
  process.inputStreamChannel.deallocShared
  process.outputStreamChannel.deallocShared
  process.serverDiedNotifications.deallocShared

proc recv*[T: char](achan: AsyncChannel[T], amount: int): Future[string] {.async.} =
  var buffer = ""
  while buffer.len < amount:
    while buffer.len < amount and achan.chan[].peek > 0:
      let c = achan.chan[].recv
      if c == '\0':
        # End of input
        return buffer

      buffer.add c

    if buffer.len < amount:
      await sleepAsync 1
  return buffer

proc recvLine*[T: char](achan: AsyncChannel[T]): Future[string] {.async.} =
  var buffer = ""

  var cr = false
  while true:
    while achan.chan[].peek > 0:
      let c = achan.chan[].recv
      if c == '\0':
        # End of input
        return buffer

      if c != '\r' and c != '\n':
        cr = false
        buffer.add c
      elif c == '\r':
        cr = true
      elif c == '\n':
        if cr and buffer.len == 0:
          return "\r\n"
        cr = false
        return buffer
    await sleepAsync 1

  return ""

proc send*[T](achan: AsyncChannel[Option[T]], data: T) {.async.} =
  while not achan.chan[].trySend(data.some):
    await sleepAsync 1

proc recv*(process: AsyncProcess, amount: int): Future[string] = process.input.recv(amount)
proc recvLine*(process: AsyncProcess): Future[string] = process.input.recvLine()
proc send*(process: AsyncProcess, data: string): Future[void] = process.output.send(data)

proc startAsyncProcess*(name: string): AsyncProcess =
  new result
  result.name = name
  result.input = newAsyncChannel[char]()
  result.output = newAsyncChannel[Option[string]]()

  result.inputStreamChannel = cast[ptr Channel[Stream]](allocShared0(sizeof(Channel[Stream])))
  result.inputStreamChannel[].open()

  result.outputStreamChannel = cast[ptr Channel[Stream]](allocShared0(sizeof(Channel[Stream])))
  result.outputStreamChannel[].open()

  result.serverDiedNotifications = cast[ptr Channel[bool]](allocShared0(sizeof(Channel[bool])))
  result.serverDiedNotifications[].open()

  proc readInput(chan: ptr Channel[Stream], serverDiedNotifications: ptr Channel[bool], data: ptr Channel[char], data2: ptr Channel[Option[string]]) =
    while true:
      let stream = chan[].recv
      # echo "readInput"

      while true:
        let c = stream.readChar()

        data[].send c

        if c == '\0':
          # echo "server died"
          data2[].send string.none
          serverDiedNotifications[].send true
          break
        # else:
          # echo "< " & c

  proc writeOutput(chan: ptr Channel[Stream], data: ptr Channel[Option[string]]) =
    var buffer: seq[string]
    while true:
      let stream = chan[].recv
      # echo "writeOutput"

      while true:
        let d = data[].recv
        if d.isNone:
          # echo "data none"
          buffer.setLen 0
          break

        # echo "> " & d.get
        buffer.add d.get

        for d in buffer:
          stream.write(d)
        buffer.setLen 0

  proc restartServer(process: AsyncProcess) {.async.} =
    while true:
      while process.serverDiedNotifications[].peek == 0:
        # echo "process active"
        await sleepAsync(1)

      # echo "process dead"
      while process.serverDiedNotifications[].peek > 0:
        discard process.serverDiedNotifications[].recv

      echo "[process] start"
      process.process = startProcess(process.name)

      spawn readInput(process.inputStreamChannel, process.serverDiedNotifications, process.input.chan, process.output.chan)
      process.inputStreamChannel[].send process.process.outputStream()

      spawn writeOutput(process.outputStreamChannel, process.output.chan)
      process.outputStreamChannel[].send process.process.inputStream()

      if not process.onRestarted.isNil:
        asyncCheck process.onRestarted()

  asyncCheck restartServer(result)
  result.serverDiedNotifications[].send true