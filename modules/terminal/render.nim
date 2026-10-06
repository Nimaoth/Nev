import std/[options, tables, math]
import vmath, bumpy, chroma
import pixie
import misc/[util, custom_logger, custom_unicode, tui]
import misc/input_api as input_api
import theme, view, config_provider, platform
import types_impl, core_settings

from std/colors as colors import nil

import nuigi
import nuigi/core/vecmath as nuiMath
import nuigi/core/arena
import nuigi/core/array_view
import nuigi/widgets/dynamic_virtuallist

type Vec2 = vmath.Vec2
# Ensure unqualified `vec2` resolves to vmath for legacy RenderCommand templates (avoids Vec2 clash with nuigi)
template vec2(a, b: untyped): untyped = vmath.vec2(a, b)

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "terminal-render"

proc toUiColor(c: Color): UiColor {.inline.} = rgba(c.r, c.g, c.b, c.a)

type TerminalInputNuiStorage = ref object of UiNodeStorageData
  view: TerminalView
  cellWidth, cellHeight: float32
  pressedButtons: UiMouseButtons
  list: UiDynamicVirtualListStorage
  historyLength: int
  historyStart: int64
  alternateScreen: bool
  initialized: bool
  followTail: bool = true
  requestedFirst, requestedLast: int = -1
  requestedOffset: float32 = -1
  requestedHistoryStart: int64 = -1
  requestedViewportRows: float32 = -1
  requestedFollowTail: bool
  fontId: UiFontId
  fontSize: float32

proc terminalInputModifiers(mods: UiModifiers): input_api.Modifiers {.gcsafe, raises: [].} =
  if ModShift in mods: result.incl input_api.Shift
  if ModControl in mods: result.incl input_api.Control
  if ModAlt in mods: result.incl input_api.Alt
  if ModSuper in mods: result.incl input_api.Super

proc terminalMouseButton(button: UiMouseButton): input_api.MouseButton {.gcsafe, raises: [].} =
  case button
  of MouseLeft: input_api.MouseButton.Left
  of MouseMiddle: input_api.MouseButton.Middle
  of MouseRight: input_api.MouseButton.Right

proc handleTerminalInputNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  discard userData
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let node = b.frame.nodes[nodeIdx].addr
  let existing = b.nodeStorageGet(node)
  if existing == nil or not (existing of TerminalInputNuiStorage):
    return
  let storage = cast[TerminalInputNuiStorage](existing)
  let view = storage.view
  if view == nil or view.terminal == nil:
    storage.pressedButtons = {}
    return
  let input = b.frameCtx.input
  let modifiers = terminalInputModifiers(input.modsDown)
  let overScrollbar = storage.list != nil and storage.list.scrollbarTrackIndex >= 0 and
    b.wasHovered(storage.list.scrollbarTrackIndex, includeChildren = true)
  if (b.previousOutput.scrolledId == node.id or
      (storage.list != nil and (view.terminal.mouseTracking or view.terminal.alternateScreen) and
        b.wasHovered(nodeIdx, includeChildren = true) and not overScrollbar)) and
      input.wheel.y != 0 and view.onScroll != nil:
    view.onScroll(view, input.wheel.y.int, modifiers)

  if storage.cellWidth <= 0 or storage.cellHeight <= 0:
    return
  let hovered = b.wasHovered(nodeIdx, includeChildren = true) and not overScrollbar
  let pos = input.mouse - b.absoluteNodePosPrev(node.id, nodeIdx)
  let col = (pos.x / storage.cellWidth).floor.int
  let row = (pos.y / storage.cellHeight).floor.int
  let moved = input.mouseDelta.x != 0 or input.mouseDelta.y != 0
  for button in UiMouseButton:
    if hovered and button in input.mousePressed and view.onClick != nil:
      storage.pressedButtons.incl button
      view.onClick(view, terminalMouseButton(button), true, modifiers, col, row)
    if button notin storage.pressedButtons:
      continue
    if moved and button notin input.mousePressed and
        (button in input.mouseDown or button in input.mouseReleased) and view.onDrag != nil:
      view.onDrag(view, terminalMouseButton(button), col, row, modifiers)
    if button in input.mouseReleased:
      if view.onClick != nil:
        view.onClick(view, terminalMouseButton(button), false, modifiers, col, row)
      storage.pressedButtons.excl button
  storage.pressedButtons = storage.pressedButtons * input.mouseDown
  if hovered and moved and input.mouseDown == {} and input.mouseReleased == {} and view.onMove != nil:
    view.onMove(view, col, row)

proc buildTerminalRowNui(nui: var UiBuilder, itemIndex, userData: int) {.nimcall, gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    let existing = nui.nodeStorageGet(nui.frame.nodes[userData].addr)
    if existing == nil or not (existing of TerminalInputNuiStorage):
      return
    let storage = cast[TerminalInputNuiStorage](existing)
    let self = storage.view
    discard nui.fillX().height(storage.cellHeight).padding(0)
    if self == nil or self.terminal == nil:
      return
    let cachedRow = itemIndex - self.terminal.bufferFirstRow
    if cachedRow < 0 or cachedRow >= self.terminal.terminalBuffer.height:
      return
    if self.terminal.terminalBuffer.width == 0:
      return
    let charW = storage.cellWidth
    let charH = storage.cellHeight
    let fontSize = storage.fontSize
    let monoFontId = storage.fontId
    let textColor = self.terminals.themes.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
    var cursorFg = self.terminals.themes.theme.color(@["editorCursor.foreground", "foreground"], color(200/255, 200/255, 200/255))
    let cursorBg = self.terminals.themes.theme.color(@["editorCursor.background", "background"], color(50/255, 50/255, 50/255))
    if self.mode == "normal":
      cursorFg = cursorFg.darken(0.3)
    let drawCursor = self.terminal.cursor.visible
    let width = self.terminal.terminalBuffer.width
    var cmds = nui.frame.arena[].allocEmptyArray(width * 4 + 64, UiRenderCommand)
    let row = cachedRow
    var lastCell: TerminalChar = self.terminal.terminalBuffer[0, row]
    self.renderBuffer.setLen(0)
    var boundsAccX = 0.0'f32
    var boundsAccY = 0.0'f32
    var boundsAccW = 0.0'f32
    let boundsAccH = charH.float32
    var bg = lastCell.bg
    var bgCol = color(0,0,0,0)
    var fgCol = color(0,0,0,0)
    var runLen = 0
    var textFlags = 0

    template `!=`(a, b: colors.Color): bool =
      not colors.`==`(a, b)

    template flushNui(draw: bool = true) =
      if self.renderBuffer.len > 0 and draw:
        if bg != bgNone:
          cmds.add UiRenderCommand(kind: CmdRectFill, pos: nuiMath.vec2(boundsAccX, boundsAccY), size: nuiMath.vec2(boundsAccW, boundsAccH), color: toUiColor(bgCol))
        # strikethrough
        if styleStrikethrough in lastCell.style:
          cmds.add UiRenderCommand(kind: CmdRectFill, pos: nuiMath.vec2(boundsAccX, boundsAccY + boundsAccH * 0.4'f32), size: nuiMath.vec2(boundsAccW, boundsAccH * 0.1'f32), color: toUiColor(fgCol))
        if styleHidden notin lastCell.style and not lastCell.isEmpty:
          let txt = self.renderBuffer
          if txt.len > 0:
            # Filter out null bytes added for empty cells (legacy adds "\0")
            var cleanTxt = txt
            # legacy renderBuffer may contain "\0" for empty cells – skip drawing if only nulls
            var hasVisible = false
            for c in cleanTxt:
              if c != '\0': hasVisible = true; break
            if hasVisible:
              # Remove null bytes for NUI text
              var filtered = newStringOfCap(cleanTxt.len)
              for c in cleanTxt:
                if c != '\0': filtered.add c
              let idx = block:
                let i = nui.frame.texts.len
                nui.frame.texts.add UiNodeText(text: filtered.uiString, fontId: monoFontId, fontSize: fontSize.float32, textColor: toUiColor(fgCol))
                (i+1).uint16
              cmds.add UiRenderCommand(kind: CmdText, pos: nuiMath.vec2(boundsAccX, boundsAccY), color: toUiColor(fgCol), textIndex: idx)
      # reset for next run
      boundsAccX = boundsAccX + boundsAccW
      boundsAccX = ceil(boundsAccX / charW.float32) * charW.float32
      boundsAccW = charW.float32
      self.renderBuffer.setLen(0)
      runLen = 0
      textFlags = 0

    for col in 0..<width:
      let cell {.cursor.} = self.terminal.terminalBuffer[col, row]
      defer: lastCell = cell
      if drawCursor and itemIndex == self.terminal.historyLength + self.terminal.cursor.row and col == self.terminal.cursor.col:
        flushNui()
        boundsAccX = col.float32 * charW.float32
        let cellX = col.float32 * charW.float32
        let cellY = 0.0'f32
        var curPos = nuiMath.vec2(cellX, cellY)
        var curSize = nuiMath.vec2(charW.float32, charH.float32)
        # NUI-GAP: old Block cursor swapped the cell text to
        # cursorBackgroundColor (fgColor=cursorBackgroundColor); new
        # discards here and always overlays cursorBg text, so Block (and
        # Underline/BarLeft reuse of the run fg) differs (see §24).
        case self.terminal.cursor.shape
        of CursorShape.Block: discard
        of CursorShape.Underline:
          curPos.y += curSize.y * 0.9'f32
          curSize.y *= 0.1'f32
        of CursorShape.BarLeft:
          curSize.x *= 0.1'f32
        cmds.add UiRenderCommand(kind: CmdRectFill, pos: curPos, size: curSize, color: toUiColor(cursorFg))
        if not cell.isEmpty and styleHidden notin cell.style:
          var txt = newString(cell.chsLen)
          for i in 0..<cell.chsLen: txt[i] = cell.chs[i]
          if txt.len > 0:
            let idx = block:
              let i = nui.frame.texts.len
              nui.frame.texts.add UiNodeText(text: txt.uiString, fontId: monoFontId, fontSize: fontSize.float32, textColor: toUiColor(cursorBg))
              (i+1).uint16
            cmds.add UiRenderCommand(kind: CmdText, pos: nuiMath.vec2(cellX, cellY), color: toUiColor(cursorBg), textIndex: idx)
        continue
      elif drawCursor and itemIndex == self.terminal.historyLength + self.terminal.cursor.row and col == self.terminal.cursor.col + 1:
        flushNui(false)
        boundsAccX = col.float32 * charW.float32
      elif cell.previousWideGlyph:
        flushNui()
        boundsAccX = col.float32 * charW.float32
        continue
      elif lastCell.previousWideGlyph:
        flushNui(false)
        boundsAccX = col.float32 * charW.float32
      elif cell.isEmpty != lastCell.isEmpty:
        flushNui()
        boundsAccX = col.float32 * charW.float32
      elif cell.fg != lastCell.fg or cell.fgColor != lastCell.fgColor or cell.bg != lastCell.bg or cell.bgColor != lastCell.bgColor or cell.style != lastCell.style:
        flushNui()
        boundsAccX = col.float32 * charW.float32

      if not cell.isEmpty:
        cell.writeCharsTo(self.renderBuffer)
      else:
        self.renderBuffer.add "\0"
      boundsAccW = (col + 1).float32 * charW.float32 - boundsAccX
      inc runLen
      if runLen == 1:
        bg = cell.bg
        bgCol = color(0,0,0,0)
        case bg
        of bgNone: discard
        of bgBlack: bgCol = color(0,0,0)
        of bgRed: bgCol = color(1,0,0)
        of bgGreen: bgCol = color(0,1,0)
        of bgYellow: bgCol = color(1,1,0)
        of bgBlue: bgCol = color(0,0,1)
        of bgMagenta: bgCol = color(1,0,1)
        of bgCyan: bgCol = color(0,1,1)
        of bgWhite: bgCol = color(1,1,1)
        of bgRGB:
          let (r,g,b) = colors.extractRGB(cell.bgColor)
          bgCol = color(r.float/255, g.float/255, b.float/255)
        fgCol = textColor
        case cell.fg
        of fgNone: fgCol = textColor
        of fgBlack: fgCol = color(0,0,0)
        of fgRed: fgCol = color(1,0,0)
        of fgGreen: fgCol = color(0,1,0)
        of fgYellow: fgCol = color(1,1,0)
        of fgBlue: fgCol = color(0,0,1)
        of fgMagenta: fgCol = color(1,0,1)
        of fgCyan: fgCol = color(0,1,1)
        of fgWhite: fgCol = color(1,1,1)
        of fgRGB:
          let (r,g,b) = colors.extractRGB(cell.fgColor)
          fgCol = color(r.float/255, g.float/255, b.float/255)
        if styleReverse in cell.style:
          case cell.fg
          of fgNone: bgCol = textColor
          else: bgCol = fgCol
          bg = bgRGB
          fgCol = cursorBg
        # NUI-GAP: textFlags (underscore/italic/blink, incl. the
        # styleBlink->TextBold quirk) is computed but never applied:
        # UiNodeText has no font-style/underline slots, so underline /
        # italic / blink-bold from the old drawText(textFlags) path are
        # visually lost (see §24). styleDim->darken(0.2) is kept.
        if styleUnderscore in cell.style: textFlags = textFlags or 1
        if styleItalic in cell.style: textFlags = textFlags or 2
        if styleBlink in cell.style: textFlags = textFlags or 4
        if styleDim in cell.style: fgCol = fgCol.darken(0.2)
    flushNui()
    discard nui.customRenderCommands(cmds)

proc requestTerminalViewportNui(b: var UiBuilder, nodeIdx, userData: int) {.nimcall, gcsafe, raises: [].} =
  discard userData
  let existing = b.nodeStorageGet(b.frame.nodes[nodeIdx].addr)
  if existing == nil or not (existing of TerminalInputNuiStorage):
    return
  let storage = cast[TerminalInputNuiStorage](existing)
  if storage.list == nil or storage.view == nil or storage.view.terminal == nil:
    return
  let terminal = storage.view.terminal
  let list = storage.list
  let visible = list.visibleItemRange()
  let offset = list.scrollOffsetY / storage.cellHeight
  let viewportRows = list.viewportHeight / storage.cellHeight
  let maxOffset = max(0.0'f32,
    (terminal.historyLength + terminal.height).float32 * storage.cellHeight - list.viewportHeight)
  storage.followTail = list.scrollOffsetY >= maxOffset - 0.5'f32
  terminal.scrollY = max(0, terminal.historyLength - offset.int)
  if visible.first == storage.requestedFirst and visible.last == storage.requestedLast and
      offset == storage.requestedOffset and terminal.historyStart == storage.requestedHistoryStart and
      storage.followTail == storage.requestedFollowTail and viewportRows == storage.requestedViewportRows:
    return
  storage.requestedFirst = visible.first
  storage.requestedLast = visible.last
  storage.requestedOffset = offset
  storage.requestedHistoryStart = terminal.historyStart
  storage.requestedViewportRows = viewportRows
  storage.requestedFollowTail = storage.followTail
  if terminal.threadTerminated or terminal.inputChannel == nil:
    return
  terminal.sendEvent(InputEvent(kind: InputEventKind.Viewport,
    firstRow: visible.first, lastRow: visible.last, scrollOffset: offset,
    viewportRows: viewportRows, historyStart: terminal.historyStart, followTail: storage.followTail))

proc renderTerminalNui*(self: TerminalView, nui: var UiBuilder,
    outWidth, outHeight, outCellWidth, outCellHeight: var int) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    self.resetDirty()
    let baseBg = nui.themeStyle(UiStyleIndexPanel)[].fillColor
    let bgColor = if self.active: accentVariation(baseBg, 0.06'f32, 1.12'f32) else: baseBg
    let headerBase = nui.themeStyle(UiStyleIndexHeader)[].fillColor
    let headerColor = if self.active: accentVariation(headerBase, 0.04'f32, 1.10'f32) else: headerBase
    nui.layoutVertical("terminal-root"):
      discard nui.fillX().fillY().fillBackground().styleIndex(UiStyleIndexPanel).backgroundColor(bgColor).backendPadding(0).backendGap(4)
      nui.layoutHorizontal("terminal-header"):
        discard nui.fillX().fitY().fillBackground().styleIndex(UiStyleIndexHeader).backgroundColor(headerColor).backendPadding(4).backendGap(4).cornerRadius(0)
        template addSection(txt: string) =
          nui.node:
            discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(txt)
        addSection("Terminal")
        if self.terminal != nil and self.terminal.group != "":
          addSection(" - ")
          addSection(self.terminal.group)
        if self.mode != "":
          addSection(" - ")
          addSection(self.mode)
        if self.terminal != nil and self.terminal.exitCode.isSome:
          addSection(" - ")
          addSection($self.terminal.exitCode.get)
        addSection(" - ")
        if self.terminal != nil:
          if self.terminal.ssh.isSome:
            let opts = self.terminal.ssh.get
            let port = if opts.port.isSome: ":" & $opts.port.get else: ""
            addSection("ssh " & opts.username & "@" & opts.address.get("127.0.0.1") & port)
          else:
            addSection(self.terminal.command)
      nui.node("terminal-body"):
        discard nui.fillX().fillY().fillBackground().styleIndex(UiStyleIndexPanel).backgroundColor(bgColor).padding(0).maskChildren()
        let bodyIndex = nui.currentNodeIndex
        let existing = nui.nodeStorageGet(nui.currentNode)
        let storage = if existing != nil and existing of TerminalInputNuiStorage:
          cast[TerminalInputNuiStorage](existing)
        else:
          TerminalInputNuiStorage()
        if storage.view != self:
          storage.pressedButtons = {}
          storage.initialized = false
          storage.followTail = true
        storage.view = self
        nui.nodeStorage(nui.currentNode, storage)
        if self.terminal == nil:
          return
        let terminal = self.terminal
        let style = nui.themeTextStyle(UiStyleIndexDefaultMono)
        var tmpText = UiNodeText(text: "M".uiString, fontId: style.fontId, fontSize: style.fontSize)
        let arr = nui.getTextArrangement(tmpText.addr, -1)
        let charW = if arr != nil and arr.size.x > 0: arr.size.x else: 8.0'f32
        let charH = if arr != nil and arr.size.y > 0: arr.size.y else: 16.0'f32
        let previousCellHeight = storage.cellHeight
        storage.cellWidth = charW
        storage.cellHeight = charH
        storage.fontId = style.fontId
        storage.fontSize = style.fontSize
        outCellWidth = max(1, charW.int)
        outCellHeight = max(1, charH.int)
        let scrollbarWidth = if nui.backendType == UiBackendType.Terminal: 1.0'f32 else: 10.0'f32
        outWidth = max(1, ((nui.currentNode.size.x - scrollbarWidth) / charW).int)
        outHeight = max(1, (nui.currentNode.size.y / charH).int)
        let previousList = storage.list
        if previousList != nil:
          if storage.alternateScreen != terminal.alternateScreen or
              (storage.historyLength > 0 and terminal.historyLength == 0):
            storage.followTail = true
          if previousCellHeight != charH:
            if not storage.followTail and previousCellHeight > 0:
              previousList.scrollOffsetY *= charH / previousCellHeight
            previousList.clearMeasuredHeights()
          if storage.followTail:
            previousList.scrollOffsetY = max(0.0'f32,
              (terminal.historyLength + terminal.height).float32 * charH - nui.currentNode.size.y)
          else:
            previousList.shiftScrollOffset(-float32(terminal.historyStart - storage.historyStart) * charH)
          if terminal.pendingScrollRows != 0:
            previousList.scrollByY(terminal.pendingScrollRows.float32 * charH)
            terminal.pendingScrollRows = 0
          previousList.scrollSpeed = if terminal.mouseTracking or terminal.alternateScreen: 0 else: charH
        storage.historyLength = terminal.historyLength
        storage.historyStart = terminal.historyStart
        storage.alternateScreen = terminal.alternateScreen
        storage.list = nui.dynamicVirtualList(terminal.historyLength + terminal.height,
          charH, buildTerminalRowNui, bodyIndex)
        if not storage.initialized:
          storage.list.scrollOffsetY = max(0.0'f32,
            (terminal.historyLength + terminal.height).float32 * charH - nui.currentNode.size.y)
          storage.initialized = true
        if terminal.mouseTracking or terminal.alternateScreen:
          storage.list.scrollSpeed = 0
        else:
          storage.list.scrollSpeed = charH
        discard nui.deferBuild(handleTerminalInputNui)
        discard nui.deferBuild(requestTerminalViewportNui)
