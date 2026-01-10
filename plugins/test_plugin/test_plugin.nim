import std/[strformat, json, jsonutils, strutils, options, random, math, sequtils, sugar, streams, tables]
import pixie, chroma
import results
import util, render_command, binary_encoder
import api
import clay

import "../../src/scroll_box.nim"
type ScrollView = ScrollBox

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
    show(renderView.get.view, ws"#build-run-terminal", true, true)
  views.add(renderView.take)

converter toRect(c: ClayBoundingBox): bumpy.Rect =
  rect(c.x, c.y, c.width, c.height)

converter toColor(c: Color): ClayColor =
  clayColor(c.r / 255, c.g / 255, c.b / 255, c.a / 255)

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
var scrollView = ScrollBox()

var blocks: seq[tuple[height: float, color: Color]] = @[]
for i in 0..<100000:
  if rand(0.0..1.0) < 0.1:
    blocks.add (rand(900.0..2000.0).floor, color(rand(1.0), rand(1.0), rand(1.0)))
  else:
    blocks.add (rand(25.0..200.0).floor, color(rand(1.0), rand(1.0), rand(1.0)))

var renderBuffer = BinaryEncoder()
var selected = 0
var sizeOffset = 0.0
var textEditor: TextEditor
var overlays: Table[int64, tuple[location: OverlayRenderLocation, textureId: TextureId, width: float, height: float, len: int]]
proc customOverlayRender(id: int64, overlaySize: Vec2f, localOffset: int): (pointer, int) {.cdecl.} =
  # echo &"customOverlayRender {id}, {overlaySize}, {localOffset}"
  renderBuffer.reset()

  if id in overlays:
    let overlay = overlays[id]
    let textureId = overlay.textureId
    let aspectRatio = overlay.width / overlay.height

    var imageWidth = max(overlaySize.x + sizeOffset, 1)
    var imageOffsetY = 0.0

    if overlay.location == Inline:
      imageWidth *= overlay.len.float
      imageOffsetY = overlaySize.y.float

    let imageSize = vec2(imageWidth, imageWidth / aspectRatio)
    let resultSize = vec2(overlaySize.x, imageSize.y + imageOffsetY)

    let r = rect(vec2(0, imageOffsetY), imageSize)
    renderBuffer.write(resultSize.x.float32) # width
    renderBuffer.write(resultSize.y.float32) # height
    renderBuffer.drawImage(r, textureId)
    renderBuffer.drawRect(r, color(1, 1, 1))
  else:
    let r = rect(vec2(0), overlaySize)
    renderBuffer.write(overlaySize.x.float32) # width
    renderBuffer.write(overlaySize.y.float32) # height
    renderBuffer.drawRect(r, color(1, 1, 1))

  result = (renderBuffer.toOpenArray()[0].addr, renderBuffer.toOpenArray().len)
  return

proc handleViewRender(id: int32, data: uint32) {.cdecl.} =
  let index = data.int
  if index notin 0..views.high:
    log lvlError, "handleViewRender: index out of bounds {index} notin 0..<{views.len}"
    return

  let view {.cursor.} = views[index]

  let texts = scrollView.items.mapIt($it)
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
    if view.scrollDelta.y != 0:
      sizeOffset += view.scrollDelta.y * 2
      discard textEditor.command(ws"rerender", ws"")

    var layoutElement = ClayLayoutConfig(padding: ClayPadding(left: 5, right: 10), layoutDirection: TopToBottom)
    var textConfig = ClayTextElementConfig(textColor: clayColor(1, 1, 1))

    clay.beginLayout()
    UI(backgroundColor = clayColor(0.3, 0, 0), layout = layoutElement, clip = ClayClipElementConfig(vertical: true, childOffset: clay.getScrollOffset())):
      let s = "test_plugin version " & $version
      clayText(s, textColor = clayColor(1, 1, 1))
      clayText(lastRenderTimeStr, textColor = clayColor(1, 1, 1))
      let uiae = &"{scrollView.items.len} items, {scrollView.index}, {scrollView.offset}"
      clayText(uiae, textColor = clayColor(1, 1, 1))
      let xvlc = &"{scrollView.scrollMomentum}"
      clayText(xvlc, textColor = clayColor(1, 1, 1))

      # echo "============================================="
      # echo texts.join("\n")
      for i in 0..scrollView.items.high:
        UI(backgroundColor = clayColor(0, 0.3, 0), cornerRadius = cornerRadius(1, 2, 3, 4), layout = ClayLayoutConfig(padding: ClayPadding(left: 20, right: 30))):
          clayText(texts[i], textColor = clayColor(0, 1, 1))

    let clayRenderCommands = clay.endLayout()

    renderCommandEncoder.reset()
    renderCommandEncoder.encodeClayRenderCommands(clayRenderCommands)

    scrollView.scrollWithMomentum(view.scrollDelta.y * 15)
    scrollView.updateScroll(deltaTime)

    var fixups: seq[tuple[itemIndex: int, renderCommandHead: int]]
    proc itemRenderer(sv: ScrollView, index: int): Option[Vec2] =
      if index in 0..blocks.high:
        fixups.add (index, renderCommandEncoder.head)
        let height = blocks[index][0]
        renderCommandEncoder.startTransform(vec2(0))
        var color = blocks[index][1]
        renderCommandEncoder.fillRect(rect(0, 0, sv.size.x, height), color.lighten(-0.2))
        renderCommandEncoder.drawText($index, rect(5, 5, 0, 0), color.lighten(0.2), 0.UINodeFlags)
        if index == selected:
          for i in 0..3:
            renderCommandEncoder.drawRect(rect(0, 0, sv.size.x, height).grow(-i.float.vec2), color(1, 1, 1))
        renderCommandEncoder.endTransform()
        return vec2(100, height).some
      return Vec2.none

    scrollView.beginRender(vec2(600, 600), 0.UINodeFlags, blocks.high)
    renderCommandEncoder.startTransform(vec2(400, 400))
    renderCommandEncoder.drawRect(rect(0, 0, scrollView.size.x, scrollView.size.y).grow(vec2(1)), color(1, 1, 1))
    renderCommandEncoder.startScissor(rect(0, 0, scrollView.size.x, scrollView.size.y))
    while scrollView.renderItem(itemRenderer):
      discard

    renderCommandEncoder.endScissor()
    renderCommandEncoder.endTransform()

    scrollView.endRender()
    scrollView.clamp(blocks.high)

    for fix in fixups:
      renderCommandEncoder.head = fix.renderCommandHead
      if scrollView.itemBounds(fix.itemIndex).getSome(b):
        renderCommandEncoder.startTransform(vec2(0, b.y))
    renderCommandEncoder.resetHead()

    view.setRenderCommands(@@(renderCommandEncoder.toOpenArray()))

    let interval = getSetting("test.render-interval", 500)
    view.setRenderInterval(interval)

    let elapsed = getTime() - start
    lastRenderTime = lerp(lastRenderTime, elapsed, 0.1)
    lastRenderTimeStr = &"dt: {lastRenderTime} ms"
  except Exception as e:
    log lvlError, &"[guest] Failed to render: {e.msg}\n{e.getStackTrace()}"

proc getArg(args: JsonNode, index: int, T: typedesc): T =
  if args != nil and args.kind == JArray and index < args.elems.len:
    return args.elems[index].jsonTo(T)
  return T.default

defineCommand(ws"add-custom-overlay-renderer",
  active = false,
  docs = ws"Decrease the size of the square",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, argsJson: WitString): WitString {.cdecl.} =
    try:
      var args = newJArray()
      for a in newStringStream($argsJson).parseJsonFragments():
        args.add a

      var text = args.getArg(0, string)
      let location = args.getArg(1, OverlayRenderLocation)

      if text.len == 0:
        text = "          \n        \n\n"

      var imageId: uint64 = 0
      var width = 0.0
      var height = 0.0
      var res = readSync("app://screenshots/browse-keybinds-command.png", {Binary})
      if res.isOk:
        var image = decodeImage($res.get)
        imageId = createTexture(image.width.int32, image.height.int32, cast[uint32](image.data[0].addr), Rgba8, false)
        width = image.width.float
        height = image.height.float
      else:
        log lvlError, &"Failed to read image: {res.error}"
      if activeTextEditor({}).getSome(editor):
        textEditor = editor
        let id = editor.addCustomRender(customOverlayRender)
        overlays[id] = (location, imageId.TextureId, width, height, 10)
        editor.addOverlay(editor.getSelection, text.ws, 5, "comment", Bias.Right, id, location)
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"scroll",
  active = false,
  docs = ws"Decrease the size of the square",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      let s = ($args).parseJson.jsonTo(float)
      scrollView.scrollWithMomentum(s)
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"select-next",
  active = false,
  docs = ws"Decrease the size of the square",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      let s = ($args).parseJson.jsonTo(int)
      selected += s
      selected = selected.clamp(0, blocks.high)
      scrollView.scrollTo(selected)
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"center-next",
  active = false,
  docs = ws"Decrease the size of the square",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      let s = ($args).parseJson.jsonTo(int)
      selected += s
      selected = selected.clamp(0, blocks.high)
      scrollView.scrollTo(selected, center = true)
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"scroll-to",
  active = false,
  docs = ws"Decrease the size of the square",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      let s = ($args).parseJson.jsonTo(int)
      let index = if s < 0:
        blocks.len + s
      else:
        s
      selected = index.clamp(0, blocks.high)
      scrollView.scrollTo(selected)
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

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
    if activeTextEditor({}).getSome(editor):
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
    if activeTextEditor({}).getSome(editor):
      var p = processStart(ws"powershell", @@[ws"-Command", ws"ls", ws"plugins"])
      let stdout = p.stdout()

      var buffer = ""
      stdout.listen proc: ChannelListenResponse =
        let s = $stdout.readAllString()
        buffer.add s
        if stdout.atEnd:
          if buffer.endsWith("\0"):
            buffer.setLen(buffer.len - 1)
          let selections = editor.edit(@@[editor.getSelection], @@[ws(buffer.replace("\r", ""))], false)
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
