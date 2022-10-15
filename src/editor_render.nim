import std/[strformat, tables, algorithm, math, sugar, strutils]
import timer
import boxy, windy, pixie/fonts, fusion/matching
import util, input, events, editor, popup, rect_utils, document_editor, text_document, ast_document, keybind_autocomplete, id, ast, theme
import compiler, node_layout, goto_popup, selector_popup
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

proc fillTextRight(ctx: contexts.Context, location: Vec2, text: string, paint: Paint, font: Font = nil): Rect =
  let textWidth = ctx.measureText(text).width
  if font != nil:
    ctx.font = font.typeface.filePath
    ctx.fontSize = font.size
  ctx.fillStyle = paint
  ctx.fillText(text, location - vec2(textWidth, 0))
  return rect(location - vec2(textWidth, 0), vec2(textWidth, ctx.fontSize))

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
  ed.ctx.fillStyle = if ed.commandLineMode: ed.theme.color("statusBar.background", rgb(60, 45, 45)) else: ed.theme.color("statusBarItem.activeBackground", rgb(40, 25, 25))
  ed.ctx.fillRect(bounds)

  ed.ctx.fillStyle = ed.theme.color("statusBar.foreground", rgb(200, 200, 225))
  ed.ctx.fillText(ed.inputBuffer, vec2(bounds.x, bounds.y))

  if ed.commandLineMode:
    ed.ctx.strokeStyle = ed.theme.color("statusBar.foreground", rgb(255, 255, 255))
    let horizontalSizeModifier: float32 = 0.615
    ed.ctx.strokeRect(rect(bounds.x + ed.inputBuffer.len.float32 * ed.ctx.fontSize * horizontalSizeModifier, bounds.y, ed.ctx.fontSize * 0.05, ed.ctx.fontSize))

method renderDocumentEditor(editor: DocumentEditor, ed: Editor, bounds: Rect, selected: bool): Rect {.base, locks: "unknown".} =
  return rect(0, 0, 0, 0)

proc measureEditorBounds(editor: TextDocumentEditor, ed: Editor, bounds: Rect): Rect =
  let document = editor.document

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
    ed.ctx.fillStyle = if selected: ed.theme.color("tab.activeBackground", rgb(45, 45, 60)) else: ed.theme.color("tab.inactiveBackground", rgb(45, 45, 45))
    ed.ctx.fillRect(headerBounds)

    ed.ctx.fillStyle = if selected: ed.theme.color("tab.activeForeground", rgb(255, 225, 255)) else: ed.theme.color("tab.inactiveForeground", rgb(255, 225, 255))
    ed.ctx.fillText(document.filename, vec2(headerBounds.x, headerBounds.y))
    ed.ctx.fillText($editor.selection, vec2(headerBounds.splitV(0.3.relative)[1].x, headerBounds.y))

  var usedBounds = rect(bounds.x, bounds.y, 0, 0)

  ed.ctx.fillStyle = ed.theme.color("editor.foreground", rgb(225, 200, 200))
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
  ed.ctx.strokeStyle = ed.theme.color("editorCursor.foreground", rgb(210, 210, 210))
  ed.ctx.strokeRect(rect(contentBounds.x + editor.selection.first.column.float32 * ed.ctx.fontSize * horizontalSizeModifier, contentBounds.y + editor.selection.first.line.float32 * ed.ctx.fontSize, ed.ctx.fontSize * 0.05, ed.ctx.fontSize))
  ed.ctx.strokeStyle = ed.theme.color("editorCursor.foreground", rgb(255, 255, 255))
  ed.ctx.strokeRect(rect(contentBounds.x + editor.selection.last.column.float32 * ed.ctx.fontSize * horizontalSizeModifier, contentBounds.y + editor.selection.last.line.float32 * ed.ctx.fontSize, ed.ctx.fontSize * 0.05, ed.ctx.fontSize))

  return usedBounds

proc renderCompletions(ed: Editor, completions: seq[Completion], selected: int, bounds: Rect, fill: bool) =
  if completions.len == 0:
    return

  let maxRenderedCompletions = if fill:
    int(bounds.h / ed.ctx.fontSize)
  else: 15

  let renderedCompletions = min(completions.len, maxRenderedCompletions)

  let firstCompletion = if selected >= renderedCompletions:
    selected - renderedCompletions + 1
  else:
    0

  var entries: seq[tuple[name: string, typ: string, value: string, color1: seq[string], color2: string, color3: string]] = @[]

  for i, com in completions[firstCompletion..completions.high]:
    case com.kind
    of SymbolCompletion:
      if ctx.getSymbol(com.id).getSome(sym):
        let typ = ctx.computeSymbolType(sym)
        var valueString = ""
        let value = ctx.computeSymbolValue(sym)
        if value.kind != vkError and value.kind != vkBuiltinFunction and value.kind != vkAstFunction and value.kind != vkVoid:
          valueString = $value
        entries.add (sym.name, $typ, valueString, ctx.getColorForSymbol(sym), "storage.type", "string")

    of AstCompletion:
      entries.add (com.name, "snippet", $com.nodeKind, @["entity.name.label", "entity.name"], "storage", "string")

    if entries.len >= renderedCompletions:
      break

  var maxNameLen = 10
  var maxTypeLen = 10
  var maxValueLen = 0
  for (name, typ, value, color1, color2, color3) in entries:
    maxNameLen = max(maxNameLen, name.len)
    maxTypeLen = max(maxTypeLen, typ.len)
    maxValueLen = max(maxValueLen, value.len)

  let sepWidth = config.font.typeset("###").layoutBounds().x
  let nameWidth = config.font.typeset('#'.repeat(maxNameLen)).layoutBounds().x
  let typeWidth = config.font.typeset('#'.repeat(maxTypeLen)).layoutBounds().x
  let valueWidth = config.font.typeset('#'.repeat(maxValueLen)).layoutBounds().x
  var totalWidth = nameWidth + typeWidth + valueWidth + sepWidth * 2
  if fill and totalWidth < bounds.w:
    totalWidth = bounds.w

  ed.ctx.fillStyle = ed.theme.color("panel.background", rgb(30, 30, 30))
  ed.ctx.fillRect(rect(bounds.xy, vec2(totalWidth, renderedCompletions.float32 * config.font.size)))
  ed.ctx.strokeStyle = ed.theme.color("panel.border", rgb(255, 255, 255))
  ed.ctx.strokeRect(rect(bounds.xy, vec2(totalWidth, renderedCompletions.float32 * config.font.size)))

  for i, (name, typ, value, color1, color2, color3) in entries:
    # if i == (selected - firstCompletion):
    #   ed.ctx.fillStyle = ed.theme.color("list.activeSelectionBackground", rgb(40, 40, 40))
    #   ed.ctx.fillRect(rect(bounds.xy + vec2(0, i.float32 * config.font.size), vec2(totalWidth, config.font.size)))
    # elif i mod 2 == 1:
    #   ed.ctx.fillStyle = ed.theme.color("list.inactiveSelectionBackground", rgb(40, 40, 40))
    #   ed.ctx.fillRect(rect(bounds.xy + vec2(0, i.float32 * config.font.size), vec2(totalWidth, config.font.size)))

    var lastRect = ed.ctx.fillText(vec2(bounds.x, bounds.y + i.float32 * config.font.size), name, ed.theme.tokenColor(color1, rgb(255, 255, 255)), config.font)
    lastRect = ed.ctx.fillText(vec2(lastRect.x + nameWidth, bounds.y + i.float32 * config.font.size), " : ", ed.theme.color("list.inactiveSelectionForeground", rgb(175, 175, 175)), config.font)
    lastRect = ed.ctx.fillText(vec2(lastRect.xw, bounds.y + i.float32 * config.font.size), typ, ed.theme.tokenColor(color2, rgb(255, 175, 175)), config.font)

    if value.len > 0:
      lastRect = ed.ctx.fillText(vec2(lastRect.x + typeWidth, bounds.y + i.float32 * config.font.size), " = ", ed.theme.color("list.inactiveSelectionForeground", rgb(175, 175, 175)), config.font)
      lastRect = ed.ctx.fillText(vec2(lastRect.xw, bounds.y + i.float32 * config.font.size), value, ed.theme.tokenColor(color3, rgb(175, 255, 175)), config.font)

  ed.ctx.strokeStyle = rgb(200, 200, 200)
  ed.ctx.strokeRect(rect(bounds.xy + vec2(0, (selected - firstCompletion).float32 * config.font.size), vec2(totalWidth, config.font.size)))

method computeBounds(item: SelectorItem, ed: Editor): Rect =
  discard

method computeBounds(item: ThemeSelectorItem, ed: Editor): Rect =
  let nameWidth = ed.ctx.measureText(item.name).width
  return rect(vec2(), vec2(nameWidth, ed.ctx.fontSize))

method renderItem(item: SelectorItem, ed: Editor, bounds: Rect) =
  discard

method renderItem(item: ThemeSelectorItem, ed: Editor, bounds: Rect) =
  let color = ed.theme.color(@["list.activeSelectionForeground", "editor.foreground"], rgb(255, 255, 255))
  discard ed.ctx.fillText(bounds.xy, item.name, color, config.font)

proc renderItems(ed: Editor, completions: seq[SelectorItem], selected: int, bounds: Rect, fill: bool) =
  if completions.len == 0:
    return

  let maxRenderedCompletions = if fill:
    int(bounds.h / ed.ctx.fontSize)
  else: 15

  let renderedCompletions = min(completions.len, maxRenderedCompletions)

  let firstCompletion = if selected >= renderedCompletions:
    selected - renderedCompletions + 1
  else:
    0

  var entries: seq[Rect] = @[]

  var maxWidth: float32 = 0
  var totalHeight: float32 = 0
  for i, com in completions[firstCompletion..completions.high]:
    let rect = com.computeBounds(ed)
    entries.add(rect + bounds.xy + vec2(0, totalHeight))
    maxWidth = max(maxWidth, rect.w)
    totalHeight += rect.h

    if entries.len >= renderedCompletions:
      break

  var totalWidth = maxWidth
  if fill and totalWidth < bounds.w:
    totalWidth = bounds.w

  ed.ctx.fillStyle = ed.theme.color("panel.background", rgb(30, 30, 30))
  ed.ctx.fillRect(rect(bounds.xy, vec2(totalWidth, totalHeight)))
  ed.ctx.strokeStyle = ed.theme.color("panel.border", rgb(255, 255, 255))
  ed.ctx.strokeRect(rect(bounds.xy, vec2(totalWidth, totalHeight)))

  for i, rect in entries:
    let com = completions[firstCompletion + i]
    com.renderItem(ed, rect)

  ed.ctx.strokeStyle = rgb(200, 200, 200)
  ed.ctx.strokeRect(rect(entries[selected - firstCompletion].xy, vec2(totalWidth, entries[selected - firstCompletion].h)))

proc renderVisualNode(editor: AstDocumentEditor, ed: Editor, drawCtx: contexts.Context, node: VisualNode, offset: Vec2, selected: AstNode, globalBounds: Rect) =
  let bounds = node.bounds + offset

  if node.len == 0:
    if (bounds or globalBounds) != globalBounds:
      return
  else:
    if not bounds.intersects(globalBounds):
      return

  if node.text.len > 0:
    let color = ed.theme.anyColor(node.colors, rgb(255, 255, 255))
    let style = ed.theme.tokenFontStyle(node.colors)
    ed.ctx.font = config.getFont(style)
    discard drawCtx.fillText(bounds.xy, node.text, color)
    ed.ctx.font = config.getFont({})
  elif node.node != nil and node.node.kind == Empty:
    drawCtx.strokeStyle = ed.theme.color("editorError.foreground", rgb(255, 100, 100))
    drawCtx.strokeRect(bounds)

  # if node.node == selected:
    # drawCtx.fillStyle = ed.theme.color("editorError.background", rgb(0, 0, 0))
    # drawCtx.fillRect(rect(bounds.xyh, vec2(200, 200)))
    # discard drawCtx.fillText(bounds.xyh, $node.colors, ed.theme.color("editorError.foreground", rgb(255, 100, 100)), node.font)

  # Render custom stuff
  if not isNil node.render:
    node.render(bounds)

  for child in node.children:
    editor.renderVisualNode(ed, drawCtx, child, bounds.xy, selected, globalBounds)

  # Draw outline around node if it refers to the selected node or the same thing the selected node refers to
  if node.node != nil and (editor.node.id == node.node.reff or (editor.node.reff == node.node.reff and node.node.reff != null)):
    ed.ctx.strokeStyle = ed.theme.color("inputValidation.infoBorder", rgb(175, 175, 255))
    ed.ctx.strokeRect(bounds)

  # Draw outline around node it is being refered to by the selected node
  if node.node != nil and editor.node.reff == node.node.id:
    ed.ctx.strokeStyle = ed.theme.color("inputValidation.warningBorder", rgb(175, 255, 200))
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

  # Render outline for selected node
  if layout.nodeToVisualNode.contains(editor.node.id):
    let visualRange = layout.nodeToVisualNode[editor.node.id]
    let bounds = visualRange.absoluteBounds + offset

    ed.ctx.strokeStyle = ed.theme.color("foreground", rgb(255, 255, 255))
    ed.ctx.lineWidth = 2.5
    ed.ctx.strokeRect(bounds)
    ed.ctx.lineWidth = 1

  # Draw diagnostics
  for (id, visualRange) in layout.nodeToVisualNode.pairs:
    if ctx.diagnosticsPerNode.contains(id):
      var foundErrors = false
      let bounds = visualRange.absoluteBounds + offset
      var last = rect(bounds.xy, vec2())
      for diagnostics in ctx.diagnosticsPerNode[id].queries.values:
        for diagnostic in diagnostics:
          last = ed.ctx.fillTextRight(vec2(contentBounds.xw, last.yh), diagnostic.message, ed.theme.color("editorError.foreground", rgb(255, 0, 0)), config.font)
          foundErrors = true
      if foundErrors:
        ed.ctx.strokeStyle = ed.theme.color("editorError.foreground", rgb(255, 0, 0))
        ed.ctx.strokeRect(bounds.grow(3.relative))

  # ed.boxy.addImage($node.id, drawCtx.image)
  # ed.boxy.drawImage($node.id, offset)

method renderDocumentEditor(editor: AstDocumentEditor, ed: Editor, bounds: Rect, selected: bool): Rect =
  let document = editor.document
  let theme = ed.theme

  let timer = startTimer()
  defer:
    if logRenderDuration:
      let queryExecutionTimes = fmt"NodeLayout: {ctx.executionTimeNodeLayout.ms:.5}, Type: {ctx.executionTimeType.ms:.2}, Value: {ctx.executionTimeValue.ms:.2}, Symbol: {ctx.executionTimeSymbol.ms:.2}, Symbols: {ctx.executionTimeSymbols.ms:.2}, SymbolType: {ctx.executionTimeSymbolType.ms:.2}, SymbolValue: {ctx.executionTimeSymbolValue.ms:.2}"
      echo fmt"Render duration: {timer.elapsed.ms:.2}ms, {queryExecutionTimes}"

    ctx.resetExecutionTimes()

  let (headerBounds, contentBounds) = bounds.splitH ed.ctx.fontSize.relative
  editor.lastBounds = rect(vec2(), contentBounds.wh)

  ed.ctx.fillStyle = if selected: theme.color("tab.activeBackground", rgb(45, 45, 60)) else: theme.color("tab.inactiveBackground", rgb(45, 45, 45))
  ed.ctx.fillRect(headerBounds)

  ed.ctx.fillStyle = if selected: theme.color("editor.background", rgb(25, 25, 40)) else: theme.color("editor.background", rgb(25, 25, 25))
  ed.ctx.fillRect(contentBounds)

  ed.ctx.fillStyle = if selected: theme.color("tab.activeForeground", rgb(255, 225, 255)) else: theme.color("tab.inactiveForeground", rgb(255, 225, 255))
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
    # Render outline around all nodes which reference the selected symbol in the completion list
    for (layout, offset) in editor.lastLayouts:
      let selectedCompletion = editor.completions[editor.selectedCompletion]
      if selectedCompletion.kind == SymbolCompletion and ctx.getSymbol(selectedCompletion.id).getSome(symbol) and symbol.kind == skAstNode and layout.nodeToVisualNode.contains(symbol.node.id):
        let selectedDeclRect = layout.nodeToVisualNode[symbol.node.id]
        ed.ctx.strokeStyle = ed.theme.color("editor.findMatchBorder", rgb(150, 150, 220))
        ed.ctx.strokeRect(selectedDeclRect.absoluteBounds + offset + contentBounds.xy)

    # Render completion window under the currently edited node
    for (layout, offset) in editor.lastLayouts:
      if layout.nodeToVisualNode.contains(editor.node.id):
        let visualRange = layout.nodeToVisualNode[editor.node.id]
        let bounds = visualRange.absoluteBounds + offset + contentBounds.xy
        ed.renderCompletions(editor.completions, editor.selectedCompletion, contentBounds.splitH(bounds.yh.absolute)[1].splitV(bounds.x.absolute)[1], false)

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
  ed.ctx.fillStyle = if selected: ed.theme.color("editorPane.background", rgb(25, 25, 40)) else: ed.theme.color("editorPane.background", rgb(25, 25, 25))
  ed.ctx.fillRect(bounds)

  discard view.editor.renderDocumentEditor(ed, bounds, selected)

method renderPopup*(popup: Popup, ed: Editor, bounds: Rect) {.base, locks: "unknown".} =
  discard

method renderPopup*(popup: AstGotoDefinitionPopup, ed: Editor, bounds: Rect) =
  let bounds = bounds.shrink(0.15.percent)
  let (textBounds, contentBounds) = bounds.splitH(ed.ctx.fontSize.relative)
  ed.ctx.fillStyle = ed.theme.color("panel.background", rgb(25, 25, 25))
  ed.ctx.fillRect(textBounds)
  discard popup.textEditor.renderDocumentEditor(ed, textBounds, true)
  ed.renderCompletions(popup.completions, popup.selected, contentBounds, true)

method renderPopup*(popup: SelectorPopup, ed: Editor, bounds: Rect) =
  let bounds = bounds.shrink(0.15.percent)
  let (textBounds, contentBounds) = bounds.splitH(ed.ctx.fontSize.relative)
  ed.ctx.fillStyle = ed.theme.color("panel.background", rgb(25, 25, 25))
  ed.ctx.fillRect(textBounds)
  discard popup.textEditor.renderDocumentEditor(ed, textBounds, true)
  ed.renderItems(popup.completions, popup.selected, contentBounds, true)


proc renderMainWindow*(ed: Editor, bounds: Rect) =
  ed.ctx.fillStyle = ed.theme.color("editorPane.background", rgb(25, 25, 25))
  ed.ctx.fillRect(bounds)

  let rects = ed.layout.layoutViews(ed.layout_props, bounds, ed.views)
  for i, view in ed.views:
    if i >= rects.len:
      break
    ed.renderView(rects[i], view, i == ed.currentView)

  for i, popup in ed.popups:
    popup.renderPopup(ed, bounds)

proc render*(ed: Editor) =
  ed.ctx.image = newImage(ed.window.size.x, ed.window.size.y)
  let lineHeight = ed.ctx.fontSize
  let windowRect = rect(vec2(), ed.window.size.vec2)

  config.fontRegular = ed.fontRegular
  config.fontBold = ed.fontBold
  config.fontItalic = ed.fontItalic
  config.fontBoldItalic = ed.fontBoldItalic

  ed.ctx.font = config.fontRegular
  if config.font.typeface.filePath != ed.ctx.font:
    config.font = newFont(readTypeface(ed.ctx.font))
    config.font.size = ed.ctx.fontSize
  elif config.font.size != ed.ctx.fontSize:
    config.font.size = ed.ctx.fontSize

  let (mainRect, statusRect) = if not ed.statusBarOnTop: windowRect.splitH(relative(windowRect.h - lineHeight))
  else: windowRect.splitHInv(relative(lineHeight))

  ed.renderMainWindow(mainRect)
  ed.renderStatusBar(statusRect)

  ed.boxy.addImage("main", ed.ctx.image)
  ed.boxy.drawImage("main", vec2(0, 0))