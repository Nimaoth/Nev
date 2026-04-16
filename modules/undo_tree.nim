#use command_component
import std/[options, algorithm, strutils, times, tables, json]
import service, dynamic_view
import component

export component

const currentSourcePath2 = currentSourcePath()
include module_base

# Implementation
when implModule:
  import std/sets
  import misc/[custom_logger, util, id, myjsonutils]
  import text_component, document_editor, document, layout, command_component, events, platform_service
  import nimsumtree/[buffer, clock]
  import ui/node
  import command_service
  import vmath, chroma
  import theme
  import misc/[render_command, event]
  import scroll_box

  logCategory "undo-tree"

  type
    AsciiGraphCell* = tuple[col: int, char: char, nodeLineIndex: int, color: Color, style: UINodeFlags]
    SeqLine* = object
      cells*: seq[AsciiGraphCell]
      isBranch*: bool
      nodeIdx*: int32 = -1
    LineSeq* = seq[SeqLine]

    UndoTreeView* = ref object of DynamicView
      lastEditor: Option[DocumentEditor]
      eventHandlers*: Table[string, EventHandler]
      cachedLines: LineSeq
      cachedBufferId: BufferID
      cachedLen: int
      cachedMaxCol: int
      selected*: int
      scrollBox*: ScrollBox
      autoApply*: bool = false

  proc add(line: var seq[AsciiGraphCell], item: tuple[col: int, char: char]) =
    line.add (item.col, item.char, -1, color(0, 0, 0), 0.UINodeFlags)

  proc getUndoTreeViewEventHandler(self: UndoTreeView, context: string): EventHandler =
    let events = getServiceChecked(EventHandlerService)
    if context notin self.eventHandlers:
      var eventHandler: EventHandler
      assignEventHandler(eventHandler, events.getEventHandlerConfig(context)):
        onAction:
          if getServiceChecked(CommandService).executeCommand(action & " " & arg, false).isSome:
            Handled
          else:
            Ignored
        onInput:
          Ignored

      self.eventHandlers[context] = eventHandler
      return eventHandler

    return self.eventHandlers[context]

  proc getUndoTreeViewEventHandlers(self: UndoTreeView, inject: Table[string, EventHandler]): seq[EventHandler] =
    result.add self.getUndoTreeViewEventHandler("undotree")

  proc getOrCreate(t: var LineSeq, i: int): var SeqLine =
    while t.len < i + 1:
      t.add(SeqLine(cells: newSeq[AsciiGraphCell]()))
    return t[i]

  proc getMaxCol(line: openArray[AsciiGraphCell]): int =
    if line.len == 0:
      return -1
    return line[^1].col

  proc adjustBranchLine(gLine: var seq[AsciiGraphCell], col: int, active: bool, depth = 0): int =
    # log "  ".repeat(depth), &"adjustBranchLine col={col} {gLine}"
    if gLine.len == 0:
      return col
    let cell = gLine[^1]
    if cell.char == '/' and (cell.col == col + 1 or cell.col == col - 1):
      if cell.col != col + 1:
        gLine.add((col + 1, '/'))
      return col + 2
    elif cell.char == '\\':
      if cell.col != col - 1:
        gLine.add((col - 1, '\\'))
      return col - 2

    if cell.col != col:
      let barChar = '|'
      gLine.add((col, barChar))
    return col

  proc newBranchLine(line2seq: var LineSeq, lnum, col: int, isMerge: bool, active: bool, depth = 0): int =
    let barChar = '|'
    var newline = SeqLine(isBranch: true, cells: newSeq[AsciiGraphCell]())
    let pLine = getOrCreate(line2seq, lnum - 1).cells
    let pLen = pLine.len
    let cLine = getOrCreate(line2seq, lnum).cells
    let cLen = cLine.len
    # log "  ".repeat(depth), &"newBranchLine lnum={lnum} col={col} merge={isMerge} {pLine} - {cLine}"
    if cLen == 0 and not isMerge:
      newline.cells.add (1, barChar)

    var pc = 0
    var cc = 0
    while pc < pLen and cc < cLen:
      let pcol = pLine[pc].col
      let ccol = cLine[cc].col
      if pcol == ccol:
        newline.cells.add (pcol, barChar)
        inc pc
        inc cc
      elif pcol > ccol:
        inc cc
      else:
        inc pc

    var finalCol = col
    if isMerge:
      finalCol = col - 2
      newline.cells.add((finalCol + 1, '\\'))
    else:
      if col > newline.cells.getMaxCol():
        newline.cells.add (col, barChar)

      finalCol = col + 2
      newline.cells.add((finalCol - 1, '/'))

    line2seq.insert(newline, lnum)
    # log "  ".repeat(depth), &"newBranchLine {lnum} -> {newline}"
    return finalCol

  proc putSeqNode(line2seq: var LineSeq, lnum, col: int, splitNode: bool, nodeIdx: int32, active: bool, depth = 0): tuple[lnum, col: int] =
    var lnum = lnum
    var col = col
    var sLine = getOrCreate(line2seq, lnum).addr
    let curCol = getMaxCol(sLine.cells)
    let barChar = '|'

    # log "  ".repeat(depth), &"putSeqNode lnum={lnum} col={col} maxCol={curCol} split={splitNode} node={nodeIdx} {sLine[]}"
    if sLine.isBranch:
      if splitNode:
        sLine.cells.add((col, barChar))
      else:
        col = adjustBranchLine(sLine.cells, col, active, depth + 1)
      inc lnum
    elif splitNode:
      discard newBranchLine(line2seq, lnum, col, false, active, depth + 1)
      inc lnum
    elif col - 2 > curCol:
      col = newBranchLine(line2seq, lnum, col, true, active, depth + 1)
      inc lnum

    sLine = getOrCreate(line2seq, lnum).addr
    if active:
      sLine.cells.add((col, '*'))
    else:
      sLine.cells.add((col, '+'))
    sLine.nodeIdx = nodeIdx
    # log "  ".repeat(depth), &"putSeqNode {lnum} -> {sLine[]}"

    return (lnum, col)

  type
    ParseStackFrame = object
      nodeIdx: int32
      lnum: int32
      col: int16
      splitNode: bool
      active: bool

  proc parseUndoTreeLines(tree: UndoTree, line2seq: var LineSeq, lnum, col: int, splitNode: bool, nodeIdx: int32, parentIdx: int32, active: bool) =
    var stack = newSeqOfCap[ParseStackFrame](tree.nodes.len)
    stack.add(ParseStackFrame(
      nodeIdx: nodeIdx,
      lnum: lnum.int32,
      col: col.int16,
      splitNode: splitNode,
      active: active,
    ))

    let barChar = '|'
    var children = newSeq[int32]()

    while stack.len > 0:
      var frame = stack[^1]

      assert frame.nodeIdx in 0..tree.nodes.high
      if tree.nodes[frame.nodeIdx].firstChild != -1: assert tree.nodes[frame.nodeIdx].firstChild > frame.nodeIdx
      if tree.nodes[frame.nodeIdx].nextSibling != -1: assert tree.nodes[frame.nodeIdx].nextSibling > frame.nodeIdx
      assert tree.nodes[frame.nodeIdx].parent < frame.nodeIdx
      var parentIdx = tree.nodes[frame.nodeIdx].parent
      if parentIdx == frame.nodeIdx:
        parentIdx = -1
      let distance = frame.nodeIdx - parentIdx - 1

      var lnum = frame.lnum.int
      var col = frame.col.int
      var remaining = distance

      while remaining > 0:
        var sLine = getOrCreate(line2seq, lnum).addr
        if sLine.isBranch:
          col = adjustBranchLine(sLine.cells, col, frame.active, stack.len + 1)
        else:
          let curCol = getMaxCol(sLine.cells)
          if col - 2 == curCol:
            sLine.cells.add((col, barChar))
          elif col > curCol:
            col = newBranchLine(line2seq, lnum, col, true, frame.active, stack.len + 1)
            inc lnum
            continue

          dec remaining
        inc lnum

      (lnum, col) = putSeqNode(line2seq, lnum, col, frame.splitNode, frame.nodeIdx, frame.active, stack.len)

      let node = tree.nodes[frame.nodeIdx]
      children.setLen(0)
      if node.firstChild > 0:
        var child = node.firstChild
        while child != -1:
          children.add child
          child = tree.nodes[child].nextSibling

      children.reverse()

      discard stack.pop()
      for i, child in children:
        stack.add(ParseStackFrame(
          nodeIdx: child,
          lnum: lnum.int32 + 1,
          col: col.int16,
          splitNode: children.len > 1 and i > 0,
          active: frame.active and tree.nodes[frame.nodeIdx].activeChild == children[i],
        ))

  proc formatTimeAgo*(now: int64, timestamp: int64): string =
    if timestamp == 0:
      return "base"
    let delta = now - timestamp
    if delta == 0:
      return "just now"
    elif delta < 5:
      return "1s ago"
    elif delta < 60:
      let delta = ((delta.float / 5).floor * 5).int
      return $delta & "s ago"
    elif delta < 3600:
      return $ (delta div 60) & "min ago"
    elif delta < 86400:
      return $ (delta div (60 * 60)) & "h ago"
    else:
      return $ (delta div (60 * 60 * 24)) & "d ago"

  proc applySelected(view: UndoTreeView) =
    if view.lastEditor.isSome:
      if view.lastEditor.get.getCommandComponent().getSome(cmd):
        if view.selected in 0..view.cachedLines.high:
          let nodeIndex = view.cachedLines[view.selected].nodeIdx
          if nodeIndex != -1:
            cmd.executeCommand(&"switch-undo-branch {nodeIndex}")

  proc generateLines(self: UndoTreeView, buffer: Buffer, theme: Theme) =
    # let t = startTimer()
    # defer:
    #   echo &"parse took {t.elapsed.ms}ms"

    let branchColors = [
      (theme.color("terminal.ansiBrightYellow", color(1.0, 1.0, 0.7)), &{TextBold}),
      (theme.color("terminal.ansiRed", color(1.0, 0.5, 0.5)), 0.UINodeFlags),
      (theme.color("terminal.ansiGreen", color(0.5, 1.0, 0.5)), 0.UINodeFlags),
      (theme.color("terminal.ansiBlue", color(0.5, 0.5, 1.0)), 0.UINodeFlags),
      (theme.color("terminal.ansiMagenta", color(1.0, 0.5, 1.0)), 0.UINodeFlags),
      (theme.color("terminal.ansiCyan", color(0.5, 1.0, 1.0)), 0.UINodeFlags),
      (theme.color("terminal.ansiYellow", color(1.0, 1.0, 0.5)), 0.UINodeFlags),
    ]

    let tree {.cursor.} = buffer.history.undoTree
    if buffer.remoteId != self.cachedBufferId:
      self.selected = 0

    let lastSelected = self.cachedLines.len > 1 and self.selected == self.cachedLines.high
    self.cachedBufferId = buffer.remoteId
    self.cachedLen = buffer.history.undoTree.nodes.len
    self.cachedLines.setLen(0)
    parseUndoTreeLines(tree, self.cachedLines, 0, 1, false, 0, -1, true)
    self.cachedLines.reverse()
    self.selected = self.selected.clamp(0, self.cachedLines.high)

    if lastSelected:
      self.selected = self.cachedLines.high

    var prevNodes: seq[tuple[col: int, leaf: int32, child: int]] = @[]
    var newPrevNodes: seq[tuple[col: int, leaf: int32, child: int]] = @[]
    proc prevLeaf(col: int, c: char): int =
      let offset = case c
      of '/': 1
      of '\\': -1
      else: 0

      for i, n in prevNodes:
        if n.col == col + offset:
          return i
      return -1

    # Calculate colors
    for lineIndex, line in self.cachedLines.mpairs:
      newPrevNodes = prevNodes
      for cell in line.cells.mitems:
        var prev = prevLeaf(cell.col, cell.char)
        if prev == -1:
          newPrevNodes.add (cell.col, line.nodeIdx, lineIndex)
          prev = newPrevNodes.high

        let (charColor, charStyle) = branchColors[prev mod branchColors.len]
        cell.color = charColor
        cell.style = charStyle
        if prev in 0..prevNodes.high:
          cell.nodeLineIndex = prevNodes[prev].child

        let offset = case cell.char
        of '/': -1
        of '\\': 1
        else: 0
        newPrevNodes[prev].col = cell.col + offset
        if line.nodeIdx != -1 and (cell.char == '*' or cell.char == '+'):
          newPrevNodes[prev].child = lineIndex

      prevNodes = newPrevNodes

    self.cachedMaxCol = 1
    for line in self.cachedLines:
      for cell in line.cells:
        if cell.col > self.cachedMaxCol:
          self.cachedMaxCol = cell.col

    self.cachedMaxCol = self.cachedMaxCol + 3

  proc renderUndoTree*(self: UndoTreeView, builder: UINodeBuilder) =
    var backgroundColor = if self.active: builder.theme.color("editor.background", color(25/255, 25/255, 40/255)) else: builder.theme.color("editor.background", color(25/255, 25/255, 25/255)).lighten(-0.025)
    let layout = getServiceChecked(LayoutService)

    builder.panel(&{FillBackground, FillX, FillY, MaskContent}, backgroundColor = backgroundColor):
      onScroll:
        self.scrollBox.scroll(delta.y * builder.textHeight * 5)
      onClickAny btn:
        if btn == Left:
          for item in self.scrollBox.items:
            if item.bounds.contains(pos - builder.textHeight * 2):
              self.selected = item.index
        elif btn == DoubleClick:
          for item in self.scrollBox.items:
            if item.bounds.contains(pos - builder.textHeight * 2):
              self.selected = item.index
          self.applySelected()
        getServiceChecked(LayoutService).tryActivateView(self)

      currentNode.renderCommands.clear()
      currentNode.markDirty(builder)

      var editor = layout.getActiveEditor()
      if editor.isNone:
        editor = self.lastEditor
      if editor.isNone:
        return
      self.lastEditor = editor

      let document = editor.get.currentDocument
      if document.isNil:
        return
      let text = document.getTextComponent().get
      let buffer {.cursor.} = text.buffer
      let tree {.cursor.} = buffer.history.undoTree
      if tree.nodes.len == 0:
        return

      let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
      let backgroundColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255))

      let charWidth = builder.charWidth
      let lineHeight = builder.textHeight.float

      var headerColor = if self.active: builder.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: builder.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
      self.scrollBox.defaultItemHeight = builder.textHeight
      self.scrollBox.scrollSpeed = builder.textHeight * 2
      self.scrollBox.margin = (5 * builder.textHeight).min(builder.currentParent.bounds.h - 10 * builder.textHeight).max(0)
      self.scrollBox.updateScroll(getServiceChecked(PlatformService).platform.deltaTime)

      buildCommands(currentNode.renderCommands):
        let b = rect(0, 0, builder.currentParent.bounds.w, lineHeight)
        fillRect(b, headerColor)
        let (path, name) = document.filename.splitPath
        drawText("Undo History for " & name & " - " & path, b, textColor, 0.UINodeFlags)

      if buffer.remoteId != self.cachedBufferId or buffer.history.undoTree.nodes.len != self.cachedLen:
        self.generateLines(buffer, builder.theme)

      if tree.nodes.len == 1:
        let node = tree.nodes[0]
        let text = "*1 " & $node.transaction.id.asNumber & " (base)"
        let bounds = rect(0, lineHeight * 2, text.len.float * charWidth, lineHeight)
        buildCommands(currentNode.renderCommands):
          fillRect(bounds, backgroundColor)
          drawText(text, bounds, textColor, 0.UINodeFlags)
        return

      let now = getTime().toUnix().int64

      let selectionColor = builder.theme.color("list.activeSelectionBackground", color(0.8, 0.8, 0.8))
      self.scrollBox.beginRender(builder.currentParent.bounds.wh - 2 * lineHeight, 0.UINodeFlags, self.cachedLines.high)

      proc drawLine(commands: var RenderCommands, index: int): Option[Vec2] =
        if index notin 0..self.cachedLines.high:
          return

        let line {.cursor.} = self.cachedLines[index]

        # Add a transform render command for which we later override the y offset to the correct y offset calculated by the
        # scroll box. Every render command for a line can then just use (0, 0) as the origin.
        commands.startTransform(vec2(0))
        defer:
          commands.endTransform()

        let isSelected = (index == self.selected)
        if isSelected:
          commands.fillRect(rect(0, 0, builder.currentParent.bounds.w, builder.textHeight), selectionColor)

        let isCurrent = (line.nodeIdx == tree.current)
        for cell in line.cells:
          let bounds = rect(cell.col.float * charWidth, 0, charWidth, lineHeight)
          if isCurrent and cell.char in {'+', '*'}:
            commands.drawText("(" & $cell.char & ")", bounds - vec2(charWidth, 0), cell.color, cell.style)
          else:
            commands.drawText($cell.char, bounds, cell.color, cell.style)

        if line.nodeIdx >= 0:
          let node = tree.nodes[line.nodeIdx]
          let seqNum = line.nodeIdx
          let saveMark = if line.nodeIdx == tree.current: ">" else: " "
          var timeStr = " (" & formatTimeAgo(now, node.transaction.timestampUnix) & ")"
          if node.transaction.id == text.savedVersion:
            timeStr.add " (saved)"
          let nodeText = $seqNum
          let bounds = rect(self.cachedMaxCol.float * charWidth, 0, nodeText.len.float * charWidth, lineHeight)
          commands.drawText(saveMark, bounds, textColor.lighten(0.1), 0.UINodeFlags)
          commands.drawText(nodeText, bounds + vec2(charWidth, 0), textColor, 0.UINodeFlags)
          commands.drawText(timeStr, bounds + vec2(charWidth + nodeText.len.float * charWidth, 0), textColor.darken(0.1), &{TextItalic})


        return vec2(builder.currentParent.bounds.w, lineHeight).some

      # List of TransformStart render command indices where we need to fix the offset when we know it the offset after rendering all lines.
      var fixups = newSeq[tuple[line: int, renderCommandHead: int]]()

      while true:
        let renderedItem = self.scrollBox.renderItemT:
          let renderCommandHead = currentNode.renderCommands.commands.len
          let size = drawLine(currentNode.renderCommands, self.scrollBox.currentIndex)
          if size.isSome:
            fixups.add (self.scrollBox.currentIndex, renderCommandHead)
          size

        if not renderedItem:
          break

      fixups.sort(proc(a, b: auto): int = cmp(a.line, b.line))
      # Fixup chunk bounds and Transform render commands now that we know the line bounds
      assert fixups.len == self.scrollBox.items.len
      for i in 0..<fixups.len:
        assert fixups[i].line == self.scrollBox.items[i].index
        let fix = fixups[i]
        let lineBounds = self.scrollBox.items[i].bounds

        # Offset TransformStart render command according to scroll box item bounds
        if fix.renderCommandHead in 0..currentNode.renderCommands.commands.high and
            currentNode.renderCommands.commands[fix.renderCommandHead].kind == RenderCommandKind.TransformStart:
          currentNode.renderCommands.commands[fix.renderCommandHead] = RenderCommand(
            kind: RenderCommandKind.TransformStart,
            bounds: rect((vec2(0, lineHeight * 2 + lineBounds.y)), vec2(0)),
          )

      self.scrollBox.endRender()
      self.scrollBox.clamp(self.cachedLines.high)

      # Scroll bar
      buildCommands(currentNode.renderCommands):
        if self.scrollBox.items.len > 0:
          let scrollBarColor = builder.theme.color(@["scrollBar", "scrollbarSlider.background"], backgroundColor.lighten(0.1))
          let topScrollOffset = clamp(self.scrollBox.items[0].index.float / self.cachedLines.high.float, 0, 1)
          let bottomScrollOffset = clamp(self.scrollBox.items[^1].index.float / self.cachedLines.high.float, 0, 1)
          let y = topScrollOffset * builder.currentParent.bounds.h
          let y2 = bottomScrollOffset * builder.currentParent.bounds.h
          let centerY = (y + y2) * 0.5
          let h = clamp(y2 - y, builder.textHeight, builder.currentParent.bounds.h * 0.5)
          let w = ceil(builder.charWidth * 0.5)
          fillRect(rect(builder.currentParent.bounds.w - w, floor(centerY - h * 0.5), w, ceil(h)), scrollBarColor)

  proc kind(self: UndoTreeView): string = "undotree"
  proc desc(self: UndoTreeView): string = "UndoTree"
  proc display(self: UndoTreeView): string = "UndoTree"
  proc copy(self: UndoTreeView): View = self
  proc saveLayout(self: UndoTreeView, discardedViews: HashSet[Id]): JsonNode =
    result = newJObject()
    result["kind"] = "undotree".toJson

  proc saveState(self: UndoTreeView): JsonNode =
    result = newJObject()
    result["kind"] = "undotree".toJson

  proc newUndoTreeView*(): UndoTreeView =
    result = UndoTreeView()
    result.renderImpl = proc(view: DynamicView, builder: UINodeBuilder): seq[OverlayRenderFunc] =
      let undoView = view.UndoTreeView
      renderUndoTree(undoView, builder)

    result.getEventHandlersImpl = proc(self: DynamicView, inject: Table[string, EventHandler]): seq[EventHandler] =
      getUndoTreeViewEventHandlers(self.UndoTreeView, inject)

    result.kindImpl = proc(self: DynamicView): string = kind(self.UndoTreeView)
    result.descImpl = proc(self: DynamicView): string = desc(self.UndoTreeView)
    result.displayImpl = proc(self: DynamicView): string = display(self.UndoTreeView)
    result.copyImpl = proc(self: DynamicView): View = copy(self.UndoTreeView)
    result.saveLayoutImpl = proc(self: DynamicView, discardedViews: HashSet[Id]): JsonNode = saveLayout(self.UndoTreeView, discardedViews)
    result.saveStateImpl = proc(self: DynamicView): JsonNode = saveState(self.UndoTreeView)

  proc init_module_undo_tree*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, "Failed to initialize init_module_undo_tree: no services found"
      return

    let layout = services.getService(LayoutService).get
    let commands = services.getService(CommandService).get

    var view: UndoTreeView = newUndoTreeView()

    layout.addViewFactory "undotree", proc(config: JsonNode): View {.raises: [].} =
      return view

    proc parseTime(args: string): int =
      try:
        let args = args.parseJson.jsonTo(string)
        var unitIndex = 0
        while unitIndex < args.len and args[unitIndex] in {'0'..'9'}:
          inc unitIndex
        let num = args[0..<unitIndex].parseInt.catch:
          return 0
        let unit = case args[unitIndex..^1]
        of "s": 1
        of "m": 60
        of "h": 60 * 60
        of "d": 60 * 60 * 24
        else: 60
        return num * unit
      except CatchableError:
        discard

    template defineCommand(inName: string, desc: string, body: untyped): untyped =
      discard commands.registerCommand(command_service.Command(
        namespace: "undotree",
        name: "undotree." & inName,
        description: desc,
        parameters: @[],
        returnType: "void",
        execute: proc(args {.inject.}: string): string {.gcsafe, raises: [].} =
          try:
            if view.lastEditor.isSome:
              if view.lastEditor.get.currentDocument.getTextComponent.getSome(textComp):
                let editor {.inject, used.} = view.lastEditor.get
                let document {.inject, used.} = editor.currentDocument
                let text {.inject, used.} = textComp
                body
          except CatchableError:
            discard
          return ""
      ))

    discard commands.registerCommand(command_service.Command(
      namespace: "undotree",
      name: "undotree.toggle",
      description: "Show undo tree for current buffer",
      parameters: @[],
      returnType: "void",
      execute: proc(argsString: string): string {.gcsafe, raises: [].} =
        try:
          if layout.isViewVisible(view):
            layout.closeView(view, keepHidden = false, restoreHidden = false)
          else:
            layout.addView(view, slot = "#small-left", focus = false)
        except CatchableError:
          discard
        return ""
    ))

    proc applySelected(editor: DocumentEditor, force = false) =
      view.scrollBox.scrollTo(view.selected)
      if (view.autoApply or force) and editor.getCommandComponent().getSome(cmd):
        if view.selected in 0..view.cachedLines.high:
          let nodeIndex = view.cachedLines[view.selected].nodeIdx
          if nodeIndex != -1:
            cmd.executeCommand(&"switch-undo-branch {nodeIndex}")

    defineCommand("toggle-auto-apply", "Toggle the auto apply setting"):
      view.autoApply = not view.autoApply

    defineCommand("prev-change", "Go to previous change in undo tree"):
      if view.selected < view.cachedLines.high:
        inc view.selected
        applySelected(editor)

    defineCommand("next-change", "Go to next change in undo tree"):
      if view.selected > 0:
        dec view.selected
        applySelected(editor)

    defineCommand("prev-change-time", "Go to previous change by stepping by a certain time interval in undo tree"):
      let tree = text.buffer.history.undoTree
      if view.selected >= 0 and view.selected < view.cachedLines.high:
        let time = parseTime(args)
        var current = view.selected
        while current < view.cachedLines.high and view.cachedLines[current].nodeIdx == -1:
          inc current
        if view.cachedLines[current].nodeIdx == -1:
          return
        let currentTime = tree.nodes[view.cachedLines[current].nodeIdx].transaction.timestampUnix
        while current < view.cachedLines.high:
          inc current
          let nodeIdx = view.cachedLines[current].nodeIdx
          if nodeIdx != -1 and currentTime - tree.nodes[nodeIdx].transaction.timestampUnix >= time:
            break
        view.selected = current
        applySelected(editor)

    defineCommand("next-change-time", "Go to next change by stepping by a certain time interval in undo tree"):
      let tree = text.buffer.history.undoTree
      if view.selected > 0 and view.selected <= view.cachedLines.high:
        let time = parseTime(args)
        var current = view.selected
        while current > 0 and view.cachedLines[current].nodeIdx == -1:
          dec current
        if view.cachedLines[current].nodeIdx == -1:
          return
        let currentTime = tree.nodes[view.cachedLines[current].nodeIdx].transaction.timestampUnix
        while current > 0:
          dec current
          let nodeIdx = view.cachedLines[current].nodeIdx
          if nodeIdx != -1 and tree.nodes[nodeIdx].transaction.timestampUnix - currentTime >= time:
            break
        view.selected = current
        applySelected(editor)

    defineCommand("first-change", "Go to first change in undo tree"):
      view.selected = view.cachedLines.high
      applySelected(editor)

    defineCommand("last-change", "Go to last change in undo tree"):
      view.selected = 0
      applySelected(editor)

    defineCommand("left-change", "Go to next change on the left branch in the undo tree"):
      if view.selected in 0..view.cachedLines.high:
        let line {.cursor.} = view.cachedLines[view.selected]
        for i in 0..<line.cells.high:
          if line.cells[i].char == '|' and line.cells[i + 1].char == '/':
            if line.cells[i].nodeLineIndex != -1:
              view.selected = line.cells[i].nodeLineIndex
              applySelected(editor)
              break

    defineCommand("right-change", "Go to next change on the right branch in the undo tree"):
      if view.selected in 0..view.cachedLines.high:
        let line {.cursor.} = view.cachedLines[view.selected]
        for i in 0..<line.cells.high:
          if line.cells[i].char == '|' and line.cells[i + 1].char == '/':
            if line.cells[i + 1].nodeLineIndex != -1:
              view.selected = line.cells[i + 1].nodeLineIndex
              applySelected(editor)
              break

    defineCommand("active-child", "Go to the active child of the current change in the undo tree"):
      let tree = text.buffer.history.undoTree
      if view.selected in 0..view.cachedLines.high:
        let line {.cursor.} = view.cachedLines[view.selected]
        if line.nodeIdx != -1 and line.nodeIdx in 0..tree.nodes.high:
          let activeChild = tree.nodes[line.nodeIdx].activeChild
          for i in countdown(view.selected, 0):
            if view.cachedLines[i].nodeIdx == activeChild:
              view.selected = i
              applySelected(editor)
              break

    defineCommand("parent-change", "Go to parent of the current change in the undo tree"):
      let tree = text.buffer.history.undoTree
      if view.selected in 0..view.cachedLines.high:
        let line {.cursor.} = view.cachedLines[view.selected]
        if line.nodeIdx != -1 and line.nodeIdx in 0..tree.nodes.high:
          let parent = tree.nodes[line.nodeIdx].parent
          for i in view.selected..view.cachedLines.high:
            if view.cachedLines[i].nodeIdx == parent:
              view.selected = i
              applySelected(editor)
              break

    defineCommand("select-current", "Go to current change in undo tree"):
      let tree = text.buffer.history.undoTree
      for i in 0..view.cachedLines.high:
        if view.cachedLines[i].nodeIdx == tree.current:
          view.selected = i
          view.scrollBox.scrollTo(view.selected)

    defineCommand("apply-selected", "Make the selected change the current one."):
      applySelected(editor, force=true)
