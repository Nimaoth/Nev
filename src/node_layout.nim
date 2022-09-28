import std/[tables]
import fusion/matching
import pixie/fonts, bumpy, chroma, vmath
import compiler, ast, util, id, rect_utils

proc measureText*(font: Font, text: string): Vec2 = font.typeset(text).layoutBounds()

proc newFont*(typeface: Typeface, fontSize: float32): Font {.raises: [].} =
  result = newFont(typeface)
  result.size = fontSize

proc getPrecedenceForNode(ctx: Context, node: AstNode): int =
  if node.kind != Call or node.len == 0:
    return 0
  if ctx.computeSymbol(node[0]).getSome(symbol):
    case symbol.kind
    of skBuiltin:
      return symbol.precedence
    of skAstNode:
      discard

  return 0

type
  VisualLayoutColorConfig = object
    constDecl: Color
    letDecl: Color
    varDecl: Color
    separator: Color
    numberLiteral: Color
    stringLiteral: Color
    empty: Color
    identifier: Color
    keyword: Color
    typ: Color
    value: Color

  VisualLayoutConfig* = object
    colors*: VisualLayoutColorConfig
    font*: Font
    indent*: float32

let config* =  VisualLayoutConfig(
  font: newFont(readTypeface("fonts/FiraCode-Regular.ttf"), 20),
  indent: 15,
  colors: VisualLayoutColorConfig(
    constDecl: rgb(175, 255, 175).color,
    letDecl: rgb(200, 255, 175).color,
    varDecl: rgb(175, 255, 200).color,
    separator: rgb(175, 175, 175).color,
    numberLiteral: rgb(255, 175, 175).color,
    stringLiteral: rgb(175, 255, 255).color,
    empty: rgb(255, 100, 100).color,
    identifier: rgb(255, 175, 255).color,
    keyword: rgb(255, 255, 255).color,
    typ: rgb(175, 175, 255).color,
    value: rgb(175, 200, 255).color,
  ),
)

proc newTextNode*(text: string, color: Color, font: Font, node: AstNode = nil): VisualNode =
  result = VisualNode(text: text, color: color, font: font, node: node)
  result.bounds.wh = font.measureText(text)

proc createReplacement(input: NodeLayoutInput, node: AstNode, layout: var NodeLayout, line: var VisualNode): bool =
  if input.replacements.contains(node.id):
    layout.nodeToVisualNode[node.id] = line.add input.replacements[node.id].clone
    return true
  if input.replacements.contains(node.reff):
    layout.nodeToVisualNode[node.id] = line.add input.replacements[node.reff].clone
    return true
  return false

proc createLayoutLineForNode(ctx: Context, input: NodeLayoutInput, node: AstNode, result: var NodeLayout, line: var VisualNode) =
  let renderInline = node.kind in {If, NodeList} and node.parent.kind in {Call}

  var prevLine = line
  let first = prevLine.children.len
  defer:
    if first < prevLine.children.len:
      result.nodeToVisualNode[node.id] = VisualNodeRange(parent: prevLine, first: first, last: prevLine.children.len)

  var oldLine = line
  var containerLine = VisualNode(node: node, parent: line)
  if renderInline:
    line = VisualNode(parent: containerLine)

  defer:
    if renderInline:
      containerLine.addLine line
      result.nodeToVisualNode[node.id] = oldLine.add(containerLine)
      line = oldLine

  case node
  of Empty():
    if not input.createReplacement(node, result, line):
      result.nodeToVisualNode[node.id] = line.add VisualNode(color: config.colors.empty, node: node, bounds: rect(vec2(), vec2(config.font.size * 0.5, config.font.size)))

  of NumberLiteral():
    if not input.createReplacement(node, result, line):
      result.nodeToVisualNode[node.id] = line.add newTextNode(node.text, config.colors.numberLiteral, config.font, node)

  of StringLiteral():
    discard line.add newTextNode("\"", config.colors.separator, config.font)
    if not input.createReplacement(node, result, line):
      discard line.add newTextNode(node.text, config.colors.stringLiteral, config.font, node)
    discard line.add newTextNode("\"", config.colors.separator, config.font)

  of Identifier():
    if not input.createReplacement(node, result, line):
      if ctx.computeSymbol(node).getSome(sym):
        result.nodeToVisualNode[node.id] = line.add newTextNode(sym.name, config.colors.identifier, config.font, node)
      else:
        result.nodeToVisualNode[node.id] = line.add newTextNode($node.reff, config.colors.identifier, config.font, node)

  of ConstDecl():
    if not input.createReplacement(node, result, line):
      if ctx.computeSymbol(node).getSome(sym):
        discard line.add newTextNode(sym.name, config.colors.constDecl, config.font, node)
      else:
        discard line.add newTextNode($node.id, config.colors.constDecl, config.font, node)

    let typ = ctx.computeType(node)
    if typ.kind == tFunction:
      discard line.add newTextNode(" :: ", config.colors.separator, config.font)
    else:
      discard line.add newTextNode(" : ", config.colors.separator, config.font)
      discard line.add newTextNode($typ, config.colors.typ, config.font)
      discard line.add newTextNode(" : ", config.colors.separator, config.font)

    if node.len > 0:
      ctx.createLayoutLineForNode(input, node[0], result, line)

      let value = ctx.computeValue(node)
      case value.kind
      of vkAstFunction, vkBuiltinFunction, vkVoid: discard
      else:
        case node[0].kind
        of StringLiteral, NumberLiteral: discard
        else:
          discard line.add newTextNode(" = ", config.colors.separator, config.font)
          discard line.add newTextNode($value, config.colors.value, config.font)

  of LetDecl():
    if not input.createReplacement(node, result, line):
      if ctx.computeSymbol(node).getSome(sym):
        discard line.add newTextNode(sym.name, config.colors.letDecl, config.font, node)
      else:
        discard line.add newTextNode($node.id, config.colors.letDecl, config.font, node)

    discard line.add newTextNode(" : ", config.colors.separator, config.font)

    if node.len > 0:
      if node[0].kind == Empty and node[0].text.len == 0:
        let typ = ctx.computeType(node)
        result.nodeToVisualNode[node[0].id] = line.add newTextNode($typ, config.colors.typ, config.font, node[0])
      else:
        ctx.createLayoutLineForNode(input, node[0], result, line)

    discard line.add newTextNode(" = ", config.colors.separator, config.font)

    if node.len > 1:
      ctx.createLayoutLineForNode(input, node[1], result, line)

  of VarDecl():
    if not input.createReplacement(node, result, line):
      if ctx.computeSymbol(node).getSome(sym):
        discard line.add newTextNode(sym.name, config.colors.varDecl, config.font, node)
      else:
        discard line.add newTextNode($node.id, config.colors.varDecl, config.font, node)

    discard line.add newTextNode(" : mut ", config.colors.separator, config.font)

    if node.len > 0:
      if node[0].kind == Empty and node[0].text.len == 0:
        let typ = ctx.computeType(node)
        result.nodeToVisualNode[node[0].id] = line.add newTextNode($typ, config.colors.typ, config.font, node[0])
      else:
        ctx.createLayoutLineForNode(input, node[0], result, line)

    discard line.add newTextNode(" = ", config.colors.separator, config.font)

    if node.len > 1:
      ctx.createLayoutLineForNode(input, node[1], result, line)

  of FunctionDefinition():
    discard line.add newTextNode("fn", config.colors.keyword, config.font)
    discard line.add newTextNode("(", config.colors.separator, config.font)

    if node.len > 0:
      for i, param in node[0].children:
        if i > 0:
          discard line.add newTextNode(", ", config.colors.separator, config.font)

        ctx.createLayoutLineForNode(input, param, result, line)

      if node[0].len == 0:
        result.nodeToVisualNode[node[0].id] = line.add newTextNode(" ", config.colors.empty, config.font, node[0])

    discard line.add newTextNode(") ", config.colors.separator, config.font)

    if node.len > 1:
      ctx.createLayoutLineForNode(input, node[1], result, line)

    discard line.add newTextNode(" = ", config.colors.separator, config.font)

    if node.len > 2:
      ctx.createLayoutLineForNode(input, node[2], result, line)

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
        discard line.add newTextNode("if ", config.colors.keyword, config.font)
      else:
        parent.addLine(line)
        line = VisualNode(parent: parent, bounds: rect(prevIndent, 0, 0, 0), indent: prevIndent)
        discard line.add newTextNode("elif ", config.colors.keyword, config.font)

      ctx.createLayoutLineForNode(input, node[i], result, line)
      discard line.add newTextNode(": ", config.colors.separator, config.font)

      ctx.createLayoutLineForNode(input, node[i + 1], result, line)

    if node.len mod 2 == 1:
      parent.addLine(line)
      line = VisualNode(parent: parent, bounds: rect(prevIndent, 0, 0, 0), indent: prevIndent)
      discard line.add newTextNode("else: ", config.colors.keyword, config.font)
      ctx.createLayoutLineForNode(input, node.last, result, line)

    parent.addLine(line)
    line = VisualNode(parent: parent, bounds: rect(prevIndent, 0, 0, 0), indent: prevIndent)

  of NodeList():
    var parent = line.parent
    let first = parent.children.len + 1
    defer:
      if first < parent.children.len:
        result.nodeToVisualNode[node.id] = VisualNodeRange(parent: parent, first: first, last: parent.children.len)

    let prevIndent = line.indent
    for child in node.children:
      parent.addLine(line)
      line = VisualNode(parent: parent, bounds: rect(prevIndent, 0, config.indent, 0), indent: prevIndent + config.indent)
      let first = parent.children.len
      ctx.createLayoutLineForNode(input, child, result, line)

    parent.addLine(line)
    line = VisualNode(parent: parent, bounds: rect(prevIndent, 0, 0, 0), indent: prevIndent)

  of Assignment():
    if node.len > 0:
      ctx.createLayoutLineForNode(input, node[0], result, line)
    discard line.add newTextNode(" = ", config.colors.separator, config.font)
    if node.len > 0:
      ctx.createLayoutLineForNode(input, node[1], result, line)

  of Call():
    if node.len == 0:
      result.nodeToVisualNode[node.id] = line.add newTextNode("<empty function call>", config.colors.empty, config.font, node)
      return

    let operatorNotation = if ctx.computeSymbol(node[0]).getSome(sym) and sym.kind == skBuiltin:
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

      if renderParens:
        discard line.add newTextNode("(", config.colors.separator, config.font)

      ctx.createLayoutLineForNode(input, node[1], result, line)
      discard line.add newTextNode(" ", config.colors.separator, config.font)
      ctx.createLayoutLineForNode(input, node[0], result, line)
      discard line.add newTextNode(" ", config.colors.separator, config.font)
      ctx.createLayoutLineForNode(input, node[2], result, line)

      if renderParens:
        discard line.add newTextNode(")", config.colors.separator, config.font)

    of Prefix:
      ctx.createLayoutLineForNode(input, node[0], result, line)
      ctx.createLayoutLineForNode(input, node[1], result, line)
    of Postfix:
      ctx.createLayoutLineForNode(input, node[1], result, line)
      ctx.createLayoutLineForNode(input, node[0], result, line)

    else:
      if node.len > 0:
        ctx.createLayoutLineForNode(input, node[0], result, line)

      discard line.add newTextNode("(", config.colors.separator, config.font)

      for i in 1..<node.len:
        if i > 1:
          discard line.add newTextNode(", ", config.colors.separator, config.font)
        ctx.createLayoutLineForNode(input, node[i], result, line)

      discard line.add newTextNode(")", config.colors.separator, config.font)

  else:
    echo "createLayoutLineForNode not implemented for ", node.kind

proc computeNodeLayoutImpl2*(ctx: Context, input: NodeLayoutInput): NodeLayout =
  let node = input.node
  result = NodeLayout(root: VisualNode(), nodeToVisualNode: initTable[Id, VisualNodeRange]())
  var line = VisualNode(node: node, parent: result.root)
  ctx.createLayoutLineForNode(input, node, result, line)
  line.parent.addLine(line)

