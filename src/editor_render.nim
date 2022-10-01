import std/[strformat, tables, algorithm, math, sugar]
import timer
import boxy, windy, fusion/matching
import util, input, events, editor, rect_utils, document_editor, text_document, ast_document, keybind_autocomplete, id, ast
import compiler, node_layout

let lineDistance = 15.0

let logRenderDuration = false

proc fillText(ctx: contexts.Context, location: Vec2, text: string, paint: Paint, font: Font = nil): Rect =
  let textWidth = ctx.measureText(text).width
  if font != nil:
    ctx.font = font.typeface.filePath
    ctx.fontSize = font.size
  ctx.fillStyle = paint
  ctx.fillText(text, location)
  return rect(location, vec2(textWidth, ctx.fontSize))

proc renderCommandAutoCompletion*(ed: Editor, handler: EventHandler, bounds: Rect): Rect =
  let ctx = ed.ctx
  let nextPossibleInputs = handler.dfa.autoComplete(handler.state).sortedByIt(it[0])

  var longestInput = 0
  var longestCommand = 0

  for kv in nextPossibleInputs:
    if kv[0].len > longestInput: longestInput = kv[0].len
    if kv[1].len > longestCommand: longestCommand = kv[1].len

  let lineSpacing: float32 = 2
  let horizontalSizeModifier: float32 = 0.615
  let gap: float32 = 10
  let height = nextPossibleInputs.len.float32 * (ctx.fontSize + lineSpacing)
  let inputsOrigin = vec2(0, 0)
  let commandsOrigin = vec2(gap + (longestInput.float32 * ctx.fontSize * horizontalSizeModifier), inputsOrigin.y.float32)

  ctx.fillStyle = rgb(200, 200, 225)

  for i, kv in nextPossibleInputs:
    let (remainingInput, action) = kv

    ctx.fillText(remainingInput, vec2(bounds.x + inputsOrigin.x, bounds.y + inputsOrigin.y + i.float * (ctx.fontSize + lineSpacing)))
    ctx.fillText(action, vec2(bounds.x + commandsOrigin.x, bounds.y + commandsOrigin.y + i.float * (ctx.fontSize + lineSpacing)))

  ctx.strokeRect(rect(inputsOrigin + vec2(bounds.x, bounds.y), vec2(bounds.w, height)))
  ctx.beginPath()
  ctx.moveTo(bounds.x + commandsOrigin.x - gap * 0.5, bounds.y)
  ctx.lineTo(bounds.x + commandsOrigin.x - gap * 0.5, bounds.y + height)
  ctx.stroke()

  return bounds.splitH(height.relative)[1]

proc renderStatusBar*(ed: Editor, bounds: Rect) =
  ed.ctx.fillStyle = if ed.commandLineMode: rgb(60, 45, 45) else: rgb(40, 25, 25)
  ed.ctx.fillRect(bounds)

  ed.ctx.fillStyle = rgb(200, 200, 225)
  ed.ctx.fillText(ed.inputBuffer, vec2(bounds.x, bounds.y))

  if ed.commandLineMode:
    ed.ctx.strokeStyle = rgb(255, 255, 255)
    let horizontalSizeModifier: float32 = 0.615
    ed.ctx.strokeRect(rect(bounds.x + ed.inputBuffer.len.float32 * ed.ctx.fontSize * horizontalSizeModifier, bounds.y, ed.ctx.fontSize * 0.05, ed.ctx.fontSize))

method renderDocumentEditor(editor: DocumentEditor, ed: Editor, bounds: Rect, selected: bool): Rect {.base, locks: "unknown".} =
  return rect(0, 0, 0, 0)

proc measureEditorBounds(editor: TextDocumentEditor, ed: Editor, bounds: Rect): Rect =
  let document = editor.document

  let headerHeight = if editor.renderHeader: ed.ctx.fontSize else: 0

  var usedBounds = rect(bounds.x, bounds.y, 0, 0)

  for i, line in document.content:
    let textWidth = ed.ctx.measureText(line).width
    usedBounds.w = max(usedBounds.w, textWidth)
    usedBounds.h += ed.ctx.fontSize

  if editor.fillAvailableSpace:
    usedBounds = bounds

  return usedBounds

method renderDocumentEditor(editor: TextDocumentEditor, ed: Editor, bounds: Rect, selected: bool): Rect =
  let document = editor.document

  let headerHeight = if editor.renderHeader: ed.ctx.fontSize else: 0

  let (headerBounds, contentBounds) = bounds.splitH headerHeight.relative

  if headerHeight > 0:
    ed.ctx.fillStyle = if selected: rgb(45, 45, 60) else: rgb(45, 45, 45)
    ed.ctx.fillRect(headerBounds)

  if headerHeight > 0:
    ed.ctx.fillStyle = rgb(255, 225, 255)
    ed.ctx.fillText(document.filename, vec2(headerBounds.x, headerBounds.y))
    ed.ctx.fillText($editor.selection, vec2(headerBounds.splitV(0.3.relative)[1].x, headerBounds.y))

  var usedBounds = rect(bounds.x, bounds.y, 0, 0)

  ed.ctx.fillStyle = rgb(225, 200, 200)
  for i, line in document.content:
    let textWidth = ed.ctx.measureText(line).width
    usedBounds.w = max(usedBounds.w, textWidth)
    usedBounds.h += ed.ctx.fontSize
    ed.ctx.fillText(line, vec2(contentBounds.x, contentBounds.y + i.float32 * ed.ctx.fontSize))

  if editor.fillAvailableSpace:
    usedBounds = bounds
  else:
    ed.ctx.strokeRect(usedBounds.grow(1.relative))

  let horizontalSizeModifier: float32 = 0.615
  ed.ctx.strokeStyle = rgb(210, 210, 210)
  ed.ctx.strokeRect(rect(contentBounds.x + editor.selection.first.column.float32 * ed.ctx.fontSize * horizontalSizeModifier, contentBounds.y + editor.selection.first.line.float32 * ed.ctx.fontSize, ed.ctx.fontSize * 0.05, ed.ctx.fontSize))
  ed.ctx.strokeStyle = rgb(255, 255, 255)
  ed.ctx.strokeRect(rect(contentBounds.x + editor.selection.last.column.float32 * ed.ctx.fontSize * horizontalSizeModifier, contentBounds.y + editor.selection.last.line.float32 * ed.ctx.fontSize, ed.ctx.fontSize * 0.05, ed.ctx.fontSize))

  return usedBounds

proc renderCompletions(editor: AstDocumentEditor, ed: Editor, bounds: Rect): Rect =
  let completions = editor.completions
  let selected = editor.selectedCompletion

  let renderedCompletions = min(completions.len, 5)

  let width = min(bounds.w, 250)

  let firstCompletion = if selected >= renderedCompletions:
    selected - renderedCompletions + 1
  else:
    0

  ed.ctx.fillStyle = rgb(25, 40, 25)
  ed.ctx.fillRect(bounds.splitH((renderedCompletions.float32 * ed.ctx.fontSize).relative)[0].splitV(width.relative)[0])
  ed.ctx.fillStyle = rgb(40, 40, 40)
  ed.ctx.fillRect(bounds.splitH(((selected - firstCompletion).float32 * ed.ctx.fontSize).relative)[1].splitH(ed.ctx.fontSize.relative)[0].splitV(width.relative)[0])
  ed.ctx.strokeStyle = rgb(255, 255, 255)
  ed.ctx.strokeRect(bounds.splitH((renderedCompletions.float32 * ed.ctx.fontSize).relative)[0].splitV(width.relative)[0])

  for i, com in completions[firstCompletion..<(firstCompletion + renderedCompletions)]:
    ed.ctx.fillStyle = rgb(255, 225, 255)
    case com.kind
    of SymbolCompletion:
      if ctx.getSymbol(com.id).getSome(symbol):
        ed.ctx.fillText(symbol.name, vec2(bounds.x, bounds.y + i.float32 * ed.ctx.fontSize))
    of AstCompletion:
      ed.ctx.fillText(com.name, vec2(bounds.x, bounds.y + i.float32 * ed.ctx.fontSize))

proc renderVisualNode(editor: AstDocumentEditor, ed: Editor, drawCtx: contexts.Context, node: VisualNode, offset: Vec2, selected: AstNode, globalBounds: Rect) =
  let bounds = node.bounds + offset

  if node.len == 0:
    if (bounds or globalBounds) != globalBounds:
      return
  else:
    if not bounds.intersects(globalBounds):
      return

  if node.text.len > 0:
    discard drawCtx.fillText(bounds.xy, node.text, node.color, node.font)
  elif node.node != nil and node.node.kind == Empty:
    drawCtx.strokeStyle = rgb(255, 100, 100)
    drawCtx.strokeRect(bounds)

  if not isNil node.render:
    node.render(bounds)

  for child in node.children:
    editor.renderVisualNode(ed, drawCtx, child, bounds.xy, selected, globalBounds)

  if node.node != nil and (editor.node.id == node.node.reff or (editor.node.reff == node.node.reff and node.node.reff != null)):
    ed.ctx.strokeStyle = rgb(175, 175, 255)
    ed.ctx.strokeRect(bounds)

  if node.node != nil and editor.node.reff == node.node.id:
    ed.ctx.strokeStyle = rgb(175, 255, 200)
    ed.ctx.strokeRect(bounds)

proc renderVisualNodeLayout(editor: AstDocumentEditor, ed: Editor, contentBounds: Rect, layout: NodeLayout, offset: var Vec2) =
  editor.lastLayouts.add (layout, offset - contentBounds.xy)

  let nodeBounds = layout.bounds
  let intersection = (nodeBounds + offset) and contentBounds
  if intersection.w < 1 or intersection.h < 1:
    return

  # drawCtx.image = newImage(nodeBounds.w.int, nodeBounds.h.int)
  # drawCtx.font = ed.ctx.font
  # drawCtx.fontSize = ed.ctx.fontSize
  # drawCtx.textBaseline = ed.ctx.textBaseline

  for line in layout.root.children:
    # ed.ctx.save()
    # ed.ctx.translate(offset)
    # defer: ed.ctx.restore()
    editor.renderVisualNode(ed, ed.ctx, line, offset, editor.node, contentBounds)

  if layout.nodeToVisualNode.contains(editor.node.id):
    let visualRange = layout.nodeToVisualNode[editor.node.id]
    let bounds = visualRange.absoluteBounds + offset

    ed.ctx.strokeStyle = rgb(255, 0, 255)
    ed.ctx.strokeRect(bounds)

  # ed.boxy.addImage($node.id, drawCtx.image)
  # ed.boxy.drawImage($node.id, offset)

method renderDocumentEditor(editor: AstDocumentEditor, ed: Editor, bounds: Rect, selected: bool): Rect =
  let document = editor.document

  let timer = startTimer()
  defer:
    if logRenderDuration:
      let queryExecutionTimes = fmt"NodeLayout: {ctx.executionTimeNodeLayout.ms:.5}, Type: {ctx.executionTimeType.ms:.2}, Value: {ctx.executionTimeValue.ms:.2}, Symbol: {ctx.executionTimeSymbol.ms:.2}, Symbols: {ctx.executionTimeSymbols.ms:.2}, SymbolType: {ctx.executionTimeSymbolType.ms:.2}, SymbolValue: {ctx.executionTimeSymbolValue.ms:.2}"
      echo fmt"Render duration: {timer.elapsed.ms:.2}ms, {queryExecutionTimes}"

    ctx.resetExecutionTimes()

  let (headerBounds, contentBounds) = bounds.splitH ed.ctx.fontSize.relative
  editor.lastBounds = rect(vec2(), contentBounds.wh)

  ed.ctx.fillStyle = if selected: rgb(45, 45, 60) else: rgb(45, 45, 45)
  ed.ctx.fillRect(headerBounds)

  ed.ctx.fillStyle = if selected: rgb(25, 25, 40) else: rgb(25, 25, 25)
  ed.ctx.fillRect(contentBounds)

  ed.ctx.fillStyle = rgb(255, 225, 255)
  ed.ctx.fillText("AST - " & document.filename, vec2(headerBounds.x, headerBounds.y))

  var lastNodeRect = contentBounds
  lastNodeRect.h = lineDistance

  let selectedNode = editor.node

  var replacements = initTable[Id, VisualNode]()

  if not isNil editor.currentlyEditedNode:
    let textEditorBounds = editor.textEditor.measureEditorBounds(ed, rect(vec2(), contentBounds.wh))
    replacements[editor.currentlyEditedNode.id] = newFunctionNode(textEditorBounds, (bounds: Rect) => (discard renderDocumentEditor(editor.textEditor, ed, bounds, true)))
  elif editor.currentlyEditedSymbol != null:
    let textEditorBounds = editor.textEditor.measureEditorBounds(ed, rect(vec2(), contentBounds.wh))
    replacements[editor.currentlyEditedSymbol] = newFunctionNode(textEditorBounds, (bounds: Rect) => (discard renderDocumentEditor(editor.textEditor, ed, bounds, true)))

  editor.previousBaseIndex = editor.previousBaseIndex.clamp(0..editor.document.rootNode.len)

  while editor.scrollOffset < 0 and editor.previousBaseIndex + 1 < editor.document.rootNode.len:
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: editor.document.rootNode[editor.previousBaseIndex], selectedNode: selectedNode.id, replacements: replacements)
    let layout = ctx.computeNodeLayout(input)
    editor.previousBaseIndex += 1
    editor.scrollOffset += layout.bounds.h + lineDistance

  while editor.scrollOffset > contentBounds.h and editor.previousBaseIndex > 0:
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: editor.document.rootNode[editor.previousBaseIndex], selectedNode: selectedNode.id, replacements: replacements)
    let layout = ctx.computeNodeLayout(input)
    editor.previousBaseIndex -= 1
    editor.scrollOffset -= layout.bounds.h + lineDistance

  editor.lastLayouts.setLen 0

  var offset = contentBounds.xy + vec2(0, editor.scrollOffset)
  for i in editor.previousBaseIndex..<editor.document.rootNode.len:
    let node = editor.document.rootNode[i]
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: node, selectedNode: selectedNode.id, replacements: replacements)
    let layout = ctx.computeNodeLayout(input)
    editor.renderVisualNodeLayout(ed, contentBounds, layout, offset)
    offset.y += layout.bounds.h + lineDistance

  offset = contentBounds.xy + vec2(0, editor.scrollOffset)
  for k in 1..editor.previousBaseIndex:
    let i = editor.previousBaseIndex - k
    let node = editor.document.rootNode[i]
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: node, selectedNode: selectedNode.id, replacements: replacements)
    let layout = ctx.computeNodeLayout(input)
    offset.y -= layout.bounds.h + lineDistance
    editor.renderVisualNodeLayout(ed, contentBounds, layout, offset)

  if editor.completions.len > 0:
    for (layout, offset) in editor.lastLayouts:
      if layout.nodeToVisualNode.contains(editor.node.id):
        let visualRange = layout.nodeToVisualNode[editor.node.id]
        let bounds = visualRange.absoluteBounds + offset + contentBounds.xy
        discard renderCompletions(editor, ed, contentBounds.splitH(bounds.yh.absolute)[1].splitV(bounds.x.absolute)[1])

      let selectedCompletion = editor.completions[editor.selectedCompletion]
      if selectedCompletion.kind == SymbolCompletion and ctx.getSymbol(selectedCompletion.id).getSome(symbol) and symbol.kind == skAstNode and layout.nodeToVisualNode.contains(symbol.node.id):
        let selectedDeclRect = layout.nodeToVisualNode[symbol.node.id]
        ed.ctx.strokeStyle = rgb(150, 150, 220)
        ed.ctx.strokeRect(selectedDeclRect.absoluteBounds + offset + contentBounds.xy)

  return bounds

method renderDocumentEditor(editor: KeybindAutocompletion, ed: Editor, bounds: Rect, selected: bool): Rect =
  let eventHandlers = ed.currentEventHandlers
  let anyInProgress = eventHandlers.anyInProgress
  var r = bounds
  for h in eventHandlers:
    if anyInProgress == (h.state != 0):
      r = ed.renderCommandAutoCompletion(h, r)

  return bounds

proc renderView*(ed: Editor, bounds: Rect, view: View, selected: bool) =
  # let bounds = bounds.shrink(0.2.relative)
  let bounds = bounds.shrink(10.relative)
  ed.ctx.fillStyle = if selected: rgb(25, 25, 40) else: rgb(25, 25, 25)
  ed.ctx.fillRect(bounds)

  discard view.editor.renderDocumentEditor(ed, bounds, selected)

proc renderMainWindow*(ed: Editor, bounds: Rect) =
  ed.ctx.fillStyle = rgb(25, 25, 25)
  ed.ctx.fillRect(bounds)

  let rects = ed.layout.layoutViews(ed.layout_props, bounds, ed.views)
  for i, view in ed.views:
    if i >= rects.len:
      break
    ed.renderView(rects[i], view, i == ed.currentView)

proc render*(ed: Editor) =
  ed.ctx.image = newImage(ed.window.size.x, ed.window.size.y)
  let lineHeight = ed.ctx.fontSize
  let windowRect = rect(vec2(), ed.window.size.vec2)

  let (mainRect, statusRect) = if not ed.statusBarOnTop: windowRect.splitH(relative(windowRect.h - lineHeight))
  else: windowRect.splitHInv(relative(lineHeight))

  ed.renderMainWindow(mainRect)
  ed.renderStatusBar(statusRect)

  ed.boxy.addImage("main", ed.ctx.image)
  ed.boxy.drawImage("main", vec2(0, 0))