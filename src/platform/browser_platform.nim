import std/[tables, dom, unicode, strutils, sugar]
import vmath
import chroma as chroma
import misc/[custom_logger, rect_utils, event, timer]
import ui/node
import platform, input, lrucache

when defined(uiNodeDebugData):
  import std/json

export platform

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
    mCharGap: float

    doubleClickTimer: Timer
    doubleClickCounter: int
    doubleClickTime: float

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
  self.mFontSize = 16
  self.mLineHeight = 20
  self.mLineDistance = 2
  self.mCharWidth = 18
  self.mCharGap = 1
  self.supportsThinCursor = true
  self.doubleClickTime = 0.35

  self.builder = newNodeBuilder()
  self.builder.useInvalidation = false

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
    if not self.builder.handleKeyPressed(input, modifiers):
      self.onKeyPress.invoke (input, modifiers)
  )

  self.content.addEventListener("wheel", proc(e: dom.Event) =
    let oldEvent = self.currentEvent
    self.currentEvent = e
    defer: self.currentEvent = oldEvent

    let we = e.WheelEvent
    let modifiers = we.getModifiers

    # debugf"wheel {we.deltaX}, {we.deltaY}, {we.deltaZ}, {we.deltaMode}, {modifiers}"
    if not self.builder.handleMouseScroll(vec2(we.clientX.float, we.clientY.float), vec2(we.deltaX, -we.deltaY) * 0.01, modifiers):
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

    var events = @[mouseButton]

    if mouseButton == MouseButton.Left:
      if self.doubleClickTimer.elapsed.float < self.doubleClickTime:
        inc self.doubleClickCounter
        case self.doubleClickCounter
        of 1:
          events.add MouseButton.DoubleClick
        of 2:
          events.add MouseButton.TripleClick
        else:
          self.doubleClickCounter = 0
      else:
        self.doubleClickCounter = 0

      self.doubleClickTimer = startTimer()
    else:
      self.doubleClickCounter = 0

    for event in events:
      if not self.builder.handleMousePressed(event, modifiers, vec2(x.float, y.float)):
        self.onMousePress.invoke (event, modifiers, vec2(x.float, y.float))

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

    if not self.builder.handleMouseReleased(mouseButton, modifiers, vec2(x.float, y.float)):
      self.onMouseRelease.invoke (mouseButton, modifiers, vec2(x.float, y.float))
  )

  self.content.addEventListener("mousemove", proc(e: dom.Event) =
    let oldEvent = self.currentEvent
    self.currentEvent = e
    defer: self.currentEvent = oldEvent

    let me = e.MouseEvent
    let modifiers = me.getModifiers

    # debugf"move {me.button}, {modifiers}, {me.clientX}, {me.clientY}, {me.movementX}, {me.movementY}, {me.getMouseButtons}"
    if not self.builder.handleMouseMoved(vec2(me.clientX.float, me.clientY.float), me.getMouseButtons):
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
  self.requestedRender = true
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
  self.mCharGap = 1
  self.content.removeChild(d)

  self.builder.charWidth = self.mCharWidth
  self.builder.lineHeight = self.mLineHeight
  self.builder.lineGap = self.mLineDistance

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

method charGap*(self: BrowserPlatform): float =
  self.mCharGap

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

proc drawNode(builder: UINodeBuilder, platform: BrowserPlatform, element: var Element, node: UINode, force: bool = false)

proc applyDomUpdates*(self: BrowserPlatform) =
  for update in self.domUpdates:
    update()

  self.domUpdates.setLen 0

method render*(self: BrowserPlatform) =
  self.boundsStack.add rect(vec2(), self.size)
  defer: discard self.boundsStack.pop()

  var element: Element = if self.content.children.len > 0: self.content.children[0].Element else: nil
  let wasNil = element.isNil
  self.builder.drawNode(self, element, self.builder.root)

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

proc drawNode(builder: UINodeBuilder, platform: BrowserPlatform, element: var Element, node: UINode, force: bool = false) =
  if element.isNotNil and node.lastChange < builder.frameIndex:
    return

  if not node.flags.any(&{DrawText, FillBackground, DrawBorder}) and node.first.isNil:
    element = nil
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
  var removeText = false
  if DrawText in node.flags:
    css += "color: ".cstring
    css += node.textColor.myToHtmlHex
    css += ";".cstring
    if TextItalic in node.flags:
      css += "font-style: italic;".cstring
    if TextBold in node.flags:
      css += "font-weight: bold;".cstring
    if TextWrap in node.flags:
      css += "word-wrap: break-word;".cstring
      css += "display: inline-block;".cstring
      css += "white-space: pre-wrap;".cstring

    if TextAlignHorizontalLeft in node.flags:
      css += "text-align: left;".cstring
    elif TextAlignHorizontalCenter in node.flags:
      css += "text-align: center;".cstring
    elif TextAlignHorizontalRight in node.flags:
      css += "text-align: right;".cstring

    text = node.text.cstring
    updateText = element.getAttribute("data-text") != text
  elif element.hasAttribute("data-text"):
    removeText = true

  when defined(uiNodeDebugData):
    for c in node.aDebugData.css:
      css += ";".cstring
      css += c.cstring

  var newChildren: seq[(Element, cstring, Node)] = @[]
  var childrenToRemove: seq[Element] = @[]

  platform.domUpdates.add proc() =
    element.class = "widget"
    element.setAttribute("style", css)

    if updateText:
      element.innerText = text
      element.setAttribute("data-text", text)
    elif removeText:
      element.removeAttribute("data-text")
      element.innerText = ""

    element.setAttribute("id", ($node.id).cstring)
    when defined(uiNodeDebugData):
      element.setAttribute("data-flags", ($node.flags).cstring)
      element.setAttribute("data-pivot", ($node.pivot).cstring)

      if node.aDebugData.metaData.isNotNil:
        element.setAttribute("data-meta", ($node.aDebugData.metaData).replace('"', '\'').cstring)

    for (c, rel, other) in newChildren:
      if rel == "":
        element.appendChild c
      else:
        other.insertAdjacentElement(rel, c)

    for c in childrenToRemove:
      c.remove()

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

    let oldChildElement = childElement
    builder.drawNode(platform, childElement, c, force)

    if oldChildElement.isNotNil and childElement.isNil:
      childrenToRemove.add oldChildElement
    elif not childElement.isNil:
      if childElement.parentElement != element:
        newChildren.add (childElement, insertRel, insertNeighbor)

  for i in k..<existingCount:
    childrenToRemove.add element.children[i].Element
