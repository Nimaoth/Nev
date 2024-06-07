import std/[strformat, tables, sugar, sequtils, strutils, algorithm, math, options, json]
import vmath, bumpy, chroma
import misc/[util, custom_logger, custom_unicode, myjsonutils]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import platform/platform
import ui/[widget_builders_base, widget_library]
import app, theme, config_provider, app_interface
import text/language/debugger

import ui/node

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_debugger"

var uiUserId = newId()

proc createStackTrace*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
      backgroundColor: Color, headerColor: Color, textColor: Color):
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

  builder.panel(sizeFlags + LayoutVertical):
    builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
        backgroundColor = headerColor):

      let text = &"Stack - Thread {currentThread.id} {currentThread.name}"
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = text)

    builder.panel(sizeFlags):
      builder.createLines(0, 0, stackTrace.stackFrames.high, sizeToContentX, sizeToContentY, backgroundColor, handleScroll, handleLine)

proc createThreads*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
      backgroundColor: Color, headerColor: Color, textColor: Color):
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

  builder.panel(sizeFlags + LayoutVertical):
    builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
        backgroundColor = headerColor):
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Threads")

    builder.panel(sizeFlags):
      builder.createLines(0, 0, threads.high, sizeToContentX, sizeToContentY,
        backgroundColor, handleScroll, handleLine)

proc createLocals*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
      backgroundColor: Color, headerColor: Color, textColor: Color):
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

  builder.panel(sizeFlags + LayoutVertical):
    builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
        backgroundColor = headerColor):
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Threads")

    builder.panel(sizeFlags):
      builder.createLines(0, 0, threads.high, sizeToContentX, sizeToContentY,
        backgroundColor, handleScroll, handleLine)

proc createOutput*(self: DebuggerView, builder: UINodeBuilder, app: App, debugger: Debugger,
      backgroundColor: Color, headerColor: Color, textColor: Color):
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

  builder.panel(sizeFlags + LayoutVertical):
    builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
        backgroundColor = headerColor):
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = "Output")

    debugger.outputEditor.createUI(builder, app)

method createUI*(self: DebuggerView, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let dirty = self.dirty
  self.dirty = false

  let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var backgroundColor = if self.active: app.theme.color("editor.background", color(25/255, 25/255, 40/255)) else: app.theme.color("editor.background", color(25/255, 25/255, 25/255)) * 0.85
  backgroundColor.a = 1

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
      var header: UINode

      builder.panel(&{LayoutVertical} + sizeFlags):
        # Header
        builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
            backgroundColor = headerColor):

          let text = &"Debugger"
          builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = text)

        # Body
        builder.panel(sizeFlags + &{FillBackground}, backgroundColor = backgroundColor):
          let bounds = currentNode.bounds

          let (stackAndThreadsBounds, rest) = bounds.splitH(0.5.percent)
          let (threadsBounds, stackBounds) = stackAndThreadsBounds.splitV(0.3.percent)
          let (localsBounds, outputBounds) = rest.splitH(0.5.percent)

          if getDebugger().getSome(debugger):

            builder.panel(sizeFlags, x = stackBounds.x, y = stackBounds.y, w = stackBounds.w,
                h = stackBounds.h):
              res.add self.createStackTrace(builder, app, debugger, backgroundColor, headerColor,
                textColor)

            builder.panel(sizeFlags, x = threadsBounds.x, y = threadsBounds.y, w = threadsBounds.w,
                h = threadsBounds.h):
              res.add self.createThreads(builder, app, debugger, backgroundColor, headerColor, textColor)

            builder.panel(sizeFlags, x = localsBounds.x, y = localsBounds.y, w = localsBounds.w,
                h = localsBounds.h):
              res.add self.createLocals(builder, app, debugger, backgroundColor, headerColor, textColor)

            builder.panel(sizeFlags, x = outputBounds.x, y = outputBounds.y, w = outputBounds.w,
                h = outputBounds.h):
              res.add self.createOutput(builder, app, debugger, backgroundColor, headerColor, textColor)

  res
