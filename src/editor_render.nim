import std/[strformat, bitops, strutils, tables, algorithm, math, macros]
import boxy, times, windy
import sugar
import input, events, editor, rect_utils, document, document_editor, text_document

let typeface = readTypeface("fonts/FiraCode-Regular.ttf")

proc renderCommandAutoCompletion*(ed: Editor, handler: EventHandler, bounds: Rect): Rect =
  let ctx = ed.ctx
  let nextPossibleInputs = handler.dfa.autoComplete(handler.state).sortedByIt(it[0])

  var longestInput = 0
  var longestCommand = 0

  for kv in nextPossibleInputs:
    if kv[0].len > longestInput: longestInput = kv[0].len
    if kv[1].len > longestCommand: longestCommand = kv[1].len

  let lineSpacing: float32 = 2
  let horizontalSizeModifier: float32 = 0.65
  let gap: float32 = 10
  let commandsOrigin = vec2(bounds.w - (longestCommand.float32 * ctx.fontSize * horizontalSizeModifier), bounds.h - (nextPossibleInputs.len.float32 * (ctx.fontSize + lineSpacing)))
  let inputsOrigin = vec2(commandsOrigin.x.float32 - gap - (longestInput.float32 * ctx.fontSize * horizontalSizeModifier), commandsOrigin.y.float32)

  ctx.fillStyle = rgb(75, 75, 75)

  for i, kv in nextPossibleInputs:
    let (remainingInput, action) = kv

    ctx.fillText(remainingInput, vec2(bounds.x + inputsOrigin.x, bounds.y + inputsOrigin.y + i.float * (ctx.fontSize + lineSpacing)))
    ctx.fillText(action, vec2(bounds.x + commandsOrigin.x, bounds.y + commandsOrigin.y + i.float * (ctx.fontSize + lineSpacing)))

  ctx.strokeRect(rect(inputsOrigin + vec2(bounds.x, bounds.y), vec2(bounds.w - inputsOrigin.x, bounds.h - inputsOrigin.y)))
  ctx.beginPath()
  ctx.moveTo(bounds.x + commandsOrigin.x - gap * 0.5, bounds.y + commandsOrigin.y)
  ctx.lineTo(bounds.x + commandsOrigin.x - gap * 0.5, bounds.y + bounds.h)
  ctx.stroke()

  return bounds.splitH(inputsOrigin.y.absolute)[0]

proc renderStatusBar*(ed: Editor, bounds: Rect) =
  ed.ctx.fillStyle = rgb(255, 0, 0)
  ed.ctx.fillRect(bounds)

  ed.ctx.fillStyle = rgb(75, 75, 75)
  ed.ctx.fillText(ed.inputBuffer, vec2(bounds.x, bounds.y))

method renderDocumentEditor(editor: DocumentEditor, ed: Editor, bounds: Rect, selected: bool) {.base.} =
  discard

method renderDocumentEditor(editor: TextDocumentEditor, ed: Editor, bounds: Rect, selected: bool) =
  let document = editor.document

  let (headerBounds, contentBounds) = bounds.splitH ed.ctx.fontSize.absolute

  ed.ctx.fillStyle = if selected: rgb(100, 200, 100) else: rgb(75, 150, 75)
  ed.ctx.fillRect(headerBounds)

  ed.ctx.fillStyle = if selected: rgb(75, 175, 75) else: rgb(50, 150, 50)
  ed.ctx.fillRect(contentBounds)

  ed.ctx.fillStyle = rgb(0, 0, 0)
  ed.ctx.fillText(document.filename, vec2(headerBounds.x, headerBounds.y))

  ed.ctx.fillStyle = rgb(0, 0, 0)
  ed.ctx.fillText($editor.selection, vec2(headerBounds.splitV(0.3.relative)[1].x, headerBounds.y))

  for i, line in document.content:
    ed.ctx.fillText(line, vec2(contentBounds.x, contentBounds.y + i.float32 * ed.ctx.fontSize))

  let horizontalSizeModifier: float32 = 0.615
  ed.ctx.strokeStyle = rgb(175, 175, 175)
  ed.ctx.strokeRect(rect(contentBounds.x + editor.selection.first.column.float32 * ed.ctx.fontSize * horizontalSizeModifier, contentBounds.y + editor.selection.first.line.float32 * ed.ctx.fontSize, ed.ctx.fontSize * 0.05, ed.ctx.fontSize))
  ed.ctx.strokeStyle = rgb(255, 255, 255)
  ed.ctx.strokeRect(rect(contentBounds.x + editor.selection.last.column.float32 * ed.ctx.fontSize * horizontalSizeModifier, contentBounds.y + editor.selection.last.line.float32 * ed.ctx.fontSize, ed.ctx.fontSize * 0.05, ed.ctx.fontSize))

method renderDocumentEditor(editor: AstDocumentEditor, ed: Editor, bounds: Rect, selected: bool) =
  discard

proc renderView*(ed: Editor, bounds: Rect, view: View, selected: bool) =
  # let bounds = bounds.shrink(0.2.relative)
  let bounds = bounds.shrink(10.absolute)
  ed.ctx.fillStyle = if selected: rgb(100, 200, 100) else: rgb(75, 150, 75)
  ed.ctx.fillRect(bounds)

  view.editor.renderDocumentEditor(ed, bounds, selected)

proc renderMainWindow*(ed: Editor, bounds: Rect) =
  ed.ctx.fillStyle = rgb(0, 255, 0)
  ed.ctx.fillRect(bounds)

  let rects = ed.layout.layoutViews(bounds, ed.views)
  for i, view in ed.views:
    if i >= rects.len:
      break
    ed.renderView(rects[i], view, i == ed.currentView)

  let eventHandlers = ed.currentEventHandlers
  let anyInProgress = eventHandlers.anyInProgress
  var r = bounds
  for h in eventHandlers:
    if anyInProgress == (h.state != 0):
      r = ed.renderCommandAutoCompletion(h, r)

proc render*(ed: Editor) =
  ed.ctx.image = newImage(ed.window.size.x, ed.window.size.y)
  let lineHeight = ed.ctx.fontSize
  let windowRect = rect(vec2(), ed.window.size.vec2)

  let (mainRect, statusRect) = if not ed.statusBarOnTop: windowRect.splitH(absolute(windowRect.h - lineHeight))
  else: windowRect.splitHInv(absolute(lineHeight))

  ed.renderMainWindow(mainRect)
  ed.renderStatusBar(statusRect)

  ed.boxy.addImage("main", ed.ctx.image)
  ed.boxy.drawImage("main", vec2(0, 0))