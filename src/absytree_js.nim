
import custom_logger

logger.enableConsoleLogger()

import std/[strformat, dom, macros]
import util, editor, timer, platform/widget_builders, platform/platform, platform/browser_platform, text_document, event, theme
from scripting_api import Backend

# Initialize renderer
var rend: BrowserPlatform = new BrowserPlatform
rend.init()

var initializedEditor = false
var ed = newEditor(Backend.Browser, rend)
const themeString = staticRead("../themes/Night Owl-Light-color-theme copy.json")
if theme.loadFromString(themeString).getSome(theme):
  ed.theme = theme

ed.setLayout("fibonacci")

var frameTime = 0.0
var frameIndex = 0

var hasRequestedRerender = false
var isRenderInProgress = false
proc requestRender(redrawEverything = false) =
  if not initializedEditor:
    return
  if hasRequestedRerender:
    return
  if isRenderInProgress:
    return

  discard window.requestAnimationFrame proc(time: float) =
    # echo "requestAnimationFrame ", time

    hasRequestedRerender = false
    isRenderInProgress = true
    defer: isRenderInProgress = false
    defer: inc frameIndex

    var layoutTime, updateTime, renderTime: float
    block:
      ed.frameTimer = startTimer()

      let updateTimer = startTimer()
      ed.updateWidgetTree(frameIndex)
      updateTime = updateTimer.elapsed.ms

      let layoutTimer = startTimer()
      ed.layoutWidgetTree(rend.size, frameIndex)
      layoutTime = layoutTimer.elapsed.ms

      let renderTimer = startTimer()
      rend.render(ed.widget, frameIndex)
      renderTime = renderTimer.elapsed.ms

      frameTime = ed.frameTimer.elapsed.ms

    if frameTime > 20:
      logger.log(lvlInfo, fmt"Frame: {frameTime:>5.2}ms (u: {updateTime:>5.2}ms, l: {layoutTime:>5.2}ms, r: {renderTime:>5.2}ms)")

discard rend.onKeyPress.subscribe proc(event: auto): void = requestRender()
discard rend.onKeyRelease.subscribe proc(event: auto): void = requestRender()
discard rend.onRune.subscribe proc(event: auto): void = requestRender()
discard rend.onMousePress.subscribe proc(event: auto): void = requestRender()
discard rend.onMouseRelease.subscribe proc(event: auto): void = requestRender()
discard rend.onMouseMove.subscribe proc(event: auto): void = requestRender()
discard rend.onScroll.subscribe proc(event: auto): void = requestRender()
discard rend.onCloseRequested.subscribe proc(_: auto) = requestRender()
discard rend.onResized.subscribe proc(redrawEverything: bool) = requestRender(redrawEverything)

block:
  ed.setHandleInputs "editor.text", true
  scriptSetOptionString "editor.text.cursor.movement.", "both"
  scriptSetOptionBool "editor.text.cursor.wide.", false

  ed.addCommandScript "editor", "<S-SPACE>cl", "load-current-config"
  ed.addCommandScript "editor", "<S-SPACE>cs", "sourceCurrentDocument"

initializedEditor = true
requestRender()

# Useful for debugging nim strings in the browser
# Just turns a nim string to a javascript string
proc nimStrToCStr(str: string): cstring {.exportc, used.} = str

# Override some functions with more optimized versions
{.emit: """
const hiXorLoJs_override_mask = BigInt("0xffffffffffffffff");
const hiXorLoJs_override_shift = BigInt("64");
function hiXorLoJs_override(a, b) {
    var prod = (a * b);
    return ((prod >> hiXorLoJs_override_shift) ^ (prod & hiXorLoJs_override_mask));
}

var hashWangYi1_override_c1 = BigInt("0xa0761d6478bd642f");
var hashWangYi1_override_c2 = BigInt("0xe7037ed1a0b428db");
var hashWangYi1_override_c3 = BigInt("0xeb44accab455d16d");

function hashWangYi1_override(x) {
    if (typeof BigInt != 'undefined') {
        var res = hiXorLoJs_override(hiXorLoJs_override(hashWangYi1_override_c1, (BigInt(x) ^ hashWangYi1_override_c2)), hashWangYi1_override_c3);
        return Number(BigInt.asIntN(32, res));
    }
    else {
        return (x & 4294967295);
    }
}
""".}

import hashes

macro overrideFunction(body: typed, override: untyped): untyped =
  # echo body.treeRepr
  let original = if body.kind == nnkCall: body[0] else: body

  return quote do:
    {.emit: ["window.", `original`, " = ", `override`, ";"].}

overrideFunction(hashWangYi1(1.int64), "hashWangYi1_override")
overrideFunction(hashWangYi1(2.uint64), "hashWangYi1_override")
overrideFunction(hashWangYi1(3.Hash), "hashWangYi1_override")