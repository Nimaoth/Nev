import std/[tables, sets, strutils, hashes, options, macros, strformat]
import timer
import fusion/matching
import ast, id, util
import lru_cache

{.experimental: "dynamicBindSym".}

var currentIndent* = 0

func repeat2*(s: string, n: Natural): string = repeat s, n

type Cache[K, V] = LruCache[K, V]
proc newCache[K, V](capacity: int): Cache[K, V] = newLRUCache[K, V](capacity)
# type Cache[K, V] = Table[K, V]
# proc newCache[K, V](capacity: int): Cache[K, V] = initTable[K, V]()

proc init[K, V](result: var Cache[K, V], capacity: int) =
  result = newCache[K, V](capacity)

type
  Fingerprint* = seq[int64]

  ItemId* = tuple[id: Id, typ: int]

  UpdateFunction* = proc(item: ItemId): Fingerprint
  Dependency* = tuple[item: ItemId, update: UpdateFunction]
  RecursionRecoveryFunction = proc(key: Dependency)

  NodeColor* = enum Grey, Red, Green
  MarkGreenResult* = enum Ok, Error, Recursion

  DependencyGraph* = ref object
    verified*: Cache[Dependency, int]
    changed*: Cache[Dependency, int]
    fingerprints*: Cache[Dependency, Fingerprint]
    dependencies*: Cache[Dependency, seq[Dependency]]
    queryNames*: Table[UpdateFunction, string]
    revision*: int

proc `$`*(item: ItemId): string =
  return fmt"({item.id}, {item.typ})"

proc hash(value: ItemId): Hash = value.id.hash xor value.typ.hash
proc `==`(a: ItemId, b: ItemId): bool = a.id == b.id and a.typ == b.typ

func fingerprint*(id: Id): Fingerprint =
  let p: ptr array[3, int32] = cast[ptr array[3, int32]](addr id)
  let p2: ptr int64 = cast[ptr int64](addr id)
  return @[p2[], p[2]]

proc newDependencyGraph*(): DependencyGraph =
  new result
  result.revision = 0
  result.queryNames[nil] = ""
  result.verified = newCache[Dependency, int](2000)
  result.changed = newCache[Dependency, int](2000)
  result.fingerprints = newCache[Dependency, Fingerprint](2000)
  result.dependencies = newCache[Dependency, seq[Dependency]](2000)

proc nodeColor*(graph: DependencyGraph, key: Dependency, parentVerified: int = 0): NodeColor =
  if key.update == nil:
    # Input
    let inputChangedRevision = graph.changed.getOrDefault(key, graph.revision)
    if inputChangedRevision > parentVerified:
      return Red
    else:
      return Green

  # Computed data
  let verified = graph.verified.getOrDefault(key, 0)
  if verified != graph.revision:
    return Grey

  let changed = graph.changed.getOrDefault(key, graph.revision)
  if changed == graph.revision:
    return Red

  return Green

proc getDependencies*(graph: DependencyGraph, key: Dependency): seq[Dependency] =
  result = graph.dependencies.getOrDefault(key, @[])
  if result.len == 0 and key.update != nil:
    result.add (key.item, nil)

proc clearEdges*(graph: DependencyGraph, key: Dependency) =
  graph.dependencies[key] = @[]

proc setDependencies*(graph: DependencyGraph, key: Dependency, deps: seq[Dependency]) =
  graph.dependencies[key] = deps

proc fingerprint*(graph: DependencyGraph, key: Dependency): Fingerprint =
  if graph.fingerprints.contains(key):
    return graph.fingerprints[key]

proc markGreen*(graph: DependencyGraph, key: Dependency) =
  graph.verified[key] = graph.revision

proc markRed*(graph: DependencyGraph, key: Dependency, fingerprint: Fingerprint) =
  graph.verified[key] = graph.revision
  graph.changed[key] = graph.revision
  graph.fingerprints[key] = fingerprint

proc `$`*(graph: DependencyGraph): string =
  result = "Dependency Graph\n"
  result.add indent("revision: " & $graph.revision, 1, "| ") & "\n"

  result.add indent("colors:", 1, "| ") & "\n"
  # for (key, value) in graph.changed.pairs:
  #   let color = graph.nodeColor key
  #   result.add indent(graph.queryNames[key.update] & ":" & $key.item & " -> " & $color, 2, "| ") & "\n"

  result.add indent("verified:", 1, "| ") & "\n"
  # for (key, value) in graph.verified.pairs:
  #   result.add indent(graph.queryNames[key.update] & ":" & $key.item & " -> " & $value, 2, "| ") & "\n"

  result.add indent("changed:", 1, "| ") & "\n"
  # for (key, value) in graph.changed.pairs:
  #   result.add indent(graph.queryNames[key.update] & ":" & $key.item & " -> " & $value, 2, "| ") & "\n"

  result.add indent("fingerprints:", 1, "| ") & "\n"
  # for (key, value) in graph.fingerprints.pairs:
  #   result.add indent(graph.queryNames[key.update] & ":" & $key.item & " -> " & $value, 2, "| ") & "\n"

  result.add indent("dependencies:", 1, "| ") & "\n"
  # for (key, value) in graph.dependencies.pairs:
  #   var deps = "["
  #   for i, dep in value:
  #     if i > 0: deps.add ", "
  #     deps.add graph.queryNames[dep.update] & ":" & $dep.item

  #   deps.add "]"
  #   result.add indent(graph.queryNames[key.update] & ":" & $key.item & " -> " & deps, 2, "| ") & "\n"

template query*(name: string, useCache: bool = true, useFingerprinting: bool = true) {.pragma.}
template recover*(name: string) {.pragma.}

macro CreateContext*(contextName: untyped, body: untyped): untyped =
  result = nnkStmtList.newTree()

  # Helper functions to access information about declarations
  proc queryFunctionName(query: NimNode): NimNode =
    if query[0].kind == nnkPostfix:
      return query[0][1]
    return query[0]
  proc queryArgType(query: NimNode): NimNode = query[3][2][1]
  proc queryValueType(query: NimNode): NimNode = query[3][0]
  proc inputName(input: NimNode): NimNode = input[1]

  proc getPragma(arg: NimNode, name: string): Option[NimNode] =
    if arg.len < 5: return none[NimNode]()
    let pragmas = arg[4]
    if pragmas.kind != nnkPragma or pragmas.len < 1: return none[NimNode]()
    for pragma in pragmas:
      if pragma.kind != nnkCall: continue
      if pragma[0].strVal == name:
        return some(pragma)
    return none[NimNode]()

  proc queryName(query: NimNode): string =
    return query[4][0][1].strVal

  proc queryUseCache(query: NimNode): bool =
    if query.getPragma("query").getSome(pragma):
      for setting in pragma:
        if setting.kind == nnkExprEqExpr and setting.len == 2 and setting[0].strVal == "useCache":
          return setting[1].boolVal
    return true

  proc queryUseFingerprinting(query: NimNode): bool =
    if query.getPragma("query").getSome(pragma):
      for setting in pragma:
        if setting.kind == nnkExprEqExpr and setting.len == 2 and setting[0].strVal == "useFingerprinting":
          return setting[1].boolVal
    return true

  proc isQuery(arg: NimNode): bool =
    if arg.getPragma("query").isSome:
      return true
    return false

  proc isRecoveryFunction(arg: NimNode): bool =
    if arg.getPragma("recover").isSome:
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

  proc isCustomMemberDefinition(arg: NimNode): bool =
    return arg.kind == nnkVarSection

  proc customMemberName(arg: NimNode): NimNode =
    if arg[0].kind == nnkPostfix:
      return arg[0][1]
    return arg[0]

  # for arg in body:
  #   if not isQuery arg:
  #     continue
  #   echo "query: ", arg.treeRepr

  var dataIndices = initTable[string, int]()

  for data in body:
    if not isDataDefinition(data) and not isInputDefinition(data): continue
    dataIndices[data.inputName.strVal] = dataIndices.len

  # List of members of the final Context type
  # depGraph: DependencyGraph
  # dependencyStack: seq[seq[Key]]
  let memberList = nnkRecList.newTree(
    nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident"*", newIdentNode("depGraph")),
      quote do: DependencyGraph,
      newEmptyNode()
    ),
    nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident"*", newIdentNode("dependencyStack")),
      quote do: seq[seq[Dependency]],
      newEmptyNode()
    ),
    nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident"*", newIdentNode("activeQuerySet")),
      quote do: HashSet[Dependency],
      newEmptyNode()
    ),
    nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident"*", newIdentNode("activeQueryStack")),
      quote do: seq[Dependency],
      newEmptyNode()
    ),
    nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident"*", newIdentNode("recursiveQueries")),
      quote do: HashSet[Dependency],
      newEmptyNode()
    ),
    nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident"*", newIdentNode("recoveryFunctions")),
      quote do: Table[UpdateFunction, RecursionRecoveryFunction],
      newEmptyNode()
    ),
    nnkIdentDefs.newTree(nnkPostfix.newTree(ident"*", newIdentNode("enableLogging")), bindSym"bool", newEmptyNode()),
  )

  # Add member for each input and data
  # items: Table[ItemId, Input]
  for input in body:
    if not isInputDefinition(input) and not isDataDefinition(input): continue

    let name = inputName input

    memberList.add nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident"*", ident("items" & name.strVal)),
      quote do: Cache[ItemId, `name`],
      newEmptyNode()
    )

  # Add member declarations for custom members
  for customMembers in body:
    if not isCustomMemberDefinition customMembers: continue

    for member in customMembers:
      memberList.add nnkIdentDefs.newTree(member[0], member[1], newEmptyNode())

  # Add two members for each query
  # queryCache: Table[QueryInput, QueryOutput]
  # update: proc(item: ItemId): Fingerprint
  for query in body:
    if not isQuery query: continue

    let name = queryName query
    let key = queryArgType query
    let value = queryValueType query

    memberList.add nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident"*", ident("queryCache" & name)),
      quote do: Cache[`key`, `value`],
      newEmptyNode()
    )
    memberList.add nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident"*", ident("update" & name)),
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

    memberList.add nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident"*", ident("executionTime" & name)),
      quote do: Nanos,
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
    if not isQuery(query) and not isRecoveryFunction(query):
      continue
    result.add query

  # Create newContext function for initializing a new context
  # proc newContext(): Context = ...
  var ctx = genSym(nskVar, "ctx")
  let newContextFnName = ident "new" & contextName.strVal
  var newContextFn = quote do:
    proc `newContextFnName`*(): `contextName` =
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
        if not `ctx`.`items`.contains(item):
          raise newException(Defect, "update" & `name` & "(" & $item & "): not in cache anymore")
        let arg = `ctx`.`items`[item]
        let value: `value` = `queryFunction`(`ctx`, arg)
        `ctx`.`queryCache`[arg] = value
        return value.fingerprint
      `ctx`.depGraph.queryNames[`ctx`.`updateName`] = `name`
      `ctx`.`queryCache`.init(2000)

  # Add recovery functions to ctx.recoveryFunctions
  for query in body:
    if not isRecoveryFunction query: continue

    let name = queryName query
    let updateName = ident "update" & name
    let recoveryFunction = queryFunctionName query
    queryInitializers.add quote do:
      `ctx`.recoveryFunctions[`ctx`.`updateName`] = proc(key: Dependency) =
        `recoveryFunction`(`ctx`, key)

  # Add initializer for each input and data
  # items: Table[ItemId, Input]
  for input in body:
    if not isInputDefinition(input) and not isDataDefinition(input): continue

    let name = inputName input
    let items = ident "items" & name.strVal

    queryInitializers.add quote do:
      `ctx`.`items`.init(2000)

  ## Add initializers for custom members
  for customMembers in body:
    if not isCustomMemberDefinition customMembers: continue

    for member in customMembers:
      if member[2].kind == nnkEmpty: continue
      let name = customMemberName member
      let initValue = member[2]
      queryInitializers.add quote do:
        `ctx`.`name` = `initValue`

  # Add the per query data initializers to the body of the newContext function
  for queryInitializer in queryInitializers:
    newContextFn[6].add queryInitializer
  newContextFn[6].add quote do: return `ctx`
  result.add newContextFn

  # Create $ for each query
  var queryCachesToString = nnkStmtList.newTree()
  let toStringCtx = genSym(nskParam)
  let toStringResult = genSym(nskVar)
  for input in body:
    if not (isInputDefinition(input) or isDataDefinition(input)): continue

    let name = inputName(input).strVal
    let items = ident "items" & name

    queryCachesToString.add quote do:
      `toStringResult`.add repeat2("| ", 1) & "Items: " & `name` & "\n"
      for (key, value) in `toStringCtx`.`items`.pairs:
        `toStringResult`.add repeat2("| ", 2) & $key & " -> " & $value & "\n"

  for query in body:
    if not isQuery query: continue

    let name = queryName query
    let queryCache = ident "queryCache" & name

    queryCachesToString.add quote do:
      `toStringResult`.add repeat2("| ", 1) & "Cache: " & `name` & "\n"
      for (key, value) in `toStringCtx`.`queryCache`.pairs:
        `toStringResult`.add repeat2("| ", 2) & $key & " -> " & $value & "\n"

  # Create $ implementation for Context
  result.add quote do:
    proc toString*(`toStringCtx`: `contextName`): string =
      var `toStringResult` = "Context\n"

      `queryCachesToString`

      `toStringResult`.add indent($`toStringCtx`.depGraph, 1, "| ")

      return `toStringResult`

  # Add function resetExecutionTimes(ctx: Context) which resets the accumulated times of each query
  block:
    var ctx = genSym(nskParam, "ctx")
    var resetExecutionTimesFn = quote do:
      proc resetExecutionTimes*(`ctx`: `contextName`) =
        discard

    var executionTimeResets: seq[NimNode] = @[]
    for query in body:
      if not isQuery query: continue

      let name = queryName query
      let executionTime = ident "executionTime" & name

      executionTimeResets.add quote do:
        `ctx`.`executionTime` = 0

    resetExecutionTimesFn[6].del 0
    for node in executionTimeResets:
      resetExecutionTimesFn[6].add node
    result.add resetExecutionTimesFn

  # proc recordDependency(ctx: Context, item: ItemId, update: UpdateFunction)
  result.add quote do:
    proc recordDependency*(ctx: `contextName`, item: ItemId, update: UpdateFunction = nil) =
      if ctx.dependencyStack.len > 0:
        ctx.dependencyStack[ctx.dependencyStack.high].add (item, update)

  # Generate functions getData and getItem
  for data in body:
    if not isDataDefinition(data) and not isInputDefinition(data): continue

    let name = inputName data
    let items = ident "items" & name.strVal
    let functionName = ident "get" & name.strVal
    let itemIndex = newLit dataIndices[data.inputName.strVal]
    let getOrCreateFunction = ident "getOrCreate" & name.strVal

    result.add quote do:
      proc `functionName`*(ctx: `contextName`, id: Id): Option[`name`] =
        let item: ItemId = (id, `itemIndex`)
        if ctx.`items`.contains(item):
          return some(ctx.`items`[item])
        return none[`name`]()

    result.add quote do:
      proc getItem*(self: `name`): ItemId =
        if self.id == null:
          self.id = newId()
        return (self.id, `itemIndex`)

    result.add quote do:
      proc `getOrCreateFunction`*(ctx: `contextName`, data: `name`): `name` =
        for existing in ctx.`items`.values:
          if existing.hash == data.hash and existing == data:
            return existing

        let item = data.getItem
        let key: Dependency = (item, nil)
        ctx.depGraph.changed[key] = ctx.depGraph.revision
        ctx.`items`[item] = data
        return data

  # Add newData function for each data
  for data in body:
    if not isDataDefinition data: continue

    let name = inputName data
    let items = ident "items" & name.strVal
    let functionName = ident "new" & name.strVal

    result.add quote do:
      proc `functionName`*(ctx: `contextName`, data: `name`): `name` =
        let item = data.getItem
        let key: Dependency = (item, nil)
        ctx.depGraph.changed[key] = ctx.depGraph.revision
        ctx.`items`[item] = data
        return data

  # proc force(ctx: Context, key: Dependency)
  result.add quote do:
    proc force(ctx: `contextName`, key: Dependency) =
      inc currentIndent, if ctx.enableLogging: 1 else: 0
      defer: dec currentIndent, if ctx.enableLogging: 1 else: 0
      if ctx.enableLogging: echo repeat2("| ", currentIndent - 1), "force ", ctx.depGraph.queryNames[key.update], key.item

      if key in ctx.activeQuerySet:
        # Recursion detected
        ctx.recursiveQueries.incl key

        let item = key.item
        let query = ctx.depGraph.queryNames[key.update]
        echo "[query_system:force] Detected recursion at ", item, " (", query, ")"
        for k in 0..ctx.activeQueryStack.high:
          let i = ctx.activeQueryStack.len - k - 1
          echo "[query_system:force] [", k, "] Parent: ", ctx.activeQueryStack[i].item, ", ", ctx.depGraph.queryNames.getOrDefault ctx.activeQueryStack[i].update

        if ctx.enableLogging: echo repeat2("| ", currentIndent), "recursion detected"

        if ctx.recoveryFunctions.contains(key.update):
          ctx.recoveryFunctions[key.update](key)
          ctx.depGraph.markRed(key, @[])
        return

      ctx.activeQuerySet.incl key
      ctx.activeQueryStack.add key

      ctx.depGraph.clearEdges(key)
      ctx.dependencyStack.add(@[])
      ctx.recordDependency(key.item)

      let fingerprint = key.update(key.item)

      ctx.depGraph.setDependencies(key, ctx.dependencyStack.pop)
      ctx.activeQuerySet.excl key
      discard ctx.activeQueryStack.pop

      let prevFingerprint = ctx.depGraph.fingerprint(key)

      if fingerprint == prevFingerprint:
        if ctx.enableLogging: echo repeat2("| ", currentIndent), "mark green"
        ctx.depGraph.markGreen(key)
      else:
        if ctx.enableLogging: echo repeat2("| ", currentIndent), "mark red"
        ctx.depGraph.markRed(key, fingerprint)

  # proc tryMarkGreen(ctx: Context, key: Dependency): bool
  result.add quote do:
    proc tryMarkGreen(ctx: `contextName`, key: Dependency): MarkGreenResult =
      inc currentIndent, if ctx.enableLogging: 1 else: 0
      defer: dec currentIndent, if ctx.enableLogging: 1 else: 0
      if ctx.enableLogging: echo repeat2("| ", currentIndent - 1), "tryMarkGreen ", ctx.depGraph.queryNames[key.update] & ":" & $key.item, ", deps: ", ctx.depGraph.getDependencies(key)

      if key in ctx.activeQuerySet:
        # Recursion detected
        ctx.recursiveQueries.incl key

        let item = key.item
        let query = ctx.depGraph.queryNames[key.update]
        echo "[query_system:tryMarkGreen] Detected recursion at ", item, " (", query, ")"
        for k in 0..ctx.activeQueryStack.high:
          let i = ctx.activeQueryStack.len - k - 1
          echo "[query_system:tryMarkGreen] [", k, "] Parent: ", ctx.activeQueryStack[i].item, ", ", ctx.depGraph.queryNames.getOrDefault ctx.activeQueryStack[i].update

        if ctx.enableLogging: echo repeat2("| ", currentIndent), "recursion detected"

        if ctx.recoveryFunctions.contains(key.update):
          ctx.recoveryFunctions[key.update](key)
          ctx.depGraph.markRed(key, @[])
        return Recursion

      ctx.activeQuerySet.incl key
      ctx.activeQueryStack.add key
      defer:
        ctx.activeQuerySet.excl key
        discard ctx.activeQueryStack.pop

      let verified = ctx.depGraph.verified.getOrDefault(key, 0)

      for i, dep in ctx.depGraph.getDependencies(key):
        if dep.item.id == null:
          if ctx.enableLogging: echo repeat2("| ", currentIndent), "Dependency got deleted -> red, failed"
          return Error
        case ctx.depGraph.nodeColor(dep, verified)
        of Green:
          if ctx.enableLogging: echo repeat2("| ", currentIndent), "Dependency ", ctx.depGraph.queryNames[dep.update] & ":" & $dep.item, " is green, skip"
          discard
        of Red:
          if ctx.enableLogging: echo repeat2("| ", currentIndent), "Dependency ", ctx.depGraph.queryNames[dep.update] & ":" & $dep.item, " is red, failed"
          return Error
        of Grey:
          if ctx.enableLogging: echo repeat2("| ", currentIndent), "Dependency ", ctx.depGraph.queryNames[dep.update] & ":" & $dep.item, " is grey"
          case ctx.tryMarkGreen(dep)
          of Recursion:
            if ctx.enableLogging: echo repeat2("| ", currentIndent), "Dependency ", ctx.depGraph.queryNames[dep.update] & ":" & $dep.item, ", recursively called 1 " & $key & ", failed"
            return Recursion

          of Error:
            if ctx.enableLogging: echo repeat2("| ", currentIndent), "Dependency ", ctx.depGraph.queryNames[dep.update] & ":" & $dep.item, ", mark green failed"


            ctx.force(dep)

            if key in ctx.recursiveQueries:
              ctx.recursiveQueries.excl key
              if ctx.enableLogging: echo repeat2("| ", currentIndent), "Dependency ", ctx.depGraph.queryNames[dep.update] & ":" & $dep.item, ", recursively called 2 " & $key & ", failed"
              return Error

            if ctx.depGraph.nodeColor(dep, verified) == Red:
              if ctx.enableLogging: echo repeat2("| ", currentIndent), "Dependency ", ctx.depGraph.queryNames[dep.update] & ":" & $dep.item, ", value changed"
              return Error

          else: discard

      if ctx.enableLogging: echo repeat2("| ", currentIndent), "mark green"
      ctx.depGraph.markGreen(key)

      return Ok

  # Add compute function for every query
  # proc compute(ctx: Context, item: QueryInput): QueryOutput
  for query in body:
    if not isQuery query: continue

    let name = queryName query
    let key = queryArgType query
    let value = queryValueType query

    let updateName = ident "update" & name
    let computeName = ident "compute" & name
    let getFunctionName = ident "get" & name
    let queryCache = ident "queryCache" & name
    let executionTime = ident "executionTime" & name

    let nameString = name

    let useCache = queryUseCache query
    let useFingerprinting = newLit queryUseFingerprinting query

    result.add quote do:
      proc `getFunctionName`*(ctx: `contextName`, input: `key`): Option[`value`] =
        if ctx.`queryCache`.contains(input):
          return some(ctx.`queryCache`[input])
        return none[`value`]()


    if useCache:
      result.add quote do:
        proc `computeName`*(ctx: `contextName`, input: `key`): `value` =
          let timer = startTimer()

          defer:
            ctx.`executionTime` += timer.elapsed

          defer:
            if ctx.dependencyStack.len == 0:
              ctx.recursiveQueries.clear()

          let item = getItem input
          let key = (item, ctx.`updateName`)

          ctx.recordDependency(item, ctx.`updateName`)

          let color = ctx.depGraph.nodeColor(key)

          inc currentIndent, if ctx.enableLogging: 1 else: 0
          defer: dec currentIndent, if ctx.enableLogging: 1 else: 0
          if ctx.enableLogging: echo repeat2("| ", currentIndent - 1), "compute", `nameString`, " ", color, ", ", item

          if color == Green:
            if not ctx.`queryCache`.contains(input):
              if ctx.enableLogging: echo repeat2("| ", currentIndent), "green, not in cache"
              ctx.force(key)
              if not `useFingerprinting`: ctx.depGraph.markRed(key, @[])
              if ctx.enableLogging and ctx.`queryCache`.contains(input): echo repeat2("| ", currentIndent), "result: ", $ctx.`queryCache`[input]
            else:
              if ctx.enableLogging and ctx.`queryCache`.contains(input): echo repeat2("| ", currentIndent), "green, in cache, result: ", $ctx.`queryCache`[input]
            if not ctx.`queryCache`.contains(input):
              raise newException(Defect, "compute" & `name` & "(" & $input & "): not in cache anymore")
            return ctx.`queryCache`[input]

          if color == Grey:
            if not ctx.`queryCache`.contains(input):
              if ctx.enableLogging: echo repeat2("| ", currentIndent), "grey, not in cache"
              ctx.force(key)
              if not `useFingerprinting`: ctx.depGraph.markRed(key, @[])
              if ctx.enableLogging and ctx.`queryCache`.contains(input): echo repeat2("| ", currentIndent), "result: ", $ctx.`queryCache`[input]
              if not ctx.`queryCache`.contains(input):
                raise newException(Defect, "compute" & `name` & "(" & $input & "): not in cache anymore")
              return ctx.`queryCache`[input]

            if ctx.enableLogging: echo repeat2("| ", currentIndent), "grey, in cache"
            if ctx.tryMarkGreen(key) == Ok:
              if ctx.enableLogging and ctx.`queryCache`.contains(input): echo repeat2("| ", currentIndent), "green, result: ", $ctx.`queryCache`[input]
              if not ctx.`queryCache`.contains(input):
                raise newException(Defect, "compute" & `name` & "(" & $input & "): not in cache anymore")
              return ctx.`queryCache`[input]
            else:
              if ctx.enableLogging: echo repeat2("| ", currentIndent), "failed to mark green"
              ctx.force(key)
              if not `useFingerprinting`: ctx.depGraph.markRed(key, @[])
              if ctx.enableLogging and ctx.`queryCache`.contains(input): echo repeat2("| ", currentIndent), "result: ", $ctx.`queryCache`[input]
              if not ctx.`queryCache`.contains(input):
                raise newException(Defect, "compute" & `name` & "(" & $input & "): not in cache anymore")
              return ctx.`queryCache`[input]

          assert color == Red
          if ctx.enableLogging and ctx.`queryCache`.contains(input): echo repeat2("| ", currentIndent), "red, in cache, result: ", $ctx.`queryCache`[input]
          if not ctx.`queryCache`.contains(input):
            raise newException(Defect, "compute" & `name` & "(" & $input & "): not in cache anymore")
          return ctx.`queryCache`[input]

    else:
      result.add quote do:
        proc `computeName`*(ctx: `contextName`, input: `key`): `value` =
          let timer = startTimer()
          defer:
            ctx.`executionTime` += timer.elapsed

          defer:
            if ctx.dependencyStack.len == 0:
              ctx.recursiveQueries.clear()

          let item = getItem input
          let key = (item, ctx.`updateName`)

          ctx.recordDependency(item, ctx.`updateName`)

          inc currentIndent, if ctx.enableLogging: 1 else: 0
          defer: dec currentIndent, if ctx.enableLogging: 1 else: 0
          if ctx.enableLogging: echo repeat2("| ", currentIndent - 1), "compute", `nameString`, ", ", item

          ctx.force(key)
          if not ctx.`queryCache`.contains(input):
            raise newException(Defect, "compute" & `name` & "(" & $input & "): not in cache anymore")
          return ctx.`queryCache`[input]


  # echo result.repr
