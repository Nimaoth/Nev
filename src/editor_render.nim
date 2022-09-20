import std/[strformat, bitops, strutils, tables, algorithm, math, macros, enumutils, sets]
import boxy, times, windy, fusion/matching, print
import sugar
import util, input, events, editor, rect_utils, document, document_editor, text_document, ast_document, keybind_autocomplete, id, ast
import compiler

let typeface = readTypeface("fonts/FiraCode-Regular.ttf")

let gap = 0.0
let horizontalGap = 2.0
let indent = 15.0
let padding = 5.0

proc fillText(ctx: contexts.Context, location: Vec2, text: string, paint: Paint): Rect =
  let textWidth = ctx.measureText(text).width
  ctx.fillStyle = paint
  ctx.fillText(text, location)
  return rect(location, vec2(textWidth, ctx.fontSize))

proc fillText(ctx: contexts.Context, location: Vec2, texts: openArray[tuple[text: string, paint: Paint]]): Rect =
  var bounds = rect(location, vec2(0, ctx.fontSize))
  for (text, paint) in texts:
    let newBounds = ctx.fillText(vec2(bounds.xw, bounds.y), text, paint)
    bounds.w += newBounds.w
  return bounds

proc renderAstNode(node: AstNode, editor: AstDocumentEditor, ed: Editor, bounds: Rect, selectedNode: AstNode, nodeBounds: var Table[AstNode, Rect]): Rect

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

method renderDocumentEditor(editor: DocumentEditor, ed: Editor, bounds: Rect, selected: bool): Rect {.base.} =
  return rect(0, 0, 0, 0)

method renderDocumentEditor(editor: TextDocumentEditor, ed: Editor, bounds: Rect, selected: bool): Rect =
  let document = editor.document

  let headerHeight = if editor.renderHeader: ed.ctx.fontSize else: 0

  let (headerBounds, contentBounds) = bounds.splitH headerHeight.relative

  if headerHeight > 0:
    ed.ctx.fillStyle = if selected: rgb(45, 45, 60) else: rgb(45, 45, 45)
    ed.ctx.fillRect(headerBounds)

  # ed.ctx.fillStyle = if selected: rgb(25, 25, 40) else: rgb(25, 25, 25)
  # ed.ctx.fillRect(contentBounds)

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

proc getPrecedenceForNode(doc: AstDocument, node: AstNode): int =
  if node.kind != Call or node.len == 0:
    return 0
  if ctx.computeSymbol(node[0]).getSome(symbol):
    case symbol.kind
    of skBuiltin:
      return symbol.precedence
    of skAstNode:
      discard

  return 0

proc renderInfixNode(node: AstNode, editor: AstDocumentEditor, ed: Editor, bounds: Rect, selectedNode: AstNode, nodeBounds: var Table[AstNode, Rect]): Rect =
  let horizontalGap = horizontalGap * 4
  let subBounds = bounds.shrink gap.relative

  let parentPrecedence = editor.document.getPrecedenceForNode node.parent
  let precedence = editor.document.getPrecedenceForNode node
  let renderParens = precedence < parentPrecedence

  let parenWidth = if renderParens: ed.ctx.measureText("(").width else: 0

  if renderParens:
    ed.ctx.fillStyle = rgb(175, 175, 175)
    ed.ctx.fillText("(", vec2(bounds.x, bounds.y))

  let lhsBounds = renderAstNode(node[1], editor, ed, subBounds.splitV(parenWidth.relative)[1], selectedNode, nodeBounds)
  let opBounds = renderAstNode(node[0], editor, ed, subBounds.splitV((lhsBounds.x + lhsBounds.w + horizontalGap).absolute)[1], selectedNode, nodeBounds)
  let rhsBounds = renderAstNode(node[2], editor, ed, subBounds.splitV((opBounds.x + opBounds.w + horizontalGap).absolute)[1], selectedNode, nodeBounds)

  if renderParens:
    ed.ctx.fillStyle = rgb(175, 175, 175)
    ed.ctx.fillText(")", vec2(rhsBounds.x + rhsBounds.w, bounds.y))

  let myBounds = rect(bounds.x, bounds.y, rhsBounds.x + rhsBounds.w + parenWidth - bounds.x, max([lhsBounds.h, opBounds.h, rhsBounds.h]) + gap * 2)

  # ed.ctx.strokeStyle = rgb(0, 255, 255)
  # ed.ctx.strokeRect(myBounds)

  return myBounds

proc renderPrefixNode(node: AstNode, editor: AstDocumentEditor, ed: Editor, bounds: Rect, selectedNode: AstNode, nodeBounds: var Table[AstNode, Rect]): Rect =
  let subBounds = bounds.shrink gap.relative

  let opBounds = renderAstNode(node[0], editor, ed, subBounds, selectedNode, nodeBounds)
  let rhsBounds = renderAstNode(node[1], editor, ed, subBounds.splitV((opBounds.w + horizontalGap).relative)[1], selectedNode, nodeBounds)

  let myBounds = rect(bounds.x, bounds.y, opBounds.w + rhsBounds.w + horizontalGap * 3, max([opBounds.h, rhsBounds.h]) + gap * 2)

  # ed.ctx.strokeStyle = rgb(0, 255, 255)
  # ed.ctx.strokeRect(myBounds)

  return myBounds

proc renderPostfixNode(node: AstNode, editor: AstDocumentEditor, ed: Editor, bounds: Rect, selectedNode: AstNode, nodeBounds: var Table[AstNode, Rect]): Rect =
  let subBounds = bounds.shrink gap.relative

  let rhsBounds = renderAstNode(node[1], editor, ed, subBounds, selectedNode, nodeBounds)
  let opBounds = renderAstNode(node[0], editor, ed, subBounds.splitV((rhsBounds.w + horizontalGap).relative)[1], selectedNode, nodeBounds)

  let myBounds = rect(bounds.x, bounds.y, opBounds.w + rhsBounds.w + horizontalGap * 3, max([opBounds.h, rhsBounds.h]) + gap * 2)

  # ed.ctx.strokeStyle = rgb(0, 255, 255)
  # ed.ctx.strokeRect(myBounds)

  return myBounds

proc renderCallNode(node: AstNode, editor: AstDocumentEditor, ed: Editor, bounds: Rect, selectedNode: AstNode, nodeBounds: var Table[AstNode, Rect]): Rect =
  let document = editor.document
  let function = node[0]
  let subBounds = bounds.shrink gap.relative

  if ctx.computeSymbol(function).getSome(sym) and sym.kind == skBuiltin:
    let arity = case sym.operatorNotation
    of Infix: 2
    of Prefix, Postfix: 1
    else: -1

    if node.len == arity + 1:
      case sym.operatorNotation
      of Infix: return renderInfixNode(node, editor, ed, bounds, selectedNode, nodeBounds)
      of Prefix: return renderPrefixNode(node, editor, ed, bounds, selectedNode, nodeBounds)
      of Postfix: return renderPostfixNode(node, editor, ed, bounds, selectedNode, nodeBounds)
      else: discard

  let parenWidth = ed.ctx.measureText("(").width

  let opBounds = renderAstNode(node[0], editor, ed, subBounds, selectedNode, nodeBounds)
  var lastRect = opBounds

  ed.ctx.fillStyle = rgb(175, 175, 175)
  ed.ctx.fillText("(", vec2(lastRect.x + lastRect.w, lastRect.y))
  lastRect.w += parenWidth
  var maxHeight = 0.0

  for i in 1..<node.len:
    if i > 1:
      ed.ctx.fillStyle = rgb(175, 175, 175)
      ed.ctx.fillText(", ", vec2(lastRect.x + lastRect.w, lastRect.y))
      lastRect.w += parenWidth * 2

    lastRect = renderAstNode(node[i], editor, ed, subBounds.splitV((lastRect.x + lastRect.w + horizontalGap).absolute)[1], selectedNode, nodeBounds)
    maxHeight = max(maxHeight, lastRect.h)

  ed.ctx.fillStyle = rgb(175, 175, 175)
  ed.ctx.fillText(")", vec2(lastRect.x + lastRect.w, lastRect.y))
  lastRect.w += parenWidth

  return rect(bounds.x, bounds.y, lastRect.x + lastRect.w - bounds.x, maxHeight + gap * 2)

proc renderAstNode(node: AstNode, editor: AstDocumentEditor, ed: Editor, bounds: Rect, selectedNode: AstNode, nodeBounds: var Table[AstNode, Rect]): Rect =
  let document = editor.document

  if node == editor.currentlyEditedNode:
    let docRect = renderDocumentEditor(editor.textEditor, ed, bounds, true)
    nodeBounds[node] = docRect
    return docRect
  elif node.len == 0 and editor.currentlyEditedSymbol != null and (node.id == editor.currentlyEditedSymbol or node.reff == editor.currentlyEditedSymbol):
    let docRect = renderDocumentEditor(editor.textEditor, ed, bounds, true)
    nodeBounds[node] = docRect
    return docRect

  var nodeRect = case node
  of Empty():
    let width = ed.ctx.measureText(node.text).width

    ed.ctx.strokeStyle = rgb(255, 0, 0)
    ed.ctx.strokeRect(bounds.splitV(width.relative)[0].splitH(ed.ctx.fontSize.relative)[0])
    ed.ctx.fillStyle = rgb(255, 225, 255)
    ed.ctx.fillText(node.text, vec2(bounds.x, bounds.y))

    rect(bounds.x, bounds.y, width, ed.ctx.fontSize)

  of If():
    var ifBodyRect = rect(bounds.xy, vec2())
    var finalRect = ifBodyRect

    var index = 0
    while index + 1 < node.len:
      defer: index += 2

      # if
      let ifText = if index == 0: "if   " else: "elif "
      let ifTextRect = ed.ctx.fillText(ifBodyRect.xyh, ifText, rgb(225, 175, 255))

      # Condition
      let condRect = renderAstNode(node[index], editor, ed, bounds.splitH(ifBodyRect.yh.absolute)[1].splitV(ifTextRect.xw.absolute)[1], selectedNode, nodeBounds)

      # :
      let colonTextRect = ed.ctx.fillText(condRect.xwy, ": ", rgb(175, 175, 175))

      let condLineRect = ifTextRect or condRect or colonTextRect

      # body
      var bodyBounds = bounds.splitH(ifBodyRect.yh.absolute)[1]
      if node[index + 1].kind == NodeList:
        # Move body to next line
        bodyBounds = bodyBounds.splitH(max(ed.ctx.fontSize, condRect.h + padding).relative)[1]
      else:
        bodyBounds = bodyBounds.splitV(colonTextRect.xw.absolute)[1]

      ifBodyRect = ifBodyRect or condLineRect or renderAstNode(node[index + 1], editor, ed, bodyBounds, selectedNode, nodeBounds)
      finalRect = finalRect or ifBodyRect

    var elseBodyRect = ifBodyRect
    if node.len > 2 and node.len mod 2 != 0:
      let origin = ifBodyRect.xyh
      let elseTextRect = ed.ctx.fillText(origin, [("else", rgb(225, 175, 255).newPaint), (": ", rgb(175, 175, 175).newPaint)])

      # body
      var bodyBounds = bounds.splitH(origin.y.absolute)[1]
      if node.last.kind == NodeList:
        # Move body to next line
        bodyBounds = bodyBounds.splitH((ed.ctx.fontSize + padding).relative)[1]
      else:
        bodyBounds = bodyBounds.splitV(elseTextRect.xw.absolute)[1]

      elseBodyRect = renderAstNode(node.last, editor, ed, bodyBounds, selectedNode, nodeBounds)
      finalRect = finalRect or elseBodyRect

    let bodyRect = ifBodyRect or elseBodyRect
    # rect(bounds.x, bounds.y, max(bodyRect.x + bodyRect.w, condRect.x + condRect.y + colonWidth) - bounds.x, max(bodyRect.y + bodyRect.h, condRect.y + condRect.h) - bounds.y)
    finalRect

  of FunctionDefinition():
    var finalRect = rect(bounds.xy, vec2())

    var last = finalRect

    last = ed.ctx.fillText(last.xwy, [("fn ", rgb(225, 175, 225).newPaint), ("(", rgb(175, 175, 175).newPaint)])
    finalRect = finalRect or last

    var paramsFinalRect = rect(last.xwy, vec2())

    # Parameters
    if node.len > 0:
      let params = node[0]
      for i, param in params.children:
        if i > 0:
          last = ed.ctx.fillText(last.xwy, ", ", rgb(175, 175, 175))
          paramsFinalRect = finalRect or last

        let paramBounds = bounds.splitV(last.xw.absolute)[1]
        last = renderAstNode(param, editor, ed, paramBounds, selectedNode, nodeBounds)
        paramsFinalRect = finalRect or last

      finalRect = finalRect or paramsFinalRect
      nodeBounds[params] = paramsFinalRect

    last = ed.ctx.fillText(last.xwy, ") -> ", rgb(175, 175, 175))
    finalRect = finalRect or last

    last = renderAstNode(node[1], editor, ed, bounds.splitV(last.xw.absolute)[1], selectedNode, nodeBounds)
    finalRect = finalRect or last

    last = finalRect
    last = renderAstNode(node[2], editor, ed, bounds.splitH(finalRect.yh.absolute)[1], selectedNode, nodeBounds)
    finalRect = finalRect or last

    finalRect

  of NodeList():
    var lastNodeRect = rect(bounds.x, bounds.y, 0, 0)
    var maxWidth = 0.0
    for i, n in node.children:
      let y = lastNodeRect.y + lastNodeRect.h - bounds.y + padding * sgn(i).float32
      lastNodeRect = renderAstNode(n, editor, ed, bounds.splitV(indent.relative)[1].splitH(y.relative)[1], selectedNode, nodeBounds)
      maxWidth = max(maxWidth, lastNodeRect.w + indent)

    let r = rect(bounds.x, bounds.y, maxWidth, lastNodeRect.y + lastNodeRect.h - bounds.y)

    ed.ctx.beginPath()
    ed.ctx.strokeStyle = rgb(150, 150, 150)
    ed.ctx.moveTo vec2(r.x + min(3, indent / 3), r.y)
    ed.ctx.lineTo vec2(r.x + min(3, indent / 3), r.y + r.h)
    ed.ctx.stroke()

    r

  of Identifier():
    var text = ""
    if ctx.computeSymbol(node).getSome(symbol):
      text = symbol.name
    else:
      text = $node.reff & " (" & node.text & ")"

    let width = ed.ctx.measureText(text).width

    # ed.ctx.strokeStyle = rgb(0, 255, 0)
    # ed.ctx.strokeRect(bounds.splitV(width.relative)[0].splitH(ed.ctx.fontSize.relative)[0])
    ed.ctx.fillStyle = rgb(255, 225, 255)
    ed.ctx.fillText(text, vec2(bounds.x, bounds.y))

    rect(bounds.x, bounds.y, width, ed.ctx.fontSize)

  of ConstDecl():
    let subBounds = bounds.shrink gap.relative

    let typ = ctx.computeType(node)

    let symbol = ctx.computeSymbol(node)
    let symbolSize = if symbol.getSome(symbol) and symbol.id == editor.currentlyEditedSymbol:
      let docRect = renderDocumentEditor(editor.textEditor, ed, subBounds, true)
      vec2(docRect.w, docRect.h)
    else:
      var name = ""
      if symbol.getSome(symbol):
        name = symbol.name
      else:
        name = $node.id & " (" & node.text & ")"

      let nameWidth = ed.ctx.measureText(name).width
      ed.ctx.fillStyle = rgb(200, 200, 200)
      ed.ctx.fillText(name, vec2(subBounds.x, subBounds.y))
      vec2(nameWidth, ed.ctx.fontSize)

    let text1 = ":"
    let text2 = ":"
    let textType = $typ
    var width = ed.ctx.measureText(text1).width
    ed.ctx.fillStyle = rgb(200, 200, 200)
    ed.ctx.fillText(text1, vec2(subBounds.x + symbolSize.x, subBounds.y))
    ed.ctx.fillStyle = rgb(100, 250, 100)
    ed.ctx.fillText(textType, vec2(subBounds.x + symbolSize.x + width, subBounds.y))
    width += ed.ctx.measureText(textType).width
    ed.ctx.fillStyle = rgb(200, 200, 200)
    ed.ctx.fillText(text2, vec2(subBounds.x + symbolSize.x + width, subBounds.y))
    width += ed.ctx.measureText(text2).width

    let valueBounds = renderAstNode(node[0], editor, ed, subBounds.splitV((symbolSize.x + width).relative)[1], selectedNode, nodeBounds)

    let myBounds = rect(bounds.x, bounds.y, symbolSize.x + width + valueBounds.w + gap * 3, max([symbolSize.y, ed.ctx.fontSize, valueBounds.h]) + gap * 2)

    # ed.ctx.strokeStyle = rgb(0, 255, 255)
    # ed.ctx.strokeRect(myBounds)

    myBounds

  of LetDecl():
    let subBounds = bounds.shrink gap.relative

    let typ = ctx.computeType(node)

    let symbol = ctx.computeSymbol(node)
    let symbolSize = if symbol.getSome(symbol) and symbol.id == editor.currentlyEditedSymbol:
      let docRect = renderDocumentEditor(editor.textEditor, ed, subBounds, true)
      vec2(docRect.w, docRect.h)
    else:
      var name = ""
      if symbol.getSome(symbol):
        name = symbol.name
      else:
        name = $node.id & " (" & node.text & ")"

      let nameWidth = ed.ctx.measureText(name).width
      ed.ctx.fillStyle = rgb(200, 200, 200)
      ed.ctx.fillText(name, vec2(subBounds.x, subBounds.y))
      vec2(nameWidth, ed.ctx.fontSize)

    var finalRect = rect(subBounds.xy, symbolSize)

    var last = finalRect

    last = ed.ctx.fillText(last.xwy, ": ", rgb(175, 175, 175))
    finalRect = finalRect or last

    if node.len > 0:
      let typeNode = node[0]
      let typeBounds = bounds.splitV(last.xw.absolute)[1]
      last = renderAstNode(typeNode, editor, ed, typeBounds, selectedNode, nodeBounds)
      finalRect = finalRect or last

    if node.len > 1:
      last = ed.ctx.fillText(last.xwy, " = ", rgb(175, 175, 175))
      finalRect = finalRect or last

      let valueNode = node[1]
      let valueBounds = bounds.splitV(last.xw.absolute)[1]
      last = renderAstNode(valueNode, editor, ed, valueBounds, selectedNode, nodeBounds)
      finalRect = finalRect or last

    finalRect

  of Call():
    renderCallNode(node, editor, ed, bounds, selectedNode, nodeBounds)

  of StringLiteral():
    let text = node.text
    let width = ed.ctx.measureText(text).width

    # ed.ctx.strokeStyle = rgb(255, 0, 255)
    # ed.ctx.strokeRect(bounds.splitV(width.relative)[0].splitH(ed.ctx.fontSize.relative)[0])
    let quoteWidth = ed.ctx.measureText("\"").width
    let textWidth = ed.ctx.measureText(text).width

    ed.ctx.fillStyle = rgb(175, 200, 245)
    ed.ctx.fillText("\"", vec2(bounds.x, bounds.y))

    ed.ctx.fillStyle = rgb(255, 225, 200)
    ed.ctx.fillText(text, vec2(bounds.x + quoteWidth + horizontalGap, bounds.y))

    ed.ctx.fillStyle = rgb(175, 200, 245)
    ed.ctx.fillText("\"", vec2(bounds.x + quoteWidth + textWidth + horizontalGap * 2, bounds.y))

    rect(bounds.x, bounds.y, quoteWidth * 2 + textWidth + horizontalGap * 2, ed.ctx.fontSize)

  of NumberLiteral():
    let r = ed.ctx.fillText(bounds.xy, node.text, rgb(200, 255, 200))
    r

  else:
    rect(0, 0, 0, 0)

  # print selectedNode
  if node == selectedNode:
    ed.ctx.strokeStyle = rgb(255, 0, 255)
    ed.ctx.lineWidth = 2
    ed.ctx.strokeRect(nodeRect.grow(2.absolute))
    ed.ctx.lineWidth = 1

  if node == selectedNode or node.kind == ConstDecl:
    let typ = ctx.computeType(node)
    let val = ctx.computeValue(node)

    var lastRect = ed.ctx.fillText(vec2(nodeRect.x, nodeRect.y + nodeRect.h + padding), $val, rgb(100, 100, 255))
    lastRect = ed.ctx.fillText(vec2(lastRect.xw, lastRect.y), " : ", rgb(200, 200, 200))
    lastRect = ed.ctx.fillText(vec2(lastRect.xw, lastRect.y), $typ, rgb(250, 175, 200))
    # lastRect = ed.ctx.fillText(vec2(lastRect.xw, lastRect.y), fmt"{node.id}", rgb(250, 175, 200))
    nodeRect.h += lastRect.h + padding * 2

    # nodeRect.w = max(nodeRect.w, lastRect.xw - nodeRect.x)

  nodeRect.w = max(nodeRect.w, ed.ctx.measureText(" ").width)
  nodeRect.h = max(nodeRect.h, ed.ctx.fontSize)

  if ctx.computeType(node).kind == tError:
    ed.ctx.strokeStyle = rgb(255, 50, 50)
    ed.ctx.strokeRect(nodeRect)
    nodeRect = nodeRect.grow(1.absolute)

  nodeBounds[node] = nodeRect

  return nodeRect

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
    else:
      discard

proc renderSymbol(symbol: Symbol, editor: AstDocumentEditor, ed: Editor, bounds: Rect, selectedNode: AstNode): Rect =
  var lastNodeRect = bounds

  if symbol.kind == skAstNode and symbol.node == selectedNode:
    ed.ctx.strokeStyle = rgb(0, 255, 0)
  else:
    ed.ctx.strokeStyle = rgb(255, 255, 255)

  ed.ctx.fillText(fmt"{symbol.name} ({symbol.id})", vec2(bounds.x + 500, bounds.y))
  var i = 0.0
  return bounds

method renderDocumentEditor(editor: AstDocumentEditor, ed: Editor, bounds: Rect, selected: bool): Rect =
  let document = editor.document

  let (headerBounds, contentBounds) = bounds.splitH ed.ctx.fontSize.relative

  ed.ctx.fillStyle = if selected: rgb(45, 45, 60) else: rgb(45, 45, 45)
  ed.ctx.fillRect(headerBounds)

  ed.ctx.fillStyle = if selected: rgb(25, 25, 40) else: rgb(25, 25, 25)
  ed.ctx.fillRect(contentBounds)

  ed.ctx.fillStyle = rgb(255, 225, 255)
  ed.ctx.fillText("AST - " & document.filename, vec2(headerBounds.x, headerBounds.y))

  var lastNodeRect = contentBounds
  lastNodeRect.h = padding

  let selectedNode = editor.node

  var nodeBounds: Table[AstNode, Rect] = initTable[AstNode, Rect]()

  for node in document.rootNode.children:
    let y = lastNodeRect.y + lastNodeRect.h - contentBounds.y + padding
    lastNodeRect = renderAstNode(node, editor, ed, contentBounds.splitH(y.relative)[1], selectedNode, nodeBounds)

  if editor.completions.len > 0:
    let bounds = nodeBounds.getOrDefault(editor.node, rect(0, 0, 0, 0))
    if bounds.h > 0:
      discard renderCompletions(editor, ed, contentBounds.splitH((bounds.y + bounds.h).absolute)[1].splitV(bounds.x.absolute)[1])

    let selectedCompletion = editor.completions[editor.selectedCompletion]
    if selectedCompletion.kind == SymbolCompletion and ctx.getSymbol(selectedCompletion.id).getSome(symbol) and symbol.kind == skAstNode and nodeBounds.contains(symbol.node):
      let selectedDeclRect = nodeBounds[symbol.node]
      ed.ctx.strokeStyle = rgb(150, 150, 220)
      ed.ctx.strokeRect(selectedDeclRect)

  elif ctx.getSymbol(selectedNode.id).getSome(symbol) and symbol.kind == skAstNode and nodeBounds.contains(symbol.node):
    let selectedDeclRect = nodeBounds[symbol.node]
    ed.ctx.strokeStyle = rgb(150, 150, 220)
    ed.ctx.strokeRect(selectedDeclRect)

  # for symbol in document.symbols.values:
  #   let y = lastNodeRect.y + lastNodeRect.h - contentBounds.y + padding
  #   lastNodeRect = renderSymbol(symbol, editor, ed, contentBounds.splitH(y.relative)[1], selectedNode)

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