import std/[options, strutils, hashes, tables, strformat, sequtils, sets, os]
import fusion/matching
import chroma, regex
import misc/[util, array_table, myjsonutils, id, macro_utils, custom_logger, event, custom_async]
import workspaces/[workspace]
import platform/filesystem
import results

export id

{.push gcsafe.}
{.push raises: [].}

logCategory "types"

template defineUniqueId(name: untyped): untyped =
  type name* = distinct Id

  proc `==`*(a, b: name): bool {.borrow.}
  proc `$`*(a: name): string {.borrow.}
  proc isNone*(id: name): bool {.borrow.}
  proc isSome*(id: name): bool {.borrow.}
  proc hash*(id: name): Hash {.borrow.}
  proc fromJsonHook*(id: var name, json: JsonNode) {.borrow.}
  proc toJson*(id: name, opt: ToJsonOptions): JsonNode = newJString $id

defineUniqueId(CellId)
defineUniqueId(RoleId)
defineUniqueId(ClassId)
defineUniqueId(NodeId)
defineUniqueId(ModelId)
defineUniqueId(LanguageId)

let IdCloneOriginal* = "654fbb281446e19b3822521c".parseId.RoleId

type
  PropertyType* {.pure.} = enum
    Int, String, Bool

  PropertyValue* = object
    case kind*: PropertyType
    of Int:
      intValue*: int64
    of String:
      stringValue*: string
    of Bool:
      boolValue*: bool

  PropertyDescription* = object
    id*: RoleId
    role*: string
    typ*: PropertyType

  ChildCount* {.pure.} = enum
    One = "1", OneOrMore = "1..n", ZeroOrOne = "0..1", ZeroOrMore = "0..n"

  NodeChildDescription* = object
    id*: RoleId
    role*: string
    class*: ClassId
    count*: ChildCount

  NodeReferenceDescription* = object
    id*: RoleId
    role*: string
    class*: ClassId

  NodeClass* {.acyclic.} = ref object
    id {.getter.}: ClassId
    name {.getter.}: string
    alias {.getter.}: string
    base*: NodeClass
    interfaces {.getter.}: seq[NodeClass]
    isAbstract {.getter.}: bool
    isFinal {.getter.}: bool
    isInterface {.getter.}: bool
    properties*: seq[PropertyDescription]
    children*: seq[NodeChildDescription]
    references*: seq[NodeReferenceDescription]
    substitutionProperty {.getter.}: Option[RoleId]
    substitutionReference {.getter.}: Option[RoleId]
    precedence {.getter.}: int
    canBeRoot {.getter.}: bool
    registryIndex: int32 # Index in the global node registry (0 if not registered)

  AstNode* {.acyclic.} = ref object
    id*: NodeId
    class*: ClassId

    registryIndex: int32 # Index in the global node registry (0 if not registered)
    model* {.cursor.}: Model # gets set when inserted into a parent node which is in a model, or when inserted into a model
    parent* {.cursor.}: AstNode # gets set when inserted into a parent node
    role*: RoleId # gets set when inserted into a parent node

    properties*: seq[tuple[role: RoleId, value: PropertyValue]]
    references*: seq[tuple[role: RoleId, node: NodeId]]
    childLists*: seq[tuple[role: RoleId, nodes: seq[AstNode]]]

  PropertyValidatorKind* = enum Regex, Custom
  PropertyValidator* = ref object
    case kind*: PropertyValidatorKind
    of Regex:
      pattern*: Regex2
    of Custom:
      impl*: proc(node: Option[AstNode], property: string): bool {.gcsafe, raises: [].}

  NodeValidator* = ref object
    propertyValidators*: ArrayTable[RoleId, PropertyValidator]

  ModelComputationContextBase* = ref object of RootObj

  TypeComputer* = object
    fun*: proc(ctx: ModelComputationContextBase, node: AstNode): AstNode {.closure, gcsafe, raises: [CatchableError].}
  ValueComputer* = object
    fun*: proc(ctx: ModelComputationContextBase, node: AstNode): AstNode {.closure, gcsafe, raises: [CatchableError].}
  ScopeComputer* = object
    fun*: proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] {.closure, gcsafe, raises: [CatchableError].}
  ValidationComputer* = object
    fun*: proc(ctx: ModelComputationContextBase, node: AstNode): bool {.closure, gcsafe, raises: [CatchableError].}

  Language* {.acyclic.} = ref object
    name* : string
    id {.getter.}: LanguageId
    version {.getter.}: int
    classes {.getter.}: Table[ClassId, NodeClass]
    rootNodeClasses {.getter.}: seq[NodeClass]
    # childClasses {.getter.}: Table[ClassId, seq[NodeClass]]
    model*: Model

    validators*: Table[ClassId, NodeValidator]

    classesToLanguages {.getter.}: Table[ClassId, Language]
    baseLanguages: seq[Language]

    # functions for computing the type of a node
    typeComputers*: Table[ClassId, TypeComputer]
    valueComputers*: Table[ClassId, ValueComputer]
    scopeComputers*: Table[ClassId, ScopeComputer]
    validationComputers*: Table[ClassId, ValidationComputer]

    onChanged*: Event[Language]

    registryIndex: int32 # Index in the global node registry (0 if not registered)

  Model* = ref object
    id {.getter.}: ModelId
    path*: string
    rootNodes {.getter.}: seq[AstNode]
    tempNodes {.getter.}: seq[AstNode]
    languages {.getter.}: seq[Language]
    models {.getter.}: seq[Model]
    importedModels {.getter.}: HashSet[ModelId]
    classesToLanguages {.getter.}: Table[ClassId, Language]
    childClasses {.getter.}: Table[ClassId, seq[NodeClass]]
    nodes {.getter.}: Table[NodeId, AstNode]
    project*: Project

    registryIndex: int32 # Index in the global node registry (0 if not registered)

    onNodeDeleted*: Event[tuple[self: Model, parent: AstNode, child: AstNode, role: RoleId, index: int]]
    onNodeInserted*: Event[tuple[self: Model, parent: AstNode, child: AstNode, role: RoleId, index: int]]
    onNodePropertyChanged*: Event[tuple[self: Model, node: AstNode, role: RoleId, oldValue: PropertyValue, newValue: PropertyValue, slice: Slice[int]]]
    onNodeReferenceChanged*: Event[tuple[self: Model, node: AstNode, role: RoleId, oldRef: NodeId, newRef: NodeId]]

  Repository* = ref object of RootObj
    languages*: Table[LanguageId, Language]
    languageFutures*: Table[LanguageId, Future[Language]]
    languageModels*: Table[LanguageId, Model]
    classesToLanguages*: Table[ClassId, Language]
    childClasses*: Table[ClassId, seq[NodeClass]]
    models*: Table[ModelId, Model]

    nodeToIndex*: Table[NodeId, int32]
    nodes*: seq[AstNode]

    modelToIndex*: Table[ModelId, int32]
    modelList*: seq[Model]

  Project* = ref object
    repository*: Repository
    rootDirectory*: string
    path*: string
    modelPaths*: Table[ModelId, string]
    models*: Table[ModelId, Model]
    loaded*: bool = false
    computationContext*: ModelComputationContextBase
    dynamicLanguages*: Table[LanguageId, Language]

proc resolveReference*(self: Model, id: NodeId): Option[AstNode]
proc resolveReference*(self: Project, id: NodeId): Option[AstNode]
proc dump*(node: AstNode, model: Model = nil, recurse: bool = false): string
proc replaceReferences*(node: AstNode, idMap: var Table[NodeId, NodeId])

func wasmUserDataKey*(_: typedesc[Repository]): string = "wasm.userdata.repository"

{.pop.}
{.pop.}

# proc forEach*(node: AstNode, f: proc(node: AstNode) {.closure, gcsafe, raises: [].}) =
proc forEach*(node: AstNode, f: proc(node: AstNode) {.closure.}) {.effectsOf: [f].} =
  f(node)
  for item in node.childLists.mitems:
    for c in item.nodes:
      c.forEach(f)

template forEach2*(node: AstNode, it: untyped, body: untyped): untyped =
  node.forEach proc(n: AstNode) =
    let it = n
    body

{.push gcsafe.}
{.push raises: [].}

iterator childrenRec*(node: AstNode): AstNode =
  var stack: seq[tuple[node: AstNode, listIndex: int, childIndex: int]]
  stack.add (node, 0, 0)

  while stack.len > 0:
    let (currentNode, listIndex, childIndex) = stack.pop
    if listIndex == 0 and childIndex == 0:
      yield currentNode

    if listIndex == currentNode.childLists.len:
      continue

    if childIndex == currentNode.childLists[listIndex].nodes.len:
      stack.add (currentNode, listIndex + 1, 0)
    else:
      stack.add (currentNode, listIndex, childIndex + 1)
      stack.add (currentNode.childLists[listIndex].nodes[childIndex], 0, 0)

proc newProject*(): Project =
  new result
  result.dynamicLanguages = initTable[LanguageId, Language]()

proc addModel*(self: Project, model: Model) =
  # log lvlWarn, fmt"addModel: {model.path}, {model.id}"
  var foundExistingNodes = false
  var map = initTable[NodeId, NodeId]()
  for root in model.rootNodes:
    for node in root.childrenRec:
      if self.resolveReference(node.id).getSome(existing):
        let newId = newId().NodeId
        map[node.id] = newId
        node.id = newId

        log lvlWarn, &"addModel({model.path} {model.id}): Node with id {existing.id} already exists in model {existing.model.path} ({existing.model.id}).\nExisting node: {existing.dump(recurse=true)}\nNew node: {node.dump(recurse=true)}"
        foundExistingNodes = true

  if foundExistingNodes:
    log lvlWarn, &"Replacing references in {model.path} {model.id}: {map}"
    for root in model.rootNodes:
      root.replaceReferences(map)
    # return

  assert model.project.isNil
  model.project = self
  self.models[model.id] = model

  if model.path.len > 0:
    self.modelPaths[model.id] = model.path

proc getModel*(self: Project, id: ModelId): Option[Model] =
  if self.models.contains(id):
    return self.models[id].some

proc findModelByPath*(self: Project, path: string): Option[Model] =
  for model in self.models.values:
    if model.path == path:
      return model.some

generateGetters(NodeClass)
generateGetters(Model)
generateGetters(Language)

proc hash*(node: AstNode): Hash = node.id.hash
proc hash*(class: NodeClass): Hash = class.id.hash
proc hash*(language: Language): Hash = language.id.hash

{.push hint[XCannotRaiseY]:off.}
method computeType*(self: ModelComputationContextBase, node: AstNode): AstNode {.base, raises: [CatchableError].} = discard
method getValue*(self: ModelComputationContextBase, node: AstNode): AstNode {.base, raises: [CatchableError].} = discard
method getScope*(self: ModelComputationContextBase, node: AstNode): seq[AstNode] {.base, raises: [CatchableError].} = discard
method validateNode*(self: ModelComputationContextBase, node: AstNode): bool {.base, raises: [CatchableError].} = discard
method dependOn*(self: ModelComputationContextBase, node: AstNode) {.base, raises: [CatchableError].} = discard
method dependOnCurrentRevision*(self: ModelComputationContextBase) {.base, raises: [CatchableError].} = discard
method addDiagnostic*(self: ModelComputationContextBase, node: AstNode, msg: string) {.base, raises: [CatchableError].} = discard
method getDiagnostics*(self: ModelComputationContextBase, node: NodeId): seq[string] {.base, raises: [CatchableError].} = discard
{.pop.}

proc notifyNodeDeleted(self: Model, parent: AstNode, child: AstNode, role: RoleId, index: int) =
  self.onNodeDeleted.invoke (self, parent, child, role, index)

proc notifyNodeInserted(self: Model, parent: AstNode, child: AstNode, role: RoleId, index: int) =
  self.onNodeInserted.invoke (self, parent, child, role, index)

proc notifyNodePropertyChanged(self: Model, node: AstNode, role: RoleId, oldValue: PropertyValue, newValue: PropertyValue, slice: Slice[int]) =
  self.onNodePropertyChanged.invoke (self, node, role, oldValue, newValue, slice)

proc notifyNodeReferenceChanged(self: Model, node: AstNode, role: RoleId, oldRef: NodeId, newRef: NodeId) =
  self.onNodeReferenceChanged.invoke (self, node, role, oldRef, newRef)

proc `$`*(node: AstNode, recurse: bool = false): string
proc nodeClass*(node: AstNode): NodeClass
proc add*(node: AstNode, role: RoleId, child: AstNode)
proc resolveClass*(language: Language, classId: ClassId): NodeClass
proc newModel*(id: ModelId = default(ModelId)): Model
proc addRootNode*(self: Model, node: AstNode)
proc addLanguage*(self: Model, language: Language)

proc verify*(self: Language): bool =
  result = true
  for c in self.classes.values:
    if c.base.isNotNil:
      let baseClass = c.base
      if baseClass.isNil:
        log(lvlError, fmt"Class {c.name} has unknown base class {c.base.name}")
        result = false

      if baseClass.isFinal:
        log(lvlError, fmt"Class {c.name} has base class {c.base.name} which is final")
        result = false

    if c.isFinal and c.isAbstract:
      log(lvlError, fmt"Class {c.name} is both final and abstract")
      result = false

proc addClasses*(language: Language, classes: openArray[NodeClass]) =
  for c in classes:
    language.classes[c.id] = c
    if c.canBeRoot:
      language.rootNodeClasses.add c

proc addBaseLanguages*(language: Language, baseLanguages: openArray[Language]) =
  for l in baseLanguages:
    for c in l.classes.values:
      language.classesToLanguages[c.id] = l

    # if c.base.isNotNil:
    #   if not language.childClasses.contains(c.base.id):
    #     language.childClasses[c.base.id] = @[]
    #   language.childClasses[c.base.id].add c

    # for i in c.interfaces:
    #   if not language.childClasses.contains(i.id):
    #     language.childClasses[i.id] = @[]
    #   language.childClasses[i.id].add c

proc addRootNodes*(language: Language, rootNodes: openArray[AstNode]) =
  assert language.model.isNotNil
  for node in rootNodes:
    language.model.addRootNode node

proc update*(self: Language,
    classes: openArray[NodeClass] = [],
    typeComputers = initTable[ClassId, TypeComputer](),
    valueComputers = initTable[ClassId, ValueComputer](),
    scopeComputers = initTable[ClassId, ScopeComputer](),
    validationComputers = initTable[ClassId, ValidationComputer](),
    baseLanguages: openArray[Language] = [],
    rootNodes: openArray[AstNode] = [],
  ) =
    inc self.version
    self.classes.clear
    self.classesToLanguages.clear
    self.rootNodeClasses.setLen 0

    # validators: Table[ClassId, NodeValidator]
    self.typeComputers = typeComputers
    self.valueComputers = valueComputers
    self.scopeComputers = scopeComputers
    self.validationComputers = validationComputers

    self.addBaseLanguages(baseLanguages)
    self.addClasses(classes)

    # todo: recreate model or reuse?
    self.model = newModel(self.id.ModelId)
    self.model.addLanguage(self)
    self.addRootNodes(rootNodes)

    self.onChanged.invoke self

proc newLanguage*(id: LanguageId, name: string,
    classes: openArray[NodeClass] = [],
    typeComputers = initTable[ClassId, TypeComputer](),
    valueComputers = initTable[ClassId, ValueComputer](),
    scopeComputers = initTable[ClassId, ScopeComputer](),
    validationComputers = initTable[ClassId, ValidationComputer](),
    baseLanguages: openArray[Language] = [],
    rootNodes: openArray[AstNode] = [],
  ): Language =

  new result
  result.id = id
  result.name = name
  result.version = -1

  result.update(classes, typeComputers, valueComputers, scopeComputers, validationComputers, baseLanguages, rootNodes)

proc forEachChildClass*(self: Model, base: NodeClass, handler: proc(c: NodeClass) {.gcsafe, raises: [].}) =
  handler(base)
  if self.childClasses.contains(base.id):
    for c in self.childClasses[base.id]:
      self.forEachChildClass(c, handler)

proc resolveClass*(language: Language, classId: ClassId): NodeClass =
  if language.classes.contains(classId):
    return language.classes[classId]
  if language.classesToLanguages.contains(classId):
    return language.classesToLanguages[classId].resolveClass(classId)
  return nil

proc resolveClass*(model: Model, classId: ClassId): NodeClass =
  let language = model.classesToLanguages.getOrDefault(classId, nil)
  result = if language.isNil: nil else: language.resolveClass(classId)

proc getLanguageForClass*(model: Model, classId: ClassId): Language =
  if model.classesToLanguages.contains(classId):
    return model.classesToLanguages[classId]
  log lvlError, fmt"getLanguageForClass: no language for class {classId}"
  return nil

proc newModel*(id: ModelId = default(ModelId)): Model =
  # log lvlWarn, fmt"newModel: {id}"
  new result
  result.id = id

proc hasLanguage*(self: Model, language: LanguageId): bool =
  for l in self.languages:
    if l.id == language:
      return true
  return false

proc hasImport*(self: Model, modelId: ModelId): bool =
  for model in self.models:
    if model.id == modelId:
      result = true
      break

  assert result == self.importedModels.contains(modelId)

proc addImport*(self: Model, model: Model) =
  # log lvlWarn, fmt"addImport to {self.path} ({self.id}): {model.path} ({model.id})"
  self.importedModels.incl model.id
  self.models.add model

proc updateClassesFromLanguage(self: Model, language: Language) =
  for c in language.classes.keys:
    self.classesToLanguages[c] = language

  for c in language.classes.values:
    if c.base.isNotNil:
      if not self.childClasses.contains(c.base.id):
        self.childClasses[c.base.id] = @[]
      self.childClasses[c.base.id].add c

    for i in c.interfaces:
      if not self.childClasses.contains(i.id):
        self.childClasses[i.id] = @[]
      self.childClasses[i.id].add c

proc addLanguage*(self: Model, language: Language) =
  if not language.verify():
    return

  for baseLanguage in language.baseLanguages:
    # self.addLanguage(baseLanguage)
    self.updateClassesFromLanguage(baseLanguage)

  discard language.onChanged.subscribe proc(language: Language) {.gcsafe, raises: [].} =
    if self.hasLanguage(language.id):
      self.classesToLanguages.clear
      self.childClasses.clear
      for l in self.languages:
        self.updateClassesFromLanguage(l)

  self.languages.add language
  self.updateClassesFromLanguage(language)

proc modelDumpNodes*(self: Model) {.exportc.} =
  debugf"{self.path} modelNodes:"
  for node in self.nodes.values:
    debugf"    node {node}"

proc addRootNode*(self: Model, node: AstNode) =
  self.rootNodes.add node
  node.forEach2 n:
    n.model = self
    self.nodes[n.id] = n
    # debugf"{self.path} addFromRootNode {n}"

proc addTempNode*(self: Model, node: AstNode) =
  # log lvlWarn, &"{self.path} addTempNode {node.dump(self)}"
  self.tempNodes.add node
  self.nodes[node.id] = node
  node.forEach2 n:
    n.model = self
    self.nodes[n.id] = n
    # debugf"{self.path} addFromTempNode {n}"

proc removeTempNode*(self: Model, node: AstNode) =
  let i = self.tempNodes.find(node)
  if i >= 0:
    self.tempNodes.del i
  node.forEach2 n:
    n.model = nil
    self.nodes.del n.id

proc resolveReference*(self: Language, id: NodeId): Option[AstNode] =
  if self.model.nodes.contains(id):
    # log lvlDebug, fmt"resove reference: {id} found in language model nodes: {self.model.nodes[id]}"
    return self.model.nodes[id].some

  for language in self.baseLanguages:
    if language.resolveReference(id).getSome(node):
      return node.some

  return AstNode.none

proc resolveReference*(self: Model, id: NodeId): Option[AstNode] =
  if self.nodes.contains(id):
    return self.nodes[id].some

  for model in self.models:
    if model.nodes.contains(id):
      return model.nodes[id].some

  for language in self.languages:
    if language.resolveReference(id).getSome(node):
      return node.some

  if self.project.isNotNil:
    return self.project.resolveReference(id)

  return AstNode.none

proc resolveReference*(self: Project, id: NodeId): Option[AstNode] =
  for model in self.models.values:
    if model.nodes.contains(id):
      return model.nodes[id].some
  return AstNode.none

proc newNodeClass*(
      id: ClassId,
      name: string,
      alias: string = "",
      base: NodeClass = nil,
      interfaces: openArray[NodeClass] = [],
      isAbstract: bool = false,
      isFinal: bool = false,
      isInterface: bool = false,
      canBeRoot: bool = false,
      properties: openArray[PropertyDescription] = [],
      children: openArray[NodeChildDescription] = [],
      references: openArray[NodeReferenceDescription] = [],
      substitutionProperty: Option[RoleId] = RoleId.none,
      substitutionReference: Option[RoleId] = RoleId.none,
      precedence: int = 0,
    ): NodeClass =

  new result
  result.id = id
  result.name = name
  result.alias = alias
  result.base = base
  result.interfaces = @interfaces
  result.isAbstract = isAbstract
  result.isFinal = isFinal
  result.isInterface = isInterface
  result.canBeRoot = canBeRoot
  result.properties = @properties
  result.children = @children
  result.references = @references
  result.substitutionProperty = substitutionProperty
  result.substitutionReference = substitutionReference
  result.precedence = precedence

proc isSubclassOf*(self: NodeClass, baseClassId: ClassId): bool =
  if self.id == baseClassId:
    return true
  if self.base.isNotNil and self.base.isSubclassOf(baseClassId):
    return true
  for i in self.interfaces:
    if i.isSubclassOf(baseClassId):
      return true
  return false

proc nodeReferenceDescription*(self: NodeClass, id: RoleId): Option[NodeReferenceDescription] =
  result = NodeReferenceDescription.none
  for c in self.references:
    if c.id == id:
      return c.some

  if self.base.isNotNil and self.base.nodeReferenceDescription(id).getSome(pd):
    return pd.some

  for inter in self.interfaces:
    if inter.isNotNil and inter.nodeReferenceDescription(id).getSome(pd):
      return pd.some

proc nodeChildDescription*(self: NodeClass, id: RoleId): Option[NodeChildDescription] =
  result = NodeChildDescription.none
  for c in self.children:
    if c.id == id:
      return c.some

  if self.base.isNotNil and self.base.nodeChildDescription(id).getSome(pd):
    return pd.some

  for inter in self.interfaces:
    if inter.isNotNil and inter.nodeChildDescription(id).getSome(pd):
      return pd.some

proc propertyDescription*(self: NodeClass, id: RoleId): Option[PropertyDescription] =
  result = PropertyDescription.none
  for c in self.properties:
    if c.id == id:
      return c.some

  if self.base.isNotNil and self.base.propertyDescription(id).getSome(pd):
    return pd.some

  for inter in self.interfaces:
    if inter.isNotNil and inter.propertyDescription(id).getSome(pd):
      return pd.some

const defaultNumberPattern = re2"[0-9]+"
const defaultBoolPattern = re2"true|false"

proc isValidPropertyValue*(language: Language, class: NodeClass, role: RoleId, value: string, node: Option[AstNode] = AstNode.none): bool =
  # debugf"isValidPropertyValue {class.name} ({class.id}) {role} '{value}'"
  if language.validators.contains(class.id):
    if language.validators[class.id].propertyValidators.tryGet(role).getSome(validator):
      case validator.kind
      of Regex:
        return value.match(validator.pattern)
      of Custom:
        return validator.impl(node, value)

  if class.propertyDescription(role).getSome(desc):
    case desc.typ
    of Bool: return value.match(defaultBoolPattern)
    of Int: return value.match(defaultNumberPattern)
    of String: return true # todo: custom regex for string

  return false

proc hasChildList*(node: AstNode, role: RoleId): bool =
  result = false
  for c in node.childLists:
    if c.role == role:
      return true

proc hasChild*(node: AstNode, role: RoleId): bool =
  result = false
  for c in node.childLists:
    if c.role == role:
      return c.nodes.len > 0

proc childCount*(node: AstNode, role: RoleId): int =
  result = 0
  for c in node.childLists:
    if c.role == role:
      return c.nodes.len

proc children*(node: AstNode, role: RoleId): seq[AstNode] =
  result = @[]
  for c in node.childLists.mitems:
    if c.role == role:
      result = c.nodes
      break

iterator children*(node: AstNode, role: RoleId): (int, AstNode) =
  for c in node.childLists.mitems:
    if c.role == role:
      for i, node in c.nodes:
        yield (i, node)
      break

proc firstChild*(node: AstNode, role: RoleId): Option[AstNode] =
  result = AstNode.none
  for c in node.childLists.mitems:
    if c.role == role:
      if c.nodes.len > 0:
        result = c.nodes[0].some
      break

proc lastChild*(node: AstNode, role: RoleId): Option[AstNode] =
  result = AstNode.none
  for c in node.childLists.mitems:
    if c.role == role:
      if c.nodes.len > 0:
        result = c.nodes.last.some
      break

proc hasReference*(node: AstNode, role: RoleId): bool =
  result = false
  for c in node.references:
    if c.role == role:
      return true

proc reference*(node: AstNode, role: RoleId): NodeId =
  result = default(NodeId)
  for c in node.references:
    if c.role == role:
      result = c.node
      break

proc resolveReference*(node: AstNode, role: RoleId): Option[AstNode] =
  result = AstNode.none
  if node.model.isNil:
    return
  for c in node.references:
    if c.role == role:
      result = node.model.resolveReference(c.node)
      break

proc resolveOriginal*(node: AstNode, recurse: bool): Option[AstNode] =
  result = AstNode.none
  if node.model.isNil:
    return

  for c in node.references:
    if c.role == IdCloneOriginal:
      let original = node.model.resolveReference(c.node)
      if recurse and original.isSome:
        return original.get.resolveOriginal(recurse)
      return original

  return node.some

proc setReference*(node: AstNode, role: RoleId, target: NodeId) =
  for c in node.references.mitems:
    if c.role == role:
      if node.model.isNotNil:
        node.model.notifyNodeReferenceChanged(node, role, c.node, target)
      c.node = target
      break

proc hasProperty*(node: AstNode, role: RoleId): bool =
  result = false
  for c in node.properties:
    if c.role == role:
      return true

proc property*(node: AstNode, role: RoleId): Option[PropertyValue] =
  result = PropertyValue.none
  for c in node.properties:
    if c.role == role:
      result = c.value.some
      break

proc setProperty*(node: AstNode, role: RoleId, value: PropertyValue, slice: Slice[int] = 0..0) =
  for c in node.properties.mitems:
    if c.role == role:
      if node.model.isNotNil:
        node.model.notifyNodePropertyChanged(node, role, c.value, value, slice)
      c.value = value
      break

proc propertyDescription*(node: AstNode, role: RoleId): Option[PropertyDescription] =
  let class = node.nodeClass
  if class.isNotNil:
    return class.propertyDescription(role)
  return PropertyDescription.none

proc getDefaultValue*(_: typedesc[PropertyValue], typ: PropertyType): PropertyValue =
  result = PropertyValue(kind: typ)
  case typ
  of PropertyType.Bool: result.boolValue = false
  of PropertyType.Int: result.intValue = 0
  of PropertyType.String: result.stringValue = ""

proc addMissingFieldsForClass*(self: AstNode, class: NodeClass) =
  for inter in class.interfaces:
    self.addMissingFieldsForClass(inter)

  if class.base.isNotNil:
    self.addMissingFieldsForClass(class.base)

  for desc in class.properties:
    if not self.hasProperty(desc.id):
      self.properties.add (desc.id, PropertyValue.getDefaultValue(desc.typ))

  for desc in class.children:
    if not self.hasChildList(desc.id):
      self.childLists.add (desc.id, @[])

  for desc in class.references:
    if not self.hasReference(desc.id):
      self.references.add (desc.id, NodeId.default)

proc newAstNode*(class: NodeClass, id: Option[NodeId] = NodeId.none): AstNode =
  let id = if id.isSome: id.get else: newId().NodeId
  result = AstNode()
  result.id = id
  result.class = class.id
  result.addMissingFieldsForClass(class)

proc isUnique*(model: Model, class: NodeClass): bool =
  if class.isFinal:
    return true
  if not model.childClasses.contains(class.id):
    return true
  return false

proc fillDefaultChildren*(node: AstNode, model: Model, onlyUnique: bool = false) =
  let language = model.classesToLanguages.getOrDefault(node.class, nil)
  let class = language.resolveClass(node.class)

  for desc in class.children:
    if desc.count in {ChildCount.One, ChildCount.OneOrMore}:
      if node.childCount(desc.id) > 0:
        continue

      let childClass = model.resolveClass(desc.class)
      if childClass.isNil:
        log lvlError, fmt"fillDefaultChildren {node} ({model.path}, {model.id}): Unknown class {desc.class}"
        continue

      let isUnique = model.isUnique(childClass)
      if onlyUnique and not isUnique:
        continue

      let child = newAstNode(childClass)
      child.fillDefaultChildren(model, onlyUnique)
      node.add(desc.id, child)

proc ancestor*(node: AstNode, distance: int): AstNode =
  result = node
  for i in 1..distance:
    result = result.parent

proc isDescendant*(node: AstNode, ancestor: AstNode): bool =
  ### Returns true if ancestor is part of the parent chain of node
  result = false
  var temp = node
  while temp.isNotNil:
    if temp.parent == ancestor:
      return true
    temp = temp.parent

proc depth*(node: AstNode): int =
  result = 0
  var temp = node.parent
  while temp.isNotNil:
    inc result
    temp = temp.parent

proc language*(node: AstNode): Language =
  result = if node.model.isNil: nil else: node.model.classesToLanguages.getOrDefault(node.class, nil)

proc nodeClass*(node: AstNode): NodeClass =
  let language = node.language
  result = if language.isNil: nil else: language.resolveClass(node.class)

proc selfDescription*(node: AstNode): Option[NodeChildDescription] =
  ### Returns the NodeChildDescription of the parent node which describes the role this node is used as.
  if node.parent.isNil:
    return NodeChildDescription.none
  let class = node.parent.nodeClass
  if class.isNil:
    return NodeChildDescription.none
  return class.nodeChildDescription(node.role)

proc canHaveSiblings*(node: AstNode): bool =
  ### Returns true if the node is in a role which allows more siblings in that role
  if node.selfDescription().getSome(desc):
    case desc.count
    of ChildCount.One, ChildCount.ZeroOrOne: # Parent already has this as child, so no more children allowed
      return false
    of ChildCount.OneOrMore, ChildCount.ZeroOrMore:
      return true
  else:
    return false

proc canInsertInto*(node: AstNode, role: RoleId): bool =
  ### Returns true if the node can have more children of the specified role
  if node.nodeClass.nodeChildDescription(role).getSome(desc):
    let childCount = node.children(role).len
    case desc.count
    of ChildCount.One, ChildCount.ZeroOrOne:
      return childCount == 0
    of ChildCount.OneOrMore, ChildCount.ZeroOrMore:
      return true
  else:
    return false

proc index*(node: AstNode): int =
  ### Returns the index of node in it's role
  if node.parent.isNil:
    return -1
  return node.parent.children(node.role).find node

proc isRequiredAndDefault*(node: AstNode): bool =
  ### Returns true if this node is the default node (class is the class of it's slot) and it is the only child in a 1+ slot
  if node.parent.isNil:
    return false

  let desc = node.selfDescription.get
  if desc.count in {One, OneOrMore} and node.parent.childCount(node.role) == 1 and node.class == desc.class:
    return true

  return false

proc insert*(node: AstNode, role: RoleId, index: int, child: AstNode) =
  ## Adds `child` as child of `node` at index `index` in the given `role`. Asserts that `node` has a child list for the given `role`
  assert child.isNotNil

  if child.id.isNone:
    child.id = newId().NodeId
  child.parent = node
  child.role = role

  if node.model.isNotNil:
    child.forEach2 n:
      n.model = node.model
      node.model.nodes[n.id] = n

  for c in node.childLists.mitems:
    if c.role == role:
      c.nodes.insert child, index
      if node.model.isNotNil:
        node.model.notifyNodeInserted(node, child, role, index)
      return

  raiseAssert(fmt"Unknown role {role} for node {node.id} of class {node.class}")

proc setChild*(node: AstNode, role: RoleId, child: AstNode) =
  ## Sets `child` as child of `node` in the given `role`. Asserts that `node` has a child list for the given `role`
  assert child.isNotNil

  if child.id.isNone:
    child.id = newId().NodeId
  child.parent = node
  child.role = role

  if node.model.isNotNil:
    child.forEach2 n:
      n.model = node.model
      node.model.nodes[n.id] = n

  for c in node.childLists.mitems:
    if c.role == role:
      # delete existing
      for i, existing in c.nodes:
        if node.model.isNotNil:
          node.model.notifyNodeDeleted(node, existing, role, i)
        existing.forEach2 n:
          n.model = nil
          node.model.nodes.del n.id

      c.nodes.setLen 1
      c.nodes[0] = child
      if node.model.isNotNil:
        node.model.notifyNodeInserted(node, child, role, 0)
      return

  raiseAssert(fmt"Unknown role {role} for node {node.id} of class {node.class}")

proc remove*(node: AstNode, child: AstNode) =
  for children in node.childLists.mitems:
    if children.role == child.role:
      let i = children.nodes.find(child)
      if i != -1:
        if node.model.isNotNil:
          node.model.notifyNodeDeleted(node, child, child.role, i)

        children.nodes.delete i

        child.forEach2 n:
          n.model = nil
          node.model.nodes.del n.id

      return

proc remove*(node: AstNode, role: RoleId, index: int) =
  for children in node.childLists.mitems:
    if children.role == role:
      if index < 0 or index >= children.nodes.len:
        continue

      let child = children.nodes[index]

      if node.model.isNotNil:
        node.model.notifyNodeDeleted(node, child, role, index)

      children.nodes.delete index

      child.forEach2 n:
        n.model = nil
        node.model.nodes.del n.id

      return

proc replace*(node: AstNode, role: RoleId, index: int, child: AstNode) =
  if child.id.isNone:
    child.id = newId().NodeId
  child.parent = node
  child.role = role

  for children in node.childLists.mitems:
    if children.role == role:
      if index < 0 or index >= children.nodes.len:
        continue

      let oldChild = children.nodes[index]

      if node.model.isNotNil:
        node.model.notifyNodeDeleted(node, oldChild, role, index)

      oldChild.forEach2 n:
        n.model = nil
        node.model.nodes.del n.id

      if node.model.isNotNil:
        child.forEach2 n:
          n.model = node.model
          node.model.nodes[n.id] = n

      children.nodes[index] = child

      if node.model.isNotNil:
        node.model.notifyNodeInserted(node, child, role, index)

proc replaceWith*(node: AstNode, other: AstNode) =
  node.parent.replace(node.role, node.index, other)

proc removeFromParent*(node: AstNode) =
  if node.parent.isNil:
    return
  node.parent.remove(node)

proc add*(node: AstNode, role: RoleId, child: AstNode) =
  ## Adds `child` as the last child of `node` in the given `role`. Asserts that `node` has a child list for the given `role`
  node.insert(role, node.children(role).len, child)

proc addChild*(node: AstNode, role: RoleId, child: AstNode) =
  ## Adds `child` as the last child of `node` in the given `role`. Asserts that `node` has a child list for the given `role`
  node.insert(role, node.children(role).len, child)

proc forceAddChild*(node: AstNode, role: RoleId, child: AstNode) =
  ## Adds `child` as the last child of `node` in the given `role`. If `node` doesn't have a child list for the given `role` then one is created.
  if node.hasChildList(role):
    node.insert(role, node.children(role).len, child)
  else:
    node.childLists.add (role, @[child])

proc forceSetChild*(node: AstNode, role: RoleId, child: AstNode) =
  ## Sets `child` as the only child of `node` in the given `role`. If `node` doesn't have a child list for the given `role` then one is created.
  ## If there is already a child in that role it is removed.
  if node.hasChildList(role):
    node.setChild(role, child)
  else:
    node.childLists.add (role, @[child])

proc replaceWithDefault*(node: AstNode, fillDefaultChildren: bool = false): Option[AstNode] =
  if node.parent.isNil:
    return AstNode.none

  let desc = node.selfDescription.get

  var child = newAstNode(node.model.resolveClass(desc.class))
  if fillDefaultChildren:
    child.fillDefaultChildren(node.model)

  # debugf"replaceWithDefault: replacing {node} with {child}"
  node.parent.replace(node.role, node.index, child)

  return child.some

proc deleteOrReplaceWithDefault*(node: AstNode, fillDefaultChildren: bool = false): Option[AstNode] =
  ## Remove the given node from it's parent. If the role requires at least one child then replace the node with a default node.
  ## Returns the new default node if replaced or none if removed.
  if node.parent.isNil:
    return AstNode.none

  # debugf"deleteOrReplaceWithDefault: {node} {node.selfDescription}"
  let desc = node.selfDescription.get
  if desc.count in {One, OneOrMore} and node.parent.childCount(node.role) == 1:
    var child = newAstNode(node.model.resolveClass(desc.class))
    if fillDefaultChildren:
      child.fillDefaultChildren(node.model)

    # debugf"deleteOrReplaceWithDefault: replacing {node} with {child}"
    node.parent.replace(node.role, node.index, child)

    return child.some

  else:
    # debugf"deleteOrReplaceWithDefault: removing {node} from parent"
    node.removeFromParent()
    return AstNode.none

proc insertDefaultNode*(node: AstNode, role: RoleId, index: int, fillDefaultChildren: bool = false): Option[AstNode] =
  result = AstNode.none

  let class = node.nodeClass
  let desc = class.nodeChildDescription(role).get

  let language = node.model.classesToLanguages.getOrDefault(desc.class, nil)
  if language.isNil:
    return

  let childClass = language.resolveClass(desc.class)
  if childClass.isNil:
    return

  var child = newAstNode(childClass)
  if fillDefaultChildren:
    child.fillDefaultChildren(node.model)

  node.insert(role, index, child)

  return child.some

proc clone*(node: AstNode, idMap: var Table[NodeId, NodeId], model: Model, linkOriginal: bool = false): AstNode =
  assert model.isNotNil

  let newNodeId = newId().NodeId
  let class = model.resolveClass(node.class)
  result = newAstNode(class, newNodeId.some)
  idMap[node.id] = newNodeId

  result.references = node.references
  result.properties = node.properties

  for children in node.childLists.mitems:
    for child in children.nodes:
      result.add(children.role, child.clone(idMap, model, linkOriginal))

  if linkOriginal:
    if result.hasReference(IdCloneOriginal):
      result.setReference(IdCloneOriginal, node.id)
    else:
      result.references.add (IdCloneOriginal, node.id)

proc replaceReferences*(node: AstNode, idMap: var Table[NodeId, NodeId]) =
  for role in node.references.mitems:
    if role.role == IdCloneOriginal:
      continue

    if idMap.contains(role.node):
      role.node = idMap[role.node]

  for children in node.childLists.mitems:
    for child in children.nodes:
      child.replaceReferences(idMap)

proc cloneAndMapIds*(node: AstNode, model: Model = nil, linkOriginal: bool = false): AstNode =
  let model = model ?? node.model
  assert model.isNotNil

  var idMap = initTable[NodeId, NodeId]()
  let newNode = node.clone(idMap, model, linkOriginal)
  newNode.replaceReferences(idMap)
  # echo &"cloneAndMapIds: {node.dump(recurse=true)}\n->\n{newNode.dump(model=model, recurse=true)}"
  return newNode

proc dump*(node: AstNode, model: Model = nil, recurse: bool = false): string =
  if node.isNil:
    return "AstNode(nil)"

  let model = model ?? node.model
  let language = if model.isNil: nil else: model.classesToLanguages.getOrDefault(node.class, nil)
  let class = if language.isNil: nil else: language.resolveClass(node.class)

  if class.isNil:
    result.add $node.class
  else:
    result.add class.name

  result.add "(id: " & $node.id & "):"

  # ├ └ ─ │ ├─

  for role in node.properties.mitems:
    result.add "\n│ "
    if class.isNotNil and class.propertyDescription(role.role).getSome(desc):
      result.add desc.role
    else:
      result.add $role.role
    result.add ": "
    result.add $role.value

  for role in node.references.mitems:
    result.add "\n│ "
    if class.isNotNil and class.nodeReferenceDescription(role.role).getSome(desc):
      result.add desc.role
    elif role.role == IdCloneOriginal:
      result.add "!CloneOriginal"
    else:
      result.add $role.role
    result.add ": "
    result.add $role.node

  if not recurse:
    return

  var roleIndex = 0
  for role in node.childLists.mitems:
    defer: inc roleIndex

    result.add "\n│ "
    if class.isNotNil and class.nodeChildDescription(role.role).getSome(desc):
      result.add desc.role
    else:
      result.add $role.role
    result.add ":"

    for i, c in role.nodes:
      if i == role.nodes.high and roleIndex == node.childLists.high:
        result.add "\n└───"
      else:
        result.add "\n├───"

      let indent = if i < role.nodes.high or roleIndex < node.childLists.high: "│   " else: "    "
      result.add indent(dump(c, model, recurse), 1, indent)[indent.len..^1]

proc `$`*(node: AstNode, recurse: bool = false): string =
  if node.isNil:
    return "AstNode(nil)"

  node.dump(node.model, recurse)

proc toJson*(value: PropertyValue, opt = initToJsonOptions()): JsonNode =
  case value.kind
  of Bool: return newJBool(value.boolValue)
  of String: return newJString(value.stringValue)
  of Int: return newJInt(value.intValue)

proc toJson*(node: AstNode, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["id"] = node.id.toJson(opt)
  result["class"] = node.class.toJson(opt)

  if node.properties.len > 0:
    var arr = newJArray()
    for (key, item) in node.properties.mitems:
      arr.add [key.toJson(opt), item.toJson(opt)].toJArray
    result["properties"] = arr

  if node.references.len > 0:
    var arr = newJArray()
    for (key, item) in node.references.mitems:
      arr.add [key.toJson(opt), item.toJson(opt)].toJArray
    result["references"] = arr

  if node.childLists.len > 0:
    var arr = newJArray()
    for (key, children) in node.childLists.mitems:
      var arr2 = newJArray()
      for c in children:
        arr2.add c.toJson(opt)
      arr.add [key.toJson(opt), arr2].toJArray
    result["children"] = arr

proc toJson*(nodes: openArray[AstNode], opt = initToJsonOptions()): JsonNode =
  result = newJArray()
  for node in nodes:
    result.add node.toJson(opt)

proc toJson*(model: Model, opt = initToJsonOptions()): JsonNode =
  result = newJObject()

  result["id"] = model.id.toJson(opt)
  result["languages"] = model.languages.mapIt(it.id.Id.toJson(opt)).toJson(opt)
  result["models"] = model.importedModels.mapIt(it.Id.toJson(opt)).toJson(opt)

  var rootNodes = newJArray()
  for node in model.rootNodes:
    rootNodes.add node.toJson(opt)
  result["rootNodes"] = rootNodes

proc toJson*(project: Project, opt = initToJsonOptions()): JsonNode =
  result = newJObject()

  var models = newJObject()
  for (id, path) in project.modelPaths.pairs:
    models[path] = id.toJson(opt)

  result["models"] = models

proc fromJsonHook*(value: var PropertyValue, json: JsonNode) =
  if json.kind == JString:
    value = PropertyValue(kind: String, stringValue: json.str)
  elif json.kind == JBool:
    value = PropertyValue(kind: Bool, boolValue: json.getBool())
  elif json.kind == JInt:
    value = PropertyValue(kind: Int, intValue: json.num)
  else:
    log(lvlError, fmt"Unknown PropertyValue {json}")

proc jsonToAstNode*(json: JsonNode, model: Model, opt = Joptions()): Option[AstNode] {.raises: [ValueError].} =
  let id = json["id"].jsonTo NodeId
  let classId = json["class"].jsonTo ClassId

  let class = model.resolveClass(classId)
  if class.isNil:
    log lvlError, fmt"jsonToAstNode: failed to resolve class {classId}"
    return AstNode.none

  var node = newAstNode(class, id.some)

  if json.hasKey("properties"):
    for entry in json["properties"]:
      let role = entry[0].jsonTo RoleId
      let value = entry[1].jsonTo PropertyValue
      node.setProperty(role, value)

  if json.hasKey("references"):
    for entry in json["references"]:
      let role = entry[0].jsonTo RoleId
      let id = entry[1].jsonTo NodeId
      node.setReference(role, id)

  if json.hasKey("children"):
    for entry in json["children"]:
      let role = entry[0].jsonTo RoleId
      for childJson in entry[1]:
        if childJson.jsonToAstNode(model, opt).getSome(childNode):
          node.forceAddChild(role, childNode)
        else:
          log(lvlError, fmt"Failed to parse node from json")

  return node.some

# todo: return Result[]
proc loadFromJson*(project: Project, json: JsonNode, opt = Joptions()): bool =
  if json.kind != JObject:
    log lvlError, fmt"Expected JObject"
    return false

  try:
    if json.hasKey("models"):
      for modelPath, modelIdJson in json["models"]:
        let absolutePath = if modelPath.isAbsolute:
          modelPath
        else:
          project.rootDirectory // modelPath

        let id = modelIdJson.jsonTo ModelId
        project.modelPaths[id] = absolutePath
        log lvlInfo, fmt"[Project.loadFromJson] Contains model ({id}): '{absolutePath}'"

  except ValueError as e:
    log lvlError, fmt"Failet to decode json: {e.msg}\n{json}"
    return false

  return true

proc loadFromJsonAsync*(model: Model, project: Project, workspace: Workspace, path: string, json: JsonNode,
  resolveLanguage: proc(project: Project, workspace: Workspace, id: LanguageId): Future[Option[Language]] {.gcsafe, async: (raises: []).},
  resolveModel: proc(project: Project, workspace: Workspace, id: ModelId): Future[Option[Model]] {.gcsafe, async: (raises: []).},
  opt = Joptions()): Future[bool] {.async.} =
  model.path = path
  if json.kind != JObject:
    log(lvlError, fmt"Expected JObject")
    return false

  try:
    if json.hasKey("id"):
      model.id = json["id"].jsonTo ModelId
    else:
      log(lvlError, fmt"Missing id")
      return false

    if json.hasKey("languages"):
      for languageIdJson in json["languages"]:
        let id = languageIdJson.jsonTo LanguageId
        if resolveLanguage(project, workspace, id).await.getSome(language):
          model.addLanguage(language)
        else:
          log(lvlError, fmt"Unknown language {id}")
          return false
    else:
      log(lvlWarn, fmt"Missing languages")

    if json.hasKey("models"):
      for modelIdJson in json["models"]:
        let id = modelIdJson.jsonTo ModelId
        model.importedModels.incl id
        if resolveModel(project, workspace, id).await.getSome(m):
          model.addImport(m)
        else:
          log(lvlError, fmt"Unknown model {id}")
          return false

    if json.hasKey("rootNodes"):
      for node in json["rootNodes"]:
        if node.jsonToAstNode(model, opt).getSome(node):
          model.addRootNode(node)
        else:
          log(lvlError, fmt"Failed to parse root node from json")
          return false
    else:
      log(lvlWarn, fmt"Missing root nodes")

  except ValueError as e:
    log lvlError, fmt"Failet to decode json: {e.msg}\n{json}"
    return false

  return true

proc loadFromJson*(model: Model, path: string, json: JsonNode,
  resolveLanguage: proc(id: LanguageId): Option[Language] {.gcsafe, raises: [].},
  resolveModel: proc(project: Project, id: ModelId): Option[Model] {.gcsafe, raises: [].},
  opt = Joptions()): bool =
  model.path = path
  if json.kind != JObject:
    log(lvlError, fmt"Expected JObject")
    return false

  try:
    if json.hasKey("id"):
      model.id = json["id"].jsonTo ModelId
    else:
      log(lvlError, fmt"Missing id")
      return false

    if json.hasKey("languages"):
      for languageIdJson in json["languages"]:
        let id = languageIdJson.jsonTo LanguageId
        if resolveLanguage(id).getSome(language):
          model.addLanguage(language)
        else:
          log(lvlError, fmt"Unknown language {id}")
          return false
    else:
      log(lvlWarn, fmt"Missing languages")

    if json.hasKey("models"):
      for modelIdJson in json["models"]:
        let id = modelIdJson.jsonTo ModelId
        model.importedModels.incl id
        if resolveModel(model.project, id).getSome(m):
          model.addImport(m)
        else:
          log(lvlError, fmt"Unknown model {id}")
          return false

    if json.hasKey("rootNodes"):
      for node in json["rootNodes"]:
        if node.jsonToAstNode(model, opt).getSome(node):
          model.addRootNode(node)
        else:
          log(lvlError, fmt"Failed to parse root node from json")
          return false
    else:
      log(lvlWarn, fmt"Missing root nodes")

  except ValueError as e:
    log lvlError, fmt"Failet to decode json: {e.msg}\n{json}"
    return false

  return true

proc getNode*(self: Repository, index: int32): Option[AstNode] =
  if index <= 0 or index >= self.nodes.len:
    log lvlError, fmt"getNode: index {index} out of range"
    return AstNode.none
  return self.nodes[index].some

proc getNode*(self: Repository, id: NodeId): Option[AstNode] =
  let index = self.nodeToIndex.getOrDefault(id, -1.int32)
  if index <= 0 or index >= self.nodes.len:
    log lvlError, fmt"getNode: {id} not registered"
    return AstNode.none
  return self.nodes[index].some

proc registerNode*(self: Repository, node: AstNode): int32 =
  if node.registryIndex != 0:
    log lvlWarn, fmt"registerNode: node {node} already registered"
    return node.registryIndex

  result = self.nodes.len.int32
  node.registryIndex = result
  self.nodes.add node
  self.nodeToIndex[node.id] = result

proc getNodeIndex*(self: Repository, node: AstNode): int32 =
  if node.registryIndex != 0:
    return node.registryIndex

  return self.registerNode(node)

proc getModel*(self: Repository, index: int32): Option[Model] =
  if index <= 0 or index >= self.modelList.len:
    log lvlError, fmt"getModel: index {index} out of range"
    return Model.none
  return self.modelList[index].some

proc registerModel*(self: Repository, model: Model): int32 =
  if model.registryIndex != 0:
    log lvlWarn, fmt"registerModel: model {model.path} ({model.id}) already registered"
    return model.registryIndex

  result = self.modelList.len.int32
  model.registryIndex = result
  self.models[model.id] = model
  self.modelList.add model
  self.modelToIndex[model.id] = result

proc updateClassesFromLanguage(self: Repository, language: Language) =
  for c in language.classes.keys:
    self.classesToLanguages[c] = language

  for c in language.classes.values:
    if c.base.isNotNil:
      if not self.childClasses.contains(c.base.id):
        self.childClasses[c.base.id] = @[]
      self.childClasses[c.base.id].add c

    for i in c.interfaces:
      if not self.childClasses.contains(i.id):
        self.childClasses[i.id] = @[]
      self.childClasses[i.id].add c

proc registerLanguage*(self: Repository, language: Language, model: Model = nil) =
  log lvlInfo, &"[repository] Register language: {language.name} ({language.id})"
  if not language.verify():
    log lvlError, &"[repository] Failed to verify language"
    return

  for baseLanguage in language.baseLanguages:
    # self.addLanguage(baseLanguage)
    self.updateClassesFromLanguage(baseLanguage)

  discard language.onChanged.subscribe proc(language: Language) {.gcsafe, raises: [].} =
    if self.languages.contains(language.id):
      self.classesToLanguages.clear
      self.childClasses.clear
      for l in self.languages.values:
        self.updateClassesFromLanguage(l)

  self.languages[language.id] = language
  self.updateClassesFromLanguage(language)

  self.languages[language.id] = language
  if model.isNotNil:
    self.languageModels[language.id] = model
    discard self.registerModel(model)

proc registerLanguageModel*(self: Repository, languageId: LanguageId, model: Model): int32 =
  log lvlInfo, &"[repository] Register language model for {languageId}: {model.id}"
  assert languageId.ModelId == model.id
  assert languageId in self.languages
  self.languageModels[languageId] = model
  discard self.registerModel(model)

proc getModelIndex*(self: Repository, model: Model): int32 =
  if model.registryIndex != 0:
    return model.registryIndex

  return self.registerModel(model)

# todo: return Option[]
proc resolveClass*(self: Repository, classId: ClassId): NodeClass =
  let language = self.classesToLanguages.getOrDefault(classId, nil)
  result = if language.isNil: nil else: language.resolveClass(classId)

proc getLanguageForClass*(self: Repository, classId: ClassId): Language =
  if self.classesToLanguages.contains(classId):
    return self.classesToLanguages[classId]
  log lvlError, fmt"getLanguageForClass: no language for class {classId}"
  return nil

proc language*(self: Repository, languageId: LanguageId): Option[Language] =
  self.languages.withValue(languageId, val):
    return val[].some

proc languageModel*(self: Repository, languageId: LanguageId): Option[Model] =
  self.languageModels.withValue(languageId, val):
    return val[].some

proc model*(self: Repository, modelId: ModelId): Option[Model] =
  self.models.withValue(modelId, val):
    return val[].some
