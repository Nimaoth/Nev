import std/[tables, sets, strutils, hashes, options, strformat]
import fusion/matching
import vmath, lrucache
import misc/[id, util, timer, custom_logger]
import query_system, model, ast_ids

{.push gcsafe.}
{.push hint[XCannotRaiseY]:off.}

logCategory "model-state"

type
  Diagnostic* = object
    message*: string

  Diagnostics* = object
    queries*: Table[Dependency, seq[Diagnostic]]

func fingerprint*(node: AstNode): Fingerprint {.raises: [].}

CreateContext ModelState:
  input AstNode

  # var globalScope*: Table[Id, Symbol] = initTable[Id, Symbol]()
  var enableQueryLogging*: bool = false
  var enableExecutionLogging*: bool = false
  var diagnosticsPerNode*: Table[NodeId, Diagnostics] = initTable[NodeId, Diagnostics]()
  var diagnosticsPerQuery*: Table[Dependency, seq[NodeId]] = initTable[Dependency, seq[NodeId]]()
  var computationContextOwner: ModelComputationContextBase = nil
  var project: Project = nil
  var currentKey: Dependency

  proc inputAstNode(ctx: ModelState, id: ItemId): AstNode {.inputProvider, raises: [CatchableError].}

  proc recoverType(ctx: ModelState, key: Dependency) {.recover("Type"), raises: [].}
  # proc recoverValue(ctx: ModelState, key: Dependency) {.recover("Value"), raises: [].}

  proc computeTypeImpl(ctx: ModelState, node: AstNode): AstNode {.query("Type"), raises: [CatchableError].}
  proc computeValueImpl(ctx: ModelState, node: AstNode): AstNode {.query("Value"), raises: [CatchableError].}
  proc computeScopeImpl(ctx: ModelState, node: AstNode): seq[AstNode] {.query("Scope"), raises: [CatchableError].}
  proc computeValidImpl(ctx: ModelState, node: AstNode): bool {.query("Valid"), raises: [CatchableError].}
  # proc computeValueImpl(ctx: ModelState, node: AstNode): Value {.query("Value"), raises: [CatchableError].}

type ModelComputationContext* = ref object of ModelComputationContextBase
  state*: ModelState

proc newModelComputationContext*(project: Project): ModelComputationContext =
  result = new(ModelComputationContext)
  result.state = newModelState()
  result.state.computationContextOwner = result
  result.state.project = project

method computeType*(self: ModelComputationContext, node: AstNode): AstNode {.gcsafe, raises: [CatchableError].} =
  return self.state.computeType(node)

method getScope*(self: ModelComputationContext, node: AstNode): seq[AstNode] {.gcsafe, raises: [CatchableError].} =
  return self.state.computeScope(node)

method getValue*(self: ModelComputationContext, node: AstNode): AstNode {.gcsafe, raises: [CatchableError].} =
  return self.state.computeValue(node)

method validateNode*(self: ModelComputationContext, node: AstNode): bool {.gcsafe, raises: [CatchableError].} =
  self.state.computeValid(node)

proc addDiagnostic*(self: ModelState, node: AstNode, msg: string) =
  # debugf"addDiagnostic {msg} for {node}"
  let key = self.currentKey

  if not self.diagnosticsPerQuery.contains(key):
    self.diagnosticsPerQuery[key] = @[]

  self.diagnosticsPerQuery[key].add node.id

  if not self.diagnosticsPerNode.contains(node.id):
    self.diagnosticsPerNode[node.id] = Diagnostics()
  if not self.diagnosticsPerNode[node.id].queries.contains(key):
    self.diagnosticsPerNode[node.id].queries[key] = @[]

  self.diagnosticsPerNode[node.id].queries[key].add Diagnostic(message: msg.replace('\n', ' '))

method addDiagnostic*(self: ModelComputationContext, node: AstNode, msg: string) =
  self.state.addDiagnostic(node, msg)

method getDiagnostics*(self: ModelComputationContext, node: NodeId): seq[string] {.raises: [CatchableError].} =
  if not self.state.diagnosticsPerNode.contains(node):
    return @[]
  for ds in self.state.diagnosticsPerNode[node].queries.values:
    for d in ds:
      result.add d.message

method dependOn*(self: ModelComputationContext, node: AstNode) {.raises: [CatchableError].} =
  self.state.recordDependency(node.getItem)

method dependOnCurrentRevision*(self: ModelComputationContext) =
  self.state.dependOnCurrentRevision()

func fingerprint*(node: AstNode): Fingerprint =
  if node.isNil:
    return @[]
  let (a, b, c) = node.id.Id.deconstruct
  result = @[a.int64, b.int64, c.int64]

template logIf(condition: bool, message: string, logResult: bool) =
  let logQuery = condition
  if logQuery: inc currentIndent, 1
  defer:
    if logQuery: dec currentIndent, 1
  if logQuery: log lvlDebug, repeat2("| ", currentIndent - 1) & message
  defer:
    if logQuery and logResult:
      log lvlDebug, repeat2("| ", currentIndent) & "-> " & $result

template enableDiagnostics(key: untyped): untyped =
  # Delete old diagnostics

  let previousKey = ctx.currentKey
  ctx.currentKey = key
  if ctx.diagnosticsPerQuery.contains(key):
    # debugf"clear diagnostics for {key}"
    for id in ctx.diagnosticsPerQuery[key]:
      # debug "clear diagnostics for " & $id
      ctx.diagnosticsPerNode[id].queries.del key

  defer:
    ctx.currentKey = previousKey

  # var diagnostics: seq[Diagnostic] = @[]
  # var ids: seq[NodeId] = @[]
  # defer:
  #   if diagnostics.len > 0:
  #     ctx.diagnosticsPerQuery[key] = ids

  #     for i in 0..ids.high:
  #       let id = ids[i]
  #       let diag = diagnostics[i]
  #       if not ctx.diagnosticsPerNode.contains(id):
  #         ctx.diagnosticsPerNode[id] = Diagnostics()
  #       if not ctx.diagnosticsPerNode[id].queries.contains(key):
  #         ctx.diagnosticsPerNode[id].queries[key] = @[]

  #       ctx.diagnosticsPerNode[id].queries[key].add diag
  #   else:
  #     ctx.diagnosticsPerQuery.del key

  # template addDiagnostic[T](id: T, msg: untyped) {.used.} =
  #   ids.add(id)
  #   diagnostics.add Diagnostic(message: msg)

# proc notifySymbolChanged*(ctx: ModelState, sym: Symbol) =
#   ctx.depGraph.revision += 1
#   ctx.depGraph.changed[(sym.getItem, -1)] = ctx.depGraph.revision
#   log(lvlInfo, fmt"Invalidating symbol {sym.name} ({sym.id})")

proc insertNode*(ctx: ModelState, node: AstNode) =
  # log lvlWarn, fmt"insertNode {node}"
  ctx.depGraph.revision += 1

  if node.parent != nil:
    ctx.depGraph.changed[(node.parent.getItem, -1)] = ctx.depGraph.revision

  proc insertNodeRec(ctx: ModelState, node: AstNode) =
    let item = node.getItem
    ctx.depGraph.changed[(item, -1)] = ctx.depGraph.revision

    ctx.itemsAstNode[item] = node

    for children in node.childLists:
      for child in children.nodes:
        ctx.insertNodeRec(child)

  ctx.insertNodeRec(node)

  # var parent = node.parent
  # while parent != nil and parent.findWithParentRec(FunctionDefinition).getSome(child):
  #   let functionDefinition = child.parent
  #   ctx.depGraph.changed[(functionDefinition.getItem, -1)] = ctx.depGraph.revision
  #   parent = functionDefinition.parent

proc updateNode*(ctx: ModelState, node: AstNode) =
  # log lvlWarn, fmt"updateNode {node}"
  ctx.depGraph.revision += 1
  ctx.depGraph.changed[(node.getItem, -1)] = ctx.depGraph.revision

  # var parent = node.parent
  # while parent != nil and parent.findWithParentRec(FunctionDefinition).getSome(child):
  #   let functionDefinition = child.parent
  #   ctx.depGraph.changed[(functionDefinition.getItem, -1)] = ctx.depGraph.revision
  #   parent = functionDefinition.parent

  log(lvlInfo, fmt"Invalidating node {node}")

proc deleteNode*(ctx: ModelState, node: AstNode, recurse: bool) =
  # log lvlWarn, fmt"deleteNode {node}"
  ctx.depGraph.revision += 1

  if node.parent != nil:
    ctx.depGraph.changed[(node.parent.getItem, -1)] = ctx.depGraph.revision

  proc deleteNodeRec(ctx: ModelState, node: AstNode, recurse: bool) =
    if recurse:
      for children in node.childLists:
        for child in children.nodes:
          ctx.deleteNodeRec(child, recurse)

    let item = node.getItem
    ctx.depGraph.changed.del((item, -1))
    ctx.itemsAstNode.del(item)

    # Remove diagnostics added by the removed node
    for i, update in ctx.updateFunctions:
      let key = (item, i)
      if ctx.diagnosticsPerQuery.contains(key):
        for id in ctx.diagnosticsPerQuery[key]:
          ctx.diagnosticsPerNode[id].queries.del key
        ctx.diagnosticsPerQuery.del(key)

  ctx.deleteNodeRec(node, recurse)

  # var parent = node.parent
  # while parent != nil and parent.findWithParentRec(FunctionDefinition).getSome(child):
  #   let functionDefinition = child.parent
  #   ctx.depGraph.changed[(functionDefinition.getItem, -1)] = ctx.depGraph.revision
  #   parent = functionDefinition.parent

proc deleteAllNodesAndSymbols*(ctx: ModelState) =
  # log lvlWarn, fmt"deleteAllNodesAndSymbols"
  ctx.depGraph.revision += 1
  ctx.depGraph.changed.clear
  ctx.depGraph.verified.clear
  ctx.depGraph.fingerprints.clear
  ctx.depGraph.dependencies.clear
  ctx.itemsAstNode.clear
  ctx.queryCacheType.clear
  ctx.queryCacheValue.clear
  ctx.queryCacheScope.clear

proc inputAstNode(ctx: ModelState, id: ItemId): AstNode =
  # debugf"inputAstNode {id}"
  for model in ctx.project.models.values:
    # debugf"  check model {model.path}"
    if model.resolveReference(id.id.NodeId).getSome(node):
      # debugf"inputAstNode {id} -> {node}"
      ctx.itemsAstNode[id] = node
      return node
  return nil

proc recoverType(ctx: ModelState, key: Dependency) =
  log(lvlInfo, fmt"Recovering type for {key}")
  # todo
  # if ctx.getAstNode(key.item.id).getSome(node):
  #   # ctx.queryCacheType[node] = errorType()
  #   discard

proc computeTypeImpl(ctx: ModelState, node: AstNode): AstNode =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeTypeImpl " & $node, true)

  let key: Dependency = ctx.getTypeKey(node.getItem)
  enableDiagnostics(key)

  let language = node.language
  if language.isNil:
    ctx.addDiagnostic(node, fmt"Missing language for: {node}")
    return nil

  if not language.typeComputers.contains(node.class):
    return nil

  let typeComputer = language.typeComputers[node.class].fun

  let typ = typeComputer(ctx.computationContextOwner.ModelComputationContext, node)

  return typ

proc computeValueImpl(ctx: ModelState, node: AstNode): AstNode =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeValueImpl " & $node, true)

  let key: Dependency = ctx.getValueKey(node.getItem)
  enableDiagnostics(key)

  let language = node.language
  if language.isNil:
    ctx.addDiagnostic(node, fmt"Missing language for: {node}")
    return nil

  if not language.valueComputers.contains(node.class):
    return nil

  let valueComputer = language.valueComputers[node.class].fun

  let value = valueComputer(ctx.computationContextOwner.ModelComputationContext, node)

  return value

proc computeScopeImpl(ctx: ModelState, node: AstNode): seq[AstNode] =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeScopeImpl " & $node, true)

  let language = node.language
  if language.isNil:
    return @[]

  var class = node.nodeClass

  while class.isNotNil:
    if language.scopeComputers.contains(class.id):
      let scopeComputer = language.scopeComputers[class.id].fun
      return scopeComputer(ctx.computationContextOwner.ModelComputationContext, node)
    class = class.base

  var declarations: seq[AstNode] = @[]

  var parent = node
  while parent.isNotNil:
    ctx.computationContextOwner.ModelComputationContext.dependOn(parent)
    for children in parent.childLists:
      for child in children.nodes:
        let class: NodeClass = child.nodeClass
        if class.isSubclassOf(IdIDeclaration):
          declarations.add child

    parent = parent.parent

  return declarations

proc computeValidImpl(ctx: ModelState, node: AstNode): bool =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeScopeImpl " & $node, true)

  let key: Dependency = ctx.getValidKey(node.getItem)
  enableDiagnostics(key)

  let language = node.language
  if language.isNil:
    ctx.addDiagnostic(node, fmt"Missing language for: {node}")
    return false

  var class = node.nodeClass

  result = true

  for property in node.properties:
    if property.value.kind == String:
      if not language.isValidPropertyValue(class, property.role, property.value.stringValue, node.some):
        ctx.addDiagnostic(node, fmt"Invalid property value")
        result = false

  while class.isNotNil:
    if language.validationComputers.contains(class.id):
      let validationComputer = language.validationComputers[class.id].fun
      return validationComputer(ctx.computationContextOwner.ModelComputationContext, node)
    class = class.base
