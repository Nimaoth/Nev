import std/[strformat, options, tables, sets, strutils]
import vmath, bumpy, chroma
import misc/[util, custom_logger, timer]
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

  let height = builder.currentParent.bounds.h
  let variablesCursor = debugger.cursor()

  builder.panel(&{FillX, FillY, MaskContent}):
    buildCommands(currentNode.renderCommands):

      var selectedY = float.none

      proc drawVariable(cursor: VariableCursor, y: float) =
        if cursor.path.len > 0:
          let v = cursor.path.last
          debugger.variables.withValue(ids & v.varRef, vars):
            let indent = cursor.path.len.float * builder.charWidth * 3
            if v.index in 0..vars.variables.high:
              let va {.cursor.} = vars.variables[v.index]
              let collapsed = debugger.isCollapsed(ids & va.variablesReference)
              let hasChildren = va.variablesReference != 0.VariablesReference
              let childrenCached = debugger.variables.contains(ids & va.variablesReference)
              let showChildren = hasChildren and childrenCached and not collapsed
              let isSelected = debugger.isSelected(v.varRef, v.index)
              let valueChanged = va.valueChanged.get(false)

              var upToDate = true
              if hasChildren and childrenCached and debugger.variables[ids & va.variablesReference].timestamp != debugger.timestamp:
                upToDate = false

              let typeText = va.`type`.mapIt(": " & it).get("")
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
              #   fillRect(rect(indent, y, builder.currentParent.bounds.w, builder.textHeight), changedColor)

              if isSelected:
                selectedY = y.some
                fillRect(rect(indent, y, builder.currentParent.bounds.w, builder.textHeight), selectionColor)

              var highlightIndices = newSeq[int]()
              var highlightIndex = -1
              if debugger.filteredVariables.contains(v):
                highlightIndex = va.name.find(debugger.variablesFilter)

              var x = indent
              drawText(collapsedText, rect(x, y, 1, 1), textColor.darken(0.15), 0.UINodeFlags)
              x += builder.charWidth * (collapsedText.len + 1).float

              if highlightIndex >= 0:
                let a = highlightIndex
                let b = highlightIndex + debugger.variablesFilter.len
                if a > 0:
                  drawText(va.name[0..<a], rect(x, y, 1, 1), nameColor, 0.UINodeFlags)
                drawText(va.name[a..<b], rect(x + a.float * builder.charWidth, y, 1, 1), textColorHighlight, 0.UINodeFlags)
                if b < va.name.len:
                  drawText(va.name[b..^1], rect(x + b.float * builder.charWidth, y, 1, 1), nameColor, 0.UINodeFlags)
              else:
                drawText(va.name, rect(x, y, 1, 1), nameColor, 0.UINodeFlags)

              x += builder.charWidth * va.name.len.float

              if va.`type`.isSome:
                drawText(": ", rect(x, y, 1, 1), textColor, 0.UINodeFlags)
                x += builder.charWidth * 2
                drawText(va.`type`.get, rect(x, y, 1, 1), typeColor, 0.UINodeFlags)
                x += builder.charWidth * va.`type`.get.len.float

              if va.value != "":
                drawText(" = ", rect(x, y, 1, 1), textColor, 0.UINodeFlags)
                x += builder.charWidth * 3

                if valueChanged:
                  fillRect(rect(x, y, va.value.len.float * builder.charWidth, builder.textHeight), changedColor)
                drawText(va.value, rect(x, y, 1, 1), valueColor, 0.UINodeFlags)

        elif cursor.scope in 0..scopes[].scopes.high:
          let scope = scopes[].scopes[cursor.scope]
          let collapsed = debugger.isCollapsed(ids & scope.variablesReference)
          let hasChildren = scope.variablesReference != 0.VariablesReference
          let childrenCached = debugger.variables.contains(ids & scope.variablesReference)
          let showChildren = hasChildren and childrenCached and not collapsed
          let isSelected = debugger.isScopeSelected(cursor.scope)

          let collapsedText = if hasChildren and showChildren:
            "-"
          elif hasChildren and not showChildren:
            "+"
          else:
            " "

          if isSelected:
            selectedY = y.some
            fillRect(rect(0, y, builder.currentParent.bounds.w, builder.textHeight), selectionColor)
          let text = &"{collapsedText} {scope.name}"
          drawText(text, rect(0, y, 1, 1), nameColor, 0.UINodeFlags)

      proc drawVariables() =
        currentNode.renderCommands.clear()
        var cursor = self.baseIndex
        var y = self.scrollOffset
        let variablesUp = (y / builder.textHeight).int + 1
        let variablesDown = ((height - y) / builder.textHeight).int + 1
        for i in 0..variablesDown:
          drawVariable(cursor, y)
          y += builder.textHeight
          let newCursor = debugger.moveNext(cursor)
          if newCursor.isNone:
            break
          cursor = newCursor.get

        y = self.scrollOffset
        cursor = self.baseIndex
        for i in 0..<variablesUp:
          y -= builder.textHeight
          let newCursor = debugger.movePrev(cursor)
          if newCursor.isNone:
            break
          cursor = newCursor.get
          drawVariable(cursor, y)

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
      let ms = t.elapsed.ms
      # debugf"draw variables took {ms}"
      currentNode.markDirty(builder)

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
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Variables")

        if debugger.variablesFilter.len > 0:
          builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = " - Filter: ")
          builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColorHighlight, text = debugger.variablesFilter)
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

method createUI*(self: DebuggerView, builder: UINodeBuilder): seq[OverlayFunction] =
  let services = ({.gcsafe.}: gServices)
  let dirty = self.dirty
  self.resetDirty()

  let config = services.getServiceChecked(ConfigService).runtime
  let platform = services.getServiceChecked(PlatformService).platform

  let transparentBackground = config.get("ui.background.transparent", false)
  let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var backgroundColor = builder.theme.color("editor.background", color(25/255, 25/255, 25/255)).darken(0.025)
  var activeBackgroundColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255))
  activeBackgroundColor.a = 1
  # let selectedBackgroundColor = builder.theme.color("editorSuggestWidget.selectedBackground", color(0.6, 0.5, 0.2)).withAlpha(1)
  let selectedBackgroundColor = color(0.6, 0.4, 0.2) # todo

  if transparentBackground:
    backgroundColor.a = 0
    activeBackgroundColor.a = 0
  else:
    backgroundColor.a = 1
    activeBackgroundColor.a = 1

  let headerColor = builder.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255)).withAlpha(1)
  let activeHeaderColor = builder.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)).withAlpha(1)

  let sizeToContentX = SizeToContentX in builder.currentParent.flags
  let sizeToContentY = SizeToContentY in builder.currentParent.flags

  var sizeFlags = 0.UINodeFlags
  if sizeToContentX:
    sizeFlags.incl SizeToContentX
  else:
    sizeFlags.incl FillX

  if sizeToContentY:
    sizeFlags.incl SizeToContentY
  else:
    sizeFlags.incl FillY

  var res: seq[OverlayFunction] = @[]

  builder.panel(&{UINodeFlag.MaskContent, OverlappingChildren} + sizeFlags, userId = uiUserId.newPrimaryId):
    if true or dirty or platform.redrawEverything or not builder.retain():
      builder.panel(&{LayoutVertical} + sizeFlags):
        # Header
        builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
            backgroundColor = headerColor):

          var text = &"Debugger"
          if getDebugger().getSome(debugger):
            case debugger.debuggerState
            of DebuggerState.None: text.add " - Not started"
            of DebuggerState.Starting: text.add " - Starting"
            of DebuggerState.Paused: text.add " - Paused"
            of DebuggerState.Running: text.add " - Running"

            if debugger.lastConfiguration.getSome(config):
              text.add " - " & config

            if debugger.breakpointsEnabled:
              text.add " - Breakpoints: ✅"
            else:
              text.add " - Breakpoints: ❌"

          builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = text)

        # Body
        builder.panel(sizeFlags + &{FillBackground}, backgroundColor = backgroundColor):
          let bounds = currentNode.bounds

          let (stackAndThreadsBounds, rest) = bounds.splitH(0.25.percent)
          let (threadsBounds, stackBounds) = stackAndThreadsBounds.splitV(0.3.percent)
          let (localsBounds, outputBounds) = rest.splitH(0.5.percent)

          if getDebugger().getSome(debugger):
            proc chooseBg(view: ActiveView): Color =
              if self.active and debugger.activeView == view:
                activeBackgroundColor
              else:
                backgroundColor

            proc chooseHeaderColor(view: ActiveView): Color =
              if self.active and debugger.activeView == view:
                activeHeaderColor
              else:
                headerColor

            proc shouldBeActive(view: ActiveView): bool =
              if self.active and debugger.activeView == view:
                true
              else:
                false

            try:
              builder.panel(sizeFlags, x = stackBounds.x, y = stackBounds.y, w = stackBounds.w,
                  h = stackBounds.h):
                self.stacktrace.active = shouldBeActive(ActiveView.StackTrace)
                res.add self.stacktrace.createUI(builder)
            except Exception:
              discard

            try:
              builder.panel(sizeFlags, x = threadsBounds.x, y = threadsBounds.y, w = threadsBounds.w,
                  h = threadsBounds.h):
                self.threads.active = shouldBeActive(ActiveView.Threads)
                res.add self.threads.createUI(builder)
            except Exception:
              discard

            try:
              builder.panel(sizeFlags, x = localsBounds.x, y = localsBounds.y, w = localsBounds.w,
                  h = localsBounds.h):
                self.variables.active = shouldBeActive(ActiveView.Variables)
                res.add self.variables.createUI(builder)
            except Exception:
              discard

            try:
              builder.panel(sizeFlags, x = outputBounds.x, y = outputBounds.y, w = outputBounds.w,
                  h = outputBounds.h):
                self.output.active = shouldBeActive(ActiveView.Output)
                res.add self.output.createUI(builder)
            except Exception:
              discard

  res
