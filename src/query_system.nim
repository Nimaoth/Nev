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

  ItemId* = tuple[id: Id, typ: int]

  UpdateFunction = proc(item: ItemId): Fingerprint
  Dependency* = tuple[item: ItemId, update: UpdateFunction]

  NodeColor* = enum Grey, Red, Green

  DependencyGraph* = ref object
    colors: Table[Dependency, NodeColor]
    verified: Table[Dependency, int]
    changed: Table[Dependency, int]
    fingerprints: Table[Dependency, Fingerprint]
    dependencies*: Table[Dependency, seq[Dependency]]
    queryNames*: Table[UpdateFunction, string]
    revision*: int

proc hash(value: ItemId): Hash = value.id.hash xor value.typ.hash
proc `==`(a: ItemId, b: ItemId): bool = a.id == b.id and a.typ == b.typ

proc newDependencyGraph*(): DependencyGraph =
  new result
  result.revision = 0

proc `$`*(graph: DependencyGraph): string =
  result = "Dependency Graph\n"
  result.add indent("revision: " & $graph.revision, 1, "| ") & "\n"

  result.add indent("colors:", 1, "| ") & "\n"
  for (key, value) in graph.colors.pairs:
    result.add indent(graph.queryNames[key.update] & ":" & $key.item & " -> " & $value, 2, "| ") & "\n"

  result.add indent("verified:", 1, "| ") & "\n"
  for (key, value) in graph.verified.pairs:
    result.add indent(graph.queryNames[key.update] & ":" & $key.item & " -> " & $value, 2, "| ") & "\n"

  result.add indent("changed:", 1, "| ") & "\n"
  for (key, value) in graph.changed.pairs:
    result.add indent(graph.queryNames[key.update] & ":" & $key.item & " -> " & $value, 2, "| ") & "\n"

  result.add indent("fingerprints:", 1, "| ") & "\n"
  for (key, value) in graph.fingerprints.pairs:
    result.add indent(graph.queryNames[key.update] & ":" & $key.item & " -> " & $value, 2, "| ") & "\n"

  result.add indent("dependencies:", 1, "| ") & "\n"
  for (key, value) in graph.dependencies.pairs:
    var deps = "["
    for i, dep in value:
      if i > 0: deps.add ", "
      deps.add graph.queryNames[dep.update] & ":" & $dep.item

    deps.add "]"
    result.add indent(graph.queryNames[key.update] & ":" & $key.item & " -> " & deps, 2, "| ") & "\n"

proc nodeColor*(graph: DependencyGraph, key: Dependency): NodeColor =
  # return graph.colors.getOrDefault(key, Grey)
  let verified = graph.verified.getOrDefault(key, 0)
  if verified != graph.revision:
    return Grey

  let changed = graph.changed.getOrDefault(key, 0)
  if changed == graph.revision:
    return Red

  return Green

proc getDependencies*(graph: DependencyGraph, key: Dependency): seq[Dependency] =
  return graph.dependencies.getOrDefault(key, @[])

proc clearEdges*(graph: DependencyGraph, key: Dependency) =
  graph.dependencies[key] = @[]

proc setDependencies*(graph: DependencyGraph, key: Dependency, deps: seq[Dependency]) =
  graph.dependencies[key] = deps

proc fingerprint*(graph: DependencyGraph, key: Dependency): Fingerprint =
  if graph.fingerprints.contains(key):
    return graph.fingerprints[key]

proc markGreen*(graph: DependencyGraph, key: Dependency) =
  graph.colors[key] = Green
  graph.verified[key] = graph.revision

proc markRed*(graph: DependencyGraph, key: Dependency, fingerprint: Fingerprint) =
  graph.colors[key] = Red
  graph.verified[key] = graph.revision
  graph.changed[key] = graph.revision
  graph.fingerprints[key] = fingerprint

template query*(name: string) {.pragma.}

macro CreateContext*(contextName: untyped, body: untyped): untyped =
  result = nnkStmtList.newTree()

  # Helper functions to access information about declarations
  proc queryFunctionName(query: NimNode): NimNode =
    if query[0].kind == nnkPostfix:
      return query[0][1]
    return query[0]
  proc queryName(query: NimNode): string =
    return query[4][0][1].strVal
  proc queryArgType(query: NimNode): NimNode = query[3][2][1]
  proc queryValueType(query: NimNode): NimNode = query[3][0]
  proc inputName(input: NimNode): NimNode = input[1]

  proc isQuery(arg: NimNode): bool =
    if arg.len < 5: return false
    let pragmas = arg[4]
    if pragmas.kind != nnkPragma or pragmas.len < 1: return false
    for pragma in pragmas:
      if pragma.kind != nnkCall or pragma.len != 2: continue
      if pragma[0].strVal == "query":
        return true
    return false

  proc isInputDefinition(arg: NimNode): bool =
    if arg.kind != nnkCommand or arg.len < 2: return false
    if arg[0].strVal != "input": return false
    return true

  proc isDataDefinition(arg: NimNode): bool =
    if arg.kind != nnkCommand or arg.len < 2: return false
    if arg[0].strVal != "data": return false
    return true

  for query in body:
    if isQuery query:
      continue
    if isInputDefinition query:
      echo "input: ", query.treeRepr
    if isDataDefinition query:
      echo "data: ", query.treeRepr

  # List of members of the final Context type
  # inputChanged: Table[AstNode, int]
  # depGraph: DependencyGraph
  # dependencyStack: seq[seq[Key]]
  let memberList = nnkRecList.newTree(
    nnkIdentDefs.newTree(
      newIdentNode("inputChanged"),
      quote do: Table[ItemId, int],
      newEmptyNode()
    ),
    nnkIdentDefs.newTree(
      newIdentNode("depGraph"),
      quote do: DependencyGraph,
      newEmptyNode()
    ),
    nnkIdentDefs.newTree(
      newIdentNode("dependencyStack"),
      quote do: seq[seq[Dependency]],
      newEmptyNode()
    )
  )

  # Add member for each input
  # items: Table[ItemId, Input]
  for input in body:
    if not isInputDefinition input: continue

    let name = inputName input

    memberList.add nnkIdentDefs.newTree(
      ident("items" & name.strVal),
      quote do: Table[ItemId, `name`],
      newEmptyNode()
    )

  # Add member for each data
  # data: Table[Data, int]
  for data in body:
    if not isDataDefinition data: continue

    let name = inputName data
    let items = ident "items" & name.strVal

    memberList.add nnkIdentDefs.newTree(
      items,
      quote do: Table[ItemId, `name`],
      newEmptyNode()
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
            nnkIdentDefs.newTree(genSym(nskParam), bindSym"ItemId", newEmptyNode())
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
    if isInputDefinition(query) or isDataDefinition(query):
      continue
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
    let items = ident "items" & key.strVal

    queryInitializers.add quote do:
      `ctx`.`updateName` = proc (item: ItemId): Fingerprint =
        let arg = `ctx`.`items`[item]
        let value: `value` = `queryFunction`(`ctx`, arg)
        `ctx`.`queryCache`[arg] = value
        return value.fingerprint
      `ctx`.depGraph.queryNames[`ctx`.`updateName`] = `name`

  # Add the per query data initializers to the body of the newContext function
  for queryInitializer in queryInitializers:
    newContextFn[6].add queryInitializer
  newContextFn[6].add quote do: return `ctx`
  result.add newContextFn

  # Add newData function for each data
  for data in body:
    if not isDataDefinition data: continue

    let name = inputName data
    let items = ident "items" & name.strVal

    result.add quote do:
      proc newData*(ctx: `contextName`, data: `name`): `name` =
        let item = data.getItem
        if ctx.inputChanged.contains(item):
          ctx.inputChanged[item] = ctx.depGraph.revision
        else:
          ctx.inputChanged.add(item, ctx.depGraph.revision)
        ctx.`items`.add(item, data)
        return data

  # proc force(ctx: Context, key: Dependency)
  result.add quote do:
    proc force(ctx: `contextName`, key: Dependency) =
      inc currentIndent, 1
      defer: dec currentIndent, 1
      echo repeat("| ", currentIndent - 1), "force ", key.item

      if ctx.dependencyStack.len > 10:
        return

      ctx.depGraph.clearEdges(key)
      ctx.dependencyStack.add(@[])

      let fingerprint = key.update(key.item)

      ctx.depGraph.setDependencies(key, ctx.dependencyStack.pop)

      let prevFingerprint = ctx.depGraph.fingerprint(key)

      if fingerprint == prevFingerprint:
        echo repeat("| ", currentIndent), "mark green"
        ctx.depGraph.markGreen(key)
      else:
        echo repeat("| ", currentIndent), "mark red"
        ctx.depGraph.markRed(key, fingerprint)

  # proc tryMarkGreen(ctx: Context, key: Dependency): bool
  result.add quote do:
    proc tryMarkGreen(ctx: `contextName`, key: Dependency): bool =
      inc currentIndent, 1
      defer: dec currentIndent, 1

      let inputChangedRevision = ctx.inputChanged.getOrDefault(key.item, ctx.depGraph.revision)
      let verified = ctx.depGraph.verified.getOrDefault(key, 0)

      if inputChangedRevision > verified:
        # Input changed after this current query got verified
        echo repeat("| ", currentIndent - 1), "tryMarkGreen ", ctx.depGraph.queryNames[key.update] & ":" & $key.item, ", input changed"
        return false

      echo repeat("| ", currentIndent - 1), "tryMarkGreen ", ctx.depGraph.queryNames[key.update] & ":" & $key.item, ", deps: ", ctx.depGraph.getDependencies(key)

      for i, dep in ctx.depGraph.getDependencies(key):
        case ctx.depGraph.nodeColor(dep)
        of Green:
          echo repeat("| ", currentIndent), "Dependency ", ctx.depGraph.queryNames[dep.update] & ":" & $dep.item, " is green, skip"
          discard
        of Red:
          echo repeat("| ", currentIndent), "Dependency ", ctx.depGraph.queryNames[dep.update] & ":" & $dep.item, " is red, failed"
          return false
        of Grey:
          echo repeat("| ", currentIndent), "Dependency ", ctx.depGraph.queryNames[dep.update] & ":" & $dep.item, " is grey"
          if not ctx.tryMarkGreen(dep):
            echo repeat("| ", currentIndent), "Dependency ", ctx.depGraph.queryNames[dep.update] & ":" & $dep.item, ", mark green failed"
            ctx.force(dep)

            if ctx.depGraph.nodeColor(dep) == Red:
              echo repeat("| ", currentIndent), "Dependency ", ctx.depGraph.queryNames[dep.update] & ":" & $dep.item, ", value changed"
              return false

      echo repeat("| ", currentIndent), "mark green"
      ctx.depGraph.markGreen(key)

      return true

  # proc recordDependency(ctx: Context, item: ItemId, update: UpdateFunction)
  result.add quote do:
    proc recordDependency*(ctx: `contextName`, item: ItemId, update: UpdateFunction) =
      if ctx.dependencyStack.len > 0:
        ctx.dependencyStack[ctx.dependencyStack.high].add (item, update)

  # Add compute function for every query
  # proc compute(ctx: Context, item: QueryInput): QueryOutput
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
      proc `computeName`*(ctx: `contextName`, input: `key`): `value` =
        let item = getItem input
        let key = (item, ctx.`updateName`)

        ctx.recordDependency(item, ctx.`updateName`)

        let color = ctx.depGraph.nodeColor(key)

        inc currentIndent, 1
        defer: dec currentIndent, 1
        echo repeat("| ", currentIndent - 1), "compute", `nameString`, " ", color, ", ", item

        if color == Green:
          if not ctx.`queryCache`.contains(input):
            echo repeat("| ", currentIndent), "green, not in cache"
            ctx.force(key)
            echo repeat("| ", currentIndent), "result: ", $ctx.`queryCache`[input]
          else:
            echo repeat("| ", currentIndent), "green, in cache, result: ", $ctx.`queryCache`[input]
          return ctx.`queryCache`[input]

        if color == Grey:
          if not ctx.`queryCache`.contains(input):
            echo repeat("| ", currentIndent), "grey, not in cache"
            ctx.force(key)
            echo repeat("| ", currentIndent), "result: ", $ctx.`queryCache`[input]
            return ctx.`queryCache`[input]

          echo repeat("| ", currentIndent), "grey, in cache"
          if ctx.tryMarkGreen(key):
            echo repeat("| ", currentIndent), "green, result: ", $ctx.`queryCache`[input]
            return ctx.`queryCache`[input]
          else:
            echo repeat("| ", currentIndent), "failed to mark green"
            ctx.force(key)
            echo repeat("| ", currentIndent), "result: ", $ctx.`queryCache`[input]
            return ctx.`queryCache`[input]

        assert color == Red
        echo repeat("| ", currentIndent), "red, in cache, result: ", $ctx.`queryCache`[input]
        return ctx.`queryCache`[input]

  # Create $ for each query
  var queryCachesToString = nnkStmtList.newTree()
  let toStringCtx = genSym(nskParam)
  let toStringResult = genSym(nskVar)
  for input in body:
    if not (isInputDefinition(input) or isDataDefinition(input)): continue

    let name = inputName(input).strVal
    let items = ident "items" & name

    queryCachesToString.add quote do:
      `toStringResult`.add repeat("| ", 1) & "Items: " & `name` & "\n"
      for (key, value) in `toStringCtx`.`items`.pairs:
        `toStringResult`.add repeat("| ", 2) & $key & " -> " & $value & "\n"

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
