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
    builder.panel(&{SizeToContentY, FillX, LayoutHorizontal}):
      let typeText = variable.`type`.mapIt(": " & it).get("")
      let text = fmt"{variable.name}{typeText} = {variable.value}"

      let isSelected = debugger.isSelected(variablesReference, i)

      if isSelected:
        builder.panel(&{SizeToContentY, FillX, FillBackground}, backgroundColor = color(0.6, 0.5, 0.2, 0.3)):
          builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = text, textColor = textColor)
      else:
        builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = text, textColor = textColor)
      # builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = variable.name, textColor = textColor)
      # builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = " = ", textColor = textColor)
      # builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = variable.value, textColor = textColor)
    if variable.variablesReference != 0.VariablesReference and
        debugger.variables.contains(variable.variablesReference):
      builder.panel(&{SizeToContentY, FillX, LayoutVertical}, x = 2 * builder.charWidth):
        self.createVariables(builder, app, debugger, variable.variablesReference, backgroundColor,
          selectedBackgroundColor, textColor, output)

proc createScope*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger, scopeId: int,
    backgroundColor: Color, headerColor: Color, textColor: Color, output: var CreateVariablesOutput):
    seq[proc() {.closure.}] =

  let scope {.cursor.} = debugger.scopes.scopes[scopeId]
  builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
    let isSelected = debugger.isScopeSelected(scopeId)
    if isSelected:
      builder.panel(&{SizeToContentY, FillX, FillBackground}, backgroundColor = color(0.6, 0.5, 0.2, 0.3)):
        builder.panel(&{SizeToContentY, FillX, DrawText}, text = scope.name, textColor = textColor)
    else:
      builder.panel(&{SizeToContentY, FillX, DrawText}, text = scope.name, textColor = textColor)

    if debugger.variables.contains(scope.variablesReference):
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

  builder.panel(sizeFlags + LayoutVertical):
    builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
        backgroundColor = headerColor):
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Variables")

    builder.panel(sizeFlags + FillBackground, backgroundColor = chosenBackgroundColor):
      builder.createLines(0, 0, debugger.scopes.scopes.high, sizeToContentX, sizeToContentY,
        chosenBackgroundColor, handleScroll, handleLine)

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

  let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var backgroundColor = app.theme.color("editor.background", color(25/255, 25/255, 25/255)) * 0.85
  backgroundColor.a = 1
  var activeBackgroundColor = app.theme.color("editor.background", color(25/255, 25/255, 40/255))
  activeBackgroundColor.a = 1

  var headerColor = if self.active: app.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: app.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
  headerColor.a = 1

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

            builder.panel(sizeFlags, x = stackBounds.x, y = stackBounds.y, w = stackBounds.w,
                h = stackBounds.h):
              res.add self.createStackTrace(builder, app, debugger, backgroundColor,
                activeBackgroundColor, headerColor, textColor)

            builder.panel(sizeFlags, x = threadsBounds.x, y = threadsBounds.y, w = threadsBounds.w,
                h = threadsBounds.h):
              res.add self.createThreads(builder, app, debugger, backgroundColor,
                activeBackgroundColor, headerColor, textColor)

            builder.panel(sizeFlags, x = localsBounds.x, y = localsBounds.y, w = localsBounds.w,
                h = localsBounds.h):
              res.add self.createLocals(builder, app, debugger, backgroundColor,
                activeBackgroundColor, headerColor, textColor)

            builder.panel(sizeFlags, x = outputBounds.x, y = outputBounds.y, w = outputBounds.w,
                h = outputBounds.h):
              res.add self.createOutput(builder, app, debugger, backgroundColor,
                activeBackgroundColor, headerColor, textColor)

  res
