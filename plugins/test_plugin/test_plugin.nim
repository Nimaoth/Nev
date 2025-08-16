import std/[strformat, json, jsonutils, strutils]
import results
import util, render_command, binary_encoder
import api

var views: seq[RenderView] = @[]
var renderCommandEncoder: BinaryEncoder
var num = 1

converter toWitString(s: string): WitString = ws(s)
var target = 50

proc handleViewRender(id: int32, data: uint32) {.cdecl.}

proc openCustomView(show: bool) =
  var renderView = renderViewFromUserId(ws"test_plugin_view")
  if renderView.isNone:
    echo "[guest] Create new RenderView"
    renderView = newRenderView().some
  else:
    echo "[guest] Reusing existing RenderView"
  renderView.get.setUserId(ws"test_plugin_view")
  renderView.get.setRenderWhenInactive(true)
  renderView.get.setPreventThrottling(true)
  renderView.get.setRenderCallback(cast[uint32](handleViewRender), views.len.uint32)
  renderView.get.addMode(ws"test-plugin")
  renderView.get.markDirty()
  if show:
    show(renderView.get.view, ws"#new-tab", true, true)
  views.add(renderView.take)

proc handleViewRender(id: int32, data: uint32) {.cdecl.} =
  let index = data.int
  if index notin 0..views.high:
    echo "handleViewRender: index out of bounds {index} notin 0..<{views.len}"
    return

  let view {.cursor.} = views[index]

  try:
    let version = apiVersion()
    inc num
    if num > target:
      num = 1

    num = target

    proc vec2(v: Vec2f): Vec2 = vec2(v.x, v.y)

    let size = vec2(view.size)
    # echo &"[guest] size: {size}"

    let s = if size.x > 500:
      vec2(20, 20)
    else:
      vec2(1, 1)
    renderCommandEncoder.buffer.setLen(0)
    buildCommands(renderCommandEncoder):
      for y in 0..<num:
        for x in 0..<num:
          fillRect(rect(vec2(x.float, y.float) * s, s), color(0, x.float / num.float, y.float / num.float, 1))

      drawText("test_plugin version " & $version, rect(size * 0.5, vec2()), color(0.5, 0.5, 1, 1), 0.UINodeFlags)

    # view.setRenderCommandsRaw(cast[uint32](renderCommandEncoder.buffer[0].addr), renderCommandEncoder.buffer.len.uint32)
    view.setRenderCommands(@@(renderCommandEncoder.buffer.toOpenArray(0, renderCommandEncoder.buffer.high)))

    let interval = getSetting("test.render-interval", 500)
    view.setRenderInterval(interval)
  except Exception as e:
    echo &"[guest] Failed to render: {e.msg}\n{e.getStackTrace()}"

defineCommand(ws"test-command-1",
  active = false,
  docs = ws"Decrease the size of the square",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      echo &"[guest] test-command-1 {data} '{args}'"
      inc target
      views[0].markDirty()
    except CatchableError as e:
      echo &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"test-command-2",
  active = false,
  docs = ws"Increase the size of the square",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      echo &"[guest] test-command-2 {data} '{args}'"
      dec target
      views[0].markDirty()
    except CatchableError as e:
      echo &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"open-custom-view",
  active = false,
  docs = ws"Open the custom view",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    openCustomView(show = true)
    return ws""

defineCommand(ws"test-command-5",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    if activeTextEditor().getSome(editor):
      let s = editor.getSelection
      let d = editor.content
      echo editor.id
      echo "========== ", s
      echo editor.command(ws"vim-move-cursor-column", ws"5")
    return ws""

defineCommand(ws"test-load-file",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    echo "============ read app://README.md"
    var res = readSync("app://README.md", {})
    if res.isOk:
      echo &"read {res.value.len} bytes"
    else:
      echo res

    echo "============ read app://src/../README.md"
    res = readSync("app://src/../README.md", {})
    if res.isOk:
      echo &"read {res.value.len} bytes"
    else:
      echo res

    echo "============ read app://src/nev.nim"
    res = readSync("app://src/nev.nim", {})
    if res.isOk:
      echo &"read {res.value.len} bytes"
    else:
      echo res

    echo "============ read app://src/nev.nim"
    let res2 = readRopeSync("app://src/nev.nim", {})
    if res2.isOk:
      echo &"read {res2.value.bytes} bytes, {res2.value.runes} runes, {res2.value.lines} lines"
      echo res2.value.text
    else:
      echo res2

    echo "============ write app://temp/uiae.txt"
    echo writeSync("app://temp/uiae.txt", "hello from\ntest_plugin")

    echo vfs.localize("app://temp/uiae.txt")
    return ws""

defineCommand(ws"test-start-process",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    if activeTextEditor().getSome(editor):
      let s = editor.getSelection
      let d = editor.content

      var p = processStart(ws"powershell", @@[ws"-Command", ws"ls", ws"plugins"])
      let stdout = p.stdout()

      var buffer = ""
      stdout.listen proc: ChannelListenResponse =
        let s = $stdout.readAllString()
        buffer.add s
        if stdout.atEnd:
          if buffer.endsWith("\0"):
            buffer.setLen(buffer.len - 1)
          let selections = editor.edit(@@[editor.getSelection], @@[ws(buffer.replace("\r", ""))])
          if selections.len > 0:
            editor.setSelection(selections[0].last.toSelection)
          return Stop
        return Continue


    else:
      echo "Not in a text editor"

    return ws""

type Shell = ref object
  process: Process
  stdout: BufferedReadChannel
  stdin: WriteChannel

var shellProcess: Shell = nil

defineCommand(ws"test-shell",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    var p = processStart(ws"powershell", wl[WitString]())
    var process = Shell(stdout: p.stdout().buffered, stdin: p.stdin(), process: p.ensureMove)
    shellProcess = process

    process.stdout.chan.listen proc(): ChannelListenResponse =
      let s = $process.stdout.chan.readAllString()
      echo "\n" & s
      if process.stdout.atEnd:
        echo "============= done"
        return Stop
      return Continue

    return ws""

proc readShellOutput(process: Shell) {.async.} =
  var res = await process.stdout.readAllString()

  # read line by line
  # var res = ""
  # while not process.stdout.atEnd:
  #   let s = await process.stdout.readLine()
  #   echo s
  #   res.add s
  #   res.add "\n"

  echo res.replace("\r", "")

defineCommand(ws"test-shell-2",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    var p = processStart(ws"powershell", wl[WitString]())
    var process = Shell(stdout: p.stdout().buffered, stdin: p.stdin(), process: p.ensureMove)
    shellProcess = process

    discard readShellOutput(process)
    return ws""

var memChannel: ref tuple[open: bool, write: WriteChannel, read: BufferedReadChannel] = nil
var threadChannel: ref tuple[write: WriteChannel, read: BufferedReadChannel] = nil

defineCommand(ws"test-send-input",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    echo &"============ send to shell '{args}'"
    if shellProcess != nil:
      shellProcess.stdin.writeString(args)
      shellProcess.stdin.writeString(ws("\n"))
      if $args == "exit":
        shellProcess[].stdin.close()
        shellProcess = nil
    if memChannel != nil and memChannel.open:
      memChannel[].write.writeString(stackWitString($args & "\n"))
      if $args == "exit":
        memChannel[].write.close()
        memChannel = nil
    if threadChannel != nil:
      threadChannel[].write.writeString(stackWitString($args & "\n"))
      if $args == "exit":
        threadChannel[].write.close()
        threadChannel = nil
    return ws""

proc readMemoryChannel(chan: ref tuple[open: bool, write: WriteChannel, read: BufferedReadChannel]) {.async.} =
  while not chan.read.atEnd:
    let s = await chan.read.readLine()
    echo "\n'" & s & "'"
  echo "============= done"

defineCommand(ws"test-in-memory-channel",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    var (reader, writer) = newInMemoryChannel()

    memChannel.new
    memChannel[] = (false, writer.ensureMove, reader.buffered)

    discard memChannel.readMemoryChannel()

    for i in 0..10:
      stackRegionInline()
      echo &"{i}: send"
      memChannel[].write.writeString(stackWitString("hello " & $i & "\nworld\n"))

    return ws""

proc readThreadChannel(chan: ref tuple[write: WriteChannel, read: BufferedReadChannel]) {.async.} =
  while not chan.read.atEnd:
    let s = await chan.read.readLine()
    echo "\nfib: '" & s & "'"
  echo "[readThreadChannel] done"

defineCommand(ws"test-background-thread",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    var (reader1, writer1) = newInMemoryChannel()
    var (reader2, writer2) = newInMemoryChannel()

    threadChannel.new
    threadChannel[] = (writer1.ensureMove, reader2.buffered)

    discard threadChannel.readThreadChannel()

    let readerPath = reader1.readChannelMount("reader", false)
    let writerPath = writer2.writeChannelMount("writer", false)

    spawnBackground(stackWitString($readerPath & "\n" & $writerPath))

    return ws""

proc fib(n: int64): int64 =
  if n <= 1:
    return 1
  return fib(n - 1) + fib(n - 2)

proc threadFun(reader: BufferedReadChannel, writer: sink WriteChannel) {.async.} =
  echo "[threadFun] start"
  while not reader.atEnd:
    let line = await reader.readLine()
    try:
      let num = line.parseInt
      echo "Calculate fib ", num
      let res = fib(num)
      writer.writeString(stackWitString($res & "\n"))

    except CatchableError as e:
      echo e.msg

  writer.close()
  echo "[threadFun] done"
  finishBackground()

proc init() =
  echo "[guest] init test_plugin"
  let s = getTime()

  if isMainThread():
    var renderView = renderViewFromUserId(ws"test_plugin_view")
    if renderView.isSome:
      openCustomView(show = false)

  else:
    var reader = readChannelOpen("reader")
    var writer = writeChannelOpen("writer")
    if reader.isSome and writer.isSome:
      discard threadFun(reader.take.buffered, writer.take)


  echo &"[guest] init test_plugin took {getTime() - s} ms"

init()
