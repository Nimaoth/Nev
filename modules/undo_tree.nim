#use command_component layout command_service input_handler
import std/[options, algorithm, strutils, times, tables, json]
import service, view
import component

export component

const currentSourcePath2 = currentSourcePath()
include module_base

# Implementation
when implModule:
  import std/sets
  import misc/[custom_logger, util, id, myjsonutils]
  import text_component, document_editor, document, layout/layout, command_component, input_handler/input_handler, platform
  import nimsumtree/[buffer, clock]
  import command_service
  import vmath, chroma
  import theme
  import app/theme_styles
  import misc/[render_command, event]
  import nuigi
  import nuigi/widgets
  import nuigi/widgets/dynamic_virtuallist

  logCategory "undo-tree"

  type
    AsciiGraphCell* = tuple[col: int, char: char, nodeLineIndex: int, color: Color, style: UINodeFlags]
    SeqLine* = object
      cells*: seq[AsciiGraphCell]
      isBranch*: bool
      nodeIdx*: int32 = -1
    LineSeq* = seq[SeqLine]

    UndoTreeView* = ref object of View
      lastEditor: Option[DocumentEditor]
      eventHandlers*: Table[string, EventHandler]
      cachedLines: LineSeq
      cachedBufferId: BufferID
      cachedLen: int
      cachedMaxCol: int
      cachedBranchColors: array[7, Color]
      selected*: int
      autoApply*: bool = false

    UndoTreeNuiStorage = ref object of UiNodeStorageData
      view: UndoTreeView
      lineDetails: seq[string]
      currentNode: int32
      charWidth: float32
      lineHeight: float32
      listStorage: UiDynamicVirtualListStorage
      lastSelected: int = -1

  var gUndoTreeView: UndoTreeView

  proc undoTreeToggleAutoApply(view: UndoTreeView) {.gcsafe, raises: [].}
  proc undoTreePrevChange(view: UndoTreeView) {.gcsafe, raises: [].}
  proc undoTreeNextChange(view: UndoTreeView) {.gcsafe, raises: [].}
  proc undoTreeFirstChange(view: UndoTreeView) {.gcsafe, raises: [].}
  proc undoTreeLastChange(view: UndoTreeView) {.gcsafe, raises: [].}
  proc undoTreeSelectCurrent(view: UndoTreeView) {.gcsafe, raises: [].}
  proc undoTreeApplySelected(view: UndoTreeView) {.gcsafe, raises: [].}

  proc getOrCreateUndoTreeNuiStorage(
      b: var UiBuilder, node: auto): UndoTreeNuiStorage =
    let existing = b.nodeStorageGet(node)
    if existing != nil:
      return cast[UndoTreeNuiStorage](existing)
    var storage = UndoTreeNuiStorage()
    b.nodeStorage(node, storage)
    storage

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

  proc undoBranchColors(nui: UiBuilder): array[7, Color] =
    const indices = [UiStyleIndexTerminalAnsiBrightYellowText,
      UiStyleIndexTerminalAnsiRedText, UiStyleIndexTerminalAnsiGreenText,
      UiStyleIndexTerminalAnsiBlueText, UiStyleIndexTerminalAnsiMagentaText,
      UiStyleIndexTerminalAnsiCyanText, UiStyleIndexTerminalAnsiYellowText]
    for i, index in indices:
      result[i] = nui.themeTextStyle(index)[].textColor.toColor

  proc generateLines(self: UndoTreeView, buffer: Buffer, nui: UiBuilder) =
    # let t = startTimer()
    # defer:
    #   echo &"parse took {t.elapsed.ms}ms"

    self.cachedBranchColors = nui.undoBranchColors()

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

        let colorIndex = prev mod self.cachedBranchColors.len
        cell.color = self.cachedBranchColors[colorIndex]
        cell.style = if colorIndex == 0: &{TextBold} else: 0.UINodeFlags
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

  proc buildUndoTreeRowNui(
      b: var UiBuilder, itemIndex: int, userData: int) {.nimcall, gcsafe, raises: [].} =
    if userData < 0 or userData >= b.frame.nodes.len:
      return
    let existing = b.nodeStorageGet(b.frame.nodes[userData].addr)
    if existing == nil or not (existing of UndoTreeNuiStorage):
      return
    let storage = cast[UndoTreeNuiStorage](existing)
    let view = storage.view
    if view == nil or itemIndex < 0 or itemIndex >= view.cachedLines.len:
      return

    try:
      let line {.cursor.} = view.cachedLines[itemIndex]
      let selected = itemIndex == view.selected
      let hovered = b.wasHovered(includeChildren = true)
      discard b.fillX().fitY().backendPadding(2).gap(0)
        .styleIndex(if selected or hovered:
          UiStyleIndexMenuItemHover
        else:
          UiStyleIndexRow)
        .fillBackground()

      # NUI-GAP: old graph cells honor per-cell UINodeFlags (TextBold for first
      # branch); new forces uniform UiStyleIndexDefaultMono (see §24).
      b.node:
        discard b.fillX().height(storage.lineHeight)
        for cell in line.cells:
          let isCurrent = line.nodeIdx == storage.currentNode and
            cell.char in {'+', '*'}
          let glyph = if isCurrent:
            "(" & $cell.char & ")"
          else:
            $cell.char
          let column = cell.col - (if isCurrent: 1 else: 0)
          b.node:
            discard b.position(column.float32 * storage.charWidth, 0)
              .fit().copyTextStyleIndex(UiStyleIndexDefaultMono)
              .textColor(rgba(cell.color.r.float32, cell.color.g.float32,
                cell.color.b.float32, cell.color.a.float32)).text(glyph)

        let detail = if itemIndex < storage.lineDetails.len:
          storage.lineDetails[itemIndex]
        else:
          ""
        # NUI-GAP: old detail splits saveMark/nodeText/timeStr into 3 drawText
        # calls (lighten/darken + italic timestamp); new collapses to one text
        # node (see §24).
        # NUI-GAP: old selection is list.activeSelectionBackground fillRect with
        # no hover state; new conflates transient wasHovered with selected and
        # loses the exact theme color (see §24).
        b.node:
          discard b.position(
            view.cachedMaxCol.float32 * storage.charWidth, 0)
            .fit().textStyleIndex(int(if selected:
              UiStyleIndexMenuItemHoverText
            else:
              UiStyleIndexDefaultMono)).text(detail)

      # NUI-GAP: old Left click selects, DoubleClick selects + applySelected
      # unconditionally; Nuigi has no double-click event so new only supports
      # single click (+ autoApply) with an explicit Apply button (see §24).
      if b.wasClicked(includeChildren = true):
        view.selected = itemIndex
        view.markDirty()
        if view.autoApply:
          view.applySelected()
    except:
      discard

  proc renderUndoTreeNui*(self: UndoTreeView, nui: var UiBuilder) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      self.resetDirty()
      let layout = getServiceChecked(LayoutService)
      var editor = layout.getActiveEditor()
      if editor.isNone:
        editor = self.lastEditor

      var title = "Undo History"
      var hasTree = false
      var currentNode = -1'i32
      var lineDetails: seq[string] = @[]
      if editor.isSome and editor.get.currentDocument != nil:
        self.lastEditor = editor
        let document = editor.get.currentDocument
        let (path, name) = document.filename.splitPath
        title = "Undo History for " & name
        if path.len > 0:
          title.add(" - " & path)
        if document.getTextComponent().getSome(text):
          let buffer {.cursor.} = text.buffer
          let tree {.cursor.} = buffer.history.undoTree
          if tree.nodes.len > 0:
            hasTree = true
            if buffer.remoteId != self.cachedBufferId or
                tree.nodes.len != self.cachedLen or
                self.cachedBranchColors != nui.undoBranchColors():
              self.generateLines(buffer, nui)
            currentNode = tree.current
            let now = getTime().toUnix().int64
            lineDetails = newSeq[string](self.cachedLines.len)
            for lineIndex, line in self.cachedLines:
              if line.nodeIdx >= 0 and line.nodeIdx < tree.nodes.len:
                let historyNode = tree.nodes[line.nodeIdx]
                let currentMark = if line.nodeIdx == tree.current: "> " else: "  "
                var detail: string
                if tree.nodes.len == 1:
                  detail = currentMark & "1 " &
                    $historyNode.transaction.id.asNumber & " (base)"
                else:
                  detail = currentMark & $line.nodeIdx & " (" &
                    formatTimeAgo(now, historyNode.transaction.timestampUnix) & ")"
                  if historyNode.transaction.id == text.savedVersion:
                    detail.add(" (saved)")
                lineDetails[lineIndex] = detail

      var charWidth = 8.0'f32
      var lineHeight = 18.0'f32
      let platform = getServiceChecked(PlatformService).platform
      if platform != nil:
        charWidth = max(1.0'f32, platform.charWidth.float32)
        lineHeight = max(1.0'f32, platform.lineHeight.float32)
      if nui.backendType == UiBackendType.Terminal:
        charWidth = 1.0'f32
        lineHeight = 1.0'f32

      let panelStyle = if self.active: UiStyleIndexPanelActive else: UiStyleIndexPanel
      let headerStyle = if self.active: UiStyleIndexHeaderActive else: UiStyleIndexHeader
      nui.layoutVertical("undo-tree"):
        discard nui.fillX().fillY().styleIndex(panelStyle)
          .fillBackground().backendPadding(0).backendGap(4)
        nui.nodeStorageParent()
        let rootIndex = nui.currentNodeIndex
        let storage = nui.getOrCreateUndoTreeNuiStorage(nui.currentNode)
        storage.view = self
        storage.lineDetails = lineDetails
        storage.currentNode = currentNode
        storage.charWidth = charWidth
        storage.lineHeight = lineHeight

        if nui.wasClicked(includeChildren = true):
          layout.tryActivateView(self)

        nui.layoutHorizontal("undo-tree-header"):
          discard nui.fillX().fitY().styleIndex(headerStyle)
            .fillBackground().backendPadding(4).backendGap(4).cornerRadius(0)
          nui.node:
            discard nui.fit().textStyleIndex(int(UiStyleIndexHeaderText))
              .text(title)
          nui.layoutHorizontalReverse:
            discard nui.fillX().fitY().backendGap(4)
            if nui.button(if self.autoApply: "Auto: On" else: "Auto: Off"):
              self.undoTreeToggleAutoApply()

        nui.layoutHorizontal("undo-tree-actions"):
          discard nui.fillX().fitY().backendGap(4)
          if nui.button("Apply"):
            self.undoTreeApplySelected()
          if nui.button("Current"):
            self.undoTreeSelectCurrent()
          if nui.button("Newer"):
            self.undoTreeNextChange()
          if nui.button("Older"):
            self.undoTreePrevChange()
          if nui.button("Newest"):
            self.undoTreeLastChange()
          if nui.button("Oldest"):
            self.undoTreeFirstChange()

        # Selection changes are brought into view by listStorage.ensureItemVisible
        # below, replacing the old explicit scroll calls.
        nui.node("undo-tree-body"):
          discard nui.fillX().fillY()
          if hasTree and self.cachedLines.len > 0:
            storage.listStorage = nui.dynamicVirtualList(
              self.cachedLines.len,
              lineHeight + 4.0'f32,
              buildUndoTreeRowNui,
              rootIndex)
            if storage.listStorage != nil and
                storage.lastSelected != self.selected and
                storage.listStorage.ensureItemVisible(
                  self.selected, storage.listStorage.viewportHeight,
                  lineHeight * 2.0'f32):
              storage.lastSelected = self.selected
          else:
            nui.node:
              discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText))
                .text("No undo history")

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
    result.renderNuiImpl = proc(view: View, nui: var UiBuilder) {.gcsafe, raises: [].} =
      renderUndoTreeNui(view.UndoTreeView, nui)

    result.getEventHandlersImpl = proc(self: View, inject: Table[string, EventHandler]): seq[EventHandler] =
      getUndoTreeViewEventHandlers(self.UndoTreeView, inject)

    result.kindImpl = proc(self: View): string = kind(self.UndoTreeView)
    result.descImpl = proc(self: View): string = desc(self.UndoTreeView)
    result.displayImpl = proc(self: View): string = display(self.UndoTreeView)
    result.copyImpl = proc(self: View): View = copy(self.UndoTreeView)
    result.saveLayoutImpl = proc(self: View, discardedViews: HashSet[Id]): JsonNode = saveLayout(self.UndoTreeView, discardedViews)
    result.saveStateImpl = proc(self: View): JsonNode = saveState(self.UndoTreeView)

  proc getUndoTreeView(): UndoTreeView =
    {.gcsafe.}:
      if gUndoTreeView.isNil:
        raise newException(ValueError, "Undo tree view not initialized")
      gUndoTreeView

  proc parseUndoTreeTime(args: string): int =
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
    0

  template withUndoTreeContext(view: UndoTreeView, body: untyped): untyped =
    if view.lastEditor.isSome:
      if view.lastEditor.get.currentDocument.getTextComponent.getSome(textComp):
        let editor {.inject, used.} = view.lastEditor.get
        let document {.inject, used.} = editor.currentDocument
        let text {.inject, used.} = textComp
        body

  proc applySelected(view: UndoTreeView, editor: DocumentEditor, force = false) =
    if (view.autoApply or force) and editor.getCommandComponent().getSome(cmd):
      if view.selected in 0..view.cachedLines.high:
        let nodeIndex = view.cachedLines[view.selected].nodeIdx
        if nodeIndex != -1:
          cmd.executeCommand(&"switch-undo-branch {nodeIndex}")

  proc undoTreeToggle(view: UndoTreeView) =
    let layout = getServiceChecked(LayoutService)
    if layout.isViewVisible(view):
      layout.closeView(view, keepHidden = false, restoreHidden = false)
    else:
      layout.addView(view, slot = "#small-left", focus = false)

  proc undoTreeToggleAutoApply(view: UndoTreeView) =
    withUndoTreeContext(view):
      view.autoApply = not view.autoApply

  proc undoTreePrevChange(view: UndoTreeView) =
    withUndoTreeContext(view):
      if view.selected < view.cachedLines.high:
        inc view.selected
        applySelected(view, editor)

  proc undoTreeNextChange(view: UndoTreeView) =
    withUndoTreeContext(view):
      if view.selected > 0:
        dec view.selected
        applySelected(view, editor)

  proc undoTreePrevChangeTime(view: UndoTreeView, args: string = "") =
    withUndoTreeContext(view):
      let tree = text.buffer.history.undoTree
      if view.selected >= 0 and view.selected < view.cachedLines.high:
        let time = parseUndoTreeTime(args)
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
        applySelected(view, editor)

  proc undoTreeNextChangeTime(view: UndoTreeView, args: string = "") =
    withUndoTreeContext(view):
      let tree = text.buffer.history.undoTree
      if view.selected > 0 and view.selected <= view.cachedLines.high:
        let time = parseUndoTreeTime(args)
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
        applySelected(view, editor)

  proc undoTreeFirstChange(view: UndoTreeView) =
    withUndoTreeContext(view):
      view.selected = view.cachedLines.high
      applySelected(view, editor)

  proc undoTreeLastChange(view: UndoTreeView) =
    withUndoTreeContext(view):
      view.selected = 0
      applySelected(view, editor)

  proc undoTreeLeftChange(view: UndoTreeView) =
    withUndoTreeContext(view):
      if view.selected in 0..view.cachedLines.high:
        let line {.cursor.} = view.cachedLines[view.selected]
        for i in 0..<line.cells.high:
          if line.cells[i].char == '|' and line.cells[i + 1].char == '/':
            if line.cells[i].nodeLineIndex != -1:
              view.selected = line.cells[i].nodeLineIndex
              applySelected(view, editor)
              break

  proc undoTreeRightChange(view: UndoTreeView) =
    withUndoTreeContext(view):
      if view.selected in 0..view.cachedLines.high:
        let line {.cursor.} = view.cachedLines[view.selected]
        for i in 0..<line.cells.high:
          if line.cells[i].char == '|' and line.cells[i + 1].char == '/':
            if line.cells[i + 1].nodeLineIndex != -1:
              view.selected = line.cells[i + 1].nodeLineIndex
              applySelected(view, editor)
              break

  proc undoTreeActiveChild(view: UndoTreeView) =
    withUndoTreeContext(view):
      let tree = text.buffer.history.undoTree
      if view.selected in 0..view.cachedLines.high:
        let line {.cursor.} = view.cachedLines[view.selected]
        if line.nodeIdx != -1 and line.nodeIdx in 0..tree.nodes.high:
          let activeChild = tree.nodes[line.nodeIdx].activeChild
          for i in countdown(view.selected, 0):
            if view.cachedLines[i].nodeIdx == activeChild:
              view.selected = i
              applySelected(view, editor)
              break

  proc undoTreeParentChange(view: UndoTreeView) =
    withUndoTreeContext(view):
      let tree = text.buffer.history.undoTree
      if view.selected in 0..view.cachedLines.high:
        let line {.cursor.} = view.cachedLines[view.selected]
        if line.nodeIdx != -1 and line.nodeIdx in 0..tree.nodes.high:
          let parent = tree.nodes[line.nodeIdx].parent
          for i in view.selected..view.cachedLines.high:
            if view.cachedLines[i].nodeIdx == parent:
              view.selected = i
              applySelected(view, editor)
              break

  proc undoTreeSelectCurrent(view: UndoTreeView) =
    withUndoTreeContext(view):
      let tree = text.buffer.history.undoTree
      for i in 0..view.cachedLines.high:
        if view.cachedLines[i].nodeIdx == tree.current:
          view.selected = i

  proc undoTreeApplySelected(view: UndoTreeView) =
    withUndoTreeContext(view):
      applySelected(view, editor, force = true)

  include generated/undo_tree_commands

  proc init_module_undo_tree*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, "Failed to initialize init_module_undo_tree: no services found"
      return

    let layout = services.getServiceChecked(LayoutService)

    gUndoTreeView = newUndoTreeView()
    let view = gUndoTreeView

    layout.addViewFactory "undotree", proc(config: JsonNode): View {.raises: [].} =
      return view

    registerCommands(getServiceChecked(CommandService))
