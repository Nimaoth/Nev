import std/[strformat, options, tables]
import vmath, bumpy, chroma
import misc/[util, custom_logger]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import platform/platform
import ui/[widget_builders_base, widget_library]
import app, theme, view
import text/text_editor
import text/language/debugger
import text/language/dap_client
import config_provider

import ui/node

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_debugger"

var uiUserId = newId()

proc createStackTrace*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
      backgroundColor: Color, selectedBackgroundColor: Color, headerColor: Color, textColor: Color):
    seq[OverlayFunction] =

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

  builder.panel(sizeFlags + LayoutVertical):
    # Header
    builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
        backgroundColor = headerColor):

      let currentThreadText = debugger.currentThread().mapIt(&" - Thread {it.id} {it.name}").get("")
      let text = &"Stack{currentThreadText}"
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = text)

    let currentThread = debugger.currentThread().getOr:
      return

    let stackTrace = debugger.getStackTrace(currentThread.id).getOr:
      return

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
        builder.panel(&{SizeToContentY, FillX, FillBackground}, y = y,
            backgroundColor = selectedBackgroundColor):
          builder.panel(&{SizeToContentY, FillX, DrawText}, text = text, textColor = textColor)
      else:
        builder.panel(&{SizeToContentY, FillX, DrawText}, y = y, text = text, textColor = textColor)

    builder.panel(sizeFlags):
      builder.createLines(0, 0, stackTrace.stackFrames.high, sizeToContentX, sizeToContentY,
        backgroundColor, handleScroll, handleLine)

proc createThreads*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
      backgroundColor: Color, selectedBackgroundColor: Color, headerColor: Color, textColor: Color):
    seq[OverlayFunction] =

  let sizeToContentX = SizeToContentX in builder.currentParent.flags
  let sizeToContentY = SizeToContentY in builder.currentParent.flags

  let threads {.cursor.} = debugger.getThreads()

  proc handleScroll(delta: float) = discard

  proc handleLine(line: int, y: float, down: bool) =
    let isSelected = line == debugger.currentThreadIndex

    let thread {.cursor.} = threads[line]
    let text = &"{thread.id} - {thread.name}"
    if isSelected:
      builder.panel(&{SizeToContentY, FillX, FillBackground}, y = y,
          backgroundColor = selectedBackgroundColor):
        builder.panel(&{SizeToContentY, FillX, DrawText}, text = text, textColor = textColor)
    else:
      builder.panel(&{SizeToContentY, FillX, DrawText}, y = y, text = text, textColor = textColor)

  var sizeFlags = 0.UINodeFlags
  if sizeToContentX:
    sizeFlags.incl SizeToContentX
  else:
    sizeFlags.incl FillX

  if sizeToContentY:
    sizeFlags.incl SizeToContentY
  else:
    sizeFlags.incl FillY

  builder.panel(sizeFlags + LayoutVertical):
    builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
        backgroundColor = headerColor):
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Threads")

    builder.panel(sizeFlags):
      builder.createLines(0, 0, threads.high, sizeToContentX, sizeToContentY,
        backgroundColor, handleScroll, handleLine)

type CreateVariablesOutput = object
  selectedNode: UINode

proc createVariables*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
    variablesReference: VariablesReference, backgroundColor: Color, selectedBackgroundColor: Color,
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
        self.createVariables(builder, app, debugger, variable.variablesReference, backgroundColor,
          selectedBackgroundColor, textColor, output)

proc createScope*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger, scopeId: int,
    backgroundColor: Color, selectedBackgroundColor: Color, headerColor: Color, textColor: Color,
    output: var CreateVariablesOutput):
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
        self.createVariables(builder, app, debugger, scope.variablesReference, backgroundColor,
          selectedBackgroundColor, textColor, output)

proc createVariables*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
    backgroundColor: Color, selectedBackgroundColor: Color, headerColor: Color, textColor: Color):
    seq[OverlayFunction] =

  let sizeToContentX = SizeToContentX in builder.currentParent.flags
  let sizeToContentY = SizeToContentY in builder.currentParent.flags

  proc handleScroll(delta: float) = discard

  var createVariablesOutput = CreateVariablesOutput()

  var res: seq[OverlayFunction]
  proc handleLine(line: int, y: float, down: bool) =
    builder.panel(&{SizeToContentY, FillX}, y = y):
      res.add self.createScope(builder, app, debugger, line, backgroundColor, selectedBackgroundColor,
        headerColor, textColor, createVariablesOutput)

  var sizeFlags = 0.UINodeFlags
  if sizeToContentX:
    sizeFlags.incl SizeToContentX
  else:
    sizeFlags.incl FillX

  if sizeToContentY:
    sizeFlags.incl SizeToContentY
  else:
    sizeFlags.incl FillY

  builder.panel(sizeFlags):
    builder.panel(sizeFlags + LayoutVertical):
      builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
          backgroundColor = headerColor):
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Variables")

      let scopes = debugger.currentScopes().getOr:
        return

      builder.panel(sizeFlags + FillBackground + MaskContent, backgroundColor = backgroundColor):
        var scrolledNode: UINode
        builder.panel(sizeFlags):
          scrolledNode = currentNode
          builder.createLines(0, 0, scopes[].scopes.high, sizeToContentX, sizeToContentY,
            backgroundColor, handleScroll, handleLine)

        debugger.maxVariablesScrollOffset = currentNode.bounds.h - builder.lineHeight

        if createVariablesOutput.selectedNode.isNotNil:
          let bounds = createVariablesOutput.selectedNode.transformBounds(currentNode)
          let scrollOffset = debugger.variablesScrollOffset - bounds.y
          scrolledNode.boundsRaw.y += scrollOffset

  res

proc createOutput*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
      backgroundColor: Color, selectedBackgroundColor: Color, headerColor: Color, textColor: Color):
    seq[OverlayFunction] =

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

  let wasActive = debugger.outputEditor.active
  debugger.outputEditor.active = self.active and debugger.activeView == ActiveView.Output
  if debugger.outputEditor.active != wasActive:
    debugger.outputEditor.markDirty(notify=false)

  builder.panel(sizeFlags + LayoutVertical):
    builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
        backgroundColor = headerColor):
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Output")

    debugger.outputEditor.createUI(builder, app)

method createUI*(self: DebuggerView, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  let dirty = self.dirty
  self.resetDirty()

  let transparentBackground = app.config.runtime.get("ui.background.transparent", false)
  let textColor = app.themes.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var backgroundColor = app.themes.theme.color("editor.background", color(25/255, 25/255, 25/255)).darken(0.025)
  var activeBackgroundColor = app.themes.theme.color("editor.background", color(25/255, 25/255, 40/255))
  activeBackgroundColor.a = 1
  # let selectedBackgroundColor = app.themes.theme.color("editorSuggestWidget.selectedBackground", color(0.6, 0.5, 0.2)).withAlpha(1)
  let selectedBackgroundColor = color(0.6, 0.4, 0.2) # todo

  if transparentBackground:
    backgroundColor.a = 0
    activeBackgroundColor.a = 0
  else:
    backgroundColor.a = 1
    activeBackgroundColor.a = 1

  let headerColor = app.themes.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255)).withAlpha(1)
  let activeHeaderColor = app.themes.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)).withAlpha(1)

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
    # onClickAny btn:
    #   self.app.tryActivateEditor(self)

    if true or dirty or app.platform.redrawEverything or not builder.retain():
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

            builder.panel(sizeFlags, x = stackBounds.x, y = stackBounds.y, w = stackBounds.w,
                h = stackBounds.h):
              res.add self.createStackTrace(builder, app, debugger, chooseBg(ActiveView.StackTrace),
                selectedBackgroundColor, chooseHeaderColor(ActiveView.StackTrace), textColor)

            builder.panel(sizeFlags, x = threadsBounds.x, y = threadsBounds.y, w = threadsBounds.w,
                h = threadsBounds.h):
              res.add self.createThreads(builder, app, debugger, chooseBg(ActiveView.Threads),
                selectedBackgroundColor, chooseHeaderColor(ActiveView.Threads), textColor)

            builder.panel(sizeFlags, x = localsBounds.x, y = localsBounds.y, w = localsBounds.w,
                h = localsBounds.h):
              res.add self.createVariables(builder, app, debugger, chooseBg(ActiveView.Variables),
                selectedBackgroundColor, chooseHeaderColor(ActiveView.Variables), textColor)

            builder.panel(sizeFlags, x = outputBounds.x, y = outputBounds.y, w = outputBounds.w,
                h = outputBounds.h):
              res.add self.createOutput(builder, app, debugger, chooseBg(ActiveView.Output),
                selectedBackgroundColor, chooseHeaderColor(ActiveView.Output), textColor)

  res
