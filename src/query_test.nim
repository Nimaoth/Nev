import std/[tables, sets, strutils, hashes, options, macros]
import sugar
import system
import print
import fusion/matching
import ast, id, util

{.experimental: "dynamicBindSym".}

var currentIndent = 0

let IdAdd = newId()

type Type* = enum
  Error
  String
  Int

type
  ValueKind = enum ValueError, Number, VKString
  Value = object
    case kind: ValueKind
    of ValueError: discard
    of Number: intValue: int
    of VKString: stringValue: string

func errorValue(): Value = Value(kind: ValueError)

proc `$`(value: Value): string =
  case value.kind
  of Number: return $value.intValue
  of VKString: return value.stringValue
  else: return "<ValueError>"

proc hash(value: Value): Hash =
  case value.kind
  of Number: return value.intValue.hash
  of VKString: return value.stringValue.hash
  else: return 0

type
  Fingerprint = seq[int64]

  KeyKind = enum Ast
  Key = tuple[node: AstNode, update: proc(node: AstNode): Fingerprint]

  NodeColor = enum Grey, Red, Green

  DependencyGraph = ref object
    colors: Table[Key, NodeColor]
    verified: Table[Key, int]
    changed: Table[Key, int]
    fingerprints: Table[Key, Fingerprint]
    dependencies: Table[Key, seq[Key]]
    revision: int

proc newDependencyGraph(): DependencyGraph =
  new result
  result.revision = 0

proc fingerprint(typ: Type, res: var Fingerprint) =
  res.add(typ.hash)

proc fingerprint(typ: Type): Fingerprint =
  result = @[]
  typ.fingerprint(result)

proc fingerprint(value: Value): Fingerprint =
  result = @[cast[int64](value.kind), value.hash]

proc nodeColor(graph: DependencyGraph, key: Key): NodeColor =
  # return graph.colors.getOrDefault(key, Grey)
  let verified = graph.verified.getOrDefault(key, 0)
  if verified != graph.revision:
    return Grey

  let changed = graph.changed.getOrDefault(key, 0)
  if changed == graph.revision:
    return Red

  return Green

proc getDependencies(graph: DependencyGraph, key: Key): seq[Key] =
  return graph.dependencies.getOrDefault(key, @[])

proc clearEdges(graph: DependencyGraph, key: Key) =
  graph.dependencies[key] = @[]

proc setDependencies(graph: DependencyGraph, key: Key, deps: seq[Key]) =
  graph.dependencies[key] = deps

proc fingerprint(graph: DependencyGraph, key: Key): Fingerprint =
  if graph.fingerprints.contains(key):
    return graph.fingerprints[key]

proc markGreen(graph: DependencyGraph, key: Key) =
  graph.colors[key] = Green
  graph.verified[key] = graph.revision

proc markRed(graph: DependencyGraph, key: Key, fingerprint: Fingerprint) =
  graph.colors[key] = Red
  graph.verified[key] = graph.revision
  graph.changed[key] = graph.revision
  graph.fingerprints[key] = fingerprint

template query(name: string) {.pragma.}

macro CreateContext(contextName: untyped, body: untyped): untyped =
  proc queryName(query: NimNode): NimNode = query[4][0][1]
  proc queryFunctionName(query: NimNode): NimNode = query[0]
  proc queryArgType(query: NimNode): NimNode = query[3][2][1]
  proc queryValueType(query: NimNode): NimNode = query[3][0]

  let memberList = nnkRecList.newTree(
    nnkIdentDefs.newTree(
      newIdentNode("inputChanged"),
      quote do: Table[AstNode, int],
      newEmptyNode()
    ),
    nnkIdentDefs.newTree(
      newIdentNode("depGraph"),
      quote do: DependencyGraph,
      newEmptyNode()
    ),
    nnkIdentDefs.newTree(
      newIdentNode("dependencyStack"),
      quote do: seq[seq[Key]],
      newEmptyNode()
    )
  )

  for query in body:
    let name = queryName query
    let key = queryArgType query
    let value = queryValueType query

    memberList.add nnkIdentDefs.newTree(
      ident("queryCache" & name.strVal),
      quote do: Table[`key`, `value`],
      newEmptyNode()
    )
    memberList.add nnkIdentDefs.newTree(
      ident("update" & name.strVal),
      quote do: (proc(arg: `key`): Fingerprint),
      newEmptyNode()
    )

  let newContextFnName = ident "new" & contextName.strVal

  result = nnkStmtList.newTree(
    nnkTypeSection.newTree(
      nnkTypeDef.newTree(
        contextName,
        newEmptyNode(),
        nnkRefTy.newTree(
          nnkObjectTy.newTree(
            newEmptyNode(),
            newEmptyNode(),
            memberList
          )
        )
      )
    )
  )

  var queryInitializers: seq[NimNode] = @[]

  var ctx = genSym(nskVar, "ctx")

  var newContextFn = quote do:
    proc `newContextFnName`(): `contextName` =
      var `ctx`: `contextName`
      new `ctx`
      `ctx`.depGraph = newDependencyGraph()
      `ctx`.dependencyStack = @[]

  for query in body:
    let name = queryName query
    let key = bindSym queryArgType query
    let value = bindSym queryValueType query
    
    let updateName = ident "update" & name.strVal
    let queryCache = ident "queryCache" & name.strVal
    let queryFunction = queryFunctionName query
    let forceFunction = ident "force" & name.strVal

    result.add query.copy

    queryInitializers.add quote do:
      `ctx`.`updateName` = proc (arg: `key`): Fingerprint =
        let value: `value` = `queryFunction`(`ctx`, arg)
        `ctx`.`queryCache`[arg] = value
        return value.fingerprint

  result.add quote do:
    proc force(ctx: `contextName`, key: Key) =
      inc currentIndent, 1
      defer: dec currentIndent, 1
      echo repeat("| ", currentIndent - 1), "force ", key.node

      ctx.depGraph.clearEdges(key)
      ctx.dependencyStack.add(@[])

      let fingerprint = key.update(key.node)

      ctx.depGraph.setDependencies(key, ctx.dependencyStack.pop)

      let prevFingerprint = ctx.depGraph.fingerprint(key)

      if fingerprint == prevFingerprint:
        echo repeat("| ", currentIndent - 1), "force ", key.node, ", mark green"
        ctx.depGraph.markGreen(key)
      else:
        echo repeat("| ", currentIndent - 1), "force ", key.node, ", mark red"
        ctx.depGraph.markRed(key, fingerprint)

  result.add quote do:
      proc tryMarkGreen(ctx: `contextName`, key: Key): bool =
        inc currentIndent, 1
        defer: dec currentIndent, 1

        let inputChangedRevision = ctx.inputChanged.getOrDefault(key.node, ctx.depGraph.revision)
        let verified = ctx.depGraph.verified.getOrDefault(key, 0)

        if inputChangedRevision > verified:
          # Input changed after this current query got verified
          echo repeat("| ", currentIndent - 1), "tryMarkGreen ", key, ", input changed"
          return false

        echo repeat("| ", currentIndent - 1), "tryMarkGreen ", key, ", deps: ", ctx.depGraph.getDependencies(key)

        for i, dep in ctx.depGraph.getDependencies(key):
          echo repeat("| ", currentIndent - 1), dep, ": ", ctx.depGraph.nodeColor(dep)
          case ctx.depGraph.nodeColor(dep)
          of Green:
            discard
          of Red:
            return false
          of Grey:
            if not ctx.tryMarkGreen(dep):
              echo repeat("| ", currentIndent - 1), "tryMarkGreen ", dep.node, ", mark green failed"
              ctx.force(dep)

              if ctx.depGraph.nodeColor(dep) == Red:
                return false

        echo repeat("| ", currentIndent - 1), "tryMarkGreen ", key, ", mark green"
        ctx.depGraph.markGreen(key)

        return true

  for query in body:
    let name = queryName query
    let key = bindSym queryArgType query
    let value = bindSym queryValueType query

    let updateName = ident "update" & name.strVal
    let computeName = ident "compute" & name.strVal
    let queryCache = ident "queryCache" & name.strVal
    let queryFunction = queryFunctionName query
    let forceFunction = ident "force" & name.strVal

    let nameString = name.strVal

    result.add quote do:
        proc `computeName`(ctx: `contextName`, node: AstNode): `value` =
          let key = (node, ctx.`updateName`)

          if ctx.dependencyStack.len > 0:
            ctx.dependencyStack[ctx.dependencyStack.high].add (node, ctx.`updateName`)

          let color = ctx.depGraph.nodeColor(key)

          inc currentIndent, 1
          defer: dec currentIndent, 1
          echo repeat("| ", currentIndent - 1), "compute", `nameString`, " ", color, ", ", node

          if color == Green:
            if not ctx.`queryCache`.contains(node):
              ctx.force(key)
            echo repeat("| ", currentIndent), "green, use cache: ", ctx.`queryCache`[node]
            return ctx.`queryCache`[node]

          if color == Grey:
            if ctx.`queryCache`.contains(node) and ctx.tryMarkGreen(key):
              echo repeat("| ", currentIndent), "grey, use cache: ", ctx.`queryCache`[node]
              return ctx.`queryCache`[node]
            else:
              ctx.force(key)
              echo repeat("| ", currentIndent), "grey, use cache: ", ctx.`queryCache`[node]
              return ctx.`queryCache`[node]

          assert color == Red
          echo repeat("| ", currentIndent), "red, use cache: ", ctx.`queryCache`[node]
          return ctx.`queryCache`[node]

  for queryInitializer in queryInitializers:
    newContextFn[6].add queryInitializer

  newContextFn[6].add quote do: return `ctx`

  result.add newContextFn

  echo result.repr

CreateContext Context:
  proc computeTypeImpl(ctx: Context, node: AstNode): Type {.query("Type").}
  proc computeValueImpl(ctx: Context, node: AstNode): Value {.query("Value").}

let customIndentation = "| "

proc customIndent(count: int): string =
  return repeat(customIndentation, count)

proc `$`(graph: DependencyGraph): string =
  result = "Dependency Graph\n"
  result.add indent("revision: " & $graph.revision, 1, customIndentation) & "\n"

  result.add indent("colors:", 1, customIndentation) & "\n"
  for (key, value) in graph.colors.pairs:
    result.add indent($key & " -> " & $value, 2, customIndentation) & "\n"

  result.add indent("verified:", 1, customIndentation) & "\n"
  for (key, value) in graph.verified.pairs:
    result.add indent($key & " -> " & $value, 2, customIndentation) & "\n"

  result.add indent("changed:", 1, customIndentation) & "\n"
  for (key, value) in graph.changed.pairs:
    result.add indent($key & " -> " & $value, 2, customIndentation) & "\n"

  result.add indent("fingerprints:", 1, customIndentation) & "\n"
  for (key, value) in graph.fingerprints.pairs:
    result.add indent($key & " -> " & $value, 2, customIndentation) & "\n"

  result.add indent("dependencies:", 1, customIndentation) & "\n"
  for (key, value) in graph.dependencies.pairs:
    result.add indent($key & " -> " & $value, 2, customIndentation) & "\n"

proc `$`(ctx: Context): string =
  result = "Context\n"

  result.add customIndent(1) & "Cache\n"
  for (key, value) in ctx.queryCacheType.pairs:
    result.add customIndent(2) & $key & " -> " & $value & "\n"

  result.add customIndent(1) & "Input Changed\n"
  for (key, value) in ctx.inputChanged.pairs:
    result.add customIndent(2) & $key & " -> " & $value & "\n"

  result.add indent($ctx.depGraph, 1, customIndentation)

proc computeTypeImpl(ctx: Context, node: AstNode): Type =
  inc currentIndent, 1
  defer: dec currentIndent, 1
  echo repeat("| ", currentIndent - 1), "computeTypeImpl ", node
  
  case node
  of NumberLiteral():
    return Int

  of StringLiteral():
    return String

  of Call():
    let function = node[0]

    if function.id != IdAdd:
      return Error
    if node.len != 3:
      return Error

    let left = node[1]
    let right = node[2]

    let leftType = ctx.computeType(left)
    let rightType = ctx.computeType(right)

    if leftType == Int and rightType == Int:
      return Int

    if leftType == String:
      return String

    return Error

  else:
    return Error

proc computeValueImpl(ctx: Context, node: AstNode): Value =
  inc currentIndent, 1
  defer: dec currentIndent, 1
  echo repeat("| ", currentIndent - 1), "computeValueImpl ", node
  
  case node
  of NumberLiteral():
    return Value(kind: Number, intValue: node.text.parseInt)

  of StringLiteral():
    return Value(kind: VKString, stringValue: node.text)

  of Call():
    let function = node[0]

    if function.id != IdAdd:
      return errorValue()
    if node.len != 3:
      return errorValue()

    let left = node[1]
    let right = node[2]

    let leftType = ctx.computeType(left)
    let rightType = ctx.computeType(right)

    let leftValue = ctx.computeValue(left)
    let rightValue = ctx.computeValue(right)

    if leftType == Int and rightType == Int:
      if leftValue.kind != Number or rightValue.kind != Number:
        return errorValue()
      let newValue = leftValue.intValue + rightValue.intValue
      return Value(kind: Number, intValue: newValue)

    if leftType == String:
      if leftValue.kind != VKString:
        return errorValue()
      let rightValueString = $rightValue
      let newValue = leftValue.stringValue & rightValueString
      return Value(kind: VKString, stringValue: newValue)

    return errorValue()

  else:
    return errorValue()

iterator nextPreOrder*(node: AstNode): tuple[key: int, value: AstNode] =
  var n = node
  var idx = -1
  var i = 0

  while true:
    defer: inc i
    if idx == -1:
      yield (i, n)
    if idx + 1 < n.len:
      n = n[idx + 1]
      idx = -1
    elif n.next.getSome(ne):
      n = ne
      idx = -1
    elif n.parent != nil and n.parent != node:
      idx = n.index
      n = n.parent
    else:
      break

proc insertNode(ctx: Context, node: AstNode) =
  ctx.depGraph.revision += 1
  ctx.inputChanged[node] = ctx.depGraph.revision
  for (key, child) in node.nextPreOrder:
    ctx.inputChanged[child] = ctx.depGraph.revision

proc updateNode(ctx: Context, node: AstNode) =
  ctx.depGraph.revision += 1
  ctx.inputChanged[node] = ctx.depGraph.revision

proc replaceNode(ctx: Context, node: AstNode, newNode: AstNode) =
  ctx.inputChanged.del(node)

  for key in ctx.depGraph.dependencies.keys:
    for i, dep in ctx.depGraph.dependencies[key]:
      if dep.node == node:
        ctx.depGraph.dependencies[key][i].node = newNode

  ctx.insertNode(newNode)

let node = makeTree(AstNode):
  # Declaration(id: == newId(), text: "foo"):
  Call():
    Identifier(id: == IdAdd)
    Call():
      Identifier(id: == IdAdd)
      NumberLiteral(text: "1")
      NumberLiteral(text: "2")
    NumberLiteral(text: "3")

let ctx = newContext()


echo "\n\n ============================= Insert node =================================\n\n"
echo ctx, "\n--------------------------------------"
ctx.insertNode(node)
echo ctx, "\n--------------------------------------"

echo "\n\n ============================= Compute Type 1 =================================\n\n"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"
echo ctx, "\n--------------------------------------"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"

# echo "\n\n ============================= Update Node 2 =================================\n\n"
# var newNode = makeTree(AstNode): StringLiteral(text: "lol")
# ctx.replaceNode(node[1][1], newNode)
# node[1][1] = newNode
# echo ctx, "\n--------------------------------------"

# echo "\n\n ============================= Compute Type 3 =================================\n\n"
# echo ctx.computeType(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
# echo ctx.computeType(node), "\n--------------------------------------"

# echo "\n\n ============================= Update Node 4 =================================\n\n"
# newNode = makeTree(AstNode): StringLiteral(text: "bar")
# ctx.replaceNode(node[1][2], newNode)
# node[1][2] = newNode
# echo ctx, "\n--------------------------------------"

# echo "\n\n ============================= Compute Type 5 =================================\n\n"
# echo ctx.computeType(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
# echo ctx.computeType(node), "\n--------------------------------------"


# echo "\n\n ============================= Update Node 6 =================================\n\n"
# node[2].text = "99"
# ctx.updateNode(node[2])
# echo ctx, "\n--------------------------------------"

# echo "\n\n ============================= Compute Type 7 =================================\n\n"
# echo ctx.computeType(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
# echo ctx.computeType(node), "\n--------------------------------------"