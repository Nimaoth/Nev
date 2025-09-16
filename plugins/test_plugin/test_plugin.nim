import std/[strformat, json, jsonutils, strutils]
import results
import util, render_command, binary_encoder
import api
import clay

var views: seq[RenderView] = @[]
var renderCommandEncoder: BinaryEncoder
var num = 1

converter toWitString(s: string): WitString = ws(s)
var target = 50

proc handleViewRender(id: int32, data: uint32) {.cdecl.}

proc fib(n: int64): int64 =
  if n <= 1:
    return 1
  return fib(n - 1) + fib(n - 2)

proc measureClayText(text: ClayStringSlice; config: ptr ClayTextElementConfig; userData: pointer): ClayDimensions {.cdecl.} =
  return ClayDimensions(width: text.length.float * 10, height: 20)

let totalMemorySize = clay.minMemorySize()
var memory = ClayArena(capacity: totalMemorySize, memory: cast[ptr UncheckedArray[uint8]](allocShared0(totalMemorySize)))
var clayErrorHandler = ClayErrorHandler(
  errorHandlerFunction: proc (error: ClayErrorData) =
    log lvlError, &"[clay] {error.errorType}: {error.errorText}"
)
var clayContext* = clay.initialize(memory, ClayDimensions(width: 1024, height: 768), clayErrorHandler)
clay.setMeasureTextFunction(measureClayText, nil)
clay.setDebugModeEnabled(true)

proc toggleClayDebugMode() =
  clay.setDebugModeEnabled(not clay.isDebugModeEnabled())

proc openCustomView(show: bool) =
  var renderView = renderViewFromUserId(ws"test_plugin_view")
  if renderView.isNone:
    log lvlInfo, "[guest] Create new RenderView"
    renderView = newRenderView().some
  else:
    log lvlInfo, "[guest] Reusing existing RenderView"
  renderView.get.setUserId(ws"test_plugin_view")
  renderView.get.setRenderWhenInactive(true)
  renderView.get.setPreventThrottling(true)
  renderView.get.setRenderCallback(cast[uint32](handleViewRender), views.len.uint32)
  renderView.get.addMode(ws"test-plugin")
  renderView.get.markDirty()
  if show:
    show(renderView.get.view, ws"#new-tab", true, true)
  views.add(renderView.take)

converter toRect(c: ClayBoundingBox): bumpy.Rect =
  rect(c.x, c.y, c.width, c.height)

converter toColor(c: ClayColor): Color =
  color(c.r / 255, c.g / 255, c.b / 255, c.a / 255)

converter toClayVec(c: Vec2f): ClayVector2 =
  ClayVector2(x: c.x, y: c.y)

converter toClayVec(c: Vec2): ClayVector2 =
  ClayVector2(x: c.x, y: c.y)

converter toVec(c: Vec2f): Vec2 =
  vec2(c.x, c.y)

proc encodeClayRenderCommands(renderCommandEncoder: var BinaryEncoder, clayRenderCommands: ClayRenderCommandArray) =
  buildCommands(renderCommandEncoder):
    for c in clayRenderCommands:
      case c.commandType
      of None:
        discard
      of Rectangle:
        let color = c.renderData.rectangle.backgroundColor.toColor
        let bounds = c.boundingBox.toRect
        fillRect(bounds, color)
      of Border:
        let color = c.renderData.border.color.toColor
        let bounds = c.boundingBox.toRect
        # let width = c.renderData.border.width
        # todo: width > 1
        drawRect(bounds, color)
      of Text:
        let color = c.renderData.text.textColor.toColor
        let bounds = c.boundingBox.toRect
        drawText(c.renderData.text.stringContents.toOpenArray(), bounds, color, 0.UINodeFlags)
      of Image:
        log lvlError, &"Not implemented: {c.commandType}"
      of ScissorStart:
        startScissor(c.boundingBox.toRect)
      of ScissorEnd:
        endScissor()
      of Custom:
        log lvlError, &"Not implemented: {c.commandType}"

var lastTime = 0.0
var lastRenderTime = 0.0
var lastRenderTimeStr = ""
proc handleViewRender(id: int32, data: uint32) {.cdecl.} =
  let index = data.int
  if index notin 0..views.high:
    log lvlError, "handleViewRender: index out of bounds {index} notin 0..<{views.len}"
    return

  let view {.cursor.} = views[index]

  try:
    let version = apiVersion()
    inc num
    if num > target:
      num = 1

    num = target
    let start = getTime()
    let deltaTime = start / 1000 - lastTime
    lastTime = start / 1000

    proc vec2(v: Vec2f): Vec2 = vec2(v.x, v.y)

    let size = vec2(view.size)

    clay.setLayoutDimensions(ClayDimensions(width: size.x, height: size.y))
    clay.setPointerState(view.mousePos, view.mouseDown(0))
    clay.updateScrollContainers(true, view.scrollDelta.toVec * 4.0, deltaTime)

    var layoutElement = ClayLayoutConfig(padding: ClayPadding(left: 5, right: 10), layoutDirection: TopToBottom)
    var textConfig = ClayTextElementConfig(textColor: clayColor(1, 1, 1))

    clay.beginLayout()
    UI(backgroundColor = clayColor(0.3, 0, 0), layout = layoutElement, clip = ClayClipElementConfig(vertical: true, childOffset: clay.getScrollOffset())):
      let s = stackWitString("test_plugin version " & $version)
      clayText(s.toOpenArray, textColor = clayColor(1, 1, 1))
      clayText(lastRenderTimeStr, textColor = clayColor(1, 1, 1))

      for i in 0..90:
        UI(backgroundColor = clayColor(0, 0.3, 0), cornerRadius = cornerRadius(1, 2, 3, 4), layout = ClayLayoutConfig(padding: ClayPadding(left: 20, right: 30))):
          clayText("hello", textColor = clayColor(0, 1, 1))
          clayText("world", textConfig)
      clayText("end", textColor = clayColor(1, 1, 1))

    let clayRenderCommands = clay.endLayout()

    renderCommandEncoder.buffer.setLen(0)
    renderCommandEncoder.encodeClayRenderCommands(clayRenderCommands)
    view.setRenderCommands(@@(renderCommandEncoder.buffer.toOpenArray(0, renderCommandEncoder.buffer.high)))

    let interval = getSetting("test.render-interval", 500)
    view.setRenderInterval(interval)

    let elapsed = getTime() - start
    lastRenderTime = lerp(lastRenderTime, elapsed, 0.1)
    lastRenderTimeStr = &"dt: {lastRenderTime} ms"
  except Exception as e:
    log lvlError, &"[guest] Failed to render: {e.msg}\n{e.getStackTrace()}"

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
      log lvlError, &"[guest] err: {e.msg}"
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
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"toggle-clay-debug-mode",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    toggleClayDebugMode()
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
var task: BackgroundTask = nil

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
    if task != nil:
      task.writer.writeString(stackWitString($args & "\n"))
      if $args == "exit":
        task.writer.close()
        task = nil
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

proc readThreadChannel(task: BackgroundTask) {.async.} =
  while not task.reader.atEnd:
    let s = await task.reader.readLine()
    echo "[readThreadChannel] from thread: '" & s & "'"
  echo "[readThreadChannel] done"

defineCommand(ws"test-background-thread",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    task = runInBackground Thread:
      proc(task: BackgroundTask) {.nimcall, async.} =
        while not task.reader.atEnd:
          let line = await task.reader.readLine()
          try:
            let num = line.parseInt
            echo "[thread] Calculate fib ", num
            let res = fib(num)
            {.gcsafe.}:
              task.writer.writeString(stackWitString($res & "\n"))

          except CatchableError as e:
            echo e.msg

        task.writer.close()
        finishBackground()

    discard task.readThreadChannel()
    return ws""

defineCommand(ws"test-thread-pool",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    for i in 0..9:
      let task = runInBackground ThreadPool:
        proc(task: BackgroundTask) {.nimcall, async.} =
          try:
            let message = await task.reader.readLine()
            let num = message.parseInt
            echo "[thread] calc fib ", num
            let res = fib(num)
            task.writer.writeString(ws(&"fib({num}) = {res}\n"))
          except CatchableError as e:
            echo "[thread] ", e.msg
          task.writer.close()
          finishBackground()

      task.writer.writeString(ws(&"{40 + (i mod 3)}\n"))
      task.writer.close()
      discard task.readThreadChannel()

    return ws""

defineCommand(ws"test-sixel",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      var (stdin, stdinWriter) = newInMemoryChannel()
      var (stdoutReader, stdout) = newInMemoryChannel()
      createTerminal(stdinWriter, stdoutReader, "test")
      stdout.writeString("Read file...\r\n")
      let file = vfs.readSync(ws"app://sixel.txt", {Binary})
      if file.isOk:
        stdout.writeString("=========== Test sixel ===================\r\n")
        let str = $file.value
        stdout.writeString("\x1b[c\r\n")
        stdout.writeString("this is an image: ")
        stdout.writeString(str)
        stdout.writeString("\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\nimage 2: ")
        stdout.writeString("\x1bP0;0;0q\"10;10;72;66#1;1;100;100;100" & """
!6?!6?!6?!6?!6?!6~!6~!6?!6?!6?!6?!6?-
!6?!6?!6?!6~!6~!6~!6~!6~!6~!6?!6?!6?-
!6?!6?!6~!6~!6~!6~!6~!6~!6~!6~!6?!6?-
!6?!6~!6~!6~!6~!6~!6~!6~!6~!6~!6~!6?-
!6?!6~!6~!6~!6~!6~!6~!6~!6~!6~!6~!6?-
""".replace("\n", ""))
        stdout.writeString("""
!6?!6~!6~!6~!6~!6~!6~!6~!6~!6~!6~!6?-
!6?!6~!6~!6~!6~!6~!6~!6~!6~!6~!6~!6?-
!6?!6~!6~!6~!6~!6~!6~!6~!6~!6~!6~!6?-
!6?!6?!6~!6~!6~!6~!6~!6~!6~!6~!6?!6?-
!6?!6?!6?!6~!6~!6~!6~!6~!6~!6?!6?!6?-
!6?!6?!6?!6?!6?!6~!6~!6?!6?!6?!6?!6?-
""".replace("\n", "") & "\x1b\\")

        stdout.writeString("\r\n=========== End ===================\r\n")

        echo stdin.readAllString()
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""



proc init() =
  if isMainThread():
    var renderView = renderViewFromUserId(ws"test_plugin_view")
    if renderView.isSome:
      openCustomView(show = false)
  else:
    discard defaultThreadHandler()


init()
