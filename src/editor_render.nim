import std/[strformat, tables, algorithm, math, sugar, strutils, options, sequtils]
import timer
import boxy, windy, pixie/fonts, chroma, fusion/matching
import util, input, events, editor, popup, rect_utils, document_editor, text_document, ast_document, keybind_autocomplete, id, ast, theme, text_renderer
import compiler, query_system, node_layout, goto_popup, selector_popup, language_server_base
import lru_cache
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, Popup, SelectorPopup

let lineDistance = 15.0

let logRenderDuration = false

func withAlpha(color: Color, alpha: float32): Color = color(color.r, color.g, color.b, alpha)

proc drawText(renderContext: RenderContext, location: Vec2, text: string, color: Color, pivot: Vec2 = vec2(0, 0), font: Option[string] = string.none, fontSize: Option[float32] = float32.none, key: string = ""): Rect =
  let image = ctx.computeRenderedText(ctx.getOrCreateRenderTextInput(newRenderTextInput(
    renderContext,
    text,
    font.get(renderContext.ctx.font),
    fontSize.get(renderContext.ctx.fontSize), renderContext.lineHeight, renderContext.charWidth,
    key)))
  let size = renderContext.boxy.getImageSize(image).vec2
  let actualLocation = location - size * pivot
  renderContext.boxy.drawImage(image, actualLocation, color)
  return rect(actualLocation, size)

proc layoutText(renderContext: RenderContext, location: Vec2, text: string, bounds: Vec2 = vec2(0, 0), pivot: Vec2 = vec2(0, 0), font: Option[string] = string.none, fontSize: Option[float32] = float32.none, key: string = ""): tuple[image: string, bounds: Rect] =
  let image = ctx.computeRenderedText(ctx.getOrCreateRenderTextInput(newRenderTextInput(
    renderContext,
    text,
    font.get(renderContext.ctx.font),
    fontSize.get(renderContext.ctx.fontSize), renderContext.lineHeight, renderContext.charWidth,
    key,
    bounds)))
  let size = renderContext.boxy.getImageSize(image).vec2
  let actualLocation = location - size * pivot
  return (image, rect(actualLocation, size))

proc fillRect*(boxy: Boxy, rect: Rect, color: Color) = boxy.drawRect(rect, color)

proc strokeRect*(boxy: Boxy, rect: Rect, color: Color, thickness: float = 1) =
  let rect = rect.grow(vec2(thickness, thickness))
  boxy.fillRect(rect.splitV(thickness.relative)[0].shrink(vec2(0, thickness)), color)
  boxy.fillRect(rect.splitVInv(thickness.relative)[1].shrink(vec2(0, thickness)), color)
  boxy.fillRect(rect.splitH(thickness.relative)[0], color)
  boxy.fillRect(rect.splitHInv(thickness.relative)[1], color)

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

  for i, kv in nextPossibleInputs:
    let (remainingInput, action) = kv

    discard ed.renderCtx.drawText(vec2(bounds.x + inputsOrigin.x, bounds.y + inputsOrigin.y + i.float * (ctx.fontSize + lineSpacing)), remainingInput, rgb(200, 200, 225).color)
    discard ed.renderCtx.drawText(vec2(bounds.x + commandsOrigin.x, bounds.y + commandsOrigin.y + i.float * (ctx.fontSize + lineSpacing)), action, rgb(200, 200, 225).color)

  ed.boxy.strokeRect(rect(inputsOrigin + vec2(bounds.x, bounds.y), vec2(bounds.w, height)), rgb(200, 200, 225).color)
  ed.boxy.strokeRect(rect(bounds.x + commandsOrigin.x - gap * 0.5, bounds.y, bounds.x + commandsOrigin.x - gap * 0.5 + 1, bounds.y + height), rgb(200, 200, 225).color)

  return bounds.splitH(height.relative)[1]

method renderDocumentEditor(editor: DocumentEditor, ed: Editor, bounds: Rect, selected: bool): Rect {.base.} =
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

proc clampToLine(selection: Selection, line: int, lineLength: int): tuple[first: int, last: int] =
  result.first = if selection.first.line < line: 0 elif selection.first.line == line: selection.first.column else: lineLength
  result.last = if selection.last.line < line: 0 elif selection.last.line == line: selection.last.column else: lineLength

proc renderTextHighlight(ed: Editor, bounds: Rect, line: int, startIndex: int, selection: Selection, selectionClamped: tuple[first: int, last: int], part: StyledText, color: Color, lineDistance: float32) =
  ## Fills a selection rect in the given color

  if (startIndex < selectionClamped.last and startIndex + part.text.len > selectionClamped.first and part.text.len > 0):
    let startOffset = max(0, selectionClamped.first - startIndex).float32 / (part.text.len.float32 - 0) * bounds.w
    let endOffset = min(part.text.len, selectionClamped.last - startIndex).float32 / (part.text.len.float32 - 0) * bounds.w
    let highlightRect = rect(bounds.xy - vec2(0, lineDistance * 0.5) + vec2(startOffset, 0), vec2(endOffset - startOffset, bounds.h - textExtraHeight + lineDistance))
    ed.boxy.fillRect(highlightRect, color)
  elif part.text.len == 0 and selection.contains((line, startIndex)) and not selection.isEmpty:
    let highlightRect = rect(bounds.xy - vec2(0, lineDistance * 0.5), vec2(ed.renderCtx.charWidth * 0.5, bounds.h - textExtraHeight + lineDistance))
    ed.boxy.fillRect(highlightRect, color)

proc renderTextHighlight(ed: Editor, bounds: Rect, line: int, startIndex: int, selections: openArray[Selection], selectionClamped: openArray[tuple[first: int, last: int]], part: StyledText, color: Color, lineDistance: float32) =
  ## Fills selections rect in the given color
  for i in 0..<selections.len:
    ed.renderTextHighlight(bounds, line, startIndex, selections[i], selectionClamped[i], part, color, lineDistance)

proc renderTextCompletions(ed: Editor, completions: seq[TextCompletion], selected: int, bounds: Rect, contentBounds: Rect, fill: bool, renderedItems: var seq[tuple[index: int, bounds: Rect]]): Rect =
  result = bounds.xyRect
  renderedItems.setLen 0

  let padding = 3.0

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
    entries.add (com.name, com.typ, com.scope, @["entity.name.label", "entity.name"], "storage", "string")

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
  var totalWidth = nameWidth + typeWidth + valueWidth + sepWidth * 2 + padding
  if fill and totalWidth < bounds.w:
    totalWidth = bounds.w

  result = rect(bounds.xy, vec2(totalWidth, renderedCompletions.float32 * config.font.size))
  ed.boxy.fillRect(result, ed.theme.color("panel.background", rgb(30, 30, 30)))
  ed.boxy.strokeRect(result, ed.theme.color("panel.border", rgb(255, 255, 255)))

  let selectionColor = ed.theme.color("list.activeSelectionBackground", rgb(200, 200, 200))
  ed.boxy.fillRect(rect(bounds.xy + vec2(0, (selected - firstCompletion).float32 * config.font.size), vec2(totalWidth, config.font.size)), selectionColor)

  for i, (name, typ, value, color1, color2, color3) in entries:
    # if i == (selected - firstCompletion):
    #   ed.boxy.fillRect(rect(bounds.xy + vec2(0, i.float32 * config.font.size), vec2(totalWidth, config.font.size)), ed.theme.color("list.activeSelectionBackground", rgb(40, 40, 40)))
    # elif i mod 2 == 1:
    #   ed.boxy.fillRect(rect(bounds.xy + vec2(0, i.float32 * config.font.size), vec2(totalWidth, config.font.size)), ed.theme.color("list.inactiveSelectionBackground", rgb(40, 40, 40)))

    var totalBounds = ed.renderCtx.drawText(vec2(bounds.x, bounds.y + i.float32 * config.font.size), name, ed.theme.tokenColor(color1, rgb(255, 255, 255)))
    var lastRect = totalBounds
    lastRect = ed.renderCtx.drawText(vec2(lastRect.x + nameWidth, bounds.y + i.float32 * config.font.size), " : ", ed.theme.color("list.inactiveSelectionForeground", rgb(175, 175, 175)))
    totalBounds = totalBounds or lastRect
    lastRect = ed.renderCtx.drawText(vec2(lastRect.xw, bounds.y + i.float32 * config.font.size), typ, ed.theme.tokenColor(color2, rgb(255, 175, 175)))
    totalBounds = totalBounds or lastRect

    if value.len > 0:
      lastRect = ed.renderCtx.drawText(vec2(lastRect.x + typeWidth, bounds.y + i.float32 * config.font.size), " = ", ed.theme.color("list.inactiveSelectionForeground", rgb(175, 175, 175)))
      totalBounds = totalBounds or lastRect
      lastRect = ed.renderCtx.drawText(vec2(lastRect.xw, bounds.y + i.float32 * config.font.size), value, ed.theme.tokenColor(color3, rgb(175, 255, 175)))
      totalBounds = totalBounds or lastRect

    renderedItems.add (firstCompletion + i, totalBounds)

  if completions[selected].doc.len > 0:
    let maxBounds = contentBounds.xwyh - (bounds.xy + vec2(totalWidth, 0))
    let (image, docBounds) = ed.renderCtx.layoutText(bounds.xy + vec2(totalWidth + 3, 3), completions[selected].doc, bounds = maxBounds - vec2(padding) * 2)
    ed.boxy.fillRect(docBounds.grow(padding.absolute), ed.theme.color("editor.foreground", rgb(255, 255, 255)))
    ed.renderCtx.boxy.drawImage(image, docBounds.xy, ed.theme.color("panel.background", rgb(30, 30, 30)))

method renderDocumentEditor(editor: TextDocumentEditor, ed: Editor, bounds: Rect, selected: bool): Rect =
  let document = editor.document

  let headerHeight = if editor.renderHeader: ed.renderCtx.lineHeight else: 0

  let (headerBounds, contentBounds) = bounds.splitH headerHeight.relative
  editor.lastContentBounds = contentBounds

  if headerHeight > 0:
    ed.boxy.fillRect(headerBounds, if selected: ed.theme.color("tab.activeBackground", rgb(45, 45, 60)) else: ed.theme.color("tab.inactiveBackground", rgb(45, 45, 45)))

    let color = if selected: ed.theme.color("tab.activeForeground", rgb(255, 225, 255)) else: ed.theme.color("tab.inactiveForeground", rgb(255, 225, 255))

    let mode = if editor.currentMode.len == 0: "normal" else: editor.currentMode
    discard ed.renderCtx.drawText(headerBounds.xy, fmt"{mode} - {document.filename}", color)
    discard ed.renderCtx.drawText(headerBounds.xwy, fmt"{editor.selection} - {editor.id}", color, pivot = vec2(1, 0))

  # Mask the rest of the rendering is this function to the contentBounds
  ed.boxy.pushLayer()
  defer:
    ed.boxy.pushLayer()
    ed.boxy.fillRect(contentBounds, color(1, 0, 0, 1))
    ed.boxy.popLayer(blendMode = MaskBlend)
    ed.boxy.popLayer()

  let usedBounds = editor.measureEditorBounds(ed, contentBounds)
  ed.boxy.fillRect(usedBounds, if selected: ed.theme.color("editor.background", rgb(25, 25, 40)) else: ed.theme.color("editor.background", rgb(25, 25, 25)) * 0.75)

  let textColor = ed.theme.color("editor.foreground", rgb(225, 200, 200))

  let printScope = ed.getFlag("text.print-scopes")
  let lineDistance = getOption[float32](ed, "text.line-distance", 2)

  block:
    editor.previousBaseIndex = editor.previousBaseIndex.clamp(0..editor.document.lines.len)

    let lineHeight = ed.renderCtx.lineHeight

    # Adjust scroll offset and base index so that the first node on screen is the base
    while editor.scrollOffset < 0 and editor.previousBaseIndex + 1 < editor.document.lines.len:
      if editor.scrollOffset + lineHeight + lineDistance >= contentBounds.h:
        break
      editor.previousBaseIndex += 1
      editor.scrollOffset += lineHeight + lineDistance

    # Adjust scroll offset and base index so that the first node on screen is the base
    while editor.scrollOffset > contentBounds.h and editor.previousBaseIndex > 0:
      if editor.scrollOffset - lineHeight <= 0:
        break
      editor.previousBaseIndex -= 1
      editor.scrollOffset -= lineHeight + lineDistance

  let selection = editor.selection
  let selectionNormalized = selection.normalized

  let selections = editor.selections
  var selectionsPerLine = initTable[int, seq[Selection]]()
  for s in selections:
    let sn = s.normalized
    for line in sn.first.line..sn.last.line:
      selectionsPerLine.mgetOrPut(line, @[]).add s

  let highlightsPerLine = editor.searchResults

  let showNodeHighlight = getOption[bool](ed, "text.show-node-highlight")
  let nodeHighlightParentIndex = getOption[int](ed, "text.node-highlight-parent-index", 0)
  let nodeHighlightSiblingIndex = getOption[int](ed, "text.node-highlight-sibling-index", 0)
  let highlightRange = if showNodeHighlight:
    editor.document.getNodeRange(selectionNormalized, nodeHighlightParentIndex, nodeHighlightSiblingIndex)
  else:
    Selection.none

  editor.lastRenderedLines.setLen 0

  let lineNumbers = editor.lineNumbers.get getOption[LineNumbers](ed, "editor.text.line-numbers", LineNumbers.Absolute)
  let maxLineNumber = case lineNumbers
    of LineNumbers.Absolute: editor.previousBaseIndex + ((contentBounds.h - editor.scrollOffset) / ed.renderCtx.lineHeight).int
    of LineNumbers.Relative: 99
    else: 0
  let maxLineNumberLen = ($maxLineNumber).len + 1
  let cursorLine = selection.last.line
  var cursorBounds = rect(vec2(), vec2())

  # Draws a line of texts, including selection background.
  proc renderLine(i: int, down: bool): bool =
    var styledText = document.getStyledText(i)

    # Pixel coordinate of the top left corner of the entire line. Includes line number
    let topLeftOffset = vec2(contentBounds.x, contentBounds.y + (i - editor.previousBaseIndex).float32 * (ed.renderCtx.lineHeight + lineDistance) + editor.scrollOffset)

    const lineNumberPadding = 10
    let lineNumberBounds = if lineNumbers != LineNumbers.None:
      rect(topLeftOffset, vec2(maxLineNumberLen.float32 * ed.renderCtx.charWidth + lineNumberPadding, 0))
    else:
      rect(topLeftOffset, vec2())
    if lineNumbers != LineNumbers.None and cursorLine == i:
      discard ed.renderCtx.drawText(lineNumberBounds.xy, $i, textColor)
    else:
      case lineNumbers
      of LineNumbers.Absolute:
        discard ed.renderCtx.drawText(lineNumberBounds.xwy - vec2(lineNumberPadding, 0), $i, textColor, pivot = vec2(1, 0))
      of LineNumbers.Relative:
        discard ed.renderCtx.drawText(lineNumberBounds.xwy - vec2(lineNumberPadding, 0), $(i - cursorLine).abs, textColor, pivot = vec2(1, 0))
      else:
        discard

    # Pixel coordinate of the top left corner of the actual text of the line
    let lineContentOffset = topLeftOffset + vec2(lineNumberBounds.w, 0)

    # Bounds of the previous line part
    var lastBounds = rect(lineContentOffset, vec2())
    if lastBounds.y > bounds.yh:
      return not down
    if lastBounds.y + ed.ctx.fontSize * 2 < 0:
      return down

    let selectionsNormalizedOnLine = selectionsPerLine.getOrDefault(i, @[]).map (s) => s.normalized
    let selectionsClampedOnLine = selectionsNormalizedOnLine.map (s) => s.clampToLine(i, styledText.len)
    let highlightsNormalizedOnLine = highlightsPerLine.getOrDefault(i, @[]).map (s) => s.normalized
    let highlightsClampedOnLine = highlightsNormalizedOnLine.map (s) => s.clampToLine(i, styledText.len)

    var startIndex = 0
    for partIndex, part in styledText.parts:
      let color = if part.scope.len == 0: textColor else: ed.theme.tokenColor(part.scope, rgb(225, 200, 200))
      let (image, bounds) = ed.renderCtx.layoutText(lastBounds.xwy, part.text)
      styledText.parts[partIndex].bounds = bounds

      # Draw background if selected
      let selectionColor = ed.theme.color("selection.background", rgb(200, 200, 200))
      ed.renderTextHighlight(bounds, i, startIndex, selectionsNormalizedOnLine, selectionsClampedOnLine, part, selectionColor, lineDistance)

      let highlightColor = ed.theme.color(@["editor.rangeHighlightBackground"], rgb(200, 200, 200))
      ed.renderTextHighlight(bounds, i, startIndex, highlightsNormalizedOnLine, highlightsClampedOnLine, part, highlightColor, lineDistance)

      let isWide = getOption[bool](ed, editor.getContextWithMode("editor.text.cursor.wide"))
      let cursorWidth = if isWide: 1.0 else: 0.2

      # Set last cursor pos if it's contained in this part
      let cursorColor = ed.theme.color(@["editorCursor.foreground", "foreground"], rgba(255, 255, 255, 127))
      for selection in selectionsPerLine.getOrDefault(i, @[]):
        if selection.last.line == i and selection.last.column >= startIndex and selection.last.column <= startIndex + part.text.len:
          let startOffset = if part.text.len == 0: 0.0 else: max(0, selection.last.column - startIndex).float32 / (part.text.len.float32 - 0) * bounds.w
          let lastCursorPos = bounds.xy + vec2(startOffset, 0)
          cursorBounds = rect(lastCursorPos, vec2(ed.renderCtx.charWidth * cursorWidth, ed.renderCtx.lineHeight))
          ed.boxy.fillRect(cursorBounds, cursorColor)

      # Draw the actual text
      ed.renderCtx.boxy.drawImage(image, bounds.xy, color)
      lastBounds = bounds

      if printScope:
        lastBounds = ed.renderCtx.drawText(lastBounds.xwy, " (" & part.scope & ") ", textColor)

      startIndex += part.text.len

    editor.lastRenderedLines.add styledText
    return true

  # Render all lines after base index
  for i in editor.previousBaseIndex..editor.document.lines.high:
    if not renderLine(i, true):
      break

  # Render all lines before base index
  for k in 1..editor.previousBaseIndex:
    let i = editor.previousBaseIndex - k
    if not renderLine(i, false):
      break

  if editor.showCompletions:
    let bounds = rect(cursorBounds.xyh, vec2(500, 500))
    discard ed.renderTextCompletions(editor.completions, editor.selectedCompletion, bounds, contentBounds, false, editor.lastItems)

  return usedBounds

  # let atlasImage = ed.boxy.readAtlas().resize(usedBounds.w.int, usedBounds.h.int)
  # let atlasImage = ed.boxy.readAtlas().resize(usedBounds.w.int, usedBounds.w.int)
  # ed.boxy2.addImage("atlas", atlasImage, false)
  # ed.boxy2.drawImage("atlas", contentBounds.xy)

proc renderCompletions(ed: Editor, completions: seq[Completion], selected: int, bounds: Rect, fill: bool, renderedItems: var seq[tuple[index: int, bounds: Rect]]): Rect =
  result = bounds.xyRect
  renderedItems.setLen 0

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

  result = rect(bounds.xy, vec2(totalWidth, renderedCompletions.float32 * config.font.size))
  ed.boxy.fillRect(result, ed.theme.color("panel.background", rgb(30, 30, 30)))
  ed.boxy.strokeRect(result, ed.theme.color("panel.border", rgb(255, 255, 255)))

  let selectionColor = ed.theme.color("list.activeSelectionBackground", rgb(200, 200, 200))
  ed.boxy.fillRect(rect(bounds.xy + vec2(0, (selected - firstCompletion).float32 * config.font.size), vec2(totalWidth, config.font.size)), selectionColor)

  for i, (name, typ, value, color1, color2, color3) in entries:
    # if i == (selected - firstCompletion):
    #   ed.boxy.fillRect(rect(bounds.xy + vec2(0, i.float32 * config.font.size), vec2(totalWidth, config.font.size)), ed.theme.color("list.activeSelectionBackground", rgb(40, 40, 40)))
    # elif i mod 2 == 1:
    #   ed.boxy.fillRect(rect(bounds.xy + vec2(0, i.float32 * config.font.size), vec2(totalWidth, config.font.size)), ed.theme.color("list.inactiveSelectionBackground", rgb(40, 40, 40)))

    var totalBounds = ed.renderCtx.drawText(vec2(bounds.x, bounds.y + i.float32 * config.font.size), name, ed.theme.tokenColor(color1, rgb(255, 255, 255)))
    var lastRect = totalBounds
    lastRect = ed.renderCtx.drawText(vec2(lastRect.x + nameWidth, bounds.y + i.float32 * config.font.size), " : ", ed.theme.color("list.inactiveSelectionForeground", rgb(175, 175, 175)))
    totalBounds = totalBounds or lastRect
    lastRect = ed.renderCtx.drawText(vec2(lastRect.xw, bounds.y + i.float32 * config.font.size), typ, ed.theme.tokenColor(color2, rgb(255, 175, 175)))
    totalBounds = totalBounds or lastRect

    if value.len > 0:
      lastRect = ed.renderCtx.drawText(vec2(lastRect.x + typeWidth, bounds.y + i.float32 * config.font.size), " = ", ed.theme.color("list.inactiveSelectionForeground", rgb(175, 175, 175)))
      totalBounds = totalBounds or lastRect
      lastRect = ed.renderCtx.drawText(vec2(lastRect.xw, bounds.y + i.float32 * config.font.size), value, ed.theme.tokenColor(color3, rgb(175, 255, 175)))
      totalBounds = totalBounds or lastRect

    renderedItems.add (firstCompletion + i, totalBounds)

method computeBounds(item: SelectorItem, ed: Editor): Rect {.base.} =
  discard

method computeBounds(item: ThemeSelectorItem, ed: Editor): Rect =
  let nameWidth = ed.ctx.measureText(item.name).width
  return rect(vec2(), vec2(nameWidth, ed.ctx.fontSize))

method computeBounds(item: FileSelectorItem, ed: Editor): Rect =
  let nameWidth = ed.ctx.measureText(item.path).width
  return rect(vec2(), vec2(nameWidth, ed.ctx.fontSize))

method renderItem(item: SelectorItem, ed: Editor, bounds: Rect) {.base.} =
  discard

method renderItem(item: ThemeSelectorItem, ed: Editor, bounds: Rect) =
  let color = ed.theme.color(@["list.activeSelectionForeground", "editor.foreground"], rgb(255, 255, 255))
  discard ed.renderCtx.drawText(bounds.xy, item.name, color)

method renderItem(item: FileSelectorItem, ed: Editor, bounds: Rect) =
  let color = ed.theme.color(@["list.activeSelectionForeground", "editor.foreground"], rgb(255, 255, 255))
  discard ed.renderCtx.drawText(bounds.xy, item.path, color)

proc renderItems(ed: Editor, completions: seq[SelectorItem], selected: int, bounds: Rect, fill: bool, renderedItems: var seq[tuple[index: int, bounds: Rect]]): Rect =
  result = bounds.xyRect
  renderedItems.setLen 0

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

  result = rect(bounds.xy, vec2(totalWidth, totalHeight))
  ed.boxy.fillRect(result, ed.theme.color("panel.background", rgb(30, 30, 30)))
  ed.boxy.strokeRect(result, ed.theme.color("panel.border", rgb(255, 255, 255)))

  let selectionColor = ed.theme.color("list.activeSelectionBackground", rgb(200, 200, 200))
  ed.boxy.fillRect(rect(entries[selected - firstCompletion].xy, vec2(totalWidth, entries[selected - firstCompletion].h)), selectionColor)

  for i, rect in entries:
    let com = completions[firstCompletion + i]
    com.renderItem(ed, rect)
    renderedItems.add (firstCompletion + i, rect)

proc renderVisualNode(editor: AstDocumentEditor, ed: Editor, node: VisualNode, offset: Vec2, selected: AstNode, globalBounds: Rect) =
  let bounds = node.bounds + offset

  if node.len == 0:
    if not bounds.intersects(globalBounds):
      return
  else:
    if not bounds.intersects(globalBounds):
      return

  if node.background.getSome(colors):
    let color = ed.theme.anyColor(colors, rgb(255, 255, 255))
    ed.boxy.fillRect(bounds, color)

  if node.text.len > 0:
    let color = ed.theme.anyColor(node.colors, rgb(255, 255, 255))
    var style = ed.theme.tokenFontStyle(node.colors)
    if node.styleOverride.getSome(override):
      style.incl override

    let font = config.getFont(style)

    let text = if ed.getFlag("ast.render-vnode-depth", false): $node.depth else: node.text
    let image = ctx.computeRenderedText(ctx.getOrCreateRenderTextInput(newRenderTextInput(
      ed.renderCtx,
      text,
      font, ed.ctx.fontSize, ed.renderCtx.lineHeight, ed.renderCtx.charWidth)))
    ed.boxy.drawImage(image, bounds.xy, color)

    if Underline in style:
      ed.boxy.fillRect(bounds.splitHInv(2.relative)[1], color)

  elif node.node != nil and node.node.kind == Empty:
    ed.boxy.fillRect(bounds, ed.theme.color("editorError.foreground", rgb(255, 100, 100)).withAlpha(0.1))
    ed.boxy.strokeRect(bounds, ed.theme.color("editorError.foreground", rgb(255, 100, 100)))

  # Render custom stuff
  if not isNil node.render:
    node.render(bounds)

  for child in node.children:
    editor.renderVisualNode(ed, child, bounds.xy, selected, globalBounds)

  # Draw outline around node if it refers to the selected node or the same thing the selected node refers to
  if node.node != nil and (editor.node.id == node.node.reff or (editor.node.reff == node.node.reff and node.node.reff != null)):
    ed.boxy.fillRect(bounds, ed.theme.color("inputValidation.infoBorder", rgb(175, 175, 255)).withAlpha(0.1))
    ed.boxy.strokeRect(bounds, ed.theme.color("inputValidation.infoBorder", rgb(175, 175, 255)))

  # Draw outline around node it is being refered to by the selected node
  if node.node != nil and editor.node.reff == node.node.id:
    ed.boxy.fillRect(bounds, ed.theme.color("inputValidation.warningBorder", rgb(175, 255, 200)).withAlpha(0.1))
    ed.boxy.strokeRect(bounds, ed.theme.color("inputValidation.warningBorder", rgb(175, 255, 200)))

proc renderVisualNodeLayout(editor: AstDocumentEditor, ed: Editor, node: AstNode, contentBounds: Rect, layout: NodeLayout, offset: var Vec2) =
  editor.lastLayouts.add (layout, offset - contentBounds.xy)

  let nodeBounds = layout.bounds
  if not contentBounds.intersects(nodeBounds + offset):
    return

  for line in layout.root.children:
    editor.renderVisualNode(ed, line, offset, editor.node, contentBounds)

  # Draw diagnostics
  for (id, visualRange) in layout.nodeToVisualNode.pairs:
    if ctx.diagnosticsPerNode.contains(id):
      var foundErrors = false
      let bounds = visualRange.absoluteBounds + offset
      var last = rect(bounds.xy, vec2())
      for diagnostics in ctx.diagnosticsPerNode[id].queries.values:
        for diagnostic in diagnostics:
          last = ed.renderCtx.drawText(vec2(contentBounds.xw, last.yh), diagnostic.message, ed.theme.color("editorError.foreground", rgb(255, 0, 0)), pivot = vec2(1, 0))
          foundErrors = true
      if foundErrors:
        ed.boxy.fillRect(bounds.grow(3.relative), ed.theme.color("editorError.foreground", rgb(255, 0, 0)).withAlpha(0.1))
        ed.boxy.strokeRect(bounds.grow(3.relative), ed.theme.color("editorError.foreground", rgb(255, 0, 0)))

  # Render outline for selected node
  if layout.nodeToVisualNode.contains(editor.node.id):
    let visualRange = layout.nodeToVisualNode[editor.node.id]
    let bounds = visualRange.absoluteBounds + offset

    ed.boxy.fillRect(bounds, ed.theme.color("foreground", rgb(255, 255, 255)).withAlpha(0.1))
    ed.boxy.strokeRect(bounds, ed.theme.color("foreground", rgb(255, 255, 255)), 2)

    let value = ctx.getValue(editor.node)
    let typ = ctx.computeType(editor.node)

    let parentBounds = visualRange.parent.absoluteBounds

    var last = rect(vec2(contentBounds.xw - 25, parentBounds.y + offset.y), vec2())
    last = ed.renderCtx.drawText(last.xy, $typ, ed.theme.tokenColor("storage.type", rgb(255, 255, 255)), pivot = vec2(1, 0))

    if value.getSome(value) and value.kind != vkVoid and value.kind != vkBuiltinFunction and value.kind != vkAstFunction and value.kind != vkError:
      last = ed.renderCtx.drawText(last.xy, " : ", ed.theme.tokenColor("punctuation", rgb(255, 255, 255)), pivot = vec2(1, 0))
      last = ed.renderCtx.drawText(last.xy, $value, ed.theme.tokenColor("string", rgb(255, 255, 255)), pivot = vec2(1, 0))

proc renderBlockIndent(editor: AstDocumentEditor, ed: Editor, layout: NodeLayout, node: AstNode, offset: Vec2) =
  for (_, child) in node.nextPreOrder:
    if child.kind == NodeList and layout.nodeToVisualNode.contains(child.id):
      let visualRange = layout.nodeToVisualNode[child.id]
      let bounds = visualRange.absoluteBounds + offset
      let indent = (visualRange.parent[visualRange.first].indent - 1) mod 6 + 1
      let color = ed.theme.color(@[fmt"editorBracketHighlight.foreground{indent}", "editor.foreground"]).withAlpha(0.75)
      ed.boxy.fillRect(bounds.splitV(2.relative)[0], color)

method renderDocumentEditor(editor: AstDocumentEditor, ed: Editor, bounds: Rect, selected: bool): Rect =
  let document = editor.document
  let theme = ed.theme

  let timer = startTimer()
  defer:
    if logRenderDuration or ed.getFlag("log-render-duration"):
      let queryExecutionTimes = fmt"  Type: {ctx.statsType}" &
        fmt"  Value: {ctx.statsValue}" &
        fmt"  Symbol: {ctx.statsSymbol}" &
        fmt"  Symbols: {ctx.statsSymbols}" &
        fmt"  SymbolType: {ctx.statsSymbolType}" &
        fmt"  SymbolValue: {ctx.statsSymbolValue}" &
        fmt"  NodeLayout: {ctx.statsNodeLayout}" &
        fmt"  RenderedText: {ctx.statsRenderedText}"
      echo fmt"Frame: {ed.frameTimer.elapsed.ms:>5.2}ms  Render duration: {timer.elapsed.ms:.2}ms{queryExecutionTimes}"

    ctx.resetExecutionTimes()

  let (headerBounds, contentBoundsWithPadding) = bounds.splitH ed.renderCtx.lineHeight.relative

  ed.boxy.fillRect(headerBounds, if selected: theme.color("tab.activeBackground", rgb(45, 45, 60)) else: theme.color("tab.inactiveBackground", rgb(45, 45, 45)))
  ed.boxy.fillRect(contentBoundsWithPadding, if selected: theme.color("editor.background", rgb(25, 25, 40)) else: theme.color("editor.background", rgb(25, 25, 25)) * 0.75)
  let mode = if editor.currentMode.len == 0: "normal" else: editor.currentMode
  let titleImage = ctx.computeRenderedText(ctx.getOrCreateRenderTextInput(newRenderTextInput(
    ed.renderCtx,
    fmt"{mode} - {document.filename}",
    config.fontRegular, ed.ctx.fontSize, ed.renderCtx.lineHeight, ed.renderCtx.charWidth)))
  ed.boxy.drawImage(titleImage, vec2(headerBounds.x, headerBounds.y), if selected: theme.color("tab.activeForeground", rgb(255, 225, 255)) else: theme.color("tab.inactiveForeground", rgb(255, 225, 255)))

  # Mask the rest of the rendering is this function to the contentBounds
  ed.boxy.pushLayer()
  defer:
    ed.boxy.pushLayer()
    ed.boxy.fillRect(contentBoundsWithPadding, color(1, 0, 0, 1))
    ed.boxy.popLayer(blendMode = MaskBlend)
    ed.boxy.popLayer()

  let contentBounds = contentBoundsWithPadding.shrink(2.relative)
  editor.lastBounds = contentBounds

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

  # Adjust scroll offset and base index so that the first node on screen is the base
  while editor.scrollOffset < 0 and editor.previousBaseIndex + 1 < editor.document.rootNode.len:
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: editor.document.rootNode[editor.previousBaseIndex], selectedNode: selectedNode.id, replacements: replacements, revision: config.revision)
    let layout = ctx.computeNodeLayout(input)

    if editor.scrollOffset + layout.bounds.h + lineDistance >= contentBounds.h:
      break

    editor.previousBaseIndex += 1
    editor.scrollOffset += layout.bounds.h + lineDistance

  # Adjust scroll offset and base index so that the first node on screen is the base
  while editor.scrollOffset > contentBounds.h and editor.previousBaseIndex > 0:
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: editor.document.rootNode[editor.previousBaseIndex - 1], selectedNode: selectedNode.id, replacements: replacements, revision: config.revision)
    let layout = ctx.computeNodeLayout(input)

    if editor.scrollOffset - layout.bounds.h <= 0:
      break

    editor.previousBaseIndex -= 1
    editor.scrollOffset -= layout.bounds.h + lineDistance

  # echo fmt"{editor.previousBaseIndex} : {editor.scrollOffset}"
  editor.lastLayouts.setLen 0

  var rendered = 0

  var offset = contentBounds.xy + vec2(0, editor.scrollOffset)
  for i in editor.previousBaseIndex..<editor.document.rootNode.len:
    let node = editor.document.rootNode[i]
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: node, selectedNode: selectedNode.id, replacements: replacements, revision: config.revision)
    let layout = ctx.computeNodeLayout(input)
    if layout.bounds.y + offset.y > contentBounds.yh:
      break

    editor.renderVisualNodeLayout(ed, node, contentBounds, layout, offset)
    editor.renderBlockIndent(ed, layout, node, offset)
    offset.y += layout.bounds.h + lineDistance

    inc rendered

  offset = contentBounds.xy + vec2(0, editor.scrollOffset)
  for k in 1..editor.previousBaseIndex:
    let i = editor.previousBaseIndex - k
    let node = editor.document.rootNode[i]
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: node, selectedNode: selectedNode.id, replacements: replacements, revision: config.revision)
    let layout = ctx.computeNodeLayout(input)
    if layout.bounds.yh + offset.y < contentBounds.y:
      break

    offset.y -= layout.bounds.h + lineDistance
    editor.renderVisualNodeLayout(ed, node, contentBounds, layout, offset)
    editor.renderBlockIndent(ed, layout, node, offset)

    inc rendered

  if editor.completions.len > 0:
    # Render outline around all nodes which reference the selected symbol in the completion list
    for (layout, offset) in editor.lastLayouts:
      let selectedCompletion = editor.completions[editor.selectedCompletion]
      if selectedCompletion.kind == SymbolCompletion and ctx.getSymbol(selectedCompletion.id).getSome(symbol) and symbol.kind == skAstNode and layout.nodeToVisualNode.contains(symbol.node.id):
        let selectedDeclRect = layout.nodeToVisualNode[symbol.node.id]
        ed.boxy.strokeRect(selectedDeclRect.absoluteBounds + offset + contentBounds.xy, ed.theme.color("editor.findMatchBorder", rgb(150, 150, 220)))

    # Render completion window under the currently edited node
    for (layout, offset) in editor.lastLayouts:
      if layout.nodeToVisualNode.contains(editor.node.id):
        let visualRange = layout.nodeToVisualNode[editor.node.id]
        let bounds = visualRange.absoluteBounds + offset + contentBounds.xy
        discard ed.renderCompletions(editor.completions, editor.selectedCompletion, contentBounds.splitH(bounds.yh.absolute)[1].splitV(bounds.x.absolute)[1], false, editor.lastItems)

  if ed.getFlag("render-execution-output"):
    ed.boxy.pushLayer()
    let lineHeight = ed.renderCtx.lineHeight

    let linesToRender = min(executionOutput.lines.len, int(bounds.h / lineHeight) + 1)
    let offset = min(executionOutput.lines.len - linesToRender, executionOutput.scroll)
    executionOutput.scroll = offset
    let firstIndex = linesToRender + offset
    let lastIndex = 1 + offset

    var maxLineLength = 0
    for (line, color) in executionOutput.lines[^firstIndex..^lastIndex]:
      maxLineLength = max(maxLineLength, line.len)

    let boundsWidth = (maxLineLength + 5).clamp(25, 100).float32 * ed.renderCtx.charWidth
    let bounds = contentBounds.splitVInv(boundsWidth.relative)[1]

    let verticalPixelOffset = max(0, linesToRender.float32 * lineHeight - bounds.h)

    var last = rect(bounds.xy - vec2(0, verticalPixelOffset), vec2())
    for (line, color) in executionOutput.lines[^firstIndex..^lastIndex]:
      last = ed.renderCtx.drawText(last.xyh, line, color)

    ed.boxy.pushLayer()
    ed.boxy.fillRect(bounds, color(1, 0, 0, 1))
    ed.boxy.popLayer(blendMode = MaskBlend)
    ed.boxy.popLayer()

    ed.boxy.strokeRect(bounds, rgb(225, 225, 225).color)

  if ed.getFlag("render-debug-info"):
    let bounds = contentBounds.splitV(relative(contentBounds.w - 500))[1]
    ed.boxy.strokeRect(bounds, rgb(225, 225, 225).color)

    var last = rect(bounds.xy, vec2())

    var text = ""
    var image = ""

    text = ""
    text.add fmt"DepGraph:"
    text.add fmt"  revision:        {ctx.depGraph.revision}" & "\n"
    text.add fmt"  verified:        {ctx.depGraph.verified.len}" & "\n"
    text.add fmt"  changed:         {ctx.depGraph.changed.len}" & "\n"
    text.add fmt"  fingerprints:    {ctx.depGraph.fingerprints.len}" & "\n"
    text.add fmt"  dependencies:    {ctx.depGraph.dependencies.len}" & "\n"
    text.add fmt"  query names:     {ctx.depGraph.queryNames.len}" & "\n"

    image = ctx.computeRenderedText(ctx.getOrCreateRenderTextInput(newRenderTextInput(
      ed.renderCtx,
      text,
      config.fontRegular, ed.ctx.fontSize, ed.renderCtx.lineHeight, ed.renderCtx.charWidth,
      "debug.depGraph")))
    ed.boxy.drawImage(image, last.xyh, rgb(255, 255, 255).color)
    last.h += ed.boxy.getImageSIze(image).y.float32

    text = ""
    text.add fmt"Inputs:" & "\n"
    text.add fmt"  AstNodes:        {ctx.itemsAstNode.len}" & "\n"
    text.add fmt"  NodeLayoutInput: {ctx.itemsNodeLayoutInput.len}" & "\n"
    text.add fmt"Data:" & "\n"
    text.add fmt"  Symbols:         {ctx.itemsSymbol.len}" & "\n"
    text.add fmt"  FuncExecContext: {ctx.itemsFunctionExecutionContext.len}" & "\n"

    image = ctx.computeRenderedText(ctx.getOrCreateRenderTextInput(newRenderTextInput(
      ed.renderCtx,
      text,
      config.fontRegular, ed.ctx.fontSize, ed.renderCtx.lineHeight, ed.renderCtx.charWidth,
      "debug.inputs")))
    ed.boxy.drawImage(image, last.xyh, rgb(255, 255, 255).color)
    last.h += ed.boxy.getImageSIze(image).y.float32

    text = ""
    text.add fmt"QueryCaches:" & "\n"
    text.add fmt"  Type:            {ctx.queryCacheType.len}" & "\n"
    text.add fmt"  Value:           {ctx.queryCacheValue.len}" & "\n"
    text.add fmt"  SymbolType:      {ctx.queryCacheSymbolType.len}" & "\n"
    text.add fmt"  SymbolValue:     {ctx.queryCacheSymbolValue.len}" & "\n"
    text.add fmt"  Symbol:          {ctx.queryCacheSymbol.len}" & "\n"
    text.add fmt"  Symbols:         {ctx.queryCacheSymbols.len}" & "\n"
    text.add fmt"  FunctionExec:    {ctx.queryCacheFunctionExecution.len}" & "\n"
    text.add fmt"  NodeLayout:      {ctx.queryCacheNodeLayout.len}" & "\n"
    text.add fmt"  RenderedText:    {ctx.queryCacheRenderedText.len}" & "\n"

    image = ctx.computeRenderedText(ctx.getOrCreateRenderTextInput(newRenderTextInput(
      ed.renderCtx,
      text,
      config.fontRegular, ed.ctx.fontSize, ed.renderCtx.lineHeight, ed.renderCtx.charWidth,
      "debug.queryCaches")))
    ed.boxy.drawImage(image, last.xyh, rgb(255, 255, 255).color)
    last.h += ed.boxy.getImageSIze(image).y.float32

    text = ""
    text.add fmt"Timings:" & "\n"
    text.add fmt"  Frame:           {ed.frameTimer.elapsed.ms:.2}ms" & "\n"
    text.add fmt"  Rendering:       {timer.elapsed.ms:.2}ms" & "\n"
    text.add fmt"  Type:            {ctx.statsType.time.ms:.2}ms  {ctx.statsType.forcedCalls: 4}  {ctx.statsType.totalCalls: 4}" & "\n"
    text.add fmt"  Value:           {ctx.statsValue.time.ms:.2}ms  {ctx.statsValue.forcedCalls: 4}  {ctx.statsValue.totalCalls: 4}" & "\n"
    text.add fmt"  Symbol:          {ctx.statsSymbol.time.ms:.2}ms  {ctx.statsSymbol.forcedCalls: 4}  {ctx.statsSymbol.totalCalls: 4}" & "\n"
    text.add fmt"  Symbols:         {ctx.statsSymbols.time.ms:.2}ms  {ctx.statsSymbols.forcedCalls: 4}  {ctx.statsSymbols.totalCalls: 4}" & "\n"
    text.add fmt"  SymbolType:      {ctx.statsSymbolType.time.ms:.2}ms  {ctx.statsSymbolType.forcedCalls: 4}  {ctx.statsSymbolType.totalCalls: 4}" & "\n"
    text.add fmt"  SymbolValue:     {ctx.statsSymbolValue.time.ms:.2}ms  {ctx.statsSymbolValue.forcedCalls: 4}  {ctx.statsSymbolValue.totalCalls: 4}" & "\n"
    text.add fmt"  NodeLayout:      {ctx.statsNodeLayout.time.ms:.2}ms  {ctx.statsNodeLayout.forcedCalls: 4}  {ctx.statsNodeLayout.totalCalls: 4}" & "\n"
    text.add fmt"  FunctionExec:    {ctx.statsFunctionExecution.time.ms:.2}ms  {ctx.statsFunctionExecution.forcedCalls: 4}  {ctx.statsFunctionExecution.totalCalls: 4}" & "\n"
    text.add fmt"  RenderedText:    {ctx.statsRenderedText.time.ms:.2}ms  {ctx.statsRenderedText.forcedCalls: 4}  {ctx.statsRenderedText.totalCalls: 4}" & "\n"

    image = ctx.computeRenderedText(ctx.getOrCreateRenderTextInput(newRenderTextInput(
      ed.renderCtx,
      text,
      config.fontRegular, ed.ctx.fontSize, ed.renderCtx.lineHeight, ed.renderCtx.charWidth,
      "debug.timings")))
    ed.boxy.drawImage(image, last.xyh, rgb(255, 255, 255).color)
    last.h += ed.boxy.getImageSIze(image).y.float32

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
  let bounds = bounds.shrink(10.relative)
  ed.boxy.fillRect(bounds, if selected: ed.theme.color("editorPane.background", rgb(25, 25, 40)) else: ed.theme.color("editorPane.background", rgb(25, 25, 25)))

  ed.boxy.pushLayer()
  discard view.editor.renderDocumentEditor(ed, bounds, selected)
  ed.boxy.pushLayer()
  ed.boxy.fillRect(bounds, color(1, 0, 0, 1))
  ed.boxy.popLayer(blendMode = MaskBlend)
  ed.boxy.popLayer()

method renderPopup*(popup: Popup, ed: Editor, bounds: Rect) {.base.} =
  discard

method renderPopup*(popup: AstGotoDefinitionPopup, ed: Editor, bounds: Rect) =
  let bounds = bounds.shrink(0.15.percent)
  let (textBounds, contentBounds) = bounds.splitH(ed.ctx.fontSize.relative)
  ed.boxy.fillRect(textBounds, ed.theme.color("panel.background", rgb(25, 25, 25)))
  discard popup.textEditor.renderDocumentEditor(ed, textBounds, true)
  popup.lastContentBounds = ed.renderCompletions(popup.completions, popup.selected, contentBounds, true, popup.lastItems)
  popup.lastBounds = textBounds or popup.lastContentBounds

method renderPopup*(popup: SelectorPopup, ed: Editor, bounds: Rect) =
  let bounds = bounds.shrink(0.15.percent)
  let (textBounds, contentBounds) = bounds.splitH(ed.ctx.fontSize.relative)
  ed.boxy.fillRect(textBounds, ed.theme.color("panel.background", rgb(25, 25, 25)))
  discard popup.textEditor.renderDocumentEditor(ed, textBounds, true)
  popup.lastContentBounds = ed.renderItems(popup.completions, popup.selected, contentBounds, true, popup.lastItems)
  popup.lastBounds = textBounds or popup.lastContentBounds

proc renderMainWindow*(ed: Editor, bounds: Rect) =
  ed.lastBounds = bounds
  ed.boxy.fillRect(bounds, ed.theme.color("editorPane.background", rgb(25, 25, 25)))

  let rects = ed.layout.layoutViews(ed.layout_props, bounds, ed.views)
  for i, view in ed.views:
    if i >= rects.len:
      break
    ed.renderView(rects[i], view, i == ed.currentView and not ed.commandLineMode)

  for i, popup in ed.popups:
    ed.boxy.pushLayer()
    popup.renderPopup(ed, bounds)
    ed.boxy.pushLayer()
    ed.boxy.fillRect(bounds, color(1, 0, 0, 1))
    ed.boxy.popLayer(blendMode = MaskBlend)
    ed.boxy.popLayer()

proc renderStatusBar*(ed: Editor, bounds: Rect) =
  let (statusBounds, commandsBounds) = bounds.splitH(relative(ed.ctx.fontSize))

  let mode = if ed.currentMode.len == 0: "normal" else: ed.currentMode
  discard ed.renderCtx.drawText(statusBounds.xy, fmt"{mode}", ed.theme.color("editor.foreground", rgb(225, 200, 200)))
  discard ed.getCommandLineTextEditor.renderDocumentEditor(ed, commandsBounds, ed.commandLineMode)

proc render*(ed: Editor) =
  defer:
    if getOption[bool](ed, "editor.log-frame-time"):
      echo fmt"Frame: {ed.frameTimer.elapsed.ms:>5.2}ms"
    ed.frameTimer = startTimer()

  if ed.clearAtlasTimer.elapsed.ms >= 5000:
    ed.boxy.clearAtlas()
    ctx.queryCacheRenderedText.clear
    ed.clearAtlasTimer = startTimer()

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
    config.revision += 1
  elif config.font.size != ed.ctx.fontSize:
    config.font.size = ed.ctx.fontSize
    config.revision += 1

  let tempArrangement = config.font.typeset("#")
  var tempBounds = tempArrangement.layoutBounds()
  ed.renderCtx.lineHeight = tempBounds.y
  ed.renderCtx.charWidth = tempBounds.x

  let (mainRect, statusRect) = if not ed.statusBarOnTop: windowRect.splitH(relative(windowRect.h - lineHeight * 2))
  else:
    let rects = windowRect.splitH(relative(lineHeight * 2))
    (rects[1], rects[0])

  ed.renderMainWindow(mainRect)
  ed.renderStatusBar(statusRect)