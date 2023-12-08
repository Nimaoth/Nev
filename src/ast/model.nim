import std/[options, strutils, hashes, tables, strformat, sugar, sequtils, sets]
import fusion/matching
import chroma
import workspaces/[workspace]
import util, array_table, myjsonutils, id, macro_utils, custom_logger, event, regex, custom_async

export id

logCategory "types"

defineBitFlag:
  type CellBuilderFlag* = enum
    OnlyExactMatch

defineBitFlag:
  type CellFlag* = enum
    DeleteWhenEmpty
    OnNewLine
    IndentChildren
    NoSpaceLeft
    NoSpaceRight

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

  NodeClass* = ref object
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

  AstNode* = ref object
    id*: NodeId
    class*: ClassId

    model*: Model # gets set when inserted into a parent node which is in a model, or when inserted into a model
    parent*: AstNode # gets set when inserted into a parent node
    role*: RoleId # gets set when inserted into a parent node

    properties*: seq[tuple[role: RoleId, value: PropertyValue]]
    references*: seq[tuple[role: RoleId, node: NodeId]]
    childLists*: seq[tuple[role: RoleId, nodes: seq[AstNode]]]

  CellIsVisiblePredicate* = proc(node: AstNode): bool
  CellNodeFactory* = proc(): AstNode

  CellStyle* = ref object
    noSpaceLeft*: bool
    noSpaceRight*: bool

  Cell* = ref object of RootObj
    when defined(js):
      aDebug*: cstring
    id*: CellId
    parent*: Cell
    flags*: CellFlags
    node*: AstNode
    referenceNode*: AstNode
    role*: RoleId                         # Which role of the target node this cell represents
    line*: int
    displayText*: Option[string]
    shadowText*: string
    fillChildren*: proc(map: NodeCellMap): void
    filled*: bool
    isVisible*: CellIsVisiblePredicate
    nodeFactory*: CellNodeFactory
    style*: CellStyle
    disableSelection*: bool
    disableEditing*: bool
    deleteImmediately*: bool              # If true then when this cell handles a delete event it will delete it immediately and not first select the entire cell
    deleteNeighbor*: bool                 # If true then when this cell handles a delete event it will delete the left or right neighbor cell instead
    dontReplaceWithDefault*: bool         # If true thennn
    fontSizeIncreasePercent*: float
    themeForegroundColors*: seq[string]
    themeBackgroundColors*: seq[string]
    foregroundColor*: Color
    backgroundColor*: Color

  EmptyCell* = ref object of Cell
    discard

  CellBuilderFunction* = proc(builder: CellBuilder, node: AstNode): Cell

  CellBuilder* = ref object
    builders*: Table[ClassId, seq[tuple[builderId: Id, impl: CellBuilderFunction, flags: CellBuilderFlags]]]
    preferredBuilders*: Table[ClassId, Id]
    forceDefault*: bool

  NodeCellMap* = ref object
    map*: Table[NodeId, Cell]
    cells*: Table[CellId, Cell]
    builder*: CellBuilder

  PropertyValidator* = ref object
    pattern*: Regex

  NodeValidator* = ref object
    propertyValidators*: ArrayTable[RoleId, PropertyValidator]

  ModelComputationContextBase* = ref object of RootObj

  Language* = ref object
    id {.getter.}: LanguageId
    version {.getter.}: int
    classes {.getter.}: Table[ClassId, NodeClass]
    rootNodeClasses {.getter.}: seq[NodeClass]
    # childClasses {.getter.}: Table[ClassId, seq[NodeClass]]
    builder {.getter.}: CellBuilder

    validators: Table[ClassId, NodeValidator]

    classesToLanguages {.getter.}: Table[ClassId, Language]
    baseLanguages: seq[Language]

    # functions for computing the type of a node
    typeComputers*: Table[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]
    valueComputers*: Table[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]
    scopeComputers*: Table[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]

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

    onNodeDeleted*: Event[tuple[self: Model, parent: AstNode, child: AstNode, role: RoleId, index: int]]
    onNodeInserted*: Event[tuple[self: Model, parent: AstNode, child: AstNode, role: RoleId, index: int]]
    onNodePropertyChanged*: Event[tuple[self: Model, node: AstNode, role: RoleId, oldValue: PropertyValue, newValue: PropertyValue, slice: Slice[int]]]
    onNodeReferenceChanged*: Event[tuple[self: Model, node: AstNode, role: RoleId, oldRef: NodeId, newRef: NodeId]]

  Project* = ref object
    path*: string
    modelPaths*: Table[ModelId, string]
    models*: Table[ModelId, Model]
    loaded*: bool = false
    computationContext*: ModelComputationContextBase

proc resolveReference*(self: Model, id: NodeId): Option[AstNode]
proc resolveReference*(self: Project, id: NodeId): Option[AstNode]
proc dump*(node: AstNode, model: Model = nil, recurse: bool = false): string

template forEach2*(node: AstNode, it: untyped, body: untyped): untyped =
  node.forEach proc(n: AstNode) =
    let it = n
    body

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

proc addModel*(self: Project, model: Model) =
  # log lvlWarn, fmt"addModel: {model.path}, {model.id}"
  var foundExistingNodes = false
  for root in model.rootNodes:
    for node in root.childrenRec:
      if self.resolveReference(node.id).getSome(existing):
        log lvlError, &"addModel({model.path} {model.id}): Node with id {node.id} already exists in model {existing.model.path} ({existing.model.id}).\nExisting node: {existing.dump(recurse=true)}\nNew node: {node.dump(recurse=true)}"
        foundExistingNodes = true

  if foundExistingNodes:
    return

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

method computeType*(self: ModelComputationContextBase, node: AstNode): AstNode {.base.} = discard
method getValue*(self: ModelComputationContextBase, node: AstNode): AstNode {.base.} = discard
method getScope*(self: ModelComputationContextBase, node: AstNode): seq[AstNode] {.base.} = discard
method dependOn*(self: ModelComputationContextBase, node: AstNode) {.base.} = discard

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

proc targetNode*(cell: Cell): AstNode =
  if cell.referenceNode.isNotNil:
    return cell.referenceNode
  return cell.node

proc forEach*(node: AstNode, f: proc(node: AstNode) {.closure.}) =
  f(node)
  for item in node.childLists.mitems:
    for c in item.nodes:
      c.forEach(f)

proc verify*(self: Language): bool =
  result = true
  for c in self.classes.values:
    if c.base.isNotNil:
      let baseClass = self.resolveClass(c.base.id)
      if baseClass.isNil:
        log(lvlError, fmt"Class {c.name} has unknown base class {c.base.name}")
        result = false

      if baseClass.isFinal:
        log(lvlError, fmt"Class {c.name} has base class {c.base.name} which is final")
        result = false

    if c.isFinal and c.isAbstract:
      log(lvlError, fmt"Class {c.name} is both final and abstract")
      result = false

proc newLanguage*(id: LanguageId, classes: seq[NodeClass], builder: CellBuilder,
  typeComputers: Table[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode],
  valueComputers: Table[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode],
  scopeComputers: Table[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]],
  baseLanguages: openArray[Language] = []): Language =
  new result
  result.id = id
  result.typeComputers = typeComputers
  result.valueComputers = valueComputers
  result.scopeComputers = scopeComputers
  result.baseLanguages = @baseLanguages

  for l in baseLanguages:
    for c in l.classes.values:
      result.classesToLanguages[c.id] = l

  for c in classes:
    result.classes[c.id] = c
    if c.canBeRoot:
      result.rootNodeClasses.add c

    # if c.base.isNotNil:
    #   if not result.childClasses.contains(c.base.id):
    #     result.childClasses[c.base.id] = @[]
    #   result.childClasses[c.base.id].add c

    # for i in c.interfaces:
    #   if not result.childClasses.contains(i.id):
    #     result.childClasses[i.id] = @[]
    #   result.childClasses[i.id].add c

  result.builder = builder

proc forEachChildClass*(self: Model, base: NodeClass, handler: proc(c: NodeClass)) =
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
  return model.classesToLanguages.getOrDefault(classId, nil)

proc newModel*(id: ModelId = default(ModelId)): Model =
  # log lvlWarn, fmt"newModel: {id}"
  new result
  result.id = id

proc hasLanguage*(self: Model, language: LanguageId): bool =
  for l in self.languages:
    if l.id == language:
      return true
  return false

proc addImport*(self: Model, model: Model) =
  # log lvlWarn, fmt"addImport to {self.path} ({self.id}): {model.path} ({model.id})"
  self.importedModels.incl model.id
  self.models.add model

proc addLanguage*(self: Model, language: Language) =
  if not language.verify():
    return

  self.languages.add language

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

proc resolveReference*(self: Model, id: NodeId): Option[AstNode] =
  if self.nodes.contains(id):
    return self.nodes[id].some
  else:
    for model in self.models:
      if model.nodes.contains(id):
        return model.nodes[id].some
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

let defaultNumberPattern = re"[0-9]+"
let defaultBoolPattern = re"true|false"

proc isValidPropertyValue*(language: Language, class: NodeClass, role: RoleId, value: string): bool =
  if language.validators.contains(class.id):
    if language.validators[class.id].propertyValidators.tryGet(role).getSome(validator):
      return value.match(validator.pattern)

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
  new result
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

      let childClass = language.resolveClass(desc.class)
      if childClass.isNil:
        log lvlError, fmt"Unknown class {desc.class}"
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

  raise newException(CatchableError, fmt"Unknown role {role} for node {node.id} of class {node.class}")

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

  raise newException(CatchableError, fmt"Unknown role {role} for node {node.id} of class {node.class}")

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

proc newCellBuilder*(): CellBuilder =
  new result

proc clear*(self: CellBuilder) =
  self.builders.clear()
  self.preferredBuilders.clear()
  self.forceDefault = false

proc addBuilderFor*(self: CellBuilder, classId: ClassId, builderId: Id, flags: CellBuilderFlags, builder: CellBuilderFunction) =
  # log lvlWarn, fmt"addBuilderFor {classId}"
  if self.builders.contains(classId):
    self.builders[classId].add (builderId, builder, flags)
  else:
    self.builders[classId] = @[(builderId, builder, flags)]

proc addBuilderFor*(self: CellBuilder, classId: ClassId, builderId: Id, builder: CellBuilderFunction) =
  self.addBuilderFor(classId, builderId, 0.CellBuilderFlags, builder)

proc addBuilder*(self: CellBuilder, other: CellBuilder) =
  for pair in other.builders.pairs:
    for builder in pair[1]:
      self.addBuilderFor(pair[0], builder.builderId, builder.flags, builder.impl)
  for pair in other.preferredBuilders.pairs:
    self.preferredBuilders[pair[0]] = pair[1]

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

method dump*(self: Cell, recurse: bool = false): string {.base.} = discard
method getChildAt*(self: Cell, index: int, clamp: bool): Option[Cell] {.base.} = Cell.none

proc `$`*(cell: Cell, recurse: bool = false): string = cell.dump(recurse)

method dump*(self: EmptyCell, recurse: bool = false): string =
  result.add fmt"EmptyCell(node: {self.node.id})"

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

proc jsonToAstNode*(json: JsonNode, model: Model, opt = Joptions()): Option[AstNode] =
  let id = json["id"].jsonTo NodeId
  let classId = json["class"].jsonTo ClassId

  let class = model.resolveClass(classId)
  if class.isNil:
    return AstNode.none

  var node = newAstNode(class, id.some)
  result = node.some

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
          node.add(role, childNode)
        else:
          log(lvlError, fmt"Failed to parse node from json")

proc loadFromJson*(project: Project, json: JsonNode, opt = Joptions()): bool =
  if json.kind != JObject:
    log(lvlError, fmt"Expected JObject")
    return false

  if json.hasKey("models"):
    for modelPath, modelIdJson in json["models"]:
      let id = modelIdJson.jsonTo ModelId
      project.modelPaths[id] = modelPath
      # echo "modelPath: ", modelPath, " id: ", id

  return true

proc loadFromJson*(project: Project, model: Model, workspace: WorkspaceFolder, path: string, json: JsonNode,
  resolveLanguage: proc(id: LanguageId): Option[Language],
  resolveModel: proc(project: Project, workspace: WorkspaceFolder, id: ModelId): Future[Option[Model]],
  opt = Joptions()): Future[void] {.async.} =
  model.path = path
  if json.kind != JObject:
    log(lvlError, fmt"Expected JObject")
    return

  if json.hasKey("id"):
    model.id = json["id"].jsonTo ModelId
  else:
    log(lvlError, fmt"Missing id")

  if json.hasKey("languages"):
    for languageIdJson in json["languages"]:
      let id = languageIdJson.jsonTo LanguageId
      if resolveLanguage(id).getSome(language):
        model.addLanguage(language)
      else:
        log(lvlError, fmt"Unknown language {id}")
  else:
    log(lvlWarn, fmt"Missing languages")

  if json.hasKey("models"):
    for modelIdJson in json["models"]:
      let id = modelIdJson.jsonTo ModelId
      model.importedModels.incl id
      if project.resolveModel(workspace, id).await.getSome(m):
        model.addImport(m)
      else:
        log(lvlError, fmt"Unknown model {id}")

  if json.hasKey("rootNodes"):
    for node in json["rootNodes"]:
      if node.jsonToAstNode(model, opt).getSome(node):
        model.addRootNode(node)
      else:
        log(lvlError, fmt"Failed to parse root node from json")
  else:
    log(lvlWarn, fmt"Missing root nodes")