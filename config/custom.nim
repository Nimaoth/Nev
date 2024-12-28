import plugin_runtime

import std/[strutils, unicode, tables, json, options, genasts, macros, sequtils, algorithm]
import misc/[util, myjsonutils]
import ui/render_command

import clay

let isTerminal = getBackend() == Terminal
let scale = if isTerminal: 1.0/16.0 else: 1

template em(f: untyped): untyped =
  f
  # when typeof(f) is float:
  #   if isTerminal:
  #     f.floor
  #   else:
  #     f * 10 # * fontSize
  # else:
  #   if isTerminal:
  #     f
  #   else:
  #     f * 10 # * fontSize

proc stackAlloc(size: int32): int32 {.wasmexport.} =
  discard
  echo "stackAlloc"

proc stackSave(): int32 {.wasmexport.} =
  discard
  echo "stackSave"

proc stackRestore(p: int32) {.wasmexport.} =
  discard
  echo "stackSave"

proc foo() {.expose("foo").} =
  ## Saves app state and quits the editor with exit code 123.
  ## You need to run the editor with tools/run.ps1 which restarts the editor when it exits with code 123.

  infof"foo"

proc sortLines(editor: TextDocumentEditor) {.expose("sort-lines").} =
  ## Saves app state and quits the editor with exit code 123.
  ## You need to run the editor with tools/run.ps1 which restarts the editor when it exits with code 123.

  var lines = editor.getText(editor.selection()).split("\n")
  lines.sort()
  editor.addNextCheckpoint "insert"
  editor.selections = editor.edit(@[editor.selection], @[lines.join("\n")])

proc quitAndRestart() {.expose("quit-and-restart").} =
  ## Saves app state and quits the editor with exit code 123.
  ## You need to run the editor with tools/run.ps1 which restarts the editor when it exits with code 123.

  infof"Quit and restart..."
  saveAppState()
  quitImmediately(123)

proc c2nim(editor: TextDocumentEditor) {.expose("c2nim").} =
  let inPath = genTempPath("nev_c2nim_", ".c", dir = "temp://")
  let outPath = genTempPath("nev_c2nim_", ".nim", dir = "temp://")
  infof"in: {inPath}, out: {outPath}"

  let text = editor.getText(editor.selection())
  writeFileSync(inPath, text)

  runProcess "c2nim.cmd", @[&"--out:{outPath.localizePath}", inPath.localizePath], callback = proc(output: string, err: string) =
    defer:
      deleteFileSync(inPath)
      deleteFileSync(outPath)

    infof"c2nim finished"
    if output != "":
      infof"output:"
      infof"{output}"
    if err != "":
      infof"err:"
      infof"{err}"

    let newText = readFileSync(outPath)
    if newText != "":
      editor.addNextCheckpoint "insert"
      editor.selections = editor.edit(@[editor.selection], @[newText])

proc measureClayText(str: ptr ClayString, config: ptr ClayTextElementConfig): ClayDimensions {.cdecl.} =
  if isTerminal:
    return ClayDimensions(width: round(str.length.float / scale), height: round(1 / scale))
  else:
    return ClayDimensions(width: str.length.float * 10, height: 16)

proc initClay() =
  let totalMemorySize = minMemorySize()
  var memory = ClayArena(label: cs"my memory arena", capacity: totalMemorySize, memory: cast[cstring](allocShared0(totalMemorySize)))
  # echo &"totalMemorySize: {totalMemorySize shr 10} kb"
  # let dims = if isTerminal:
  #   # clay.uiScale = 1
  #   # clay.debugViewFontSize = 1
  #   ClayDimensions(width: 160, height: 50)
  # else:
  #   # clay.uiScale = 10
  #   # clay.debugViewFontSize = 16
  #   ClayDimensions(width: 1024, height: 768)
  let dims = ClayDimensions(width: 1024, height: 768)
  clay.initialize(memory, dims)
  setMeasureTextFunction(measureClayText)

initClay()

proc toRect(bb: ClayBoundingBox): Rect =
  rect(bb.x, bb.y, bb.width, bb.height)

proc toColor(bb: ClayColor): Color =
  color(bb.r / 255, bb.g / 255, bb.b / 255, bb.a / 255)

proc printf(frmt: cstring) {.varargs, header: "<stdio.h>", cdecl.}

var lastMouse: Vec2
var lastMouseDown = false
var lastScroll: Vec2
proc drawClay(): RenderCommands =
  setPointerState(ClayVector2(x: lastMouse.x, y: lastMouse.y), lastMouseDown)
  updateScrollContainers(false, ClayVector2(x: lastScroll.x, y: lastScroll.y), 0.5)
  var layoutElement = ClayLayoutConfig(padding: ClayPadding(x: 1.em, y: 2.em), layoutDirection: TopToBottom)
  var textConfig = ClayTextElementConfig(textColor: clayColor(1, 1, 1))
  clay.beginLayout()
  UI(rectangle(color = clayColor(1, 0, 0)), layout(layoutElement)):
    UI(rectangle(color = clayColor(0, 1, 0), cornerRadius = cornerRadius(1.em, 2.em, 3.em, 4.em)), layout(padding = ClayPadding(x: 2.em, y: 3.em))):
      clayText($lastMouse, textColor = clayColor(0, 0, 1))
      clayText($lastMouseDown, textConfig)
      clayText($lastScroll, textColor = clayColor(0, 1, 0))
    UI(rectangle(color = clayColor(0, 1, 0), cornerRadius = cornerRadius(1.em, 2.em, 3.em, 4.em)), layout(padding = ClayPadding(x: 2.em, y: 3.em))):
      clayText("hello", textColor = clayColor(0, 0, 1))
      clayText("world", textConfig)
    UI(rectangle(color = clayColor(0, 1, 0), cornerRadius = cornerRadius(1.em, 2.em, 3.em, 4.em)), layout(padding = ClayPadding(x: 2.em, y: 3.em))):
      clayText("hello", textColor = clayColor(0, 0, 1))
      clayText("world", textConfig)
    UI(rectangle(color = clayColor(0, 1, 0), cornerRadius = cornerRadius(1.em, 2.em, 3.em, 4.em)), layout(padding = ClayPadding(x: 2.em, y: 3.em))):
      clayText("hello", textColor = clayColor(0, 0, 1))
      clayText("world", textConfig)
  let renderCommands = clay.endLayout()
  let arr = cast[ptr UncheckedArray[ClayRenderCommand]](renderCommands.internalArray)


  buildCommands:
    for i in 0..<renderCommands.length.int:
      case arr[i].commandType
      of Rectangle:
        fillRect(arr[i].boundingBox.toRect * scale, arr[i].config.rectangleElementConfig.color.toColor)
      of Text:
        drawText($arr[i].text, arr[i].boundingBox.toRect * scale, arr[i].config.rectangleElementConfig.color.toColor, 0.UINodeFlags)
      of ScissorStart:
        startScissor(arr[i].boundingBox.toRect * scale)
        # echo arr[i].commandType
        # echo arr[i]
      of ScissorEnd:
        endScissor()
        # echo arr[i].commandType
        # echo arr[i]
      else: discard

var renderCommandsGlobal: RenderCommands

block: # Custom render
  let id = addCallback proc(args: JsonNode): JsonNode =
    type Payload = object
      editor: EditorId
      bounds: Rect
      lastCursorLocationBounds: Option[Rect]
      scrollOffset: float
      previousBaseIndex: int
      lastLines: seq[int]

    let commands = drawClay()
    renderCommandsGlobal = commands

    type Result = object
      address: uint32
      len: uint32
      stride: uint32
      strings: uint32
      stringsLen: uint32

    return Result(
      address: cast[uint32](renderCommandsGlobal.commands[0].addr),
      len: uint32(renderCommandsGlobal.commands.len),
      stride: uint32(sizeof(RenderCommand)),
      strings: cast[uint32](renderCommandsGlobal.strings[0].addr),
      stringsLen: cast[uint32](renderCommandsGlobal.strings.len),
    ).toJson

    # return commands.toJson

    # let input = args.jsonTo(Payload)
    # let cursorBounds = input.lastCursorLocationBounds.get(rect(300, 300, 10, 10)) - input.bounds.xy
    # let commands2 = buildCommands:
    #   if input.editor.isTextEditor editor:
    #     fillRect(rect(cursorBounds.xyh, vec2(100, 50)), color(0.1, 0.1, 0.1))
    #     drawText(editor.mode, rect(cursorBounds.xyh, vec2(200, 300)), color(1, 0.1, 0.1), 0.UINodeFlags)
    # return commands2.toJson

  scriptSetCallback("custom-render", id)

block: # handle-click
  let id = addCallback proc(args: JsonNode): JsonNode =
    type Payload = object
      editor: EditorId
      button: MouseButton
      pos: Vec2
      down: bool

    let input = args.jsonTo(Payload)
    if isTerminal:
      lastMouse = ((input.pos + 0.5) / scale).floor
    else:
      lastMouse = (input.pos / scale).floor
    lastMouseDown = input.down
    # setPointerState(ClayVector2(x: input.pos.x, y: input.pos.y), input.down)
    return newJNull()

  scriptSetCallback("handle-click", id)

block: # handle-scroll
  let id = addCallback proc(args: JsonNode): JsonNode =
    type Payload = object
      editor: EditorId
      delta: Vec2

    let input = args.jsonTo(Payload)
    # echo input
    lastScroll = input.delta
    # updateScrollContainers(true, ClayVector2(x: input.delta.x, y: input.delta.y), 0.016)
    return newJNull()

  scriptSetCallback("handle-scroll", id)

var debugModeEnabled = false
proc toggleDebugMode() {.expose("toggle-debug-mode").} =
  debugModeEnabled = not debugModeEnabled
  setDebugModeEnabled(debugModeEnabled)

proc toggleCustomRender(editor: TextDocumentEditor) {.exposeActive("editor", "toggle-custom-render").} =
  if editor.hasCustomRenderer("custom-render"):
    editor.removeCustomRenderer("custom-render")
  else:
    editor.addCustomRenderer("custom-render")

toggleDebugMode()
when defined(wasm):
  include plugin_runtime_impl
