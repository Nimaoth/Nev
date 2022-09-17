import std/[tables, sets, strutils, hashes, options, macros]
import sugar
import system
import print
import fusion/matching
import ast, id, util

{.experimental: "dynamicBindSym".}

var currentIndent* = 0

type
  Fingerprint* = seq[int64]

  KeyKind* = enum Ast
  Key* = tuple[node: AstNode, update: proc(node: AstNode): Fingerprint]

  NodeColor* = enum Grey, Red, Green

  DependencyGraph* = ref object
    colors: Table[Key, NodeColor]
    verified: Table[Key, int]
    changed: Table[Key, int]
    fingerprints: Table[Key, Fingerprint]
    dependencies*: Table[Key, seq[Key]]
    revision*: int

proc newDependencyGraph*(): DependencyGraph =
  new result
  result.revision = 0

proc `$`*(graph: DependencyGraph): string =
  result = "Dependency Graph\n"
  result.add indent("revision: " & $graph.revision, 1, "| ") & "\n"

  result.add indent("colors:", 1, "| ") & "\n"
  for (key, value) in graph.colors.pairs:
    result.add indent($key.node & " -> " & $value, 2, "| ") & "\n"

  result.add indent("verified:", 1, "| ") & "\n"
  for (key, value) in graph.verified.pairs:
    result.add indent($key.node & " -> " & $value, 2, "| ") & "\n"

  result.add indent("changed:", 1, "| ") & "\n"
  for (key, value) in graph.changed.pairs:
    result.add indent($key.node & " -> " & $value, 2, "| ") & "\n"

  result.add indent("fingerprints:", 1, "| ") & "\n"
  for (key, value) in graph.fingerprints.pairs:
    result.add indent($key.node & " -> " & $value, 2, "| ") & "\n"

  result.add indent("dependencies:", 1, "| ") & "\n"
  for (key, value) in graph.dependencies.pairs:
    result.add indent($key.node & " -> " & $value, 2, "| ") & "\n"


proc nodeColor*(graph: DependencyGraph, key: Key): NodeColor =
  # return graph.colors.getOrDefault(key, Grey)
  let verified = graph.verified.getOrDefault(key, 0)
  if verified != graph.revision:
    return Grey

  let changed = graph.changed.getOrDefault(key, 0)
  if changed == graph.revision:
    return Red

  return Green

proc getDependencies*(graph: DependencyGraph, key: Key): seq[Key] =
  return graph.dependencies.getOrDefault(key, @[])

proc clearEdges*(graph: DependencyGraph, key: Key) =
  graph.dependencies[key] = @[]

proc setDependencies*(graph: DependencyGraph, key: Key, deps: seq[Key]) =
  graph.dependencies[key] = deps

proc fingerprint*(graph: DependencyGraph, key: Key): Fingerprint =
  if graph.fingerprints.contains(key):
    return graph.fingerprints[key]

proc markGreen*(graph: DependencyGraph, key: Key) =
  graph.colors[key] = Green
  graph.verified[key] = graph.revision

proc markRed*(graph: DependencyGraph, key: Key, fingerprint: Fingerprint) =
  graph.colors[key] = Red
  graph.verified[key] = graph.revision
  graph.changed[key] = graph.revision
  graph.fingerprints[key] = fingerprint

template query*(name: string) {.pragma.}

macro CreateContext*(contextName: untyped, body: untyped): untyped =
  result = nnkStmtList.newTree()

  # for query in body:
  #   echo query.treeRepr

  # Helper functions to access information about query declarations
  proc queryFunctionName(query: NimNode): NimNode =
    if query[0].kind == nnkPostfix:
      return query[0][1]
    return query[0]
  proc queryName(query: NimNode): string =
    return query[4][0][1].strVal
  proc queryArgType(query: NimNode): NimNode = query[3][2][1]
  proc queryValueType(query: NimNode): NimNode = query[3][0]
  proc isQuery(arg: NimNode): bool =
    let pragmas = arg[4]
    if pragmas.kind != nnkPragma or pragmas.len < 1: return false
    for pragma in pragmas:
      if pragma.kind != nnkCall or pragma.len != 2: continue
      if pragma[0].strVal == "query":
        return true
    return false

  # List of members of the final Context type
  # inputChanged: Table[AstNode, int]
  # depGraph: DependencyGraph
  # dependencyStack: seq[seq[Key]]
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

  # Add two members for each query
  # queryCache: Table[QueryInput, QueryOutput]
  # update: proc(arg: QueryInput): Fingerprint
  for query in body:
    if not isQuery query: continue

    let name = queryName query
    let key = queryArgType query
    let value = queryValueType query

    memberList.add nnkIdentDefs.newTree(
      ident("queryCache" & name),
      quote do: Table[`key`, `value`],
      newEmptyNode()
    )
    memberList.add nnkIdentDefs.newTree(
      ident("update" & name),
      nnkPar.newTree(
        nnkProcTy.newTree(
          nnkFormalParams.newTree(
            bindSym"Fingerprint",
            nnkIdentDefs.newTree(genSym(nskParam), key, newEmptyNode())
          ),
          newEmptyNode()
        )
      ),
      newEmptyNode()
    )

  # Create Context type
  # type Context* = ref object
  #   memberList...
  result.add nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nnkPostfix.newTree(ident"*", contextName),
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

  # Add all statements in the input body of this macro as is to the output
  for query in body:
    result.add query

  # Create newContext function for initializing a new context
  # proc newContext(): Context = ...
  var ctx = genSym(nskVar, "ctx")
  let newContextFnName = ident "new" & contextName.strVal
  var newContextFn = quote do:
    proc `newContextFnName`(): `contextName` =
      var `ctx`: `contextName`
      new `ctx`
      `ctx`.depGraph = newDependencyGraph()
      `ctx`.dependencyStack = @[]

  # Add initialization code to the newContext function for each query
  # ctx.update = proc(arg: QueryInput): Fingerprint = ...
  var queryInitializers: seq[NimNode] = @[]
  for query in body:
    if not isQuery query: continue

    let name = queryName query
    let key = queryArgType query
    let value = queryValueType query

    let updateName = ident "update" & name
    let queryCache = ident "queryCache" & name
    let queryFunction = queryFunctionName query

    queryInitializers.add quote do:
      `ctx`.`updateName` = proc (arg: `key`): Fingerprint =
        let value: `value` = `queryFunction`(`ctx`, arg)
        `ctx`.`queryCache`[arg] = value
        return value.fingerprint

  # Add the per query data initializers to the body of the newContext function
  for queryInitializer in queryInitializers:
    newContextFn[6].add queryInitializer
  newContextFn[6].add quote do: return `ctx`
  result.add newContextFn

  # proc force(ctx: Context, key: Key)
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

  # proc tryMarkGreen(ctx: Context, key: Key): bool
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

  # Add compute function for every query
  # proc compute(ctx: Context, node: QueryInput): QueryOutput
  for query in body:
    if not isQuery query: continue

    let name = queryName query
    let key = queryArgType query
    let value = queryValueType query

    let updateName = ident "update" & name
    let computeName = ident "compute" & name
    let queryCache = ident "queryCache" & name

    let nameString = name

    result.add quote do:
      proc `computeName`*(ctx: `contextName`, node: `key`): `value` =
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

  # Create $ for each query
  var queryCachesToString = nnkStmtList.newTree()
  let toStringCtx = genSym(nskParam)
  let toStringResult = genSym(nskVar)
  for query in body:
    if not isQuery query: continue

    let name = queryName query
    let queryCache = ident "queryCache" & name

    queryCachesToString.add quote do:
      `toStringResult`.add repeat("| ", 1) & "Cache: " & `name` & "\n"
      for (key, value) in `toStringCtx`.`queryCache`.pairs:
        `toStringResult`.add repeat("| ", 2) & $key & " -> " & $value & "\n"

  # Create $ implementation for Context
  result.add quote do:
    proc `$$`*(`toStringCtx`: `contextName`): string =
      var `toStringResult` = "Context\n"

      `queryCachesToString`

      `toStringResult`.add repeat("| ", 1) & "Input Changed\n"
      for (key, value) in `toStringCtx`.inputChanged.pairs:
        `toStringResult`.add repeat("| ", 2) & $key & " -> " & $value & "\n"

      `toStringResult`.add indent($`toStringCtx`.depGraph, 1, "| ")

      return `toStringResult`

  echo result.repr
