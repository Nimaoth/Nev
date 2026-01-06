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

proc getArg(args: JsonNode, index: int, T: typedesc): T =
  if args != nil and args.kind == JArray and index < args.elems.len:
    return args.elems[index].jsonTo(T)
  return T.default

proc createTextureForFile(path: string): tuple[id: TextureId, width: float, height: float] =
  var res = readSync(path, {Binary})
  if res.isOk:
    var image = decodeImage($res.get)
    var data: seq[chroma.Color]
    data.setLen(image.data.len)
    for i in 0..image.data.high:
      data[i] = image.data[i].color()
    let id = createTexture(image.width.int32, image.height.int32, cast[uint32](data[0].addr), Rgba32)
    return (id.TextureId, image.width.float, image.height.float)
  else:
    log lvlError, &"Failed to read image: {res.error}"
    return

defineCommand(ws"md-images",
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

      let location = args.getArg(0, OverlayRenderLocation)
      if activeTextEditor({}).getSome(editor):
        editor.clearOverlays(5)
        textEditor = editor
        let regex = "\\[.*?\\]\\(.*?\\)"
        let content = textEditor.content
        let imageRanges = content.findAll(regex)
        for r in imageRanges:
          let text = $content.sliceSelection(r, false).text()
          let start = text.find("(")
          if start != -1:
            let file = text[(start + 1)..^2]
            if not file.endsWith("png"):
              continue

            log lvlInfo, &"{r} -> {file}"
            let (texture, width, height) = createTextureForFile(file)
            if texture == 0.TextureId:
              continue
            let id = editor.addCustomRender(customOverlayRender)
            overlays[id] = (location, texture, width, height, r.last.column.int - r.first.column.int)
            editor.addOverlay(Selection(first: r.first, last: r.first), "*", 5, "comment", Bias.Right, id, location )
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

type ImageOverlay = object
  range: Selection
  texture: TextureId
  width: float
  height: float

proc findImagesInFile(content: Rope): seq[ImageOverlay] =
  let regex = "\\[.*?\\]\\(.*?\\)"
  let imageRanges = content.findAll(regex)
  echo &"findImagesInFile {imageRanges}"
  for r in imageRanges:
    let text = $content.sliceSelection(r, false).text()
    let start = text.find("(")
    if start != -1:
      let file = text[(start + 1)..^2]
      if not file.endsWith("png"):
        continue

      echo &"{r} -> {file}"
      let (texture, width, height) = createTextureForFile(file)
      if texture == 0.TextureId:
        continue

      result.add ImageOverlay(range: r, texture: texture, width: width, height: height)

proc readMemoryChannel(chan: ref tuple[open: bool, write: WriteChannel, read: BufferedReadChannel]) {.async.} =
  while not chan.read.atEnd:
    let s = await chan.read.readLine()
    echo "\n'" & s & "'"
  echo "============= done"

var task: BackgroundTask = nil

proc toJsonHook*(editor: TextEditor): JsonNode =
  return %{"id": ($editor.id).toJson}

proc fromJsonHook*(editor: var Editor, json: JsonNode) =
  if json.kind == JObject and json.hasKey("id"):
    editor.id = json["id"].str.parseBiggestUint
  else:
    editor.id = 0

proc toJsonHook*(id: TextureId): JsonNode =
  return ($id).toJson

proc fromJsonHook*(id: var TextureId, json: JsonNode) =
  if json.kind == JString:
    id = json.str.parseBiggestUint.TextureId
  else:
    id = 0.TextureId

type
  RequestKind = enum ScanFile
  Request = object
    case kind: RequestKind
    of ScanFile:
      editor: TextEditor
      path: string
      ropePath: string

  ResponseKind = enum UpdateImages
  Response = object
    case kind: ResponseKind
    of UpdateImages:
      editor: TextEditor
      images: seq[ImageOverlay]

proc readThreadChannel(task: BackgroundTask) {.async.} =
  while not task.reader.atEnd:
    try:
      let line = await task.reader.readLine()
      let response = line.parseJson().jsonTo(Response)
      log lvlInfo, &"handleResponse {response}"
      case response.kind
      of UpdateImages:
        response.editor.clearOverlays(5)
        for overlay in response.images:
          let id = response.editor.addCustomRender(customOverlayRender)
          let r = overlay.range
          overlays[id] = (Below, overlay.texture, overlay.width, overlay.height, r.last.column.int - r.first.column.int)
          log lvlInfo, &"Add image overlay {overlay} with id {id}"
          response.editor.addOverlay(Selection(first: r.first, last: r.first), "*", 5, "comment", Bias.Right, id, Below)
    except CatchableError as e:
      log lvlError, &"Failed to add image overlays: {e.msg}"
  log lvlError, "[readThreadChannel] done"

proc sendRequest(request: Request) =
  {.gcsafe.}:
    let str = $request.toJson() & "\n"
    echo &"sendRequest {request}"
    task.writer.writeString(str.ws)

proc sendResponse(task: BackgroundTask, response: Response) =
  {.gcsafe.}:
    let str = $response.toJson() & "\n"
    echo &"sendResponse {response}"
    task.writer.writeString(str.ws)

proc init() =
  if isMainThread():
    listenEvent "editor/*/loaded", proc(data: uint32, event: WitString, payload: WitString) {.cdecl, gcsafe, raises: [].} =
      try:
        let editor = TextEditor(id: ($payload).parseBiggestUint())
        let path = $editor.getDocument().mapIt(it.path()).get("")
        if path.endsWith(".md"):
          echo &"loaded {path}"
          let ropePath = editor.content().ropeMount(path.ws, true)
          sendRequest(Request(kind: ScanFile, editor: editor, path: path, ropePath: $ropePath))
      except CatchableError:
        discard

    listenEvent "editor/*/saved", proc(data: uint32, event: WitString, payload: WitString) {.cdecl, gcsafe, raises: [].} =
      try:
        let editor = TextEditor(id: ($payload).parseBiggestUint())
        let path = $editor.getDocument().mapIt(it.path()).get("")
        if path.endsWith(".md"):
          echo &"saved {path}"
          let ropePath = editor.content().ropeMount(path.ws, true)
          sendRequest(Request(kind: ScanFile, editor: editor, path: path, ropePath: $ropePath))
      except CatchableError:
        discard

    task = runInBackground Thread:
      proc(task: BackgroundTask) {.nimcall, async.} =
        while not task.reader.atEnd:
          try:
            let line = await task.reader.readLine()
            let request = line.parseJson().jsonTo(Request)
            echo &"handleRequest {request}"
            case request.kind
            of ScanFile:
              var rope = ropeOpen(request.ropePath.ws)
              if rope.isSome:
                echo &"got rope {request.ropePath.ws}"
                let images = findImagesInFile(rope.get)
                task.sendResponse(Response(kind: UpdateImages, editor: request.editor, images: images))

          except CatchableError as e:
            echo e.msg

        task.writer.close()
        finishBackground()

    discard task.readThreadChannel()

    # for editor in allTextEditors():
    #   let path = $editor.getDocument().mapIt(it.path()).get("")
    #   if path.endsWith(".md"):
    #     let ropePath = editor.content().ropeMount(path.ws, true)
    #     sendRequest(Request(kind: ScanFile, path: path, ropePath: $ropePath))
  else:
    discard defaultThreadHandler()


init()
