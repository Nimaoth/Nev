
import std/[options, algorithm, strutils, hashes, enumutils, json, jsonutils, tables, macros, sequtils, strformat]
import fusion/matching
import chroma
import util, id, macro_utils, custom_logger, event
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
  CellNodeFactory* = proc(): AstNode

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
    displayText*: Option[string]
    shadowText*: string
    fillChildren*: proc(): void
    filled*: bool
    isVisible*: CellIsVisiblePredicate
    nodeFactory*: CellNodeFactory
    style*: CellStyle
    disableSelection*: bool
    disableEditing*: bool
    increaseIndentBefore*: bool
    decreaseIndentBefore*: bool
    increaseIndentAfter*: bool
    decreaseIndentAfter*: bool
    fontSizeIncreasePercent*: float
    themeForegroundColors*: seq[string]
    themeBackgroundColors*: seq[string]
    foregroundColor*: Color
    backgroundColor*: Color

  EmptyCell* = ref object of Cell
    discard

  CellBuilderFunction* = proc(builder: CellBuilder, node: AstNode): Cell

  CellBuilder* = ref object
    builders*: Table[Id, seq[tuple[builderId: Id, impl: CellBuilderFunction]]]
    preferredBuilders*: Table[Id, Id]

  Language* = ref object
    id {.getter.}: Id
    version {.getter.}: int
    classes {.getter.}: Table[Id, NodeClass]
    childClasses {.getter.}: Table[Id, seq[NodeClass]]
    builder {.getter.}: CellBuilder

  Model* = ref object
    id {.getter.}: Id
    rootNodes {.getter.}: seq[AstNode]
    languages {.getter.}: seq[Language]
    importedModels {.getter.}: seq[Model]
    classesToLanguages {.getter.}: Table[Id, Language]
    nodes {.getter.}: Table[Id, AstNode]

    onNodeDeleted*: Event[tuple[self: Model, parent: AstNode, child: AstNode, role: Id, index: int]]
    onNodeInserted*: Event[tuple[self: Model, parent: AstNode, child: AstNode, role: Id, index: int]]
    onNodePropertyChanged*: Event[tuple[self: Model, node: AstNode, role: Id, oldValue: PropertyValue, newValue: PropertyValue, slice: Slice[int]]]
    onNodeReferenceChanged*: Event[tuple[self: Model, node: AstNode, role: Id, oldRef: Id, newRef: Id]]

  Project* = ref object
    models*: Table[Id, Model]
    builder*: CellBuilder

generateGetters(NodeClass)
generateGetters(Model)
generateGetters(Language)

proc notifyNodeDeleted(self: Model, parent: AstNode, child: AstNode, role: Id, index: int) =
  self.onNodeDeleted.invoke (self, parent, child, role, index)

proc notifyNodeInserted(self: Model, parent: AstNode, child: AstNode, role: Id, index: int) =
  self.onNodeInserted.invoke (self, parent, child, role, index)

proc notifyNodePropertyChanged(self: Model, node: AstNode, role: Id, oldValue: PropertyValue, newValue: PropertyValue, slice: Slice[int]) =
  self.onNodePropertyChanged.invoke (self, node, role, oldValue, newValue, slice)

proc notifyNodeReferenceChanged(self: Model, node: AstNode, role: Id, oldRef: Id, newRef: Id) =
  self.onNodeReferenceChanged.invoke (self, node, role, oldRef, newRef)

proc `$`*(node: AstNode, recursive: bool = false): string
proc nodeClass*(node: AstNode): NodeClass
proc add*(node: AstNode, role: Id, child: AstNode)

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

    if c.base.isNotNil:
      if not result.childClasses.contains(c.base.id):
        result.childClasses[c.base.id] = @[]
      result.childClasses[c.base.id].add c

  result.builder = builder

proc forEachChildClass*(self: Language, base: Id, handler: proc(c: NodeClass)) =
  if self.childClasses.contains(base):
    for c in self.childClasses[base]:
      handler(c)
      self.forEachChildClass(c.id, handler)

proc resolveClass*(model: Model, classId: Id): NodeClass =
  let language = model.classesToLanguages.getOrDefault(classId, nil)
  result = if language.isNil: nil else: language.classes.getOrDefault(classId, nil)

proc resolveClass*(language: Language, classId: Id): NodeClass =
  return language.classes.getOrDefault(classId, nil)

proc getLanguageForClass*(model: Model, classId: Id): Language =
  return model.classesToLanguages.getOrDefault(classId, nil)

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

proc isSubclassOf*(self: NodeClass, baseClassId: Id): bool =
  if self.id == baseClassId:
    return true
  if self.base.isNotNil and self.base.isSubclassOf(baseClassId):
    return true
  for i in self.interfaces:
    if i.isSubclassOf(baseClassId):
      return true
  return false

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
      if node.model.isNotNil:
        node.model.notifyNodeReferenceChanged(node, role, c.node, target)
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

proc setProperty*(node: AstNode, role: Id, value: PropertyValue, slice: Slice[int] = 0..0) =
  for c in node.properties.mitems:
    if c.role == role:
      if node.model.isNotNil:
        node.model.notifyNodePropertyChanged(node, role, c.value, value, slice)
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

proc fillDefaultChildren*(node: AstNode, language: Language) =
  let class = language.classes.getOrDefault(node.class, nil)
  for desc in class.children:
    if desc.count in {ChildCount.One, ChildCount.OneOrMore}:
      let childClass = language.classes.getOrDefault(desc.class)
      let child = newAstNode(childClass)
      child.fillDefaultChildren(language)
      node.add(desc.id, child)

proc ancestor*(node: AstNode, distance: int): AstNode =
  result = node
  for i in 1..distance:
    result = result.parent

proc isDescendant*(node: AstNode, ancestor: AstNode): bool =
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
  result = if language.isNil: nil else: language.classes.getOrDefault(node.class, nil)

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

proc canInsertInto*(node: AstNode, role: Id): bool =
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

proc insert*(node: AstNode, role: Id, index: int, child: AstNode) =
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
      c.nodes.insert child, index
      if node.model.isNotNil:
        node.model.notifyNodeInserted(node, child, role, index)
      return

  raise newException(Defect, fmt"Unknown role {role} for node {node.id} of class {node.class}")

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

proc remove*(node: AstNode, role: Id, index: int) =
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

proc removeFromParent*(node: AstNode) =
  if node.parent.isNil:
    return
  node.parent.remove(node)

proc add*(node: AstNode, role: Id, child: AstNode) =
  node.insert(role, node.children(role).len, child)

proc insertDefaultNode*(node: AstNode, role: Id, index: int): Option[AstNode] =
  result = AstNode.none

  let class = node.nodeClass
  let desc = class.nodeChildDescription(role).get

  let language = node.language
  if language.isNil:
    return

  let childClass = language.classes.getOrDefault(desc.class, nil)
  if childClass.isNil:
    return

  var child = newAstNode(childClass)
  child.fillDefaultChildren(language)

  node.insert(role, index, child)

  return child.some

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

method dump*(self: Cell, recurse: bool = false): string {.base.} = discard
method getChildAt*(self: Cell, index: int, clamp: bool): Option[Cell] {.base.} = Cell.none

method dump(self: EmptyCell): string =
  result.add fmt"EmptyCell(node: {self.node.id})"

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