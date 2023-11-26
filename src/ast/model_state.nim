import std/[tables, sets, strutils, hashes, options, strformat]
import fusion/matching
import vmath
import lrucache
import id, util, timer, query_system, custom_logger, model, ast_ids

logCategory "model-state"

type
  Diagnostic* = object
    message*: string

  Diagnostics* = object
    queries*: Table[Dependency, seq[Diagnostic]]

func fingerprint*(node: AstNode): Fingerprint

CreateContext ModelState:
  input AstNode

  # var globalScope*: Table[Id, Symbol] = initTable[Id, Symbol]()
  var enableQueryLogging*: bool = false
  var enableExecutionLogging*: bool = false
  var diagnosticsPerNode*: Table[Id, Diagnostics] = initTable[Id, Diagnostics]()
  var diagnosticsPerQuery*: Table[Dependency, seq[Id]] = initTable[Dependency, seq[Id]]()
  var computationContextOwner: ModelComputationContextBase = nil
  var models: seq[Model]

  proc inputAstNode(ctx: ModelState, id: ItemId): AstNode {.inputProvider.}

  proc recoverType(ctx: ModelState, key: Dependency) {.recover("Type").}
  # proc recoverValue(ctx: ModelState, key: Dependency) {.recover("Value").}

  proc computeTypeImpl(ctx: ModelState, node: AstNode): AstNode {.query("Type").}
  proc computeValueImpl(ctx: ModelState, node: AstNode): AstNode {.query("Value").}
  proc computeScopeImpl(ctx: ModelState, node: AstNode): seq[AstNode] {.query("Scope").}
  # proc computeValueImpl(ctx: ModelState, node: AstNode): Value {.query("Value").}

type ModelComputationContext* = ref object of ModelComputationContextBase
  state*: ModelState

proc newModelComputationContext*(): ModelComputationContext =
  result = new(ModelComputationContext)
  result.state = newModelState()
  result.state.computationContextOwner = result

method computeType*(self: ModelComputationContext, node: AstNode): AstNode =
  return self.state.computeType(node)

method getScope*(self: ModelComputationContext, node: AstNode): seq[AstNode] =
  return self.state.computeScope(node)

method getValue*(self: ModelComputationContext, node: AstNode): AstNode =
  return self.state.computeValue(node)

method dependOn*(self: ModelComputationContext, node: AstNode) =
  self.state.recordDependency(node.getItem)

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
  if ctx.diagnosticsPerQuery.contains(key):
    for id in ctx.diagnosticsPerQuery[key]:
      ctx.diagnosticsPerNode[id].queries.del key

  var diagnostics: seq[Diagnostic] = @[]
  var ids: seq[Id] = @[]
  defer:
    if diagnostics.len > 0:
      ctx.diagnosticsPerQuery[key] = ids

      for i in 0..ids.high:
        let id = ids[i]
        let diag = diagnostics[i]
        if not ctx.diagnosticsPerNode.contains(id):
          ctx.diagnosticsPerNode[id] = Diagnostics()
        if not ctx.diagnosticsPerNode[id].queries.contains(key):
          ctx.diagnosticsPerNode[id].queries[key] = @[]

        ctx.diagnosticsPerNode[id].queries[key].add diag
    else:
      ctx.diagnosticsPerQuery.del key

  template addDiagnostic[T](id: T, msg: untyped) {.used.} =
    ids.add(id.Id)
    diagnostics.add Diagnostic(message: msg)

# proc notifySymbolChanged*(ctx: ModelState, sym: Symbol) =
#   ctx.depGraph.revision += 1
#   ctx.depGraph.changed[(sym.getItem, -1)] = ctx.depGraph.revision
#   log(lvlInfo, fmt"Invalidating symbol {sym.name} ({sym.id})")

proc addModel*(ctx: ModelState, model: Model) =
  ctx.models.add model

proc removeModel*(ctx: ModelState, model: Model) =
  ctx.models.del model

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
  for model in ctx.models:
    if model.resolveReference(id.id.NodeId).getSome(node):
      # debugf"inputAstNode {id} -> {node}"
      ctx.itemsAstNode[id] = node
      return node
  return nil

proc recoverType(ctx: ModelState, key: Dependency) =
  log(lvlInfo, fmt"Recovering type for {key}")
  if ctx.getAstNode(key.item.id).getSome(node):
    # ctx.queryCacheType[node] = errorType()
    discard

proc computeTypeImpl(ctx: ModelState, node: AstNode): AstNode =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeTypeImpl " & $node, true)

  let key: Dependency = ctx.getTypeKey(node.getItem)
  enableDiagnostics(key)

  let language = node.language
  if language.isNil:
    addDiagnostic(node.id, fmt"Node has no language: {node}")
    return nil

  if not language.typeComputers.contains(node.class):
    addDiagnostic(node.id, fmt"Node has no type computer: {node}")
    return nil

  let typeComputer = language.typeComputers[node.class]

  let typ = typeComputer(ctx.computationContextOwner.ModelComputationContext, node)

  return typ

proc computeValueImpl(ctx: ModelState, node: AstNode): AstNode =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeValueImpl " & $node, true)

  let key: Dependency = ctx.getTypeKey(node.getItem)
  enableDiagnostics(key)

  let language = node.language
  if language.isNil:
    addDiagnostic(node.id, fmt"Node has no language: {node}")
    return nil

  if not language.valueComputers.contains(node.class):
    addDiagnostic(node.id, fmt"Node has no value computer: {node}")
    return nil

  let valueComputer = language.valueComputers[node.class]

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
      let scopeComputer = language.scopeComputers[class.id]
      return scopeComputer(ctx.computationContextOwner.ModelComputationContext, node)
    class = class.base

  var declarations: seq[AstNode] = @[]
  for root in node.model.rootNodes:
    ctx.computationContextOwner.ModelComputationContext.dependOn(root)
    for children in root.childLists:
      for child in children.nodes:
        let class: NodeClass = child.nodeClass
        if class.isSubclassOf(IdIDeclaration):
          declarations.add child

  return declarations