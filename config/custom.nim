import plugin_runtime

import std/[strutils, unicode, tables, json, options, genasts, macros, sequtils, algorithm]
import misc/[util, myjsonutils]
import ui/render_command

import clay

let isTerminal = getBackend() == Terminal
let scale = if isTerminal: 1.0 else: 1

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

# proc stackAlloc(size: int32): int32 {.wasmexport.} =
#   discard
#   echo "stackAlloc"

# proc stackSave(): int32 {.wasmexport.} =
#   discard
#   echo "stackSave"

# proc stackRestore(p: int32) {.wasmexport.} =
#   discard
#   echo "stackSave"


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
  if isTerminal:
    clay.debugViewWidth = 40
    clay.rowHeight = 1
    clay.configHeaderRowHeight = 0
    clay.closeButtonPadding = 1
    clay.outerPadding = 0
    clay.indentWidth = 2
    clay.colorSizing = 1
    clay.padding = 0
    clay.paddingX = 0
    clay.paddingY = 0
    clay.colorPadding = 0
    clay.childGap = 0
    clay.collapseElementSize = 1
    clay.fontSize = 1
    clay.emptySquareSize = 1
    clay.propertiesSize = 11
    clay.titleRowHeight = 1
    clay.separatorWidth = 0
    clay.scrollSpeed = 1
  else:
    clay.debugViewWidth = 400
    clay.rowHeight = 30
    clay.configHeaderRowHeight = 30
    clay.closeButtonPadding = 10
    clay.outerPadding = 10
    clay.indentWidth = 16
    clay.colorSizing = 10
    clay.padding = 8
    clay.paddingX = 8
    clay.paddingY = 2
    clay.colorPadding = 8
    clay.childGap = 6
    clay.collapseElementSize = 16
    clay.fontSize = 16
    clay.emptySquareSize = 8
    clay.propertiesSize = 300
    clay.titleRowHeight = 8
    clay.separatorWidth = 1
    clay.scrollSpeed = 30

  let dims = ClayDimensions(width: 1024, height: 768)
  clay.initialize(memory, dims)
  setMeasureTextFunction(measureClayText)

type ClayStateWrapper = ref object
  data: seq[uint8]

var clayStates: Table[EditorId, ClayStateWrapper]
var currentState: ClayStateWrapper = nil

proc new(_: typedesc[ClayStateWrapper]): ClayStateWrapper =
  new(result)
  result.data.setLen(clay.stateSize())

proc save(state: ClayStateWrapper) =
  clay.saveState(cast[ptr ClayState](state.data[0].addr))

proc restore(state: ClayStateWrapper) =
  clay.restoreState(cast[ptr ClayState](state.data[0].addr))
  currentState = state

proc clayState(editorId: EditorId): ClayStateWrapper =
  clayStates.withValue(editorId, val):
    return val[]

  var state = ClayStateWrapper.new()
  clayStates[editorId] = state
  initClay()
  state.save()
  state

proc toRect(bb: ClayBoundingBox): Rect =
  rect(bb.x, bb.y, bb.width, bb.height)

proc toColor(bb: ClayColor): Color =
  color(bb.r / 255, bb.g / 255, bb.b / 255, bb.a / 255)

proc printf(frmt: cstring) {.varargs, header: "<stdio.h>", cdecl.}

var lastMouse: Vec2
var lastMouseDown = false
var lastScroll: Vec2
proc drawClay(editor: EditorId, size: Vec2): RenderCommands =
  var state = editor.clayState()
  state.restore()
  defer:
    state.save()

  setLayoutDimensions(ClayDimensions(width: size.x, height: size.y))
  var layoutElement = ClayLayoutConfig(padding: ClayPadding(x: 0.em, y: 0.em), layoutDirection: TopToBottom)
  var textConfig = ClayTextElementConfig(textColor: clayColor(0.8, 0.5, 0.5))
  clay.beginLayout()
  UI(rectangle(color = clayColor(0.5, 0.1, 0.1)), layout(layoutElement)):
    UI(rectangle(color = clayColor(0.1, 0.5, 0.1), cornerRadius = cornerRadius(1.em, 2.em, 3.em, 4.em)), layout(padding = ClayPadding(x: 0.em, y: 0.em))):
      clayText(&"{lastMouse}, {lastMouseDown}, {lastScroll}", textColor = clayColor(0, 0, 1))
    for i in 0..4:
      UI(rectangle(color = clayColor(0.1, 0.5, 0.1), cornerRadius = cornerRadius(1.em, 2.em, 3.em, 4.em)), layout(padding = ClayPadding(x: 0.em, y: 0.em))):
        for k in 0..1:
          clayText("hello ", textColor = clayColor(0.5, 0.1, 1))
          clayText($i, textConfig)
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
      of ScissorEnd:
        endScissor()
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

    let input = args.jsonTo(Payload)

    # todo: don't recreate renderCommandsGlobal, reuse the existing memory instead
    renderCommandsGlobal = drawClay(input.editor, input.bounds.wh)

    type Result = object
      address: uint32
      len: uint32
      stride: uint32
      strings: uint32
      stringsLen: uint32

    if renderCommandsGlobal.commands.len == 0:
      return Result().toJson

    # The caller will currently copy the data in the renderCommandsGlobal after this function returns
    return Result(
      address: cast[uint32](renderCommandsGlobal.commands[0].addr),
      len: uint32(renderCommandsGlobal.commands.len),
      stride: uint32(sizeof(RenderCommand)),
      strings: cast[uint32](renderCommandsGlobal.strings.cstring),
      stringsLen: cast[uint32](renderCommandsGlobal.strings.len),
    ).toJson

  scriptSetCallback("custom-render", id)

block: # handle-click
  let id = addCallback proc(args: JsonNode): JsonNode =
    type Payload = object
      editor: EditorId
      button: MouseButton
      pos: Vec2
      down: bool

    let input = args.jsonTo(Payload)
    lastMouse = (input.pos / scale).floor
    lastMouseDown = input.down

    input.editor.clayState().restore()
    setPointerState(ClayVector2(x: input.pos.x, y: input.pos.y), input.down)
    input.editor.clayState().save()
    return clay.isAnyHovered().toJson

  scriptSetCallback("handle-click", id)

block: # handle-scroll
  let id = addCallback proc(args: JsonNode): JsonNode =
    type Payload = object
      editor: EditorId
      delta: Vec2

    let input = args.jsonTo(Payload)
    lastScroll = input.delta

    input.editor.clayState().restore()
    updateScrollContainers(true, ClayVector2(x: input.delta.x, y: input.delta.y), 0.016)
    input.editor.clayState().save()
    return clay.isAnyHovered().toJson

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
