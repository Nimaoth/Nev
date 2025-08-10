import std/[strformat, json, jsonutils, strutils]
import results
import util, render_command, binary_encoder
import api

var views: seq[RenderView] = @[]
var renderCommandEncoder: BinaryEncoder
var num = 1

converter toWitString(s: string): WitString = ws(s)
var target = getSetting("test.num-squares", 50)

proc handleViewRender(id: int32, data: uint32) {.cdecl.}

proc openCustomView() =
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

proc init() =
  echo "[guest] init test_plugin"

  let s = getTime()
  var renderView = renderViewFromUserId(ws"test_plugin_view")
  if renderView.isSome:
    echo "[guest] Reusing existing RenderView"
    renderView.get.setRenderWhenInactive(true)
    renderView.get.setPreventThrottling(true)
    renderView.get.setRenderCallback(cast[uint32](handleViewRender), views.len.uint32)
    renderView.get.addMode(ws"test-plugin")
    renderView.get.markDirty()
    show(renderView.get.view, ws"#new-tab", true, true)
    views.add(renderView.take)

  echo &"[guest] init test_plugin took {getTime() - s} ms"

init()

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
    openCustomView()
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
          # echo "============="
          # echo buffer
          # echo "============="

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
  stdout: ReadChannel
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
    var process = Shell(stdout: p.stdout(), stdin: p.stdin(), process: p.ensureMove)
    shellProcess = process

    process.stdout.listen proc: ChannelListenResponse =
      let s = $process.stdout.readAllString()
      echo "\n" & s
      if process.stdout.atEnd:
        echo "============= done"
        return Stop
      return Continue

    return ws""

var memChannel: ref WriteChannel = nil

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
    if memChannel != nil:
      memChannel[].writeString(stackWitString($args & "\n"))
      if $args == "exit":
        memChannel[].close()
    return ws""

defineCommand(ws"test-in-memory-channel",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    var (reader, writer) = newInMemoryChannel()

    reader.listen proc: ChannelListenResponse =
      let s = $reader.readAllString()
      echo "on listen '", s, "'"
      if reader.atEnd:
        echo "============= done"
        return Stop
      return Continue

    memChannel = WriteChannel.new
    memChannel[] = writer.ensureMove

    for i in 0..10:
      stackRegionInline()
      echo &"{i}: send"
      memChannel[].writeString(stackWitString("hello " & $i & "\n"))
      echo &"{i}: send done"

    return ws""

