import std/[strformat, options, tables, sets, strutils, algorithm]
import vmath, bumpy, chroma
import misc/[util, custom_logger, timer, array_set]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import platform/platform
import platform_service
import ui/[widget_builders_base, widget_library]
import theme, view
import text/text_editor
import service
import text/language/debugger
import text/language/dap_client
import config_provider

import ui/node

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_debugger"

var uiUserId = newId()

proc createStackTrace*(self: StacktraceView, builder: UINodeBuilder, debugger: Debugger): seq[OverlayFunction] =
  let currentThread = debugger.currentThread().getOr:
    return

  let stackTrace = debugger.getStackTrace(currentThread.id).getOr:
    return

  let textColor = builder.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let selectionColor = builder.theme.color("list.activeSelectionBackground", color(0.8, 0.8, 0.8)).withAlpha(1)

  proc handleScroll(delta: float) = discard

  proc handleLine(line: int, y: float, down: bool) =
    let isSelected = line == debugger.currentFrameIndex
    let frame {.cursor.} = stackTrace.stackFrames[line]
    var text = &"{frame.name}:{frame.line}"
    if frame.source.getSome(source):
      if source.name.isSome:
        text.add &" - {source.name.get}"
      elif source.path.isSome:
        text.add &" - {source.path.get}"

    if isSelected:
      builder.panel(&{SizeToContentY, FillX, FillBackground}, y = y, backgroundColor = selectionColor):
        builder.panel(&{SizeToContentY, FillX, DrawText}, text = text, textColor = textColor)
    else:
      builder.panel(&{SizeToContentY, FillX, DrawText}, y = y, text = text, textColor = textColor)

  let height = builder.currentParent.bounds.h
  updateBaseIndexAndScrollOffset(height, self.baseIndex, self.scrollOffset, stackTrace.stackFrames.len, builder.textHeight, debugger.currentFrameIndex.some)
  builder.createLines(self.baseIndex, self.scrollOffset, stackTrace.stackFrames.high, color(0, 0, 0, 0), handleScroll, handleLine)

proc createThreads*(self: ThreadsView, builder: UINodeBuilder, debugger: Debugger): seq[OverlayFunction] =
  let textColor = builder.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let selectionColor = builder.theme.color("list.activeSelectionBackground", color(0.8, 0.8, 0.8)).withAlpha(1)
  let threads {.cursor.} = debugger.getThreads()

  proc handleScroll(delta: float) = discard

  proc handleLine(line: int, y: float, down: bool) =
    let isSelected = line == debugger.currentThreadIndex

    let thread {.cursor.} = threads[line]
    let text = &"{thread.id} - {thread.name}"
    if isSelected:
      builder.panel(&{SizeToContentY, FillX, FillBackground}, y = y, backgroundColor = selectionColor):
        builder.panel(&{SizeToContentY, FillX, DrawText}, text = text, textColor = textColor)
    else:
      builder.panel(&{SizeToContentY, FillX, DrawText}, y = y, text = text, textColor = textColor)

  let height = builder.currentParent.bounds.h
  updateBaseIndexAndScrollOffset(height, self.baseIndex, self.scrollOffset, threads.len, builder.textHeight, debugger.currentThreadIndex.some)
  builder.createLines(self.baseIndex, self.scrollOffset, threads.high, color(0, 0, 0, 0), handleScroll, handleLine)

proc createVariables*(self: VariablesView, builder: UINodeBuilder, debugger: Debugger): seq[OverlayFunction] =
  let textColor = builder.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let changedColor = builder.theme.color("diffEditor.insertedTextBackground", color(0.8, 0.8, 0.8))
  let selectionColor = builder.theme.color("list.activeSelectionBackground", color(0.8, 0.8, 0.8))
  let borderColor = builder.theme.color("panel.border", color(0, 0, 0))
  let threads {.cursor.} = debugger.getThreads()
  let textColorHighlight = builder.theme.color("editor.foreground.highlight", color(0.9, 0.8, 0.8))
  let typeColor = builder.theme.tokenColor("type", color(0.9, 0.8, 0.8))
  let valueColor = builder.theme.tokenColor("string", color(0.9, 0.8, 0.8))
  let nameColor = builder.theme.tokenColor("variable", color(0.9, 0.8, 0.8))

  let scopes = debugger.currentScopes().getOr:
    return

  let ids = debugger.currentVariablesContext().getOr:
    return

  let sizeFlags = builder.currentSizeFlags

  var width = builder.currentParent.bounds.w
  var height = builder.currentParent.bounds.h

  if SizeToContentX in sizeFlags:
    width = builder.charWidth * 60 + self.sizeOffset.x
  if SizeToContentY in sizeFlags:
    height = builder.textHeight * 10 + self.sizeOffset.y

  let variablesCursor = self.variablesCursor

  proc detach(self: VariablesView, node: UINode) =
    self.detach(node.boundsAbsolute)
    # if not self.detached:
    #   self.absoluteBounds = node.boundsAbsolute
    # self.detached = true

  builder.panel(&{MaskContent} + sizeFlags, x = 0, y = 0):
    let root = currentNode
    onScroll:
      self.scrollOffset += delta.y * 10
      self.markDirty()
    currentNode.handleDrag = proc(node: UINode, btn: MouseButton, modifiers: set[Modifier], pos: Vec2, delta: Vec2): bool =
      builder.draggedNodes.incl(node)
      let oldPos = pos - delta
      if Alt in modifiers:
        let resizeWidth = builder.textHeight * 3
        if oldPos.x > root.bounds.w - resizeWidth:
          if self.detached:
            self.absoluteBounds.w += delta.x
            self.sizeOffset.x = 0
          else:
            self.sizeOffset.x += delta.x
        elif oldPos.x < resizeWidth:
          self.detach(node)
          self.absoluteBounds.x += delta.x
          self.absoluteBounds.w -= delta.x
          self.sizeOffset.x = 0

        if oldPos.y > root.bounds.h - resizeWidth:
          self.detach(node)
          if self.detached:
            self.absoluteBounds.h += delta.y
            self.sizeOffset.y = 0
          else:
            self.sizeOffset.y += delta.y
        elif oldPos.y < resizeWidth:
          if self.detached:
            self.absoluteBounds.y += delta.y
            self.absoluteBounds.h -= delta.y
            self.sizeOffset.y = 0
          else:
            self.sizeOffset.y -= delta.y

        if oldPos.y <= root.bounds.h - resizeWidth and oldPos.y >= resizeWidth and oldPos.x <= root.bounds.w - resizeWidth and oldPos.x >= resizeWidth:
          self.detach(node)
          self.absoluteBounds.x += delta.x
          self.absoluteBounds.y += delta.y
          self.sizeOffset = vec2()

        self.absoluteBounds.w = max(self.absoluteBounds.w, builder.textHeight)
        self.absoluteBounds.h = max(self.absoluteBounds.h, builder.textHeight)

        self.markDirty()
      return true
    onClickAny btn:
      for line in self.lastRenderedCursors:
        if pos in line.bounds:
          if btn == MouseButton.Left:
            self.variablesCursor = line.cursor
            self.markDirty()
          elif btn == MouseButton.DoubleClick:
            self.variablesCursor = line.cursor
            self.expandOrCollapseVariable()
            self.markDirty()
          break

    builder.panel(sizeFlags, x = 0, y = 0):
      buildCommands(currentNode.renderCommands):

        var selectedY = float.none
        var maxX = 0.float
        var maxY = 0.float
        var minY = float.high
        var selectedVariableMultilineValue: string = ""

        proc drawVariable(indent: float, y: float, varRef: VariablesReference, name: string, typ: Option[string], value: string, valueChanged: bool, isSelected: bool, isFiltered: bool) =
          let collapsed = self.isCollapsed(ids & varRef)
          let hasChildren = varRef != 0.VariablesReference
          let childrenCached = debugger.variables.contains(ids & varRef)
          let showChildren = hasChildren and childrenCached and not collapsed

          var upToDate = true
          if hasChildren and childrenCached and debugger.variables[ids & varRef].timestamp != debugger.timestamp:
            upToDate = false

          let typeText = typ.mapIt(": " & it).get("")
          var collapsedText = if hasChildren and showChildren:
            "-"
          elif hasChildren and not showChildren:
            "+"
          else:
            " "

          var nameColor = nameColor
          var typeColor = typeColor
          var valueColor = valueColor
          if not upToDate:
            nameColor = nameColor.darken(0.15)
            typeColor = typeColor.darken(0.15)
            valueColor = valueColor.darken(0.15)

          # if valueChanged:
          #   fillRect(rect(indent, y, width, builder.textHeight), changedColor)

          if isSelected:
            selectedY = y.some
            fillRect(rect(indent, y, width, builder.textHeight), selectionColor)

          var highlightIndices = newSeq[int]()
          var highlightIndex = -1
          if isFiltered:
            highlightIndex = name.find(self.variablesFilter)

          var x = indent
          drawText(collapsedText, rect(x, y, 1, 1), textColor.darken(0.15), 0.UINodeFlags)
          x += builder.charWidth * (collapsedText.len + 1).float

          if highlightIndex >= 0:
            let a = highlightIndex
            let b = highlightIndex + self.variablesFilter.len
            if a > 0:
              drawText(name[0..<a], rect(x, y, 1, 1), nameColor, 0.UINodeFlags)
            drawText(name[a..<b], rect(x + a.float * builder.charWidth, y, 1, 1), textColorHighlight, 0.UINodeFlags)
            if b < name.len:
              drawText(name[b..^1], rect(x + b.float * builder.charWidth, y, 1, 1), nameColor, 0.UINodeFlags)
          else:
            drawText(name, rect(x, y, 1, 1), nameColor, 0.UINodeFlags)

          x += builder.charWidth * name.len.float

          if typ.isSome:
            drawText(": ", rect(x, y, 1, 1), textColor, 0.UINodeFlags)
            x += builder.charWidth * 2
            drawText(typ.get, rect(x, y, 1, 1), typeColor, 0.UINodeFlags)
            x += builder.charWidth * typ.get.len.float

          if value != "":
            drawText(" = ", rect(x, y, 1, 1), textColor, 0.UINodeFlags)
            x += builder.charWidth * 3

            var nl = value.find("\n")
            if nl == -1:
              nl = value.len

            if valueChanged:
              fillRect(rect(x, y, nl.float * builder.charWidth, builder.textHeight), changedColor)
            if nl < value.len:
              # if isSelected:
              #   # todo: don't copy string
              #   selectedVariableMultilineValue = value
              drawText(value[0..<nl], rect(x, y, 1, 1), valueColor, 0.UINodeFlags)
            else:
              drawText(value, rect(x, y, 1, 1), valueColor, 0.UINodeFlags)
            x += builder.charWidth * nl.float

          maxX = max(maxX, x)
          maxY = max(maxY, y + builder.textHeight)
          minY = min(minY, y)

        proc drawVariable(cursor: VariableCursor, y: float) =
          if cursor.path.len > 0:
            let v = cursor.path.last
            debugger.variables.withValue(ids & v.varRef, vars):
              let indent = cursor.path.len.float * builder.charWidth * 3
              if v.index in 0..vars.variables.high:
                let va {.cursor.} = vars.variables[v.index]
                let isSelected = self.isSelected(v.varRef, v.index)
                let isFiltered = self.filteredVariables.contains(v)
                drawVariable(indent, y, va.variablesReference, va.name, va.`type`, va.value, va.valueChanged.get(false), isSelected, isFiltered)

          elif cursor.scope == -1:
            drawVariable(0, y, self.evaluation.variablesReference, self.evaluationName, self.evaluation.`type`, self.evaluation.result, false, self.variablesCursor.path.len == 0, false)

          elif cursor.scope in 0..scopes[].scopes.high:
            let scope = scopes[].scopes[cursor.scope]
            let collapsed = self.isCollapsed(ids & scope.variablesReference)
            let hasChildren = scope.variablesReference != 0.VariablesReference
            let childrenCached = debugger.variables.contains(ids & scope.variablesReference)
            let showChildren = hasChildren and childrenCached and not collapsed
            let isSelected = self.isScopeSelected(cursor.scope)

            let collapsedText = if hasChildren and showChildren:
              "-"
            elif hasChildren and not showChildren:
              "+"
            else:
              " "

            if isSelected:
              selectedY = y.some
              fillRect(rect(0, y, width, builder.textHeight), selectionColor)
            let text = &"{collapsedText} {scope.name}"
            drawText(text, rect(0, y, 1, 1), nameColor, 0.UINodeFlags)

        var cursorsUp = newSeq[tuple[bounds: Rect, cursor: VariableCursor]]()
        var cursorsDown = newSeq[tuple[bounds: Rect, cursor: VariableCursor]]()

        proc drawVariables() =
          currentNode.renderCommands.clear()
          cursorsUp.setLen(0)
          cursorsDown.setLen(0)
          maxX = 0
          maxY = 0
          minY = float.high
          var cursorDown = self.baseIndex.some
          var yDown = self.scrollOffset
          var variablesUp = (yDown / builder.textHeight).int + 1
          var variablesDown = ((height - yDown) / builder.textHeight).int + 1
          if SizeToContentY in sizeFlags:
            variablesUp = max(variablesUp, 5)
            variablesDown = max(variablesDown, 5)
          while variablesDown > 0 and cursorDown.isSome:
            cursorsDown.add (rect(0, yDown, width, builder.textHeight), cursorDown.get)
            drawVariable(cursorDown.get, yDown)
            dec variablesDown
            yDown += builder.textHeight
            cursorDown = self.moveNext(debugger, cursorDown.get)

          variablesUp += variablesDown
          var yUp = self.scrollOffset - builder.textHeight
          var cursorUp = self.movePrev(debugger, self.baseIndex)
          while variablesUp > 0 and cursorUp.isSome:
            cursorsUp.add (rect(0, yUp, width, builder.textHeight), cursorUp.get)
            drawVariable(cursorUp.get, yUp)
            dec variablesUp
            yUp -= builder.textHeight
            cursorUp = self.movePrev(debugger, cursorUp.get)

          variablesDown += variablesUp
          while variablesDown > 0 and cursorDown.isSome:
            cursorsDown.add (rect(0, yDown, width, builder.textHeight), cursorDown.get)
            drawVariable(cursorDown.get, yDown)
            dec variablesDown
            yDown += builder.textHeight
            cursorDown = self.moveNext(debugger, cursorDown.get)

        var t = startTimer()
        drawVariables()
        self.baseIndex = variablesCursor
        if selectedY.isNone:
          self.scrollOffset = height * 0.5
          drawVariables()
        elif selectedY.get > height - builder.textHeight:
          self.scrollOffset = height - builder.textHeight
          drawVariables()
        elif selectedY.get < 0:
          self.scrollOffset = 0
          drawVariables()
        else:
          self.scrollOffset = selectedY.get

        cursorsUp.reverse()
        self.lastRenderedCursors = cursorsUp & cursorsDown
        # todo: make this more performant
        # if selectedVariableMultilineValue != "":
        #   let textSize = debugger.platform.measureText(selectedVariableMultilineValue)
        #   drawText(selectedVariableMultilineValue, rect(maxX + builder.charWidth, selectedY.get, 1, 1), valueColor, 0.UINodeFlags)
        #   maxX += textSize.x + builder.charWidth
        #   maxY = max(maxY, selectedY.get + textSize.y)

        if SizeToContentY in sizeFlags and minY < float.high:
          if (maxY - minY) < height:
            currentNode.rawY = -minY
            for c in self.lastRenderedCursors.mitems:
              c.bounds.y -= minY
          currentNode.h = min(maxY - minY + self.sizeOffset.y, height)
        if SizeToContentX in sizeFlags:
          currentNode.w = min(maxX + self.sizeOffset.x, width)

        currentNode.markDirty(builder)

        let ms = t.elapsed.ms
        # debugf"draw variables took {ms}, bounds: {rect(0, minY, maxX, maxY - minY)}"

method createUI*(self: StacktraceView, builder: UINodeBuilder): seq[OverlayFunction] =
  let textColor = builder.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  if getDebugger().getSome(debugger):
    self.renderView(builder,
      proc(): seq[OverlayFunction] =
        self.createStackTrace(builder, debugger)
      ,
      proc(): seq[OverlayFunction] =
        let currentThreadText = debugger.currentThread().mapIt(&" - Thread {it.id} {it.name}").get("")
        let text = &"Stack{currentThreadText}"
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = text)
    )
  else:
    @[]

method createUI*(self: ThreadsView, builder: UINodeBuilder): seq[OverlayFunction] =
  let textColor = builder.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  if getDebugger().getSome(debugger):
    self.renderView(builder,
      proc(): seq[OverlayFunction] =
        self.createThreads(builder, debugger)
      ,
      proc(): seq[OverlayFunction] =
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Threads")
    )
  else:
    @[]

method createUI*(self: VariablesView, builder: UINodeBuilder): seq[OverlayFunction] =
  let textColor = builder.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let textColorHighlight = builder.theme.color("editor.foreground.highlight", color(0.9, 0.8, 0.8))
  let selectionColor = builder.theme.color("list.activeSelectionBackground", color(0.8, 0.8, 0.8)).withAlpha(1)
  if getDebugger().getSome(debugger):
    self.renderView(builder,
      proc(): seq[OverlayFunction] =
        self.createVariables(builder, debugger)
      ,
      proc(): seq[OverlayFunction] =
        if self.renderHeader:
          builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Variables")

          if self.variablesFilter.len > 0:
            builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = " - Filter: ")
            builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColorHighlight, text = self.variablesFilter)
    )
  else:
    @[]

method createUI*(self: OutputView, builder: UINodeBuilder): seq[OverlayFunction] =
  let textColor = builder.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  if getDebugger().getSome(debugger):
    self.renderView(builder,
      proc(): seq[OverlayFunction] =
        if debugger.outputEditor != nil:
          let wasActive = debugger.outputEditor.active
          debugger.outputEditor.active = self.active
          if debugger.outputEditor.active != wasActive:
            debugger.outputEditor.markDirty(notify=false)
          return debugger.outputEditor.createUI(builder)
      ,
      proc(): seq[OverlayFunction] =
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Output")
    )
  else:
    @[]

method createUI*(self: ToolbarView, builder: UINodeBuilder): seq[OverlayFunction] =
  let textColor = builder.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  self.renderView(builder,
    proc(): seq[OverlayFunction] =
      if getDebugger().getSome(debugger):
        if debugger.debuggerState == DebuggerState.Paused:
          if debugger.currentStopData.description.isSome:
            builder.panel(&{FillX, SizeToContentY, DrawText, TextWrap}, textColor = textColor, text = debugger.currentStopData.description.get)
    ,
    proc(): seq[OverlayFunction] =
      var text = &"Debugger"
      if getDebugger().getSome(debugger):
        case debugger.debuggerState
        of DebuggerState.None: text.add " - Not started"
        of DebuggerState.Starting: text.add " - Starting"
        of DebuggerState.Paused:
          text.add " - Paused"
          if debugger.currentStopData.reason != "":
            text.add " (" & debugger.currentStopData.reason & ")"
        of DebuggerState.Running: text.add " - Running"

        if debugger.lastConfiguration.getSome(config):
          text.add " - " & config

        if debugger.breakpointsEnabled:
          text.add " - Breakpoints: ✅"
        else:
          text.add " - Breakpoints: ❌"
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = text)
  )
