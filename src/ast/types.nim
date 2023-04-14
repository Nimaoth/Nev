
import std/[options, algorithm, strutils, hashes, enumutils, json, jsonutils, tables, macros, sequtils, strformat]
import fusion/matching
import util, id, macro_utils, custom_logger
import print

type
  PropertyType* {.pure.} = enum
    Int, String, Bool

  PropertyValue* = object
    case kind*: PropertyType
    of Int:
      intValue*: int
    of String:
      stringValue*: string
    of Bool:
      boolValue*: bool

  PropertyDescription* = object
    id*: Id
    role*: string
    typ*: PropertyType

  ChildCount* {.pure.} = enum
    One = "1", OneOrMore = "1..n", ZeroOrOne = "0..1", ZeroOrMore = "0..n"

  NodeChildDescription* = object
    id*: Id
    role*: string
    class*: Id
    count*: ChildCount

  NodeReferenceDescription* = object
    id*: Id
    role*: string
    class*: Id

  NodeClass* = ref object
    id {.getter.}: Id
    name {.getter.}: string
    alias {.getter.}: string
    base {.getter.}: NodeClass
    interfaces {.getter.}: seq[NodeClass]
    isAbstract {.getter.}: bool
    isInterface {.getter.}: bool
    properties {.getter.}: seq[PropertyDescription]
    children {.getter.}: seq[NodeChildDescription]
    references {.getter.}: seq[NodeReferenceDescription]

  AstNode* = ref object
    id*: Id
    class*: Id

    model*: Model # gets set when inserted into a parent node which is in a model, or when inserted into a model
    parent*: AstNode # gets set when inserted into a parent node
    role*: Id # gets set when inserted into a parent node

    properties*: seq[tuple[role: Id, value: PropertyValue]]
    references*: seq[tuple[role: Id, node: Id]]
    childLists*: seq[tuple[role: Id, nodes: seq[AstNode]]]

  CellIsVisiblePredicate* = proc(node: AstNode): bool

  CellStyle* = ref object
    onNewLine*: bool
    addNewlineAfter*: bool
    indentChildren*: bool
    noSpaceLeft*: bool
    noSpaceRight*: bool

  Cell* = ref object of RootObj
    id*: Id
    parent*: Cell
    node*: AstNode
    line*: int
    fillChildren*: proc(): void
    filled*: bool
    isVisible*: CellIsVisiblePredicate
    style*: CellStyle
    disableSelection*: bool

  EmptyCell* = ref object of Cell
    discard

  CellBuilderFunction* = proc(builder: CellBuilder, node: AstNode): Cell

  CellBuilder* = ref object
    builders: Table[Id, seq[tuple[builderId: Id, impl: CellBuilderFunction]]]
    preferredBuilders: Table[Id, Id]

  Language* = ref object
    id {.getter.}: Id
    version {.getter.}: int
    classes {.getter.}: Table[Id, NodeClass]
    builder {.getter.}: CellBuilder

  Model* = ref object
    id {.getter.}: Id
    rootNodes {.getter.}: seq[AstNode]
    languages {.getter.}: seq[Language]
    importedModels {.getter.}: seq[Model]
    classesToLanguages {.getter.}: Table[Id, Language]
    nodes {.getter.}: Table[Id, AstNode]

  Project* = ref object
    models*: Table[Id, Model]
    builder*: CellBuilder

generateGetters(NodeClass)
generateGetters(Model)
generateGetters(Language)

proc nodeClass*(node: AstNode): NodeClass

proc forEach*(node: AstNode, f: proc(node: AstNode)) =
  f(node)
  for item in node.childLists.mitems:
    for c in item.nodes:
      c.forEach(f)

template forEach2*(node: AstNode, it: untyped, body: untyped): untyped =
  node.forEach proc(n: AstNode) =
    let it = n
    body

proc newProject*(): Project =
  new result

proc newLanguage*(id: Id, classes: seq[NodeClass], builder: CellBuilder): Language =
  new result
  result.id = id
  for c in classes:
    result.classes[c.id] = c
  result.builder = builder

proc newModel*(id: Id): Model =
  new result
  result.id = id

proc addModel*(self: Project, model: Model) =
  self.models[model.id] = model

proc addLanguage*(self: Model, language: Language) =
  self.languages.add language
  for c in language.classes.keys:
    self.classesToLanguages[c] = language

proc addRootNode*(self: Model, node: AstNode) =
  self.rootNodes.add node
  # node.forEach proc(n: AstNode) =
  node.forEach2 n:
    n.model = self
    self.nodes[n.id] = n

proc resolveReference*(self: Model, id: Id): Option[AstNode] =
  if self.nodes.contains(id):
    return self.nodes[id].some
  else:
    return AstNode.none

proc newNodeClass*(
      id: Id,
      name: string,
      alias: string = "",
      base: NodeClass = nil,
      interfaces: openArray[NodeClass] = [],
      isAbstract: bool = false,
      isInterface: bool = false,
      properties: openArray[PropertyDescription] = [],
      children: openArray[NodeChildDescription] = [],
      references: openArray[NodeReferenceDescription] = [],
    ): NodeClass =

  new result
  result.id = id
  result.name = name
  result.alias = alias
  result.base = base
  result.interfaces = @interfaces
  result.isAbstract = isAbstract
  result.isInterface = isInterface
  result.properties = @properties
  result.children = @children
  result.references = @references

proc nodeReferenceDescription*(self: NodeClass, id: Id): Option[NodeReferenceDescription] =
  result = NodeReferenceDescription.none
  for c in self.references:
    if c.id == id:
      return c.some

  if self.base.isNotNil and self.base.nodeReferenceDescription(id).getSome(pd):
    return pd.some

  for inter in self.interfaces:
    if inter.isNotNil and inter.nodeReferenceDescription(id).getSome(pd):
      return pd.some

proc nodeChildDescription*(self: NodeClass, id: Id): Option[NodeChildDescription] =
  result = NodeChildDescription.none
  for c in self.children:
    if c.id == id:
      return c.some

  if self.base.isNotNil and self.base.nodeChildDescription(id).getSome(pd):
    return pd.some

  for inter in self.interfaces:
    if inter.isNotNil and inter.nodeChildDescription(id).getSome(pd):
      return pd.some

proc propertyDescription*(self: NodeClass, id: Id): Option[PropertyDescription] =
  result = PropertyDescription.none
  for c in self.properties:
    if c.id == id:
      return c.some

  if self.base.isNotNil and self.base.propertyDescription(id).getSome(pd):
    return pd.some

  for inter in self.interfaces:
    if inter.isNotNil and inter.propertyDescription(id).getSome(pd):
      return pd.some

proc hasChildList(node: AstNode, role: Id): bool =
  result = false
  for c in node.childLists:
    if c.role == role:
      return true

proc hasChild*(node: AstNode, role: Id): bool =
  result = false
  for c in node.childLists:
    if c.role == role:
      return c.nodes.len > 0

proc children*(node: AstNode, role: Id): seq[AstNode] =
  result = @[]
  for c in node.childLists.mitems:
    if c.role == role:
      result = c.nodes
      break

proc hasReference*(node: AstNode, role: Id): bool =
  result = false
  for c in node.references:
    if c.role == role:
      return true

proc reference*(node: AstNode, role: Id): Id =
  result = idNone()
  for c in node.references:
    if c.role == role:
      result = c.node
      break

proc resolveReference*(node: AstNode, role: Id): Option[AstNode] =
  result = AstNode.none
  if node.model.isNil:
    return
  for c in node.references:
    if c.role == role:
      result = node.model.resolveReference(c.node)
      break

proc setReference*(node: AstNode, role: Id, target: Id) =
  for c in node.references.mitems:
    if c.role == role:
      c.node = target
      break

proc hasProperty*(node: AstNode, role: Id): bool =
  result = false
  for c in node.properties:
    if c.role == role:
      return true

proc property*(node: AstNode, role: Id): Option[PropertyValue] =
  result = PropertyValue.none
  for c in node.properties:
    if c.role == role:
      result = c.value.some
      break

proc setProperty*(node: AstNode, role: Id, value: PropertyValue) =
  for c in node.properties.mitems:
    if c.role == role:
      c.value = value
      break

proc propertyDescription*(node: AstNode, role: Id): Option[PropertyDescription] =
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
      self.references.add (desc.id, idNone())

proc newAstNode*(class: NodeClass, id: Option[Id] = Id.none): AstNode =
  let id = if id.isSome: id.get else: newId()
  new result
  result.id = id
  result.class = class.id
  result.addMissingFieldsForClass(class)

proc language*(node: AstNode): Language =
  result = if node.model.isNil: nil else: node.model.classesToLanguages.getOrDefault(node.class, nil)

proc nodeClass*(node: AstNode): NodeClass =
  let language = node.language
  result = if language.isNil: nil else: language.classes.getOrDefault(node.class, nil)

proc add*(node: AstNode, role: Id, child: AstNode) =
  if child.isNil:
    return

  if child.id == idNone():
    child.id = newId()
  child.parent = node
  child.role = role

  if node.model.isNotNil:
    child.forEach2 n:
      n.model = node.model
      node.model.nodes[n.id] = n

  for c in node.childLists.mitems:
    if c.role == role:
      c.nodes.add child
      return

  raise newException(Defect, fmt"Unknown role {role} for node {node.id} of class {node.class}")

proc newCellBuilder*(): CellBuilder =
  new result

proc addBuilderFor*(self: CellBuilder, classId: Id, builderId: Id, builder: CellBuilderFunction) =
  if self.builders.contains(classId):
    self.builders[classId].add (builderId, builder)
  else:
    self.builders[classId] = @[(builderId, builder)]

proc addBuilder*(self: CellBuilder, other: CellBuilder) =
  for pair in other.builders.pairs:
    for builder in pair[1]:
      self.addBuilderFor(pair[0], builder[0], builder[1])
  for pair in other.preferredBuilders.pairs:
    self.preferredBuilders[pair[0]] = pair[1]

method dump*(self: Cell): string {.base.} = discard
method getChildAt*(self: Cell, index: int, clamp: bool): Option[Cell] {.base.} = Cell.none

method dump(self: EmptyCell): string =
  result.add fmt"EmptyCell(node: {self.node.id})"

proc fill*(self: Cell) =
  if self.fillChildren.isNil or self.filled:
    return
  self.fillChildren()
  self.filled = true

proc expand*(self: Cell, path: openArray[int]) =
  self.fill()
  if path.len > 0 and self.getChildAt(path[0], true).getSome(child):
    child.expand path[1..^1]

proc findBuilder(self: CellBuilder, class: NodeClass, preferred: Id): Option[CellBuilderFunction] =
  if not self.builders.contains(class.id):
    if class.base.isNotNil:
      return self.findBuilder(class.base, preferred)
    return CellBuilderFunction.none

  let builders = self.builders[class.id]
  if builders.len == 0:
    if class.base.isNotNil:
      return self.findBuilder(class.base, preferred)
    return CellBuilderFunction.none

  if builders.len == 1:
    return builders[0].impl.some

  let preferredBuilder = self.preferredBuilders.getOrDefault(class.id, idNone())
  for builder in builders:
    if builder.builderId == preferredBuilder:
      return builder.impl.some

  return builders[0].impl.some

proc buildCell*(self: CellBuilder, node: AstNode): Cell =
  let class = node.nodeClass
  if class.isNil:
    debugf"Unknown class {node.class}"
    return EmptyCell(node: node)

  if self.findBuilder(class, idNone()).getSome(builder):
    result = builder(self, node)
    result.fill()
  else:
    debugf"Unknown builder for {class.name}"
    return EmptyCell(node: node)

proc `$`*(node: AstNode, recursive: bool = false): string =
  let class = node.nodeClass

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
    else:
      result.add $role.role
    result.add ": "
    result.add $role.node

  if not recursive:
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
      result.add indent(`$`(c, recursive), 1, indent)[indent.len..^1]