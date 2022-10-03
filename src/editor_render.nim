import std/[strformat, tables, algorithm, math, sugar, strutils]
import timer
import boxy, windy, fusion/matching
import util, input, events, editor, rect_utils, document_editor, text_document, ast_document, keybind_autocomplete, id, ast
import compiler, node_layout
import lru_cache

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

  usedBounds.w = max(usedBounds.w, config.font.size * 0.5)
  usedBounds.h = max(usedBounds.h, config.font.size)

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

  let renderedCompletions = min(completions.len, 15)

  let width = min(bounds.w, 250)

  let firstCompletion = if selected >= renderedCompletions:
    selected - renderedCompletions + 1
  else:
    0

  var entries: seq[tuple[name: string, typ: string, value: string]] = @[]

  for i, com in completions[firstCompletion..completions.high]:
    case com.kind
    of SymbolCompletion:
      if ctx.getSymbol(com.id).getSome(symbol):
        let typ = ctx.computeSymbolType(symbol)
        var valueString = ""
        let value = ctx.computeSymbolValue(symbol)
        if value.kind != vkError and value.kind != vkBuiltinFunction and value.kind != vkAstFunction and value.kind != vkVoid:
          valueString = $value
        entries.add (symbol.name, $typ, valueString)

    of AstCompletion:
      entries.add (com.name, "snippet", $com.nodeKind)

    if entries.len >= renderedCompletions:
      break

  var maxNameLen = 10
  var maxTypeLen = 10
  var maxValueLen = 0
  for (name, typ, value) in entries:
    maxNameLen = max(maxNameLen, name.len)
    maxTypeLen = max(maxTypeLen, typ.len)
    maxValueLen = max(maxValueLen, value.len)

  let sepWidth = config.font.typeset("###").layoutBounds().x
  let nameWidth = config.font.typeset('#'.repeat(maxNameLen)).layoutBounds().x
  let typeWidth = config.font.typeset('#'.repeat(maxTypeLen)).layoutBounds().x
  let valueWidth = config.font.typeset('#'.repeat(maxValueLen)).layoutBounds().x
  let totalWidth = nameWidth + typeWidth + valueWidth + sepWidth * 2

  ed.ctx.fillStyle = rgb(30, 30, 30)
  ed.ctx.fillRect(rect(bounds.xy, vec2(totalWidth, renderedCompletions.float32 * config.font.size)))
  ed.ctx.strokeStyle = rgb(255, 255, 255)
  ed.ctx.strokeRect(rect(bounds.xy, vec2(totalWidth, renderedCompletions.float32 * config.font.size)))


  for i, (name, typ, value) in entries:
    if i mod 2 == 1:
      ed.ctx.fillStyle = rgb(40, 40, 40)
      ed.ctx.fillRect(rect(bounds.xy + vec2(0, i.float32 * config.font.size), vec2(totalWidth, config.font.size)))

    var lastRect = ed.ctx.fillText(vec2(bounds.x, bounds.y + i.float32 * config.font.size), name, rgb(255, 255, 255), config.font)
    lastRect = ed.ctx.fillText(vec2(lastRect.x + nameWidth, bounds.y + i.float32 * config.font.size), " : ", rgb(175, 175, 175), config.font)
    lastRect = ed.ctx.fillText(vec2(lastRect.xw, bounds.y + i.float32 * config.font.size), typ, rgb(255, 175, 175), config.font)

    if value.len > 0:
      lastRect = ed.ctx.fillText(vec2(lastRect.x + typeWidth, bounds.y + i.float32 * config.font.size), " = ", rgb(175, 175, 175), config.font)
      lastRect = ed.ctx.fillText(vec2(lastRect.xw, bounds.y + i.float32 * config.font.size), value, rgb(175, 255, 175), config.font)

  ed.ctx.strokeStyle = rgb(200, 200, 200)
  ed.ctx.strokeRect(rect(bounds.xy + vec2(0, (selected - firstCompletion).float32 * config.font.size), vec2(totalWidth, config.font.size)))

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
  if not contentBounds.intersects(nodeBounds + offset):
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

    ed.ctx.strokeStyle = rgb(255, 255, 255)
    ed.ctx.lineWidth = 2.5
    ed.ctx.strokeRect(bounds)
    ed.ctx.lineWidth = 1

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
      let selectedCompletion = editor.completions[editor.selectedCompletion]
      if selectedCompletion.kind == SymbolCompletion and ctx.getSymbol(selectedCompletion.id).getSome(symbol) and symbol.kind == skAstNode and layout.nodeToVisualNode.contains(symbol.node.id):
        let selectedDeclRect = layout.nodeToVisualNode[symbol.node.id]
        ed.ctx.strokeStyle = rgb(150, 150, 220)
        ed.ctx.strokeRect(selectedDeclRect.absoluteBounds + offset + contentBounds.xy)

    for (layout, offset) in editor.lastLayouts:
      if layout.nodeToVisualNode.contains(editor.node.id):
        let visualRange = layout.nodeToVisualNode[editor.node.id]
        let bounds = visualRange.absoluteBounds + offset + contentBounds.xy
        discard renderCompletions(editor, ed, contentBounds.splitH(bounds.yh.absolute)[1].splitV(bounds.x.absolute)[1])

  if editor.renderExecutionOutput:
    let bounds = contentBounds.splitV(relative(contentBounds.w - 500))[1]
    ed.ctx.strokeStyle = rgb(225, 225, 225)
    ed.ctx.strokeRect(bounds)

    let linesToRender = min(executionOutput.lines.len, int(bounds.h / ed.ctx.fontSize))
    let offset = min(executionOutput.lines.len - linesToRender, executionOutput.scroll)
    executionOutput.scroll = offset
    let firstIndex = linesToRender + offset
    let lastIndex = 1 + offset

    var last = rect(bounds.xy, vec2())
    for (line, color) in executionOutput.lines[^firstIndex..^lastIndex]:
      last = ed.ctx.fillText(last.xyh, line, color)

  if editor.renderDebugInfo:
    let bounds = contentBounds.splitV(relative(contentBounds.w - 400))[1]
    ed.ctx.strokeStyle = rgb(225, 225, 225)
    ed.ctx.strokeRect(bounds)

    var last = rect(bounds.xy, vec2())

    last.y += ed.ctx.fontSize
    last = ed.ctx.fillText(last.xyh,       fmt"DepGraph:", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  revision:        {ctx.depGraph.revision}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  verified:        {ctx.depGraph.verified.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  changed:         {ctx.depGraph.changed.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  fingerprints:    {ctx.depGraph.fingerprints.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  dependencies:    {ctx.depGraph.dependencies.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  query names:     {ctx.depGraph.queryNames.len}", rgb(255, 255, 255))

    last.y += ed.ctx.fontSize
    last = ed.ctx.fillText(last.xyh,       fmt"Inputs:", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  AstNodes:        {ctx.itemsAstNode.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  NodeLayoutInput: {ctx.itemsNodeLayoutInput.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"Data:", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  Symbols:         {ctx.itemsSymbol.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  FuncExecContext: {ctx.itemsFunctionExecutionContext.len}", rgb(255, 255, 255))

    last.y += ed.ctx.fontSize
    last = ed.ctx.fillText(last.xyh,       fmt"QueryCaches:", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  Type:            {ctx.queryCacheType.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  Value:           {ctx.queryCacheValue.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  SymbolType:      {ctx.queryCacheSymbolType.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  SymbolValue:     {ctx.queryCacheSymbolValue.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  Symbol:          {ctx.queryCacheSymbol.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  Symbols:         {ctx.queryCacheSymbols.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  FunctionExec:    {ctx.queryCacheFunctionExecution.len}", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  NodeLayout:      {ctx.queryCacheNodeLayout.len}", rgb(255, 255, 255))

    last.y += ed.ctx.fontSize
    last = ed.ctx.fillText(last.xyh,       fmt"Timings:", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  Rendering:       {timer.elapsed.ms:.2}ms", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  Type:            {ctx.executionTimeType.ms:.2}ms", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  Value:           {ctx.executionTimeValue.ms:.2}ms", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  Symbol:          {ctx.executionTimeSymbol.ms:.2}ms", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  Symbols:         {ctx.executionTimeSymbols.ms:.2}ms", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  SymbolType:      {ctx.executionTimeSymbolType.ms:.2}ms", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  SymbolValue:     {ctx.executionTimeSymbolValue.ms:.2}ms", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  NodeLayout:      {ctx.executionTimeNodeLayout.ms:.2}ms", rgb(255, 255, 255))
    last = ed.ctx.fillText(last.xyh,       fmt"  FunctionExec:    {ctx.executionTimeFunctionExecution.ms:.2}ms", rgb(255, 255, 255))

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