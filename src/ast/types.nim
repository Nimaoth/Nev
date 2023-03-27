
import std/[options, algorithm, strutils, hashes, enumutils, json, jsonutils, tables, macros, sequtils, strformat]
import fusion/matching
import util, id, macro_utils
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
    children2*: seq[tuple[role: Id, nodes: seq[AstNode]]]

  Cell* = ref object of RootObj
    id*: Id
    parent*: Cell

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

  Project* = ref object
    models*: Table[Id, Model]
    builder*: CellBuilder

generateGetters(NodeClass)
generateGetters(Model)
generateGetters(Language)

proc forEach*(node: AstNode, f: proc(node: AstNode)) =
  f(node)
  for item in node.children2.mitems:
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

proc newNodeClass*(
      id: Id,
      name: string,
      alias: string = "",
      base: NodeClass = nil,
      interfaces: seq[NodeClass] = @[],
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
  result.interfaces = interfaces
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

proc nodeChildDescription*(self: NodeClass, id: Id): Option[NodeChildDescription] =
  result = NodeChildDescription.none
  for c in self.children:
    if c.id == id:
      return c.some

proc propertyDescription*(self: NodeClass, id: Id): Option[PropertyDescription] =
  result = PropertyDescription.none
  for c in self.properties:
    if c.id == id:
      return c.some

proc children*(node: AstNode, role: Id): seq[AstNode] =
  result = @[]
  for c in node.children2.mitems:
    if c.role == role:
      result = c.nodes
      break

proc reference*(node: AstNode, role: Id): Id =
  result = idNone()
  for c in node.references:
    if c.role == role:
      result = c.node
      break

proc property*(node: AstNode, role: Id): PropertyValue =
  for c in node.properties:
    if c.role == role:
      result = c.value
      break

proc setProperty*(node: AstNode, role: Id, value: PropertyValue) =
  for c in node.properties.mitems:
    if c.role == role:
      c.value = value
      break

proc getDefaultValue*(_: typedesc[PropertyValue], typ: PropertyType): PropertyValue =
  result = PropertyValue(kind: typ)
  case typ
  of PropertyType.Bool: result.boolValue = false
  of PropertyType.Int: result.intValue = 0
  of PropertyType.String: result.stringValue = ""

proc newAstNode*(class: NodeClass, id: Option[Id] = Id.none): AstNode =
  let id = if id.isSome: id.get else: newId()
  new result
  result.id = id
  result.class = class.id

  for desc in class.properties:
    result.properties.add (desc.id, PropertyValue.getDefaultValue(desc.typ))

  for desc in class.children:
    result.children2.add (desc.id, @[])

  for desc in class.references:
    result.references.add (desc.id, idNone())

proc language*(node: AstNode): Language =
  result = if node.model.isNil: nil else: node.model.classesToLanguages.getOrDefault(node.class, nil)

proc nodeClass*(node: AstNode): NodeClass =
  let language = node.language
  result = if language.isNil: nil else: language.classes.getOrDefault(node.class, nil)

proc add*(node: AstNode, role: Id, child: AstNode) =
  if child.id == idNone():
    child.id = newId()
  child.parent = node
  child.role = role

  for c in node.children2.mitems:
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

proc buildCell*(self: CellBuilder, node: AstNode): Cell =
  let class = node.class
  if not self.builders.contains(class):
    return nil

  let builders = self.builders[class]
  if builders.len == 0:
    return nil

  if builders.len == 1:
    return builders[0].impl(self, node)

  let preferredBuilder = self.preferredBuilders.getOrDefault(class, idNone())
  for builder in builders:
    if builder.builderId == preferredBuilder:
      return builder.impl(self, node)

  return builders[0].impl(self, node)

proc `$`*(node: AstNode): string =
  let class = node.nodeClass

  if class.isNil:
    result.add $node.class
  else:
    result.add class.name

  result.add "(id: " & $node.id & "):"

  for role in node.properties.mitems:
    result.add "\n  "
    if class.isNotNil and class.propertyDescription(role.role).getSome(desc):
      result.add desc.role
    else:
      result.add $role.role
    result.add ": "
    result.add $role.value

  for role in node.references.mitems:
    result.add "\n  "
    if class.isNotNil and class.nodeReferenceDescription(role.role).getSome(desc):
      result.add desc.role
    else:
      result.add $role.role
    result.add ": "
    result.add $role.node

  for role in node.children2.mitems:
    result.add "\n  "
    if class.isNotNil and class.nodeChildDescription(role.role).getSome(desc):
      result.add desc.role
    else:
      result.add $role.role
    result.add ":\n"
    for c in role.nodes:
      result.add indent($c, 4)