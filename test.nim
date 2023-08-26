import std/[os, macros, genasts, strutils, sequtils, sugar, strformat, options, random, tables, sets]
import src/macro_utils, src/util, src/id
import boxy, boxy/textures, pixie, windy, vmath, rect_utils, opengl, timer, lrucache, ui/node
import custom_logger

logger.enableConsoleLogger()
logCategory "test", true

const testText = """
macro defineBitFlag*(body: untyped): untyped =
  let flagName = body[0][0].typeName
  let flagsName = (flagName.repr & "s").ident

  result = genAst(body, flagName, flagsName):
    body
    type flagsName* = distinct uint32

    func contains*(flags: flagsName, flag: flagName): bool {.inline.} = (flags.uint32 and (1.uint32 shl flag.uint32)) != 0
    func contains*(flags: flagsName, expected: flagsName): bool {.inline.} = (flags.uint32 and expected.uint32) == expected.uint32
    func incl*(flags: var flagsName, flag: flagName) {.inline.} =
      flags = (flags.uint32 or (1.uint32 shl flag.uint32)).flagsName
    func excl*(flags: var flagsName, flag: flagName) {.inline.} =
      flags = (flags.uint32 and not (1.uint32 shl flag.uint32)).flagsName

    func `==`*(a, b: flagsName): bool {.borrow.}

    macro `&`*(flags: static set[flagName]): flagsName =
      var res = 0.flagsName
      for flag in flags:
        res.incl flag
      return genAst(res2 = res.uint32):
        res2.flagsName

    iterator flags*(self: flagsName): flagName =
      for v in flagName.low..flagName.high:
        if (self.uint32 and (1.uint32 shl v.uint32)) != 0:
          yield v

    proc `$`*(self: flagsName): string =
      var res2: string = "{"
      for flag in self.flags:
        if res2.len > 1:
          res2.add ", "
        res2.add $flag
      res2.add "}"
      return res2
""".splitLines(keepEol=false)

const testText2 = """
hi, wassup?
lol
uiaeuiaeuiae
uiui uia eu
""".splitLines(keepEol=false)

proc getFont*(font: string, fontSize: float32): Font =
  let typeface = readTypeface(font)

  result = newFont(typeface)
  result.paint.color = color(1, 1, 1)
  result.size = fontSize

var builder = newNodeBuilder()

var image = newImage(1000, 1000)
var ctx = newContext(image)
ctx.strokeStyle = rgb(255, 0, 0)
ctx.font = "fonts/FiraCode-Regular.ttf"
ctx.fontSize = 17

let font = getFont(ctx.font, ctx.fontSize)
let bounds = font.typeset(repeat("#", 100)).layoutBounds()

builder.charWidth = bounds.x / 100.0
builder.lineHeight = bounds.y - 3
builder.lineGap = 6

var framebufferId: GLuint
var framebuffer: Texture

var window = newWindow("", ivec2(image.width.int32 * 2, image.height.int32), WindowStyle.DecoratedResizable)
makeContextCurrent(window)
loadExtensions()
enableAutoGLerrorCheck(false)

var bxy = newBoxy()
bxy.addImage("image", image)

framebuffer = Texture()
framebuffer.width = image.width.int32 * 2
framebuffer.height = image.height.int32
framebuffer.componentType = GL_UNSIGNED_BYTE
framebuffer.format = GL_RGBA
framebuffer.internalFormat = GL_RGBA8
framebuffer.minFilter = minLinear
framebuffer.magFilter = magLinear
bindTextureData(framebuffer, nil)

glGenFramebuffers(1, framebufferId.addr)
glBindFramebuffer(GL_FRAMEBUFFER, framebufferId)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, framebuffer.textureId, 0)
glBindFramebuffer(GL_FRAMEBUFFER, 0)
bxy.setTargetFramebuffer framebufferId

var nodesDrawn = 0
var drawnNodes: seq[UINode] = @[]

var cachedImages: LruCache[string, string] = newLruCache[string, string](1000, true)

proc strokeRect*(boxy: Boxy, rect: Rect, color: Color, thickness: float = 1, offset: float = 0) =
  let rect = rect.grow(vec2(thickness * offset, thickness * offset))
  boxy.drawRect(rect.splitV(thickness.relative)[0].shrink(vec2(0, thickness)), color)
  boxy.drawRect(rect.splitVInv(thickness.relative)[1].shrink(vec2(0, thickness)), color)
  boxy.drawRect(rect.splitH(thickness.relative)[0], color)
  boxy.drawRect(rect.splitHInv(thickness.relative)[1], color)

proc drawNode(builder: UINodeBuilder, node: UINode, offset: Vec2 = vec2(0, 0)) =
  var nodePos = offset
  nodePos.x += node.x
  nodePos.y += node.y

  if node.lastChange < builder.frameIndex and node.lx == nodePos.x and node.ly == nodePos.y and node.lw == node.w and node.lh == node.h:
    return

  if node.flags.any &{FillBackground, DrawBorder, DrawText}:
    inc nodesDrawn
    drawnNodes.add node
  debug "draw ", node.dump

  node.lx = nodePos.x
  node.ly = nodePos.y
  node.lw = node.w
  node.lh = node.h
  let bounds = rect(nodePos.x, nodePos.y, node.w, node.h)

  if FillBackground in node.flags:
    bxy.drawRect(bounds, node.backgroundColor)

  # Mask the rest of the rendering is this function to the contentBounds
  if MaskContent in node.flags:
    bxy.pushLayer()
  defer:
    if MaskContent in node.flags:
      bxy.pushLayer()
      bxy.drawRect(bounds, color(1, 0, 0, 1))
      bxy.popLayer(blendMode = MaskBlend)
      bxy.popLayer()

  if DrawText in node.flags:
    let key = node.text
    var imageId: string
    if cachedImages.contains(key):
      imageId = cachedImages[key]
    else:
      imageId = $newId()
      cachedImages[key] = imageId

      # let font = renderer.getFont(renderer.ctx.fontSize * (1 + self.fontSizeIncreasePercent), self.style.fontStyle)

      const wrap = false
      let wrapBounds = if wrap: vec2(node.w, node.h) else: vec2(0, 0)
      let arrangement = font.typeset(node.text, bounds=wrapBounds)
      var bounds = arrangement.layoutBounds()
      if bounds.x == 0:
        bounds.x = 1
      if bounds.y == 0:
        bounds.y = builder.textHeight
      # const textExtraHeight = 10.0
      # bounds.y += textExtraHeight

      var image = newImage(bounds.x.int, bounds.y.int)
      image.fillText(arrangement)
      bxy.addImage(imageId, image, false)

    let pos = vec2(nodePos.x.floor, nodePos.y.floor)
    bxy.drawImage(imageId, pos, node.textColor)

  for c in node.children:
    builder.drawNode(c, nodePos)

  if DrawBorder in node.flags:
    bxy.strokeRect(bounds, node.borderColor)

template panel*(builder: UINodeBuilder, body: untyped): untyped =
  builder.panel(0.UINodeFlags, body)

template button*(builder: UINodeBuilder, name: string, body: untyped): untyped =
  builder.panel(&{DrawText, DrawBorder, FillBackground, SizeToContentX, SizeToContentY}):
    currentNode.setTextColor(1, 0, 0)
    currentNode.setBackgroundColor(0.5, 0.5, 0)

    currentNode.text = name

    onClick:
      body

template withText*(builder: UINodeBuilder, str: string, body: untyped): untyped =
  builder.panel(&{DrawText, FillBackground, SizeToContentX, SizeToContentY, LayoutHorizontal}):
    currentNode.setTextColor(1, 0, 0)
    currentNode.setBackgroundColor(0, 0, 0)

    currentNode.text = str

    body

proc randomColor(node: UINode, a: float32): Color =
  let h = node.id.hash
  result.r = (((h shr 0) and 0xff).float32 / 255.0).sqrt
  result.g = (((h shr 8) and 0xff).float32 / 255.0).sqrt
  result.b = (((h shr 16) and 0xff).float32 / 255.0).sqrt
  result.a = a

var logRoot = false

template frame(builder: UINodeBuilder, body: untyped) =
  block:
    # echo "=========================== ", builder.frameIndex
    builder.beginFrame(vec2(image.width.float32, image.height.float32))

    let buildTime = startTimer()
    body
    builder.endFrame()
    echo "[build] ", buildTime.elapsed.ms, "ms"

    if logRoot:
      echo builder.root.dump(true)
    # for n in builder.nodePool.allNodes:
    #   debug n.dump
    #   if n.parent.isNotNil:
    #     debug "  parent: ", n.parent.dump
    #   if n.prev.isNotNil:
    #     debug "  prev: ", n.prev.dump
    #   if n.next.isNotNil:
    #     debug "  next: ", n.next.dump
    #   if n.first.isNotNil:
    #     debug "  first: ", n.first.dump
    #   if n.last.isNotNil:
    #     debug "  last: ", n.last.dump

    nodesDrawn = 0
    drawnNodes.setLen 0

    let drawTime = startTimer()
    builder.drawNode(builder.root)
    echo "[draw] ", drawTime.elapsed.ms, "ms (", nodesDrawn, " nodes)"

    if true:
      bxy.drawRect(rect(image.width.float32, 0, image.width.float32, image.height.float32), color(0, 0, 0))

      for node in drawnNodes:
        let c = node.randomColor(0.3)
        bxy.drawRect(rect(node.lx + image.width.float32, node.ly, node.lw, node.lh), c)

        if DrawBorder in node.flags:
          bxy.strokeRect(rect(node.lx + image.width.float32, node.ly, node.lw, node.lh), color(c.r, c.g, c.b, 0.5), 5, offset = 0.5)

    # builder.frameIndex.inc

    yield

var cursor = (0, 0)

proc renderLine(builder: UINodeBuilder, line: string, curs: Option[int]) =
  builder.panel(&{LayoutHorizontal, FillX, SizeToContentY}):
    builder.withText(line):
      if curs.getSome(curs) and curs <= line.high:
        builder.panel(&{FillY}):
          let width = builder.textWidth(curs).round
          currentNode.w = width

        # cursor
        builder.panel(&{FillY, FillBackground}):
          currentNode.w = builder.charWidth
          currentNode.setBackgroundColor(0.5, 0.5, 1, 0.7)
          # onClick:
          #   # echo "clicked cursor ", btn
          #   cursor[1] = rand(0..line.len)

    # cursor after latest char
    if curs.getSome(curs) and curs == line.len:
      builder.panel(&{FillY, FillBackground}):
        currentNode.w = builder.charWidth
        currentNode.setBackgroundColor(0.5, 0.5, 1, 1)
        onClick:
          # echo "clicked cursor ", btn
          cursor[1] = rand(0..line.len)

    # Fill rest of line with background
    builder.panel(&{FillX, FillY, FillBackground}):
      currentNode.setBackgroundColor(0, 1, 0, 1)

proc renderText(builder: UINodeBuilder, lines: openArray[string], first: int, cursor: (int, int)) =
  builder.panel(&{MaskContent, LayoutVertical, FillX, SizeToContentY}):
    for i, line in lines:
      let column = if cursor[0] == i: cursor[1].some else: int.none
      builder.renderLine(line, column)

iterator drawFrames() {.closure.} =
  var counter = 0
  var testWidth = 10.float32

  var popupPos = vec2(100, 100)
  var popupPos2 = vec2(400, 400)

  while true:
    builder.frame:
      builder.panel(&{FillX, FillY, OverlappingChildren}): # fullscreen overlay

        builder.panel(&{FillX, FillY, LayoutVertical}): # main panel

          builder.panel(&{LayoutHorizontal, FillX, SizeToContentY}): # first row
            builder.button("press me"):
              if btn == MouseButton.Left:
                inc counter
            builder.withText($counter):
              discard
            builder.withText(" * "):
              discard
            builder.withText($counter):
              discard
            builder.withText(" = "):
              discard
            builder.withText($(counter * counter)):
              discard

          builder.panel(&{LayoutHorizontal, FillX, SizeToContentY}): # second row
            builder.button("-"):
              if btn == MouseButton.Left:
                testWidth = testWidth / 1.5
            builder.button("+"):
              if btn == MouseButton.Left:
                testWidth = testWidth * 1.5
            builder.panel(&{FillBackground, FillY}):
              currentNode.w = testWidth
              currentNode.setBackgroundColor(0, 1, 0)
            builder.panel(&{FillBackground, FillY}):
              currentNode.w = 50
              currentNode.setBackgroundColor(1, 0, 0)
            builder.panel(&{FillX, FillY, FillBackground}):
              currentNode.setBackgroundColor(0, 0, 1)

          # text area
          builder.renderText(testText, 0, cursor)

          # background filler
          builder.panel(&{FillX, FillY, FillBackground}):
            currentNode.setBackgroundColor(0, 0, 1)

        builder.panel(&{LayoutVertical, DrawBorder}): # draggable overlay
          currentNode.x = popupPos.x
          currentNode.y = popupPos.y
          currentNode.w = 150
          currentNode.h = 150
          currentNode.setBorderColor(1, 0, 1)

          onDrag(MouseButton.Left, delta):
            echo "drag ", delta
            popupPos += delta

          builder.renderText(testText2, 0, (0, 0))

          # background filler
          builder.panel(&{FillX, FillY, FillBackground}):
            currentNode.setBackgroundColor(0, 0, 0)

        builder.panel(&{FillBackground}): # draggable overlay 2
          currentNode.x = popupPos2.x
          currentNode.y = popupPos2.y
          currentNode.w = 100
          currentNode.h = 100
          currentNode.setBackgroundColor(0, 1, 1)

          onDrag(MouseButton.Left, delta):
            echo "drag2 ", delta
            popupPos2 += delta

  builder.frameIndex = 0
  ctx.fillStyle = rgb(0, 0, 0)
  ctx.fillRect(0, 0, ctx.image.width.float32, ctx.image.height.float32)
  bxy.addImage("image" & $(builder.frameIndex mod 2), image)

var frameIterator: iterator() = drawFrames
var advanceFrame = false

proc toMouseButton(button: Button): MouseButton =
  result = case button:
    of MouseLeft: MouseButton.Left
    of MouseMiddle: MouseButton.Middle
    of MouseRight: MouseButton.Right
    of DoubleClick: MouseButton.DoubleClick
    of TripleClick: MouseButton.TripleClick
    else: MouseButton.Unknown

window.onMouseMove = proc() =
  let buttons = set[Button](window.buttonDown)
  let mouseDelta = window.mouseDelta.vec2
  if buttons.len > 0:
    # echo buttons, ", ", mouseDelta

    let targetNode = builder.root.findNodeContaining(window.mousePos.vec2, (node) => node.handleDrag.isNotNil)
    if targetNode.getSome(node):
      # echo "Found target ", node.dump
      for button in buttons:
        discard node.handleDrag()(node, button.toMouseButton, mouseDelta)
        advanceFrame = true

window.onButtonPress = proc(button: Button) =
  case button
  of MouseLeft, MouseRight, MouseMiddle, MouseButton4, MouseButton5, DoubleClick, TripleClick, QuadrupleClick:
    # echo "click ", button, ", ", window.mousePos
    let targetNode = builder.root.findNodeContaining(window.mousePos.vec2, (node) => node.handleClick.isNotNil)
    if targetNode.getSome(node):
      # echo "Found target ", node.dump
      discard node.handleClick()(node, button.toMouseButton)

  of Button.KeyX:
    window.closeRequested = true
    return
  of Button.KeyL:
    logRoot = not logRoot
  of Button.KeyC:
    logInvalidationRects = not logInvalidationRects
  of Button.KeyW:
    logPanel = not logPanel

  of Button.KeyUp:
    cursor[0] = max(0, cursor[0] - 1)
    cursor[1] = cursor[1].clamp(0, testText[cursor[0]].len)
  of Button.KeyDown:
    cursor[0] = min(testText.high, cursor[0] + 1)
    cursor[1] = cursor[1].clamp(0, testText[cursor[0]].len)

  of Button.KeyLeft:
    cursor[1] = max(0, cursor[1] - 1)
  of Button.KeyRight:
    cursor[1] = min(testText[cursor[0]].len, cursor[1] + 1)

  of Button.KeyHome:
    cursor[1] = 0
  of Button.KeyEnd:
    cursor[1] = testText[cursor[0]].len

  else:
    discard

  advanceFrame = true

advanceFrame = true
while not window.closeRequested:
  let frameTimer = startTimer()

  pollEvents()

  let tBeginFrame = startTimer()
  bxy.beginFrame(window.size, clearFrame=false)
  let msBeginFrame = tBeginFrame.elapsed.ms

  let tRemoveImages = startTimer()
  for image in cachedImages.removedKeys:
    bxy.removeImage(image)
  cachedImages.clearRemovedKeys()
  let msRemoveImages = tRemoveImages.elapsed.ms

  let tAdvanceFrame = startTimer()
  if advanceFrame:
    if frameIterator.finished:
      echo "============================================================== restarting frames"
      frameIterator = drawFrames
    frameIterator()
  let msAdvanceFrame = tAdvanceFrame.elapsed.ms

  # if bxy.hasImage("image1_" & $(builder.frameIndex mod 2)):
  #   bxy.drawImage("image1_" & $(builder.frameIndex mod 2), vec2(0, 0))
  # if bxy.hasImage("image2_" & $(builder.frameIndex mod 2)):
  #   bxy.drawImage("image2_" & $(builder.frameIndex mod 2), vec2(image.width.float32, 0))
  let tEndFrame = startTimer()
  bxy.endFrame()
  let msEndFrame = tEndFrame.elapsed.ms

  if advanceFrame:
    echo fmt"[frame] {nodesDrawn} {frameTimer.elapsed.ms}, begin: {msBeginFrame}, remove: {msRemoveImages}, advance: {msAdvanceFrame}, end: {msEndFrame}"

    glBindFramebuffer(GL_READ_FRAMEBUFFER, framebufferId)
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0)
    glBlitFramebuffer(
      0, 0, framebuffer.width.GLint, framebuffer.height.GLint,
      0, 0, window.size.x.GLint, window.size.y.GLint,
      GL_COLOR_BUFFER_BIT, GL_NEAREST.GLenum)

    window.swapBuffers()

  else:
    sleep(3)

  advanceFrame = false

window.close()