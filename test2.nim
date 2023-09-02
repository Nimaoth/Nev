import std/[os, macros, genasts, strutils, sequtils, sugar, strformat, options, random, tables, sets, strmisc, dom, unicode]
import src/macro_utils, src/util, src/id
import vmath, rect_utils, timer, lrucache, ui/node
import custom_logger, custom_async

import platform/platform, input, event, lrucache, theme

import test_lib

logCategory "js"

proc requestRender(redrawEverything = false)

var builder = newNodeBuilder()
var logRoot = false
var logFrameTime = false

var advanceFrame = false
var invalidateOverlapping* = true

type
  WheelEvent* {.importc.} = ref object of MouseEvent ## see `docs<https://developer.mozilla.org/en-US/docs/Web/API/WheelEvent>`_
    deltaX: float
    deltaY: float
    deltaZ: float
    deltaMode: uint

  ProgressEvent* {.importc.} = ref object of dom.Event ## see `docs<https://developer.mozilla.org/en-US/docs/Web/API/ProgressEvent>`_
    result*: cstring

  DragEvent = ref dom.DragEvent

type
  BrowserPlatform* = ref object of Platform
    content: Element
    boundsStack: seq[Rect]

    onResized*: event.Event[bool]

    mFontSize: float
    mLineHeight: float
    mLineDistance: float
    mCharWidth: float

    doubleClickTimer: Timer
    doubleClickCounter: int
    doubleClickTime: float

    escapedText: LruCache[string, string]

    domUpdates: seq[proc(): void]

    currentEvent: dom.Event

proc toInput(key: cstring, code: cstring, keyCode: int): int64
proc updateFontSettings*(self: BrowserPlatform)

proc getTextStyle(x, y, width, height: int, color, backgroundColor: cstring, italic, bold: bool, wrap: bool): cstring
proc getTextStyle(x, y, width, height: int, color, backgroundColor: cstring, italic, bold: bool, wrap: bool, fontSize: float): cstring
proc drawNode(builder: UINodeBuilder, platform: BrowserPlatform, element: var Element, node: UINode, force: bool = false)

proc getModifiers*(self: KeyboardEvent): Modifiers =
  if self.altKey:
    result.incl Modifier.Alt
  if self.shiftKey:
    result.incl Modifier.Shift
  if self.ctrlKey:
    result.incl Modifier.Control

proc getModifiers*(self: MouseEvent): Modifiers =
  if self.altKey:
    result.incl Modifier.Alt
  if self.shiftKey:
    result.incl Modifier.Shift
  if self.ctrlKey:
    result.incl Modifier.Control

proc getMouseButtons*(event: dom.MouseEvent): set[MouseButton] =
  let buttons = event.buttons
  if (buttons and 0b1) != 0: result.incl MouseButton.Left
  if (buttons and 0b10) != 0: result.incl MouseButton.Right
  if (buttons and 0b100) != 0: result.incl MouseButton.Middle

proc getMouseButton*(event: dom.MouseEvent): MouseButton =
  result = case event.button
  of 0: MouseButton.Left
  of 1: MouseButton.Middle
  of 2: MouseButton.Right
  else: MouseButton.Unknown

method init*(self: BrowserPlatform) =
  self.mFontSize = 18
  self.mLineHeight = 20
  self.mLineDistance = 2
  self.mCharWidth = 18
  self.supportsThinCursor = true
  self.doubleClickTime = 0.35

  self.escapedText = newLruCache[string, string](1000)

  self.layoutOptions.getTextBounds = proc(text: string, fontSizeIncreasePercent: float = 0): Vec2 =
    result.x = text.len.float * self.mCharWidth * (1 + fontSizeIncreasePercent)
    result.y = self.totalLineHeight * (1 + fontSizeIncreasePercent)

  window.addEventListener "resize", proc(e: dom.Event) =
    let oldEvent = self.currentEvent
    self.currentEvent = e
    defer: self.currentEvent = oldEvent

    self.onResized.invoke(true)

  self.content = document.getElementById("view")

  self.content.addEventListener("keydown", proc(e: dom.Event) =
    let oldEvent = self.currentEvent
    self.currentEvent = e
    defer: self.currentEvent = oldEvent

    let ke = e.KeyboardEvent
    let modifiers = ke.getModifiers
    # debugf"keyevent {ke.key}, {ke.code}, {ke.keyCode}"

    var input = toInput(ke.key, ke.code, ke.keyCode)
    # debugf"{inputToString(input)}, {modifiers}"
    self.onKeyPress.invoke (input, modifiers)
  )

  self.content.addEventListener("wheel", proc(e: dom.Event) =
    let oldEvent = self.currentEvent
    self.currentEvent = e
    defer: self.currentEvent = oldEvent

    let we = e.WheelEvent
    let modifiers = we.getModifiers

    # debugf"wheel {we.deltaX}, {we.deltaY}, {we.deltaZ}, {we.deltaMode}, {modifiers}"
    self.onScroll.invoke (vec2(we.clientX.float, we.clientY.float), vec2(we.deltaX, -we.deltaY) * 0.01, modifiers)
  , AddEventListenerOptions(passive: true))

  self.content.addEventListener("mousedown", proc(e: dom.Event) =
    let oldEvent = self.currentEvent
    self.currentEvent = e
    defer: self.currentEvent = oldEvent

    let me = e.MouseEvent
    let modifiers = me.getModifiers
    let mouseButton = me.getMouseButton

    let currentTargetRect = me.currentTarget.getBoundingClientRect()
    let x = me.pageX.float - currentTargetRect.x
    let y = me.pageY.float - currentTargetRect.y
    # debugf"click {me.button}, {modifiers}, {x}, {y}"
    self.onMousePress.invoke (mouseButton, modifiers, vec2(x.float, y.float))

    if mouseButton == MouseButton.Left:
      if self.doubleClickTimer.elapsed.float < self.doubleClickTime:
        inc self.doubleClickCounter
        case self.doubleClickCounter
        of 1:
          self.onMousePress.invoke (MouseButton.DoubleClick, modifiers, vec2(x.float, y.float))
        of 2:
          self.onMousePress.invoke (MouseButton.TripleClick, modifiers, vec2(x.float, y.float))
        else:
          self.doubleClickCounter = 0
      else:
        self.doubleClickCounter = 0

      self.doubleClickTimer = startTimer()
    else:
      self.doubleClickCounter = 0
  )

  self.content.addEventListener("mouseup", proc(e: dom.Event) =
    let oldEvent = self.currentEvent
    self.currentEvent = e
    defer: self.currentEvent = oldEvent

    let me = e.MouseEvent
    let modifiers = me.getModifiers
    let mouseButton = me.getMouseButton

    let currentTargetRect = me.currentTarget.getBoundingClientRect()
    let x = me.pageX.float - currentTargetRect.x
    let y = me.pageY.float - currentTargetRect.y
    # debugf"click {me.button}, {modifiers}, {x}, {y}"
    self.onMouseRelease.invoke (mouseButton, modifiers, vec2(x.float, y.float))
  )

  self.content.addEventListener("mousemove", proc(e: dom.Event) =
    let oldEvent = self.currentEvent
    self.currentEvent = e
    defer: self.currentEvent = oldEvent

    let me = e.MouseEvent
    let modifiers = me.getModifiers

    # debugf"move {me.button}, {modifiers}, {me.clientX}, {me.clientY}, {me.movementX}, {me.movementY}, {me.getMouseButtons}"
    self.onMouseMove.invoke (vec2(me.clientX.float, me.clientY.float), vec2(me.movementX.float, me.movementY.float), modifiers, me.getMouseButtons) # @todo: buttons
  )

  # proc console[T](t: T) {.importjs: "console.log(#);".}

  # self.content.addEventListener("dragover", proc(e: dom.Event) =
  #   let oldEvent = self.currentEvent
  #   self.currentEvent = e
  #   defer: self.currentEvent = oldEvent

  #   let de = e.DragEvent
  #   de.preventDefault()
  # )

  # self.content.addEventListener("drop", proc(e: dom.Event) =
  #   let oldEvent = self.currentEvent
  #   self.currentEvent = e
  #   defer: self.currentEvent = oldEvent

  #   let de = e.DragEvent
  #   de.preventDefault()
  #   console de.dataTransfer
  #   for f in de.dataTransfer.files:
  #     capture f:
  #       let fileReader = newFileReader()

  #       type RootObjRef = ref RootObj
  #       type File = dom.File
  #       proc result(fileReader: FileReader): cstring {.importjs: "(#.result || '')".}

  #       # @hack: we know that f is actually a file, but it's got the wrong type in std/dom
  #       fileReader.readAsText(f.RootObjRef.File)
  #       fileReader.onload = proc (e: dom.Event) =
  #         self.onDropFile.invoke ($f.name, $fileReader.result)
  # )

  self.updateFontSettings()
  self.content.focus()

method requestRender*(self: BrowserPlatform, redrawEverything = false) =
  self.redrawEverything = self.redrawEverything or redrawEverything
  self.onResized.invoke(redrawEverything)

method deinit*(self: BrowserPlatform) =
  discard

proc vec2Js*(x: float, y: float) {.importjs: "return {x: #, y: #};".}
method size*(self: BrowserPlatform): Vec2 =
  vec2Js(self.content.clientWidth.float, self.content.clientHeight.float)

proc `+=`*[T](a: cstring, b: T) {.importjs: "(#) += (#);".}
proc `+`*[T](a: cstring, b: T) {.importjs: "((#) + (#))".}

# method sizeChanged*(self: BrowserPlatform): bool =
#   let (w, h) = (terminalWidth(), terminalHeight())
#   return self.buffer.width != w or self.buffer.height != h

method preventDefault*(self: BrowserPlatform) =
  if self.currentEvent.isNil:
    return
  self.currentEvent.preventDefault()

proc updateFontSettings*(self: BrowserPlatform) =
  var d = document.createElement("div")
  d.setAttr("style", "position: absolute; visibility: hidden; height: auto; width: auto;")
  d.innerHTML = repeat("#", 100).cstring
  self.content.appendChild(d)
  self.mLineHeight = d.clientHeight.float
  self.mCharWidth = d.clientWidth.float / 100
  self.content.removeChild(d)

  builder.charWidth = self.mCharWidth
  builder.lineHeight = self.mLineHeight
  builder.lineGap = self.mLineDistance

method `fontSize=`*(self: BrowserPlatform, fontSize: float) =
  if self.mFontSize != fontSize:
    self.mFontSize = fontSize
    self.content.style.fontSize = ($fontSize).cstring
    self.redrawEverything = true
    self.updateFontSettings()

method fontSize*(self: BrowserPlatform): float =
  result = self.mFontSize

method lineDistance*(self: BrowserPlatform): float =
  self.mLineDistance

method lineHeight*(self: BrowserPlatform): float =
  self.mLineHeight

method charWidth*(self: BrowserPlatform): float =
  self.mCharWidth

method measureText*(self: BrowserPlatform, text: string): Vec2 =
  return vec2(text.len.float * self.mCharWidth, self.totalLineHeight)

proc toInput(key: cstring, code: cstring, keyCode: int): int64 =
  case key
  of "Enter": result = INPUT_ENTER
  of "Escape": result = INPUT_ESCAPE
  of "Backspace": result = INPUT_BACKSPACE
  of " ": result = INPUT_SPACE
  of "Delete": result = INPUT_DELETE
  of "Tab": result = INPUT_TAB
  of "ArrowLeft": result = INPUT_LEFT
  of "ArrowRight": result = INPUT_RIGHT
  of "ArrowUp": result = INPUT_UP
  of "ArrowDown": result = INPUT_DOWN
  of "Home": result = INPUT_HOME
  of "End": result = INPUT_END
  of "PageUp": result = INPUT_PAGE_UP
  of "PageDown": result = INPUT_PAGE_DOWN
  of "F1": result = INPUT_F1
  of "F2": result = INPUT_F2
  of "F3": result = INPUT_F3
  of "F4": result = INPUT_F4
  of "F5": result = INPUT_F5
  of "F6": result = INPUT_F6
  of "F7": result = INPUT_F7
  of "F8": result = INPUT_F8
  of "F9": result = INPUT_F9
  of "F10": result = INPUT_F10
  of "F11": result = INPUT_F11
  of "F12": result = INPUT_F12
  else:
    case keyCode
    of 112..123: result = int64(INPUT_F1 + (keyCode - 112))
    else:
      if key.len == 1:
        result =  ($key).runeAt(0).int64

method processEvents*(self: BrowserPlatform): int =
  result = 0

proc applyDomUpdates*(self: BrowserPlatform) =
  for update in self.domUpdates:
    update()

  self.domUpdates.setLen 0

method render*(self: BrowserPlatform, widget: WWidget, frameIndex: int) =
  self.boundsStack.add rect(vec2(), self.size)
  defer: discard self.boundsStack.pop()

  var buffer = ""

  var element: Element = if self.content.children.len > 0: self.content.children[0].Element else: nil
  let wasNil = element.isNil
  # widget.renderWidget(self, element, self.redrawEverything, frameIndex, buffer)
  builder.drawNode(self, element, builder.root)

  self.applyDomUpdates()

  if not element.isNil and wasNil:
    self.content.appendChild element

  self.redrawEverything = false

proc createOrReplaceElement(element: var Element, name: cstring, nameUpper: cstring) =
  if element.isNil:
    # echo "create element ", name
    element = document.createElement(name)
    element.class = "widget"
  elif element.nodeName != nameUpper:
    # echo "replace element ", element.nodeName, " with ", name
    let dif = document.createElement(name)
    element.replaceWith(dif)
    element = dif
    element.class = "widget"

proc updateRelativePosition(element: var Element, bounds: Rect) =
  element.style.left = ($bounds.x.int).cstring
  element.style.top = ($bounds.y.int).cstring
  element.style.width = ($bounds.w.int).cstring
  element.style.height = ($bounds.h.int).cstring

proc myToHtmlHex(c: Color): cstring =
  result = "rgba(".cstring
  result += round(c.r * 255).int
  result += ", ".cstring
  result += round(c.g * 255).int
  result += ", ".cstring
  result += round(c.b * 255).int
  result += ", ".cstring
  result += c.a
  result += ")".cstring

# Initialize renderer
var rend: BrowserPlatform = new BrowserPlatform
rend.init()

var initializedEditor = false
var hasRequestedRerender = false
var isRenderInProgress = false

var frameIndex = 0

var start: float = -1
var previousTimestep: float = 0

proc doRender(timestep: float) =
  # echo "requestAnimationFrame ", time

  if timestep == previousTimestep:
    # echo "multiple per frame"
    return

  if start < 0 or builder.animatingNodes.len == 0:
    start = timestep
    builder.frameTime = 0
  else:
    builder.frameTime = timestep - previousTimestep
  previousTimestep = timestep

  defer:
    if builder.animatingNodes.len > 0:
      requestRender()

  hasRequestedRerender = false
  isRenderInProgress = true
  defer: isRenderInProgress = false
  defer: inc frameIndex

  var layoutTime, updateTime, renderTime: float
  var frameTime = 0.0
  block:
    let frameTimer = startTimer()

    let updateTimer = startTimer()
    if advanceFrame:
      builder.beginFrame(rend.size)
      builder.buildUINodes()
      builder.endFrame()
    elif builder.animatingNodes.len > 0:
      builder.frameIndex.inc
      builder.postProcessNodes()
    updateTime = updateTimer.elapsed.ms

    if logRoot:
      echo "frame ", builder.frameIndex
      echo builder.root.dump(true)

    let renderTimer = startTimer()
    rend.render(nil, frameIndex)
    renderTime = renderTimer.elapsed.ms

    frameTime = frameTimer.elapsed.ms

  # if frameTime > 20:
  if logFrameTime:
    echo fmt"Frame: {frameTime:>5.2}ms (u: {updateTime:>5.2}ms, l: {layoutTime:>5.2}ms, r: {renderTime:>5.2}ms)"

proc drawNode(builder: UINodeBuilder, platform: BrowserPlatform, element: var Element, node: UINode, force: bool = false) =
  if element.isNotNil and node.lastChange < builder.frameIndex:
    return

  node.lastRenderTime = builder.frameIndex

  let force = force or element.isNil

  element.createOrReplaceElement("div", "DIV")

  let relBounds = node.boundsActual

  var css: cstring = "left: "
  css += relBounds.x.int
  css += "px; top: ".cstring
  css += relBounds.y.int
  css += "px; width: ".cstring
  css += relBounds.w.int
  css += "px; height: ".cstring
  css += relBounds.h.int
  css += "px;".cstring

  if FillBackground in node.flags:
    css += "background: ".cstring
    css += node.backgroundColor.myToHtmlHex
    css += ";".cstring

  if MaskContent in node.flags:
    css += "overflow: hidden;".cstring

  if DrawBorder in node.flags:
    css += "outline: 1px solid ".cstring
    css += node.borderColor.myToHtmlHex
    css += ";".cstring

  var text = "".cstring
  var updateText = false
  if DrawText in node.flags:
    css += "color: ".cstring
    css += node.textColor.myToHtmlHex
    css += ";".cstring
    # if italic:
    #   {.emit: [result, " += `font-style: italic;`"].} #"""
    # if bold:
    #   {.emit: [result, " += `font-weight: bold;`"].} #"""
    # if wrap:
    #   {.emit: [result, " += `word-wrap: break-word;`"].} #"""
    #   {.emit: [result, " += `display: inline-block;`"].} #"""
    #   {.emit: [result, " += `white-space: pre-wrap;`"].} #"""

    text = node.text.cstring
    updateText = element.getAttribute("data-text") != text

  var newChildren: seq[(Element, cstring, Node)] = @[]
  var childrenToRemove: seq[Element] = @[]

  platform.domUpdates.add proc() =
    for (c, rel, other) in newChildren:
      if rel == "":
        element.appendChild c
      else:
        other.insertAdjacentElement(rel, c)

    for c in childrenToRemove:
      c.remove()

    element.class = "widget"
    element.setAttribute("style", css)

    if updateText:
      element.innerText = text
      element.setAttribute("data-text", text)

    element.setAttribute("id", ($node.id).cstring)

  var existingCount = element.children.len
  var k = 0
  for i, c in node.children:
    var childElement: Element = nil
    var insertRel: cstring = ""
    var insertNeighbor: Element = nil

    if c.lastRenderTime == 0:
      # new node, insert
      if k < existingCount:
        # echo i, ", insert after ", k - 1
        insertNeighbor = element.children[k].Element
        insertRel = "beforebegin"

    else:
      let childId = ($c.id).cstring
      while k < existingCount:
        defer: inc k

        let element = element.children[k].Element
        if element.getAttribute("id") == childId:
          childElement = element
          break

        # echo "found different id, delete"
        childrenToRemove.add element

    builder.drawNode(platform, childElement, c, force)
    if not childElement.isNil:
      if childElement.parentElement != element:
        newChildren.add (childElement, insertRel, insertNeighbor)

  for i in k..<existingCount:
    childrenToRemove.add element.children[i].Element

proc requestRender(redrawEverything = false) =
  advanceFrame = true
  if not initializedEditor:
    return
  if hasRequestedRerender:
    return
  if isRenderInProgress:
    return

  discard window.requestAnimationFrame doRender

proc runApp(): Future[void] {.async.} =
  # discard await newEditor(Backend.Browser, rend)

  discard rend.onKeyPress.subscribe proc(event: auto): void =
    case event.input
    of '1'.int64:
      showPopup1 = not showPopup1
    of '2'.int64:
      showPopup2 = not showPopup2

    of 'u'.int64:
      logRoot = not logRoot

    of 'i'.int64:
      logFrameTime = not logFrameTime

    of 'k'.int64:
      builder.animationSpeedModifier /= 2
      echo "anim speed: ", builder.animationSpeedModifier

    of 'q'.int64:
      builder.animationSpeedModifier *= 2
      echo "anim speed: ", builder.animationSpeedModifier

    of INPUT_UP:
      cursor[0] = max(0, cursor[0] - 1)
      cursor[1] = cursor[1].clamp(0, testText[cursor[0]].len)
      mainTextChanged = true
    of INPUT_DOWN:
      cursor[0] = min(testText.high, cursor[0] + 1)
      cursor[1] = cursor[1].clamp(0, testText[cursor[0]].len)
      mainTextChanged = true

    of INPUT_LEFT:
      cursor[1] = max(0, cursor[1] - 1)
      mainTextChanged = true
    of INPUT_RIGHT:
      cursor[1] = min(testText[cursor[0]].len, cursor[1] + 1)
      mainTextChanged = true

    of INPUT_HOME:
      cursor[1] = 0
      mainTextChanged = true
    of INPUT_END:
      cursor[1] = testText[cursor[0]].len
      mainTextChanged = true

    else:
      discard
    requestRender()

  discard rend.onKeyRelease.subscribe proc(event: auto): void = requestRender()
  discard rend.onRune.subscribe proc(event: auto): void =
    echo "rune ", event
    requestRender()

  discard rend.onMousePress.subscribe proc(event: auto): void =
    builder.handleMousePressed(event.button, event.pos)
    requestRender()

  discard rend.onMouseRelease.subscribe proc(event: auto): void =
    builder.handleMouseReleased(event.button, event.pos)
    requestRender()
  discard rend.onMouseMove.subscribe proc(event: auto): void =
    if builder.handleMouseMoved(event.pos, event.buttons):
      requestRender()

  discard rend.onScroll.subscribe proc(event: auto): void = requestRender()
  discard rend.onCloseRequested.subscribe proc(_: auto) = requestRender()
  discard rend.onResized.subscribe proc(redrawEverything: bool) = requestRender(redrawEverything)


  initializedEditor = true
  requestRender(true)

asyncCheck runApp()

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

let nimCopyCounters = new Map();
let nimCopyTimers = new Map();
let breakOnCopyType = null;
let stats = []

function clearNimCopyStats() {
    nimCopyCounters.clear();
    nimCopyTimers.clear();
}

function dumpNimCopyStatsImpl(desc, map, sortBy, setBreakOnCopyTypeIndex) {
    let values = []
    for (let entry of map.entries()) {
        values.push(entry)
    }

    values.sort((a, b) => b[1][sortBy] - a[1][sortBy])

    stats = values

    console.log(desc)

    let i = 0;
    for (let [type, stat] of values) {
        if (i == setBreakOnCopyTypeIndex) {
            breakOnCopyType = type
        }
        console.log(stat, ": ", type)
        i++
        if (i > 20) {
          break
        }
    }
}

function selectType(setBreakOnCopyTypeIndex) {
    if (setBreakOnCopyTypeIndex < stats.length) {
        breakOnCopyType = stats[setBreakOnCopyTypeIndex][0]
    }
}

function dumpNimCopyStats(sortBy, setBreakOnCopyTypeIndex) {
    //dumpNimCopyStatsImpl("Counts: ", nimCopyCounters)
    dumpNimCopyStatsImpl("Times: ", nimCopyTimers, sortBy || 0, setBreakOnCopyTypeIndex)
}

function nimCopyOverride(dest, src, ti) {
    if (ti === breakOnCopyType) {
      debugger;
    }

    let existing = nimCopyCounters.get(ti) || 0;
    nimCopyCounters.set(ti, existing + 1)

    let start = Date.now()
    let result = window._old_nimCopy(dest, src, ti);
    let elapsed = Date.now() - start

    let existingTime = nimCopyTimers.get(ti) || [0, 0];
    nimCopyTimers.set(ti, [existingTime[0] + elapsed, existingTime[1] + 1])

    return result;
}
""".}

import hashes

macro overrideFunction(body: typed, override: untyped): untyped =
  # echo body.treeRepr
  let original = case body.kind
  of nnkCall: body[0]
  of nnkStrLit: body
  else: body

  return quote do:
    {.emit: ["window._old_", `original`, " = ", `original`, ";"].}
    {.emit: ["window.", `original`, " = ", `override`, ";"].}

overrideFunction(hashWangYi1(1.int64), "hashWangYi1_override")
overrideFunction(hashWangYi1(2.uint64), "hashWangYi1_override")
overrideFunction(hashWangYi1(3.Hash), "hashWangYi1_override")

# overrideFunction("nimCopy", "nimCopyOverride")

proc getTextStyle(x, y, width, height: int, color, backgroundColor: cstring, italic, bold: bool, wrap: bool): cstring =
  {.emit: [result, " = `left: ${", x, "}px; top: ${", y, "}px; width: ${", width, "}px; height: ${", height, "}px; overflow: visible; color: ${", color, "}; ${", backgroundColor, "}`"].} #"""
  if italic:
    {.emit: [result, " += `font-style: italic;`"].} #"""
  if bold:
    {.emit: [result, " += `font-weight: bold;`"].} #"""
  if wrap:
    {.emit: [result, " += `word-wrap: break-word;`"].} #"""
    {.emit: [result, " += `display: inline-block;`"].} #"""
    {.emit: [result, " += `white-space: pre-wrap;`"].} #"""

proc getTextStyle(x, y, width, height: int, color, backgroundColor: cstring, italic, bold: bool, wrap: bool, fontSize: float): cstring =
  {.emit: [result, " = `left: ${", x, "}px; top: ${", y, "}px; width: ${", width, "}px; height: ${", height, "}px; overflow: visible; color: ${", color, "}; ${", backgroundColor, "}; font-size: ${", fontSize, "}`"].} #"""
  if italic:
    {.emit: [result, " += `font-style: italic;`"].} #"""
  if bold:
    {.emit: [result, " += `font-weight: bold;`"].} #"""
  if wrap:
    {.emit: [result, " += `word-wrap: break-word;`"].} #"""
    {.emit: [result, " += `display: inline-block;`"].} #"""
    {.emit: [result, " += `white-space: pre-wrap;`"].} #"""