import std/[strformat, json, jsonutils]
import wit_types, wit_runtime
import scripting/binary_encoder
import ui/render_command
import ../plugin_api/api

var views: seq[View] = @[]
var renderCommandEncoder: BinaryEncoder
var num = 1

proc handleViewRender(id: int32, data: uint32) {.cdecl.} =
  let view {.cursor.} = views[0]

  try:
    let version = apiVersion()
    let target = getSetting("test.num-squares", 50)
    inc num
    if num > target:
      num = 1

    # num = target

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
          fillRect(rect(vec2(x.float, y.float) * s, s), color(x.float / num.float, y.float / num.float, 0, 1))

      drawText("comp_test version " & $version, rect(size * 0.5, vec2()), color(0.5, 0.5, 1, 1), 0.UINodeFlags)

    # view.setRenderCommandsRaw(cast[uint32](renderCommandEncoder.buffer[0].addr), renderCommandEncoder.buffer.len.uint32)
    view.setRenderCommands(@@(renderCommandEncoder.buffer.toOpenArray(0, renderCommandEncoder.buffer.high)))

    let interval = getSetting("test.render-interval", 500)
    view.setRenderInterval(interval)
  except Exception as e:
    echo &"[guest] Failed to render: {e.msg}\n{e.getStackTrace()}"

proc init() =
  echo "[guest] init comp_test"

  addModeChangedHandler proc(old: WitString, new: WitString) {.cdecl.} =
    echo &"[guest] mode changed handler {old} -> {new}"

  echo getSelection()

  let r = newRope(ws"hello, what is going on today?")
  echo r.slice(4, 14).debug()
  echo r.slice(4, 14).text()

  let e = editorCurrent()
  if e.isSome:
    echo &"[guest] found current editor"
    let r2 = e.get.rope()
    let s = getSelection()
    echo r2.slice(s.first.column, s.last.column).debug()
    echo r2.slice(s.first.column, s.last.column).text()
  else:
    echo &"[guest] didn't find current editor"

  bindKeys(ws"editor.text", ws"", ws"<C-a>", ws"uiaeuiae", ws"1", ws"MOVE THE CURSOR", (ws"comp_test.nim", 0.int32, 0.int32))

  let view = viewCreate()
  view.setRenderWhenInactive(true)
  view.setPreventThrottling(true)
  view.setRenderCallback(cast[uint32](handleViewRender), 123)
  view.setRenderInterval(500)
  views.add(view)

init()
