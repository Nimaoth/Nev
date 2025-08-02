import std/[strformat, json, jsonutils]
import wit_types, wit_runtime
import scripting/binary_encoder
import ui/render_command
import ../plugin_api/api

var views: seq[View] = @[]
var renderCommandEncoder: BinaryEncoder
var num = 1

proc handleViewRender(id: int32, data: uint32) {.cdecl.} =
  # echo &"[guest] handleViewRender"
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

  let view = viewCreate()
  view.setRenderWhenInactive(true)
  view.setPreventThrottling(true)
  view.setRenderCallback(cast[uint32](handleViewRender), 123)
  views.add(view)

init()
