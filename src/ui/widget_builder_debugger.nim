import std/[strformat, math, options, tables]
import vmath, bumpy, chroma
import misc/[util, custom_logger]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import platform/platform
import ui/[widget_builders_base, widget_library]
import app, theme, view
import text/text_editor
import text/language/debugger
import text/language/dap_client

import ui/node

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_debugger"

var uiUserId = newId()

proc createStackTrace*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
      backgroundColor: Color, activeBackgroundColor: Color, headerColor: Color, textColor: Color):
    seq[proc() {.closure.}] =

  let sizeToContentX = SizeToContentX in builder.currentParent.flags
  let sizeToContentY = SizeToContentY in builder.currentParent.flags

  let currentThread = debugger.currentThread().getOr:
    return

  let stackTrace = debugger.getStackTrace(currentThread.id).getOr:
    return

  proc handleScroll(delta: float) = discard

  proc handleLine(line: int, y: float, down: bool) =
    let frame {.cursor.} = stackTrace.stackFrames[line]
    var text = &"{frame.name}:{frame.line}"
    if frame.source.getSome(source):
      if source.name.isSome:
        text.add &" - {source.name.get}"
      elif source.path.isSome:
        text.add &" - {source.path.get}"

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

  let chosenBackgroundColor = if self.active and debugger.activeView == ActiveView.StackTrace:
    activeBackgroundColor
  else:
    backgroundColor

  builder.panel(sizeFlags + LayoutVertical):
    builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
        backgroundColor = headerColor):

      let text = &"Stack - Thread {currentThread.id} {currentThread.name}"
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = text)

    builder.panel(sizeFlags):
      builder.createLines(0, 0, stackTrace.stackFrames.high, sizeToContentX, sizeToContentY, chosenBackgroundColor, handleScroll, handleLine)

proc createThreads*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
      backgroundColor: Color, activeBackgroundColor: Color, headerColor: Color, textColor: Color):
    seq[proc() {.closure.}] =

  let sizeToContentX = SizeToContentX in builder.currentParent.flags
  let sizeToContentY = SizeToContentY in builder.currentParent.flags

  let threads {.cursor.} = debugger.getThreads()

  proc handleScroll(delta: float) = discard

  proc handleLine(line: int, y: float, down: bool) =
    let thread {.cursor.} = threads[line]
    let text = &"{thread.id} - {thread.name}"
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

  let chosenBackgroundColor = if self.active and debugger.activeView == ActiveView.Threads:
    activeBackgroundColor
  else:
    backgroundColor

  builder.panel(sizeFlags + LayoutVertical):
    builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
        backgroundColor = headerColor):
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Threads")

    builder.panel(sizeFlags):
      builder.createLines(0, 0, threads.high, sizeToContentX, sizeToContentY,
        chosenBackgroundColor, handleScroll, handleLine)

type CreateVariablesOutput = object
  selectedNode: UINode

proc createVariables*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
    variablesReference: VariablesReference, backgroundColor: Color, selectedBackgroundColor: Color,
    textColor: Color, output: var CreateVariablesOutput) =

  let variables {.cursor.} = debugger.variables[variablesReference]
  for i, variable in variables.variables:
    let collapsed = debugger.isCollapsed(variable.variablesReference)
    let hasChildren = variable.variablesReference != 0.VariablesReference
    let childrenCached = debugger.variables.contains(variable.variablesReference)
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
        builder.panel(&{SizeToContentY, FillX, FillBackground}, backgroundColor = color(0.6, 0.5, 0.2, 0.3)):
          builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = text, textColor = textColor)
          output.selectedNode = currentNode
      else:
        builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = text, textColor = textColor)

      if collapsed:
        builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = "...", textColor = textColor)

    if showChildren:
      builder.panel(&{SizeToContentY, FillX, LayoutVertical}, x = 2 * builder.charWidth):
        self.createVariables(builder, app, debugger, variable.variablesReference, backgroundColor,
          selectedBackgroundColor, textColor, output)

proc createScope*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger, scopeId: int,
    backgroundColor: Color, headerColor: Color, textColor: Color, output: var CreateVariablesOutput):
    seq[proc() {.closure.}] =

  let scope {.cursor.} = debugger.scopes.scopes[scopeId]
  builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
    let collapsed = debugger.isCollapsed(scope.variablesReference)
    let hasChildren = scope.variablesReference != 0.VariablesReference
    let childrenCached = debugger.variables.contains(scope.variablesReference)
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
      builder.panel(&{SizeToContentY, FillX, FillBackground}, backgroundColor = color(0.6, 0.5, 0.2, 0.3)):
        builder.panel(&{SizeToContentY, FillX, DrawText}, text = text, textColor = textColor)
        output.selectedNode = currentNode
    else:
      builder.panel(&{SizeToContentY, FillX, DrawText}, text = text, textColor = textColor)

    if showChildren:
      builder.panel(&{SizeToContentY, FillX, LayoutVertical}, x = 2 * builder.charWidth):
        self.createVariables(builder, app, debugger, scope.variablesReference, backgroundColor,
          headerColor, textColor, output)

proc createLocals*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
    backgroundColor: Color, activeBackgroundColor: Color, headerColor: Color, textColor: Color):
    seq[proc() {.closure.}] =

  let sizeToContentX = SizeToContentX in builder.currentParent.flags
  let sizeToContentY = SizeToContentY in builder.currentParent.flags

  proc handleScroll(delta: float) = discard

  let chosenBackgroundColor = if self.active and debugger.activeView == ActiveView.Variables:
    activeBackgroundColor
  else:
    backgroundColor

  var createVariablesOutput = CreateVariablesOutput()

  var res: seq[proc() {.closure.}]
  proc handleLine(line: int, y: float, down: bool) =
    builder.panel(&{SizeToContentY, FillX}, y = y):
      res.add self.createScope(builder, app, debugger, line, chosenBackgroundColor, headerColor, textColor, createVariablesOutput)

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

      builder.panel(sizeFlags + FillBackground + MaskContent, backgroundColor = chosenBackgroundColor):
        var scrolledNode: UINode
        builder.panel(sizeFlags):
          scrolledNode = currentNode
          builder.createLines(0, 0, debugger.scopes.scopes.high, sizeToContentX, sizeToContentY,
            chosenBackgroundColor, handleScroll, handleLine)

        debugger.maxVariablesScrollOffset = currentNode.bounds.h - builder.lineHeight

        if createVariablesOutput.selectedNode.isNotNil:
          let bounds = createVariablesOutput.selectedNode.transformBounds(currentNode)
          let scrollOffset = debugger.variablesScrollOffset - bounds.y
          scrolledNode.boundsRaw.y += scrollOffset

  res

proc createOutput*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
      backgroundColor: Color, activeBackgroundColor: Color, headerColor: Color, textColor: Color):
    seq[proc() {.closure.}] =

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

method createUI*(self: DebuggerView, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let dirty = self.dirty
  self.dirty = false

  let transparentBackground = getOption[bool](app, "ui.background.transparent", false)
  let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var backgroundColor = app.theme.color("editor.background", color(25/255, 25/255, 25/255)).darken(0.025)
  var activeBackgroundColor = app.theme.color("editor.background", color(25/255, 25/255, 40/255))
  activeBackgroundColor.a = 1

  if transparentBackground:
    backgroundColor.a = 0
    activeBackgroundColor.a = 0
  else:
    backgroundColor.a = 1
    activeBackgroundColor.a = 1

  let headerColor = app.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255)).withAlpha(1)
  let activeHeaderColor = app.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)).withAlpha(1)

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

  var res: seq[proc() {.closure.}] = @[]

  builder.panel(&{UINodeFlag.MaskContent, OverlappingChildren} + sizeFlags, userId = uiUserId.newPrimaryId):
    # onClickAny btn:
    #   self.app.tryActivateEditor(self)

    if true or dirty or app.platform.redrawEverything or not builder.retain():
      builder.panel(&{LayoutVertical} + sizeFlags):
        # Header
        builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
            backgroundColor = headerColor):

          let text = &"Debugger"
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
                chooseBg(ActiveView.StackTrace), chooseHeaderColor(ActiveView.StackTrace), textColor)

            builder.panel(sizeFlags, x = threadsBounds.x, y = threadsBounds.y, w = threadsBounds.w,
                h = threadsBounds.h):
              res.add self.createThreads(builder, app, debugger, chooseBg(ActiveView.Threads),
                chooseBg(ActiveView.Threads), chooseHeaderColor(ActiveView.Threads), textColor)

            builder.panel(sizeFlags, x = localsBounds.x, y = localsBounds.y, w = localsBounds.w,
                h = localsBounds.h):
              res.add self.createLocals(builder, app, debugger, chooseBg(ActiveView.Variables),
                chooseBg(ActiveView.Variables), chooseHeaderColor(ActiveView.Variables), textColor)

            builder.panel(sizeFlags, x = outputBounds.x, y = outputBounds.y, w = outputBounds.w,
                h = outputBounds.h):
              res.add self.createOutput(builder, app, debugger, chooseBg(ActiveView.Output),
                chooseBg(ActiveView.Output), chooseHeaderColor(ActiveView.Output), textColor)

  res
