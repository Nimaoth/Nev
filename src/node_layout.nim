import std/[tables, strformat]
import fusion/matching
import bumpy, chroma, vmath, theme
import compiler, ast, util, id, ast_ids
import custom_logger

proc getPrecedenceForNode(ctx: Context, node: AstNode): int =
  if node.kind != Call or node.len == 0:
    return 0
  if ctx.computeSymbol(node[0], false).getSome(symbol):
    case symbol.kind
    of skBuiltin:
      return symbol.precedence
    of skAstNode:
      discard

  return 0

type
  VisualLayoutColorConfig = object
    separator: string
    separatorParen: seq[string]
    separatorBrace: seq[string]
    separatorBracket: seq[string]
    empty: string
    keyword: string
    typ: string

  VisualLayoutConfig* = object
    colors*: VisualLayoutColorConfig
    fontSize: float
    fontRegular: string
    fontBold*: string
    fontItalic*: string
    fontBoldItalic*: string
    indent*: float32
    revision*: int

template createConfigAccessor(member: untyped, typ: type) =
  proc member*(config: var VisualLayoutConfig): typ = config.member
  proc `member=`*(config: var VisualLayoutConfig, newValue: typ) =
    if config.member != newValue:
      config.revision += 1
    config.member = newValue

createConfigAccessor(colors, VisualLayoutColorConfig)
createConfigAccessor(fontSize, float)
createConfigAccessor(fontRegular, string)
createConfigAccessor(fontBold, string)
createConfigAccessor(fontItalic, string)
createConfigAccessor(fontBoldItalic, string)
createConfigAccessor(indent, float32)

var config* =  VisualLayoutConfig(
  fontSize: 20,
  fontRegular: "fonts/DejaVuSansMono.ttf",
  fontBold: "fonts/DejaVuSansMono-Bold.ttf",
  fontItalic: "fonts/DejaVuSansMono-Oblique.ttf",
  fontBoldItalic: "fonts/DejaVuSansMono-BoldOblique.ttf",
  indent: 20,
  colors: VisualLayoutColorConfig(
    separator: "punctuation",
    separatorParen: @["meta.brace.round", "punctuation", "&editor.foreground"],
    separatorBrace: @["meta.brace.curly", "punctuation", "&editor.foreground"],
    separatorBracket: @["meta.brace.square", "punctuation", "&editor.foreground"],
    empty: "string",
    keyword: "keyword",
    typ: "storage.type",
  ),
)

proc getFont*(config: VisualLayoutConfig, style: set[FontStyle]): string =
  if Italic in style and Bold in style:
    return config.fontBoldItalic
  if Italic in style:
    return config.fontItalic
  if Bold in style:
    return config.fontBold
  return config.fontRegular

proc newTextNode*(text: string, color: string, font: string, measureText: proc(text: string): Vec2, node: AstNode = nil): VisualNode =
  result = VisualNode(id: newId(), text: text, colors: @[color], font: font, fontSize: config.fontSize, node: node)
  result.bounds.wh = measureText(text)

proc newTextNode*(text: string, colors: seq[string], font: string, measureText: proc(text: string): Vec2, node: AstNode = nil, styleOverride: Option[set[FontStyle]] = set[FontStyle].none): VisualNode =
  result = VisualNode(id: newId(), text: text, colors: colors, font: font, fontSize: config.fontSize, node: node, styleOverride: styleOverride)
  result.bounds.wh = measureText(text)

proc newBlockNode*(colors: seq[string], size: Vec2, node: AstNode = nil, styleOverride: Option[set[FontStyle]] = set[FontStyle].none): VisualNode =
  result = VisualNode(id: newId(), node: node, styleOverride: styleOverride, background: some(colors))
  result.bounds.wh = size

proc newFunctionNode*(bounds: Rect, render: VisualNodeRenderFunc): VisualNode =
  result = VisualNode(id: newId(), bounds: bounds, render: render)

proc createReplacement(input: NodeLayoutInput, node: AstNode, layout: var NodeLayout, line: var VisualNode): bool =
  if input.replacements.contains(node.id):
    var n = input.replacements[node.id].clone
    n.cloneWidget = false
    layout.nodeToVisualNode[node.id] = line.add n
    return true
  if input.replacements.contains(node.reff):
    var n = input.replacements[node.reff].clone
    n.cloneWidget = true
    layout.nodeToVisualNode[node.id] = line.add n
    return true
  return false

proc getColorForSymbol*(ctx: Context, sym: Symbol): seq[string] =
  let typ = ctx.computeSymbolType(sym, false)
  case typ.kind
  of tError: return @["invalid"]
  of tType: return @["storage.type"]
  of tFunction:
    if sym.kind == skBuiltin:
      case sym.operatorNotation
      of Prefix, Infix, Postfix: return @["keyword.operator"]
      else: return @["variable.function", "variable"]
    return @["variable.function", "variable"]
  elif sym.kind == skAstNode:
    if sym.node.kind == ConstDecl: return @["variable.other.constant", "variable"]
    elif sym.node.kind == VarDecl or sym.node.kind == LetDecl:
      if sym.node.parent.kind == Params: return @["variable.parameter", "variable"]
      else: return @["variable"]
    else: return @["variable.other", "variable"]

  return @["variable.other", "variable"]

proc getStyleForSymbol*(ctx: Context, sym: Symbol): Option[set[FontStyle]] =
  var style: set[FontStyle] = {}
  if sym.kind == skAstNode:
    if sym.node.kind == VarDecl:
      style.incl {Italic}
    if sym.node.kind == ConstDecl:
      let typ = ctx.computeSymbolType(sym, false)
      if typ.kind != tFunction:
        style.incl {Bold}
  elif sym.kind == skBuiltin:
    if sym.operatorNotation == Regular:
      style.incl Underline

  if style != {}:
    result = some(style)

template createInlineBlock(condition: untyped, node: AstNode, line: untyped, output: untyped): untyped =
  var oldLine = line
  var containerLine = VisualNode(id: newId(), node: node, parent: line, orientation: Vertical, depth: line.depth + 1)
  if condition:
    line = VisualNode(id: newId(), parent: containerLine, orientation: Horizontal, depth: containerLine.depth + 1)

  defer:
    if condition:
      containerLine.addLine line
      output.nodeToVisualNode[node.id] = oldLine.add(containerLine)
      line = oldLine

proc createLayoutLineForNode(ctx: Context, input: NodeLayoutInput, node: AstNode, result: var NodeLayout, line: var VisualNode)

proc createLayoutLineForRemainingChildren(ctx: Context, input: NodeLayoutInput, node: AstNode, firstChildIndex: int, result: var NodeLayout, line: var VisualNode) =
  if firstChildIndex >= node.len:
    return

  discard line.add newTextNode("<", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)
  for i in firstChildIndex..<node.len:
    if i > firstChildIndex:
      discard line.add newTextNode(", ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)
    ctx.createLayoutLineForNode(input, node[i], result, line)
  discard line.add newTextNode(">", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)

proc createLayoutLineForNode(ctx: Context, input: NodeLayoutInput, node: AstNode, result: var NodeLayout, line: var VisualNode) =
  let renderInline = node.kind in {While, If, NodeList} and node.parent.kind in {Call} and input.inlineBlocks

  var prevLine = line
  let first = prevLine.children.len
  defer:
    if first < prevLine.children.len:
      result.nodeToVisualNode[node.id] = VisualNodeRange(parent: prevLine, first: first, last: prevLine.children.len)

  createInlineBlock(renderInline, node, line, result)

  # force computation of type so that errors diagnostics can be generated
  discard ctx.computeType(node, false)

  var lastUsedChild = -1
  defer:
    ctx.createLayoutLineForRemainingChildren(input, node, lastUsedChild + 1, result, line)

  case node
  of Empty():
    if not input.createReplacement(node, result, line):
      let bounds = input.measureText(" ")
      result.nodeToVisualNode[node.id] = line.add VisualNode(id: newId(), colors: @[config.colors.empty], node: node, bounds: rect(vec2(), bounds))

  of NumberLiteral():
    if not input.createReplacement(node, result, line):
      result.nodeToVisualNode[node.id] = line.add newTextNode(node.text, "constant.numeric", config.fontRegular, input.measureText, node)

  of StringLiteral():
    discard line.add newTextNode("\"", @["punctuation.definition.string", config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)
    if not input.createReplacement(node, result, line):
      discard line.add newTextNode(node.text, "string", config.fontRegular, input.measureText, node)
    discard line.add newTextNode("\"", @["punctuation.definition.string", config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)

  of Identifier():
    if not input.createReplacement(node, result, line):
      if ctx.computeSymbol(node, false).getSome(sym):
        result.nodeToVisualNode[node.id] = line.add newTextNode(sym.name, ctx.getColorForSymbol(sym), config.fontRegular, input.measureText, node, styleOverride = ctx.getStyleForSymbol(sym))
      else:
        result.nodeToVisualNode[node.id] = line.add newTextNode($node.reff, "variable", config.fontRegular, input.measureText, node)

  of ConstDecl():
    if not input.createReplacement(node, result, line):
      let color = if ctx.computeSymbol(node, false).getSome(sym): ctx.getColorForSymbol(sym)
      else: @["entity.name.constant"]

      if ctx.computeSymbol(node, false).getSome(sym):
        discard line.add newTextNode(sym.name, color, config.fontRegular, input.measureText, node, styleOverride = ctx.getStyleForSymbol(sym))
      else:
        discard line.add newTextNode($node.id, color, config.fontRegular, input.measureText, node)

    let typ = ctx.computeType(node, false)
    if typ.kind == tFunction:
      discard line.add newTextNode(" :: ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)
    else:
      discard line.add newTextNode(" : ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)
      discard line.add newTextNode($typ, config.colors.typ, config.fontRegular, input.measureText)
      discard line.add newTextNode(" : ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)

    if node.len > 0:
      ctx.createLayoutLineForNode(input, node[0], result, line)

      let value = ctx.computeValue(node, false)
      case value.kind
      of vkAstFunction, vkBuiltinFunction, vkVoid: discard
      else:
        case node[0].kind
        of StringLiteral, NumberLiteral: discard
        else:
          discard line.add newTextNode(" = ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)
          discard line.add newTextNode($value, "string", config.fontRegular, input.measureText)

    lastUsedChild = 0

  of LetDecl():
    if not input.createReplacement(node, result, line):
      let (color, style) = if ctx.computeSymbol(node, false).getSome(sym): (ctx.getColorForSymbol(sym), ctx.getStyleForSymbol(sym))
      else: (@["variable"], set[FontStyle].none)

      discard line.add newTextNode(node.text, color, config.fontRegular, input.measureText, node, styleOverride = style)

    discard line.add newTextNode(" : ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)

    if node.len > 0:
      if node[0].kind == Empty and node[0].text.len == 0 and not input.replacements.contains(node[0].id):
        let typ = ctx.computeType(node, false)
        result.nodeToVisualNode[node[0].id] = line.add newTextNode($typ, config.colors.typ, config.fontRegular, input.measureText, node[0])
      else:
        ctx.createLayoutLineForNode(input, node[0], result, line)

    if node.len > 1:
      discard line.add newTextNode(" = ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)
      ctx.createLayoutLineForNode(input, node[1], result, line)

    lastUsedChild = 1

  of VarDecl():
    if not input.createReplacement(node, result, line):
      let (color, style) = if ctx.computeSymbol(node, false).getSome(sym): (ctx.getColorForSymbol(sym), ctx.getStyleForSymbol(sym))
      else: (@["variable"], set[FontStyle].none)

      discard line.add newTextNode(node.text, color, config.fontRegular, input.measureText, node, styleOverride = style)

    discard line.add newTextNode(" : mut ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)

    if node.len > 0:
      if node[0].kind == Empty and node[0].text.len == 0 and not input.replacements.contains(node[0].id):
        let typ = ctx.computeType(node, false)
        result.nodeToVisualNode[node[0].id] = line.add newTextNode($typ, config.colors.typ, config.fontRegular, input.measureText, node[0])
      else:
        ctx.createLayoutLineForNode(input, node[0], result, line)

    if node.len > 1:
      discard line.add newTextNode(" = ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)
      ctx.createLayoutLineForNode(input, node[1], result, line)

    lastUsedChild = 1

  of FunctionDefinition():
    discard line.add newTextNode("fn", config.colors.keyword, config.fontRegular, input.measureText)
    discard line.add newTextNode("(", config.colors.separatorParen, config.fontRegular, input.measureText)

    if node.len > 0:
      var parent = line
      let first = parent.len
      for i, param in node[0].children:
        if i > 0:
          discard line.add newTextNode(", ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)

        ctx.createLayoutLineForNode(input, param, result, line)

      if node[0].len == 0:
        result.nodeToVisualNode[node[0].id] = line.add newTextNode(" ", config.colors.empty, config.fontRegular, input.measureText, node[0])
      else:
        result.nodeToVisualNode[node[0].id] = VisualNodeRange(parent: parent, first: first, last: parent.len)


    discard line.add newTextNode(") ", config.colors.separatorParen, config.fontRegular, input.measureText)

    if node.len > 1:
      ctx.createLayoutLineForNode(input, node[1], result, line)

    discard line.add newTextNode(" = ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)

    if node.len > 2:
      ctx.createLayoutLineForNode(input, node[2], result, line)

    lastUsedChild = 2

  of If():
    var parent = line.parent
    let prevIndent = line.indent

    let first = parent.children.len
    defer:
      if first < parent.children.len:
        result.nodeToVisualNode[node.id] = VisualNodeRange(parent: parent, first: first, last: parent.children.len)

    var i = 0
    while i + 1 < node.len:
      defer: i += 2

      if i == 0:
        discard line.add newTextNode("if ", config.colors.keyword, config.fontRegular, input.measureText)
      else:
        parent.addLine(line)
        line = VisualNode(id: newId(), parent: parent, bounds: rect(prevIndent.float32 * input.indent, 0, 0, 0), indent: prevIndent, depth: parent.depth + 1)
        discard line.add newTextNode("elif ", config.colors.keyword, config.fontRegular, input.measureText)

      ctx.createLayoutLineForNode(input, node[i], result, line)
      discard line.add newTextNode(": ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)

      ctx.createLayoutLineForNode(input, node[i + 1], result, line)

    if node.len mod 2 == 1:
      parent.addLine(line)
      line = VisualNode(id: newId(), parent: parent, bounds: rect(prevIndent.float32 * input.indent, 0, 0, 0), indent: prevIndent, depth: parent.depth + 1)
      discard line.add newTextNode("else: ", config.colors.keyword, config.fontRegular, input.measureText)
      ctx.createLayoutLineForNode(input, node.last, result, line)

    parent.addLine(line)
    line = VisualNode(id: newId(), parent: parent, bounds: rect(prevIndent.float32 * input.indent, 0, 0, 0), indent: prevIndent, depth: parent.depth + 1)

    lastUsedChild = node.len - 1

  of While():
    discard line.add newTextNode("while ", config.colors.keyword, config.fontRegular, input.measureText)

    if node.len >= 1:
      ctx.createLayoutLineForNode(input, node[0], result, line)

    discard line.add newTextNode(": ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)

    if node.len >= 2:
      ctx.createLayoutLineForNode(input, node[1], result, line)

    lastUsedChild = 1

  of NodeList():
    var parent = line.parent
    let first = parent.children.len + 1
    defer:
      if first < parent.children.len:
        result.nodeToVisualNode[node.id] = VisualNodeRange(parent: parent, first: first, last: parent.children.len)

    let prevIndent = line.indent
    for child in node.children:
      parent.addLine(line)
      line = VisualNode(id: newId(), parent: parent, bounds: rect(prevIndent.float32 * input.indent, 0, input.indent, 0), indent: prevIndent + 1, node: child, depth: parent.depth + 1)
      ctx.createLayoutLineForNode(input, child, result, line)

    parent.addLine(line)
    line = VisualNode(id: newId(), parent: parent, bounds: rect(prevIndent.float32 * input.indent, 0, 0, 0), indent: prevIndent, depth: parent.depth + 1)

    lastUsedChild = node.len - 1

  of Assignment():
    if node.len > 0:
      ctx.createLayoutLineForNode(input, node[0], result, line)
    discard line.add newTextNode(" = ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)
    if node.len > 0:
      ctx.createLayoutLineForNode(input, node[1], result, line)

    lastUsedChild = 1

  of Call():
    if node.len == 0:
      result.nodeToVisualNode[node.id] = line.add newTextNode("<empty function call>", config.colors.empty, config.fontRegular, input.measureText, node)
      return

    var isDivision = false

    let operatorNotation = if ctx.computeSymbol(node[0], false).getSome(sym) and sym.kind == skBuiltin:
      if sym.id == IdDiv:
        isDivision = true
      let arity = case sym.operatorNotation
      of Infix: 2
      of Prefix, Postfix: 1
      else: -1

      if node.len == arity + 1:
        sym.operatorNotation
      else:
        Regular
    else:
      Regular

    case operatorNotation
    of Infix:
      let parentPrecedence = ctx.getPrecedenceForNode node.parent
      let precedence = ctx.getPrecedenceForNode node
      let renderParens = precedence < parentPrecedence

      if isDivision and input.renderDivisionVertically and input.inlineBlocks:
        createInlineBlock(true, node, line, result)

        var parent = line.parent
        let prevIndent = line.indent

        let first = parent.children.len
        defer:
          if first < parent.children.len:
            result.nodeToVisualNode[node.id] = VisualNodeRange(parent: parent, first: first, last: parent.children.len)

        ctx.createLayoutLineForNode(input, node[1], result, line)
        parent.addLine(line)
        let line1 = line
        line = VisualNode(id: newId(), parent: parent, bounds: rect(prevIndent.float32 * input.indent, 0, 0, 0), indent: prevIndent, depth: parent.depth + 1)

        let fontSize = input.measureText(" ").y
        let divLine = newBlockNode(@["keyword.operator"], vec2(0, fontSize * 0.1), node[0])
        discard line.add divLine
        result.nodeToVisualNode[node[0].id] = VisualNodeRange(parent: line, first: 0, last: 1)
        parent.addLine(line)
        line = VisualNode(id: newId(), parent: parent, bounds: rect(prevIndent.float32 * input.indent, 0, 0, 0), indent: prevIndent, depth: parent.depth + 1)

        ctx.createLayoutLineForNode(input, node[2], result, line)
        parent.addLine(line)
        let line2 = line
        line = VisualNode(id: newId(), parent: parent, bounds: rect(prevIndent.float32 * input.indent, 0, 0, 0), indent: prevIndent, depth: parent.depth + 1)

        divLine.bounds.w = max(line1.bounds.w, line2.bounds.w)
        divLine.parent.bounds.w = divLine.bounds.w

        var shorterLine = line1
        var longerLine = line2
        if shorterLine.bounds.w > longerLine.bounds.w:
          shorterLine = line2
          longerLine = line1

        let lengthDiff = longerLine.bounds.w - shorterLine.bounds.w
        shorterLine.bounds.x += lengthDiff / 2

        lastUsedChild = 2

      else:
        if renderParens:
          discard line.add newTextNode("(", config.colors.separatorParen, config.fontRegular, input.measureText)

        ctx.createLayoutLineForNode(input, node[1], result, line)
        discard line.add newTextNode(" ", config.colors.separator, config.fontRegular, input.measureText)
        ctx.createLayoutLineForNode(input, node[0], result, line)
        discard line.add newTextNode(" ", config.colors.separator, config.fontRegular, input.measureText)
        ctx.createLayoutLineForNode(input, node[2], result, line)

        if renderParens:
          discard line.add newTextNode(")", config.colors.separatorParen, config.fontRegular, input.measureText)

        lastUsedChild = 2

    of Prefix:
      ctx.createLayoutLineForNode(input, node[0], result, line)
      ctx.createLayoutLineForNode(input, node[1], result, line)
      lastUsedChild = 1
    of Postfix:
      ctx.createLayoutLineForNode(input, node[1], result, line)
      ctx.createLayoutLineForNode(input, node[0], result, line)
      lastUsedChild = 1

    else:
      if node.len > 0:
        ctx.createLayoutLineForNode(input, node[0], result, line)

      discard line.add newTextNode("(", config.colors.separatorParen, config.fontRegular, input.measureText)

      for i in 1..<node.len:
        if i > 1:
          discard line.add newTextNode(", ", @[config.colors.separator, "&editor.foreground"], config.fontRegular, input.measureText)
        ctx.createLayoutLineForNode(input, node[i], result, line)

      discard line.add newTextNode(")", config.colors.separatorParen, config.fontRegular, input.measureText)

      lastUsedChild = node.len - 1

  else:
    log(lvlError, fmt"createLayoutLineForNode not implemented for {node.kind}")

proc centerChildrenVertically(vnode: VisualNode) =
  let height = vnode.bounds.h
  for child in vnode.children:
    if vnode.orientation == Horizontal:
      let heightDiff = height - child.bounds.h
      child.bounds.y += heightDiff * 0.5
    child.centerChildrenVertically()

proc computeNodeLayoutImpl2*(ctx: Context, input: NodeLayoutInput): NodeLayout =
  # log(lvlInfo, fmt"computeNodeLayoutImpl2 {input.node}")
  let node = input.node
  result = NodeLayout(node: node, root: VisualNode(id: newId(), orientation: Vertical), nodeToVisualNode: initTable[Id, VisualNodeRange]())
  var line = VisualNode(id: newId(), node: node, parent: result.root, orientation: Horizontal, depth: result.root.depth + 1)
  ctx.createLayoutLineForNode(input, node, result, line)
  line.parent.addLine(line)

  # Go through all visual nodes and center stuff vertically
  result.root.centerChildrenVertically()

