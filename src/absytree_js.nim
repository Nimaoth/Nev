
import custom_logger

logger.enableConsoleLogger()

import std/[strformat, dom]
import util, editor, timer, platform/widget_builders, platform/platform, platform/browser_platform, text_document, event, theme
from scripting_api import Backend

# Initialize renderer
var rend: BrowserPlatform = new BrowserPlatform
rend.init()

var ed = newEditor(Backend.Browser, rend)
const themeString = staticRead("../themes/Night Owl-Light-color-theme copy.json")
if theme.loadFromString(themeString).getSome(theme):
  ed.theme = theme

ed.setLayout("fibonacci")

# ed.createView(newTextDocument("absytree_browser.html", file1))
# ed.createView(newTextDocument("absytree_js.nim", file2))
# ed.openFile("absytree_browser.html")
# ed.openFile("src/absytree_js.nim")
# ed.openFile("absytree_config.nims")

var frameTime = 0.0
var frameIndex = 0

var hasRequestedRerender = false
proc requestRender() =
  if hasRequestedRerender:
    return

  discard window.requestAnimationFrame proc(time: float) =
    # echo "requestAnimationFrame ", time

    hasRequestedRerender = false
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

    logger.log(lvlInfo, fmt"Frame: {frameTime:>5.2}ms (u: {updateTime:>5.2}ms, l: {layoutTime:>5.2}ms, r: {renderTime:>5.2}ms)")

discard rend.onKeyPress.subscribe proc(event: auto): void = requestRender()
discard rend.onKeyRelease.subscribe proc(event: auto): void = requestRender()
discard rend.onRune.subscribe proc(event: auto): void = requestRender()
discard rend.onMousePress.subscribe proc(event: auto): void = requestRender()
discard rend.onMouseRelease.subscribe proc(event: auto): void = requestRender()
discard rend.onMouseMove.subscribe proc(event: auto): void = requestRender()
discard rend.onScroll.subscribe proc(event: auto): void = requestRender()
discard rend.onCloseRequested.subscribe proc(_: auto) = requestRender()
discard rend.onResized.subscribe proc(_: auto) = requestRender()

block:
  ed.setHandleInputs "editor.text", true
  scriptSetOptionString "editor.text.cursor.movement.", "both"
  scriptSetOptionBool "editor.text.cursor.wide.", false

  scriptAddCommand "editor.text", "<LEFT>", "move-cursor-column -1"
  scriptAddCommand "editor.text", "<RIGHT>", "move-cursor-column 1"
  scriptAddCommand "editor.text", "<C-d>", "delete-move \"line-next\""
  scriptAddCommand "editor.text", "<C-LEFT>", "move-first \"word-line\""
  scriptAddCommand "editor.text", "<C-RIGHT>", "move-last \"word-line\""
  scriptAddCommand "editor.text", "<HOME>", "move-first \"line\""
  scriptAddCommand "editor.text", "<END>", "move-last \"line\""
  scriptAddCommand "editor.text", "<C-UP>", "scroll-text 20"
  scriptAddCommand "editor.text", "<C-DOWN>", "scroll-text -20"
  scriptAddCommand "editor.text", "<CS-LEFT>", "move-first \"word-line\" \"last\""
  scriptAddCommand "editor.text", "<CS-RIGHT>", "move-last \"word-line\" \"last\""
  scriptAddCommand "editor.text", "<UP>", "move-cursor-line -1"
  scriptAddCommand "editor.text", "<DOWN>", "move-cursor-line 1"
  scriptAddCommand "editor.text", "<C-HOME>", "move-first \"file\""
  scriptAddCommand "editor.text", "<C-END>", "move-last \"file\""
  scriptAddCommand "editor.text", "<CS-HOME>", "move-first \"file\" \"last\""
  scriptAddCommand "editor.text", "<CS-END>", "move-last \"file\" \"last\""
  scriptAddCommand "editor.text", "<S-LEFT>", "move-cursor-column -1 \"last\""
  scriptAddCommand "editor.text", "<S-RIGHT>", "move-cursor-column 1 \"last\""
  scriptAddCommand "editor.text", "<S-UP>", "move-cursor-line -1 \"last\""
  scriptAddCommand "editor.text", "<S-DOWN>", "move-cursor-line 1 \"last\""
  scriptAddCommand "editor.text", "<S-HOME>", "move-first \"line\" \"last\""
  scriptAddCommand "editor.text", "<S-END>", "move-last \"line\" \"last\""
  scriptAddCommand "editor.text", "<CA-d>", "duplicate-last-selection"
  scriptAddCommand "editor.text", "<CA-UP>", "add-cursor-above"
  scriptAddCommand "editor.text", "<CA-DOWN>", "add-cursor-below"
  scriptAddCommand "editor.text", "<BACKSPACE>", "delete-left"
  scriptAddCommand "editor.text", "<DELETE>", "delete-right"
  scriptAddCommand "editor.text", "<ENTER>", "insert-text \"\n\""
  scriptAddCommand "editor.text", "<SPACE>", "insert-text \" \""
  scriptAddCommand "editor.text", "<C-l>", "select-line-current"
  scriptAddCommand "editor.text", "<A-UP>", "select-parent-current-ts"
  scriptAddCommand "editor.text", "<C-r>", "select-prev"
  scriptAddCommand "editor.text", "<C-t>", "select-next"
  scriptAddCommand "editor.text", "<C-n>", "invert-selection"
  scriptAddCommand "editor.text", "<C-y>", "undo"
  scriptAddCommand "editor.text", "<C-z>", "redo"

requestRender()
