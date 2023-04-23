import std/[strformat, tables, dom, unicode, strutils, sugar]
import std/htmlgen as hg
import platform, widgets, custom_logger, rect_utils, input, event, lrucache, theme
import vmath
import chroma as chroma

export platform, widgets

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

    escapedText: LruCache[string, string]

    domUpdates: seq[proc(): void]

    currentEvent: dom.Event

proc toInput(key: cstring, code: cstring, keyCode: int): int64
proc updateFontSettings*(self: BrowserPlatform)

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

  proc console[T](t: T) {.importjs: "console.log(#);".}

  self.content.addEventListener("dragover", proc(e: dom.Event) =
    let oldEvent = self.currentEvent
    self.currentEvent = e
    defer: self.currentEvent = oldEvent

    let de = e.DragEvent
    de.preventDefault()
  )

  self.content.addEventListener("drop", proc(e: dom.Event) =
    let oldEvent = self.currentEvent
    self.currentEvent = e
    defer: self.currentEvent = oldEvent

    let de = e.DragEvent
    de.preventDefault()
    console de.dataTransfer
    for f in de.dataTransfer.files:
      capture f:
        let fileReader = newFileReader()

        type RootObjRef = ref RootObj
        type File = dom.File
        proc result(fileReader: FileReader): cstring {.importjs: "(#.result || '')".}

        # @hack: we know that f is actually a file, but it's got the wrong type in std/dom
        fileReader.readAsText(f.RootObjRef.File)
        fileReader.onload = proc (e: dom.Event) =
          self.onDropFile.invoke ($f.name, $fileReader.result)
  )

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

proc `+=`[T](a: cstring, b: T) {.importjs: "(#) += (#);".}
proc `+`[T](a: cstring, b: T) {.importjs: "((#) + (#))".}

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

method renderWidget(self: WWidget, renderer: BrowserPlatform, element: var Element, forceRedraw: bool, frameIndex: int, buffer: var string) {.base.} = discard

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
  widget.renderWidget(self, element, self.redrawEverything, frameIndex, buffer)

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
  element.style.left = $bounds.x.int
  element.style.top = $bounds.y.int
  element.style.width = $bounds.w.int
  element.style.height = $bounds.h.int

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

method renderWidget(self: WPanel, renderer: BrowserPlatform, element: var Element, forceRedraw: bool, frameIndex: int, buffer: var string) =
  if self.lastHierarchyChange < frameIndex and self.lastBoundsChange < frameIndex and self.lastInvalidation < frameIndex and not forceRedraw:
    return

  # debugf"renderPanel (frame {frameIndex}) {self.lastHierarchyChange}, {self.lastBoundsChange}, {self.lastBounds}"

  element.createOrReplaceElement("div", "DIV")

  while element.children.len > self.len:
    element.removeChild(element.lastChild)

  let relBounds = self.lastBounds - renderer.boundsStack[renderer.boundsStack.high].xy
  renderer.boundsStack.add self.lastBounds
  defer: discard renderer.boundsStack.pop()

  var css: cstring = "left: "
  css += relBounds.x.int
  css += "px; top: ".cstring
  css += relBounds.y.int
  css += "px; width: ".cstring
  css += relBounds.w.int
  css += "px; height: ".cstring
  css += relBounds.h.int
  css += "px;".cstring

  let backgroundColor = self.getBackgroundColor
  if self.fillBackground:
    css += "background: ".cstring
    css += backgroundColor.myToHtmlHex
    css += ";".cstring

  if self.maskContent:
    css += "overflow: hidden;".cstring

  if self.drawBorder:
    css += "border: 1px solid ".cstring
    css += self.getForegroundColor.myToHtmlHex
    css += ";".cstring

  renderer.domUpdates.add proc() =
    element.class = "widget"
    element.setAttribute("style", css)

  let existingCount = element.children.len
  for i, c in self.children:
    var childElement: Element = if i < existingCount: element.children[i].Element else: nil
    c.renderWidget(renderer, childElement, forceRedraw or self.fillBackground, frameIndex, buffer)
    if i >= existingCount and not childElement.isNil:
      element.appendChild childElement

method renderWidget(self: WStack, renderer: BrowserPlatform, element: var Element, forceRedraw: bool, frameIndex: int, buffer: var string) =
  if self.lastHierarchyChange < frameIndex and self.lastBoundsChange < frameIndex and self.lastInvalidation < frameIndex and not forceRedraw:
    return

  # debugf"renderWidget (frame {frameIndex}) {self.lastHierarchyChange}, {self.lastBoundsChange}, {self.lastBounds}"

  element.createOrReplaceElement("div", "DIV")

  while element.children.len > self.children.len:
    element.removeChild(element.lastChild)

  let relBounds = self.lastBounds - renderer.boundsStack[renderer.boundsStack.high].xy
  renderer.boundsStack.add self.lastBounds
  defer: discard renderer.boundsStack.pop()

  element.updateRelativePosition(relBounds)

  let existingCount = element.children.len
  for i, c in self.children:
    var childElement: Element = if i < existingCount: element.children[i].Element else: nil
    c.renderWidget(renderer, childElement, forceRedraw or self.fillBackground, frameIndex, buffer)
    if i >= existingCount and not childElement.isNil:
      element.appendChild childElement

proc getTextStyle(x, y, width, height: int, color, backgroundColor: cstring, italic, bold: bool): cstring
proc getTextStyle(x, y, width, height: int, color, backgroundColor: cstring, italic, bold: bool, fontSize: float): cstring

method renderWidget(self: WText, renderer: BrowserPlatform, element: var Element, forceRedraw: bool, frameIndex: int, buffer: var string) =
  if self.lastHierarchyChange < frameIndex and self.lastBoundsChange < frameIndex and self.lastInvalidation < frameIndex and not forceRedraw:
    return

  # debugf"renderText {stackDepth} {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange}, {self.text}"

  element.createOrReplaceElement("span", "SPAN")

  let relBounds = self.lastBounds - renderer.boundsStack[renderer.boundsStack.high].xy
  renderer.boundsStack.add self.lastBounds
  defer: discard renderer.boundsStack.pop()

  let color = self.foregroundColor.myToHtmlHex.cstring

  let text = self.text.cstring
  let updateText = element.getAttribute("data-text") != text

  let backgroundColor = if self.fillBackground:
    fmt"background: {self.backgroundColor.myToHtmlHex};".cstring
  else:
    ""

  let italic = FontStyle.Italic in self.style.fontStyle
  let bold = FontStyle.Bold in self.style.fontStyle

  renderer.domUpdates.add proc() =
    if self.fontSizeIncreasePercent != 0:
      element.setAttribute("style", getTextStyle(relBounds.x.int, relBounds.y.int, relBounds.w.int, relBounds.h.int, color, backgroundColor, italic, bold, renderer.mFontSize * (1 + self.fontSizeIncreasePercent)))
    else:
      element.setAttribute("style", getTextStyle(relBounds.x.int, relBounds.y.int, relBounds.w.int, relBounds.h.int, color, backgroundColor, italic, bold))
    if updateText:
      element.innerText = text
      element.setAttribute("data-text", text)

  self.lastRenderedText = self.text

proc getTextStyle(x, y, width, height: int, color, backgroundColor: cstring, italic, bold: bool): cstring =
  {.emit: [result, " = `left: ${", x, "}px; top: ${", y, "}px; width: ${", width, "}px; height: ${", height, "}px; overflow: visible; color: ${", color, "}; ${", backgroundColor, "}`"].} #"""
  if italic:
    {.emit: [result, " += `font-style: italic;`"].} #"""
  if bold:
    {.emit: [result, " += `font-weight: bold;`"].} #"""

proc getTextStyle(x, y, width, height: int, color, backgroundColor: cstring, italic, bold: bool, fontSize: float): cstring =
  {.emit: [result, " = `left: ${", x, "}px; top: ${", y, "}px; width: ${", width, "}px; height: ${", height, "}px; overflow: visible; color: ${", color, "}; ${", backgroundColor, "}; font-size: ${", fontSize, "}`"].} #"""
  if italic:
    {.emit: [result, " += `font-style: italic;`"].} #"""
  if bold:
    {.emit: [result, " += `font-weight: bold;`"].} #"""