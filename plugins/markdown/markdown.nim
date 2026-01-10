import std/[os, strformat, json, jsonutils, strutils, options, random, math, sequtils, sugar, streams, tables, sets]
import pixie, chroma
import results
import util, render_command, binary_encoder
import api
import regex
import gif

# todo: this can easily conflict with other overlay uses
const markdownOverlayId = 5

type
  RequestKind = enum ScanFile, UpdateRemaps, ClearImageCache, ActiveGifs
  Request = object
    case kind: RequestKind
    of ScanFile:
      editor: TextEditor
      path: string
      ropePath: string
    of UpdateRemaps:
      remaps: seq[tuple[src: string, dst: string]]
    of ClearImageCache:
      discard
    of ActiveGifs:
      textures: seq[TextureId]

  ResponseKind = enum UpdateImages
  Response = object
    case kind: ResponseKind
    of UpdateImages:
      editor: TextEditor
      path: string
      images: seq[ImageOverlay]

  ImageOverlay = object
    range: Selection
    texture: LoadedTexture

  LoadedTexture = object
    texture: TextureId
    width: int
    height: int
    animated: bool

  GifState = ref object
    lastTime: float
    data: string
    texture: LoadedTexture
    iter: iterator(state: GifState): tuple[image: Image, timestamp: float] {.closure.}

  BackgroundState = object
    remaps: seq[tuple[src: string, dst: string]]
    loadedTextures: Table[string, LoadedTexture]
    gifStates: Table[TextureId, GifState]
    activeGifs: seq[TextureId]

  OverlayInstance = object
    editor: TextEditor
    location: OverlayRenderLocation
    textureId: TextureId
    width: float
    height: float
    len: int
    animated: bool
    frameIndex: int
    frameTime: float
    lastTime: float

var bgState = BackgroundState()
var imageScale: float = 1

converter toWitString(s: string): WitString = ws(s)

converter toVec(c: Vec2f): Vec2 =
  vec2(c.x, c.y)

proc sendRequest(request: Request) {.raises: [].}

var renderBuffer = BinaryEncoder()
var overlays: Table[int64, OverlayInstance]
var lastRenderedOverlays = initHashSet[int64]()
var currentRenderedOverlays = initHashSet[int64]()
proc drawOverlayImage(id: int64, overlaySize: Vec2f, localOffset: int): (pointer, int) {.cdecl, raises: [].} =
  renderBuffer.reset()
  currentRenderedOverlays.incl(id)

  if id in overlays:
    let overlay = overlays[id].addr
    let textureId = overlay.textureId
    let aspectRatio = overlay.width / overlay.height

    let now = getTime()
    let dt = now - overlay.lastTime
    overlay.lastTime = now

    var imageWidth = max(overlaySize.x * imageScale, 1)
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

    if overlay.animated:
      discard overlay.editor.command(ws"rerender", ws"")
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

proc remapPath(bgState: BackgroundState, path: string): string =
  for r in bgState.remaps:
    if path.startsWith(r.src):
      var subPath = path
      subPath.removePrefix(r.src)
      return r.dst & subPath

  return path

iterator gifFrames(state: GifState): tuple[image: Image, timestamp: float] {.closure.} =
  try:
    for frame in decodeGif(state.data, loop = true):
      yield frame
  except CatchableError:
    discard

proc tickGifs(state: BackgroundState) {.raises: [].} =
  let t = getTime() * 0.001
  for gifTex in state.activeGifs:
    let gif = state.gifStates.getOrDefault(gifTex, nil)
    if gif == nil:
      continue

    try:
      let dt = t - gif.lastTime
      if t > gif.lastTime:
        let (frame, timestamp) = gif.iter(gif)
        if finished(gif.iter):
          gif.iter = gifFrames
          continue
        gif.lastTime = t + timestamp
        if frame == nil or frame.data.len == 0:
          continue
        updateTexture(gif.texture.texture.uint64, gif.texture.width.int32, gif.texture.height.int32, cast[uint32](frame.data[0].addr), Rgba8)
    except:
      discard

proc createTextureForFile(path: string): LoadedTexture =
  let s = stackSave()
  defer:
    stackRestore(s)

  if path in bgState.loadedTextures:
    return bgState.loadedTextures[path]

  let remappedPath = bgState.remapPath(path)
  var res = readSync(remappedPath, {Binary})
  if res.isOk:
    try:
      if path.endsWith(".gif"):
        # Create texture for first frame
        for (frame, timestamp) in decodeGif(res.get.toOpenArray()):
          let id = createTexture(frame.width.int32, frame.height.int32, cast[uint32](frame.data[0].addr), Rgba8, true)
          result = LoadedTexture(texture: id.TextureId, width: frame.width, height: frame.height, animated: true)
          break

        bgState.gifStates[result.texture] = GifState(iter: gifFrames, data: $res.get, texture: result, lastTime: getTime() * 0.001)
        bgState.loadedTextures[path] = result
      else:
        let image = decodeImage($res.get)
        let id = createTexture(image.width.int32, image.height.int32, cast[uint32](image.data[0].addr), Rgba8, false)
        result = LoadedTexture(texture: id.TextureId, width: image.width, height: image.height)
        bgState.loadedTextures[path] = result
    except CatchableError as e:
      log lvlError, &"Failed to decode image: {e.msg}\n{e.getStackTrace()}"
      return
  else:
    log lvlError, &"Failed to read image '{path}' (mapped to '{remappedPath}'): {res.error}"
    result = LoadedTexture()
    bgState.loadedTextures[path] = result
    return

iterator findImagesInFile(content: Rope): ImageOverlay =
  let regex = "\\[.*?\\]\\(.*?\\)"
  let imageRanges = content.findAll(regex)
  for r in imageRanges:
    let text = $content.sliceSelection(r, false).text()
    let start = text.find("(")
    if start != -1:
      let file = text[(start + 1)..^2]
      let ext = file.splitFile.ext
      case ext
      of ".png", ".jpeg", ".gif", ".bpm", ".qoi", ".ppm":
        discard
      else:
        continue

      let tex = createTextureForFile(file)
      if tex.texture == 0.TextureId:
        continue

      yield ImageOverlay(range: r, texture: tex)

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

proc handleResponse(response: Response) =
  case response.kind
  of UpdateImages:
    let currentPath = $response.editor.getDocument().mapIt(it.path()).get("")
    if currentPath != response.path:
      return
    response.editor.clearOverlays(markdownOverlayId)
    for overlay in response.images:
      let id = response.editor.addCustomRender(drawOverlayImage)
      let r = overlay.range
      response.editor.addOverlay(Selection(first: r.first, last: r.first), "*", markdownOverlayId, "comment", Bias.Right, id, Inline)

      overlays[id] = OverlayInstance(
        editor: response.editor,
        location: Inline,
        textureId: overlay.texture.texture,
        width: overlay.texture.width.float,
        height: overlay.texture.height.float,
        len: r.last.column.int - r.first.column.int,
        animated: overlay.texture.animated,
      )

proc readThreadChannel(task: BackgroundTask) {.async.} =
  while not task.reader.atEnd:
    try:
      let line = await task.reader.readLine()
      let response = line.parseJson().jsonTo(Response)
      handleResponse(response)
    except CatchableError as e:
      log lvlError, &"Failed to add image overlays: {e.msg}"

proc sendRequest(request: Request) =
  {.gcsafe.}:
    let str = $request.toJson() & "\n"
    task.writer.writeString(str.ws)

proc sendResponse(task: BackgroundTask, response: Response) =
  {.gcsafe.}:
    let str = $response.toJson() & "\n"
    task.writer.writeString(str.ws)

proc scanFile(editor: TextEditor) =
  let path = $editor.getDocument().mapIt(it.path()).get("")
  {.gcsafe.}:
    if path.endsWith(".md"):
      let ropePath = editor.content().ropeMount(path.ws, true)
      sendRequest(Request(kind: ScanFile, editor: editor, path: path, ropePath: $ropePath))

proc updateRemaps() =
  let remaps = getSetting("plugin.markdown.path-remaps", seq[seq[string]])
  var request = Request(kind: UpdateRemaps)
  for r in remaps:
    if r.len == 2:
      request.remaps.add (r[0], r[1])
    else:
      log lvlError, &"Invalid markdown image path remap, expected array of two strings (src and dst), got {r}"
  sendRequest(request)

if isMainThread():
  proc saveState() =
    setSessionData("imageScale", imageScale)

  proc loadState() =
    imageScale = getSessionData("imageScale", float)
    imageScale = clamp(imageScale, 0.001, 10000)

  listenEvent "session/save", proc(data: uint32, event: WitString, payload: WitString) {.cdecl, gcsafe, raises: [].} =
    saveState()

  listenEvent "session/restored", proc(data: uint32, event: WitString, payload: WitString) {.cdecl, gcsafe, raises: [].} =
    loadState()

  setPluginSaveCallback(proc(): string =
    saveState()
    return ""
  )

  listenEvent "platform/prerender", proc(data: uint32, event: WitString, payload: WitString) {.cdecl, gcsafe, raises: [].} =
    if lastRenderedOverlays != currentRenderedOverlays:
      let textures = collect:
        for id in currentRenderedOverlays:
          if id in overlays:
            overlays[id].textureId
      sendRequest(Request(kind: ActiveGifs, textures: textures))
    lastRenderedOverlays = currentRenderedOverlays
    currentRenderedOverlays.clear()

  listenEvent "editor/*/loaded", proc(data: uint32, event: WitString, payload: WitString) {.cdecl, gcsafe, raises: [].} =
    try:
      let editor = TextEditor(id: ($payload).parseBiggestUint())
      scanFile(editor)
    except CatchableError:
      discard

  listenEvent "editor/*/saved", proc(data: uint32, event: WitString, payload: WitString) {.cdecl, gcsafe, raises: [].} =
    try:
      let editor = TextEditor(id: ($payload).parseBiggestUint())
      scanFile(editor)
    except CatchableError:
      discard

  loadState()

  proc threadTickGifs() {.async.} =
    while true:
      await sleepAsync(10)
      bgState.tickGifs()

  task = runInBackground Thread:
    proc(task: BackgroundTask) {.nimcall, async.} =
      discard threadTickGifs()
      while not task.reader.atEnd:
        try:
          let line = await task.reader.readLine()
          let request = line.parseJson().jsonTo(Request)
          case request.kind
          of ScanFile:
            var rope = ropeOpen(request.ropePath.ws)
            if rope.isSome:
              var images: seq[ImageOverlay] = @[]
              for image in findImagesInFile(rope.get):
                images.add(image)
                task.sendResponse(Response(kind: UpdateImages, editor: request.editor, path: request.path, images: images))
          of UpdateRemaps:
            bgState.remaps = request.remaps
          of ClearImageCache:
            # todo: delete textures
            for tex in bgState.loadedTextures.values:
              deleteTexture(tex.texture.uint64)
            bgState.loadedTextures.clear()
          of ActiveGifs:
            bgState.activeGifs = request.textures

        except CatchableError as e:
          log lvlError, e.msg

      task.writer.close()
      finishBackground()

  discard task.readThreadChannel()

  updateRemaps()

  for editor in allTextEditors():
    scanFile(editor)
else:
  discard defaultThreadHandler()

defineCommand(ws"change-image-scale",
  active = false,
  docs = ws"Change size of images",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      let s = ($args).parseJson.jsonTo(float)
      imageScale *= s
      imageScale = clamp(imageScale, 0.001, 10000)
      for editor in allTextEditors():
        discard editor.command(ws"rerender", ws"")
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"set-image-scale",
  active = false,
  docs = ws"Change size of images",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      let s = ($args).parseJson.jsonTo(float)
      imageScale = clamp(s, 0.001, 10000)
      for editor in allTextEditors():
        discard editor.command(ws"rerender", ws"")
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"clear-image-cache",
  active = false,
  docs = ws"Change size of images",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      sendRequest(Request(kind: ClearImageCache))
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""
