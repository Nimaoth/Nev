import std/[os, macros, genasts, strutils, sequtils, sugar, strformat, options, random, tables, sets, strmisc]
import src/macro_utils, src/util, src/id
import vmath, rect_utils, timer, lrucache, ui/node
import custom_logger

var retainMainText* = true

let pop1Id* = newPrimaryId()
let pop2Id* = newPrimaryId()
var popup1* = neww (vec2(100, 100), vec2(0, 0), false)
var popup2* = neww (vec2(200, 200), vec2(0, 0), false)
var showPopup1* = false
var showPopup2* = false

var sliderMin* = 0.float32
var sliderMax* = 100.float32
var sliderStep* = 1.float32
var slider* = 35.float32

var counter = 0
var testWidth = 10.float32

let lastTextArea* = newPrimaryId()
var cursor*: (int, int) = (0, 0)

var mainTextChanged* = false

const testText* = """
import std/[os, macros, genasts, strutils, sequtils, sugar, strformat, options, random, tables, sets]
import src/macro_utils, src/util, src/id
import boxy, boxy/textures, pixie, windy, vmath, rect_utils, opengl, timer, lrucache, ui/node
import custom_logger

logger.enableConsoleLogger()
logCategory "test", true

var showPopup1 = true
var showPopup2 = false

var logRoot = false
var logFrameTime = true
var showDrawnNodes = true

var advanceFrame = false
var counter = 0
var testWidth = 10.float32
var invalidateOverlapping* = true

var popup1 = neww (vec2(100, 100), vec2(0, 0), false)
var popup2 = neww (vec2(200, 200), vec2(0, 0), false)

var cursor = (0, 0)
var mainTextChanged = false
var retainMainText = true
""".splitLines(keepEol=false)

const testText2 = """
proc getFont*(font: string, fontSize: float32): Font =
  let typeface = readTypeface(font)

  result = newFont(typeface)
  result.paint.color = color(1, 1, 1)
  result.size = fontSize
""".splitLines(keepEol=false)

const testText3 = """
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

var drawnNodes: seq[UINode] = @[]
""".splitLines(keepEol=false)


template button*(builder: UINodeBuilder, name: string, body: untyped): untyped =
  builder.panel(&{DrawText, FillBackground, SizeToContentX, SizeToContentY, MouseHover}, text = name):
    currentNode.setTextColor(1, 0, 0)

    if currentNode.some == builder.hoveredNode:
      currentNode.setBackgroundColor(0.6, 0.5, 0.5)
    else:
      currentNode.setBackgroundColor(0.3, 0.2, 0.2)

    onClick Left:
      body

template withText*(builder: UINodeBuilder, str: string, body: untyped): untyped =
  builder.panel(&{DrawText, FillBackground, SizeToContentX, SizeToContentY}, text = str):
    # currentNode.setTextColor(1, 0, 0)
    # currentNode.setBackgroundColor(0, 0, 0)

    body

iterator splitLine(str: string): string =
  if str.len == 0:
    yield ""
  else:
    var start = 0
    var i = 0
    var ws = str[0] in Whitespace
    while i < str.len:
      let currWs = str[i] in Whitespace
      if ws != currWs:
        yield str[start..<i]
        start = i
        ws = currWs
      inc i
    if start < i:
      yield str[start..<i]

proc renderLine*(builder: UINodeBuilder, line: string, curs: Option[int], backgroundColor, textColor: Color, sizeToContentX: bool): Option[(UINode, string, Rect)] =
  var flags = &{LayoutHorizontal, FillX, SizeToContentY}
  if sizeToContentX:
    flags.incl SizeToContentX

  builder.panel(flags):
    var start = 0
    var lastPartXW: float32 = 0
    for part in line.splitLine:
      defer:
        start += part.len

      builder.withText(part):
        currentNode.backgroundColor = backgroundColor
        currentNode.textColor = textColor

        # cursor
        if curs.getSome(curs) and curs >= start and curs < start + part.len:
          let cursorX = builder.textWidth(curs - start).round
          result = some (currentNode, $part[curs - start], rect(cursorX, 0, builder.charWidth, builder.textHeight))

        lastPartXW = currentNode.bounds.xw

    # cursor after latest char
    if curs.getSome(curs) and curs == line.len:
      result = some (currentNode, "", rect(lastPartXW, 0, builder.charWidth, builder.textHeight))

    # Fill rest of line with background
    builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = backgroundColor)

proc renderText*(builder: UINodeBuilder, changed: bool, lines: openArray[string], first: int, cursor: (int, int), backgroundColor, textColor: Color, sizeToContentX = false, sizeToContentY = true, id = noneUserId) =
  var flags = &{MaskContent, OverlappingChildren}
  var flagsInner = &{LayoutVertical}
  if sizeToContentX:
    flags.incl SizeToContentX
    flagsInner.incl SizeToContentX
  else:
    flags.incl FillX
    flagsInner.incl FillX

  if sizeToContentY:
    flags.incl SizeToContentY
    flagsInner.incl SizeToContentY
  else:
    flags.incl FillY
    flagsInner.incl FillY

  builder.panel(flags, userId = id):
    if not retainMainText or changed or not builder.retain():
      # echo "render text ", lines[0]

      var cursorLocation = (UINode, string, Rect).none

      builder.panel(flagsInner):
        for i, line in lines:
          let column = if cursor[0] == i: cursor[1].some else: int.none
          if builder.renderLine(line, column, backgroundColor, textColor, sizeToContentX).getSome(cl):
            cursorLocation = cl.some
          # break

      # let cursorX = builder.textWidth(curs - start).round
      if cursorLocation.getSome(cl):
        var bounds = cl[2].transformRect(cl[0], currentNode) - vec2(1, 0)
        bounds.w += 1
        builder.panel(&{FillBackground, AnimateBounds}, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, backgroundColor = color(0.7, 0.7, 1)):
          builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, x = 1, y = 0, text = cl[1], textColor = color(0.4, 0.2, 2))

proc createPopup*(builder: UINodeBuilder, lines: openArray[string], pop: ref tuple[pos: Vec2, offset: Vec2, collapsed: bool], backgroundColor, borderColor, headerColor, textColor: Color, id = noneUserId) =
  let pos = pop.pos + pop.offset

  var flags = &{LayoutVertical, SizeToContentX, SizeToContentY, MouseHover, MaskContent}
  if pop.collapsed:
    flags.incl SizeToContentY

  when defined(js):
    flags.incl FillBackground

  builder.panel(flags, x = pos.x, y = pos.y, userId = id, backgroundColor = backgroundColor): # draggable overlay
    currentNode.setBorderColor(1, 0, 1)
    currentNode.flags.incl DrawBorder

    let headerWidth = if pop.collapsed: 100.float32.some else: float32.none

    # header
    builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal}, w = headerWidth):
      currentNode.setBackgroundColor(0.2, 0.2, 0.2)
      builder.button("X"):
        pop.collapsed = not pop.collapsed

      onClick Left:
        pop.pos += pop.offset
        pop.offset = vec2(0, 0)
        builder.draggedNode = currentNode.some

      onDrag Left:
        pop.offset = builder.mousePos - builder.mousePosClick[Left]

    if not pop.collapsed:
      builder.renderText(false, lines, 0, (0, 0), backgroundColor=backgroundColor, textColor = textColor, sizeToContentX = true)

proc createSlider*(builder: UINodeBuilder, value: float32, inBackgroundColor, handleColor: Color, min: float32 = 0, max: float32 = 1, step: float32 = 0, valueChanged: proc(value: float32) = nil) =
  builder.panel(&{FillX, FillBackground, LayoutHorizontal}, h = builder.textHeight):
    currentNode.backgroundColor = inBackgroundColor

    builder.panel(&{SizeToContentY, DrawText}, text = fmt"{value:6.2f}", textColor = color(1, 1, 1), w = 100)

    builder.panel(&{FillX, FillY, DrawBorder}, borderColor = handleColor):
      let slider = currentNode

      let x = (slider.w - builder.charWidth) * ((value - min).abs / (max - min).abs).clamp(0, 1)
      builder.panel(&{FillY, FillBackground}, x = x, w = builder.charWidth):
        currentNode.backgroundColor = handleColor

      proc updateValue() =
        let alpha = ((builder.mousePos.x - slider.lx - builder.charWidth * 0.5) / (slider.w - builder.charWidth)).clamp(0, 1)
        var targetValue = if max >= min:
          min + alpha * (max - min)
        else:
          min - alpha * (min - max)

        if step > 0:
          targetValue = (targetValue / step).round * step

        if valueChanged.isNotNil:
          valueChanged(targetValue)

      onClick Left:
        builder.draggedNode = currentNode.some
        updateValue()

      onDrag Left:
        updateValue()

proc createCheckbox*(builder: UINodeBuilder, value: bool, valueChanged: proc(value: bool) = nil) =
  let margin = builder.textHeight * 0.2
  builder.panel(&{FillBackground}, w = builder.textHeight, h = builder.textHeight, backgroundColor = color(0.5, 0.5, 0.5)):
    if value:
      builder.panel(&{FillBackground, AnimateBounds}, x = margin, y = margin, w = builder.textHeight - margin * 2, h = builder.textHeight - margin * 2, backgroundColor = color(0.8, 0.8, 0.8))
    else:
      builder.panel(&{FillBackground, AnimateBounds}, x = builder.textHeight / 2, y = builder.textHeight / 2, w = 0, h = 0, backgroundColor = color(0.8, 0.8, 0.8))

    onClick Left:
      if valueChanged.isNotNil:
        valueChanged(not value)

template createLine(builder: UINodeBuilder, body: untyped) =
  builder.panel(&{FillX, SizeToContentY, LayoutHorizontal}):
    body

    # fill background
    builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

proc buildUINodes*(builder: UINodeBuilder) =
  var rootFlags = &{FillX, FillY, OverlappingChildren, MaskContent}

  builder.panel(rootFlags, backgroundColor = color(0, 0, 0)): # fullscreen overlay

    builder.panel(&{FillX, FillY, LayoutVertical}): # main panel

      builder.createLine: builder.createSlider(sliderMin, color(0.5, 0.3, 0.3), color(0.9, 0.6, 0.6), min = -200, max = 200, step = 0.1, (value: float32) => (sliderMin = value))
      builder.createLine: builder.createSlider(sliderMax, color(0.3, 0.5, 0.3), color(0.6, 0.9, 0.6), min = -200, max = 200, step = 0.1, (v: float32) => (sliderMax = v))
      builder.createLine: builder.createSlider(sliderStep, color(0.3, 0.3, 0.5), color(0.6, 0.6, 0.9), min = 0.1, max = 10, step = 0.1, (v: float32) => (sliderStep = v))
      builder.createLine: builder.createSlider(slider, color(0.3, 0.5, 0.3), color(0.6, 0.9, 0.6), min = sliderMin, max = sliderMax, step = sliderStep, (v: float32) => (slider = v))
      builder.createLine: builder.createCheckbox(showPopup1, (v: bool) => (showPopup1 = v))
      builder.createLine: builder.createCheckbox(showPopup2, (v: bool) => (showPopup2 = v))

      if not showPopup2:
        builder.createLine: builder.createCheckbox(showPopup2, (v: bool) => (showPopup2 = v))
      else:
        builder.panel(&{FillX})

      builder.panel(&{LayoutHorizontal, FillX, SizeToContentY}): # first row
        builder.button("press me"):
          if btn == MouseButton.Left:
            inc counter
        builder.withText($counter):
          currentNode.textColor = color(1, 1, 1)
          currentNode.backgroundColor = color(0, 0, 0)
        builder.withText(" * "):
          currentNode.textColor = color(1, 1, 1)
          currentNode.backgroundColor = color(0, 0, 0)
        builder.withText($counter):
          currentNode.textColor = color(1, 1, 1)
          currentNode.backgroundColor = color(0, 0, 0)
        builder.withText(" = "):
          currentNode.textColor = color(1, 1, 1)
          currentNode.backgroundColor = color(0, 0, 0)
        builder.withText($(counter * counter)):
          currentNode.textColor = color(1, 1, 1)
          currentNode.backgroundColor = color(0, 0, 0)
        builder.panel(&{FillX, FillY, FillBackground}):
          currentNode.backgroundColor = color(0, 0, 0)

      builder.panel(&{LayoutHorizontal, FillX, SizeToContentY}): # second row
        builder.button("-"):
          if btn == MouseButton.Left:
            testWidth = testWidth / 1.5
        builder.button("+"):
          if btn == MouseButton.Left:
            testWidth = testWidth * 1.5
        builder.panel(&{FillBackground, FillY, AnimateBounds}, w = testWidth):
          currentNode.setBackgroundColor(0, 1, 0)
        builder.panel(&{FillBackground, FillY, AnimateBounds}, w = 50):
          currentNode.setBackgroundColor(1, 0, 0)
        builder.panel(&{FillX, FillY, FillBackground, AnimateBounds}):
          currentNode.setBackgroundColor(0, 0, 1)

      # text area
      builder.renderText(mainTextChanged, testText, 0, cursor, backgroundColor = color(0.1, 0.1, 0.1), textColor = color(0.9, 0.9, 0.9), sizeToContentX = false, id = lastTextArea)

      # background filler
      builder.panel(&{FillX, FillY, FillBackground}):
        currentNode.setBackgroundColor(0, 0, 1)

    if showPopup1:
      builder.createPopup(testText2, popup1, backgroundColor = color(0.3, 0.1, 0.1), textColor = color(0.9, 0.5, 0.5), headerColor = color(0.4, 0.2, 0.2), borderColor = color(1, 0.1, 0.1), id = pop1Id)
    if showPopup2:
      builder.createPopup(testText3, popup2, backgroundColor = color(0.1, 0.3, 0.1), textColor = color(0.5, 0.9, 0.5), headerColor = color(0.2, 0.4, 0.2), borderColor = color(0.1, 1, 0.1), id = pop2Id)