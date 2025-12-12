import std/[strformat, options, tables]
import vmath, bumpy, chroma
import misc/[util, custom_logger]
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

  builder.createLines(0, 0, stackTrace.stackFrames.high, color(0, 0, 0, 0), handleScroll, handleLine)

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

  builder.createLines(0, 0, threads.high, color(0, 0, 0, 0), handleScroll, handleLine)

type CreateVariablesOutput = object
  selectedNode: UINode

proc createVariables*(self: VariablesView, builder: UINodeBuilder, debugger: Debugger,
    variablesReference: VariablesReference, selectedBackgroundColor: Color,
    textColor: Color, output: var CreateVariablesOutput) =

  let ids = debugger.currentVariablesContext().getOr:
    return

  let variables {.cursor.} = debugger.variables[ids & variablesReference]
  for i, variable in variables.variables:
    let collapsed = debugger.isCollapsed(ids & variable.variablesReference)
    let hasChildren = variable.variablesReference != 0.VariablesReference
    let childrenCached = debugger.variables.contains(ids & variable.variablesReference)
    let showChildren = hasChildren and childrenCached and not collapsed

    builder.panel(&{SizeToContentY, FillX, LayoutHorizontal}):
      let typeText = variable.`type`.mapIt(": " & it).get("")
      let collapsedText = if hasChildren and showChildren:
        "-"
      elif hasChildren and not showChildren:
        "+"
      else:
        " "

      let text = fmt"{collapsedText} {variable.name}{typeText} = {variable.value}"

      let isSelected = debugger.isSelected(variablesReference, i)

      if isSelected:
        builder.panel(&{SizeToContentY, FillX, FillBackground},
            backgroundColor = selectedBackgroundColor):
          builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = text, textColor = textColor)
          output.selectedNode = currentNode
      else:
        builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = text, textColor = textColor)

    if showChildren:
      builder.panel(&{SizeToContentY, FillX, LayoutVertical}, x = 2 * builder.charWidth):
        self.createVariables(builder, debugger, variable.variablesReference,
          selectedBackgroundColor, textColor, output)

proc createScope*(self: VariablesView, builder: UINodeBuilder, debugger: Debugger, scopeId: int,
    selectedBackgroundColor: Color, textColor: Color, output: var CreateVariablesOutput):
    seq[OverlayFunction] =

  let ids = debugger.currentVariablesContext().getOr:
    return

  let scopes = debugger.currentScopes().get

  let scope {.cursor.} = scopes[].scopes[scopeId]

  builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
    let collapsed = debugger.isCollapsed(ids & scope.variablesReference)
    let hasChildren = scope.variablesReference != 0.VariablesReference
    let childrenCached = debugger.variables.contains(ids & scope.variablesReference)
    let showChildren = hasChildren and childrenCached and not collapsed

    let collapsedText = if hasChildren and showChildren:
      "-"
    elif hasChildren and not showChildren:
      "+"
    else:
      " "

    let text = &"{collapsedText} {scope.name}"

    let isSelected = debugger.isScopeSelected(scopeId)
    if isSelected:
      builder.panel(&{SizeToContentY, FillX, FillBackground}, backgroundColor = selectedBackgroundColor):
        builder.panel(&{SizeToContentY, FillX, DrawText}, text = text, textColor = textColor)
        output.selectedNode = currentNode
    else:
      builder.panel(&{SizeToContentY, FillX, DrawText}, text = text, textColor = textColor)

    if showChildren:
      builder.panel(&{SizeToContentY, FillX, LayoutVertical}, x = 2 * builder.charWidth):
        self.createVariables(builder, debugger, scope.variablesReference,
          selectedBackgroundColor, textColor, output)

proc createVariables*(self: VariablesView, builder: UINodeBuilder, debugger: Debugger): seq[OverlayFunction] =
  let textColor = builder.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let selectionColor = builder.theme.color("list.activeSelectionBackground", color(0.8, 0.8, 0.8)).withAlpha(1)
  let threads {.cursor.} = debugger.getThreads()

  proc handleScroll(delta: float) = discard

  var createVariablesOutput = CreateVariablesOutput()

  var res: seq[OverlayFunction]
  proc handleLine(line: int, y: float, down: bool) =
    builder.panel(&{SizeToContentY, FillX}, y = y):
      res.add self.createScope(builder, debugger, line, selectionColor, textColor, createVariablesOutput)

  let scopes = debugger.currentScopes().getOr:
    return

  var scrolledNode: UINode
  builder.panel(builder.currentSizeFlags):
    scrolledNode = currentNode
    builder.createLines(0, 0, scopes[].scopes.high, color(0, 0, 0, 0), handleScroll, handleLine)
    debugger.maxVariablesScrollOffset = currentNode.bounds.h - builder.lineHeight

  if createVariablesOutput.selectedNode.isNotNil:
    let bounds = createVariablesOutput.selectedNode.transformBounds(builder.currentParent)
    let scrollOffset = debugger.variablesScrollOffset - bounds.y
    scrolledNode.rawY = scrolledNode.boundsRaw.y + scrollOffset

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
  let selectionColor = builder.theme.color("list.activeSelectionBackground", color(0.8, 0.8, 0.8)).withAlpha(1)
  if getDebugger().getSome(debugger):
    self.renderView(builder,
      proc(): seq[OverlayFunction] =
        self.createVariables(builder, debugger)
      ,
      proc(): seq[OverlayFunction] =
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Variables")
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
    proc(): seq[OverlayFunction] = @[],
    proc(): seq[OverlayFunction] =
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
