import std/[tables, strutils, strformat, options, algorithm, sequtils]
import ui/node
import misc/[id, util, custom_logger, macro_utils]
import model, ast_ids

logCategory "cells"

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

type
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
    customIsVisible*: CellIsVisiblePredicate
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

  CellBuilderFunction* = proc(map: NodeCellMap, builder: CellBuilder, node: AstNode, owner: AstNode): Cell

  CellBuilder* = ref object
    sourceLanguage*: LanguageId
    builders*: Table[ClassId, seq[tuple[builderId: Id, impl: CellBuilderFunction, flags: CellBuilderFlags, sourceLanguage: LanguageId]]]
    builders2*: Table[ClassId, seq[tuple[builderId: Id, impl: CellBuilderCommands, flags: CellBuilderFlags, sourceLanguage: LanguageId]]]
    preferredBuilders*: Table[ClassId, Id]
    forceDefault*: bool

  NodeCellMap* = ref object
    map*: Table[NodeId, Cell]
    cells*: Table[CellId, Cell]
    builder*: CellBuilder

  CollectionCell* = ref object of Cell
    uiFlags*: UINodeFlags
    inline*: bool
    children*: seq[Cell]

  ConstantCell* = ref object of Cell
    text*: string

  PropertyCell* = ref object of Cell
    property*: RoleId

  AliasCell* = ref object of Cell
    discard

  PlaceholderCell* = ref object of Cell
    discard

  EmptyCell* = ref object of Cell
    discard

  CellBuilderCommands* = ref object
    commands*: seq[CellBuilderCommand]

  CellBuilderCommandKind* {.pure.} = enum CollectionCell, EndCollectionCell, ConstantCell, PropertyCell, AliasCell, ReferenceCell, PlaceholderCell, Children
  CellBuilderCommand* = object
    disableEditing*: bool
    disableSelection*: bool
    deleteNeighbor*: bool
    uiFlags*: UINodeFlags
    flags*: CellFlags
    shadowText*: string
    themeForegroundColors*: seq[string]
    themeBackgroundColors*: seq[string]
    builderFunc*: CellBuilderFunction

    case kind*: CellBuilderCommandKind
    of CollectionCell:
      inline*: bool

    of ConstantCell:
      text*: string

    of PropertyCell:
      propertyRole*: RoleId

    of ReferenceCell:
      referenceRole*: RoleId
      targetProperty*: Option[RoleId]

    of AliasCell:
      discard

    of PlaceholderCell:
      discard

    of Children:
      childrenRole*: RoleId
      separator*: Option[string]
      placeholder*: Option[string]

    of EndCollectionCell:
      discard

method dump*(self: Cell, recurse: bool = false): string {.base.} = discard
method getChildAt*(self: Cell, index: int, clamp: bool): Option[Cell] {.base.} = Cell.none
proc editableLow*(self: Cell, ignoreStyle: bool = false): int
proc editableHigh*(self: Cell, ignoreStyle: bool = false): int
proc buildDefaultPlaceholder*(builder: CellBuilder, node: AstNode, owner: AstNode, role: RoleId, flags: CellFlags = 0.CellFlags): Cell
proc buildChildren*(builder: CellBuilder, map: NodeCellMap, node: AstNode, owner: AstNode, role: RoleId, uiFlags: UINodeFlags = 0.UINodeFlags, flags: CellFlags = 0.CellFlags,
    customIsVisible: proc(node: AstNode): bool = nil,
    separatorFunc: proc(builder: CellBuilder): Cell = nil,
    placeholderFunc: proc(builder: CellBuilder, node: AstNode, owner: AstNode, role: RoleId, flags: CellFlags): Cell = buildDefaultPlaceholder,
    builderFunc: CellBuilderFunction = nil): Cell
proc buildReference*(map: NodeCellMap, node: AstNode, owner: AstNode, role: RoleId, builderFunc: CellBuilderFunction = nil): Cell

proc `$`*(cell: Cell, recurse: bool = false): string = cell.dump(recurse)

proc buildCell*(map: NodeCellMap, node: AstNode, useDefault: bool = false, builderFunc: CellBuilderFunction = nil, owner: AstNode = nil): Cell

proc isVisible*(cell: Cell): bool =
  if cell.customIsVisible.isNotNil and not cell.customIsVisible(cell.node):
    return false

  return true

proc canSelect*(cell: Cell): bool =
  if cell.customIsVisible.isNotNil and not cell.customIsVisible(cell.node):
    return false
  if cell.disableSelection:
    return false
  if cell.editableLow > cell.editableHigh:
    return false

  if cell of CollectionCell and cell.CollectionCell.children.len == 0:
    return false

  return true

method getText*(cell: Cell): string {.base.} = discard
method setText*(cell: Cell, text: string, slice: Slice[int] = 0..0) {.base.} = discard

proc currentText*(cell: Cell): string =
  # todo: maybe remove display text?
  if not cell.displayText.isNone:
    return cell.displayText.get
  return cell.getText

proc `currentText=`*(cell: Cell, text: string) =
  cell.displayText = text.some

proc hasAncestor*(cell: Cell, ancestor: Cell): bool =
  if cell.parent == ancestor:
    return true
  if cell.parent.isNotNil:
    return cell.parent.hasAncestor(ancestor)
  return false

proc closestInlineAncestor*(cell: Cell): Cell =
  result = cell.parent
  while result.isNotNil and not result.CollectionCell.inline:
    result = result.parent

proc ancestor*(cell: Cell, targetParent: Cell): Cell =
  ### Returns the ancestor of cell which has targetParent as it's parent
  result = cell
  while result.parent.isNotNil and result.parent != targetParent:
    result = result.parent

proc isDescendant*(cell: Cell, ancestor: Cell): bool =
  ### Returns true if cell has ancestor in it's parent chain
  result = false
  var temp = cell
  while temp.isNotNil:
    if temp == ancestor:
      return true
    temp = temp.parent

proc add*(self: CollectionCell, cell: Cell) =
  if cell.id.isNone:
    cell.id = newId().CellId
  cell.parent = self
  self.children.add cell

proc indexOf*(self: CollectionCell, cell: Cell): int =
  result = -1
  for i, c in self.children:
    if c == cell:
      return i

proc index*(self: Cell): int =
  if self.parent.isNil:
    return -1
  return self.parent.CollectionCell.indexOf self

proc parentHigh*(self: Cell): int =
  if self.parent.isNil:
    return -1
  return self.parent.CollectionCell.children.high

proc parentLen*(self: Cell): int =
  if self.parent.isNil:
    return -1
  return self.parent.CollectionCell.children.len

proc len*(self: Cell): int =
  if self of CollectionCell:
    return self.CollectionCell.children.len
  return self.getText.len

proc visibleLow*(self: CollectionCell): int =
  assert self.fillChildren.isNil or self.filled
  for i, child in self.children:
    if child.isVisible:
      return i
  return -1

proc visibleHigh*(self: CollectionCell): int =
  assert self.fillChildren.isNil or self.filled
  for i in countdown(self.children.high, self.children.low):
    if self.children[i].isVisible:
      return i
  return -1

proc low*(self: Cell): int =
  if self of CollectionCell:
    return self.CollectionCell.children.low
  else:
    return self.currentText.low

proc editableLow*(self: Cell, ignoreStyle: bool = false): int =
  if self of CollectionCell:
    return self.CollectionCell.visibleLow
  let noSpaceLeft = NoSpaceLeft in self.flags or (self.style.isNotNil and self.style.noSpaceLeft)
  if not ignoreStyle and noSpaceLeft and self.currentText.len > 0:
    return self.low + 1
  return self.low

proc high*(self: Cell): int =
  if self of CollectionCell:
    return self.CollectionCell.children.high
  else:
    return self.currentText.high

proc editableHigh*(self: Cell, ignoreStyle: bool = false): int =
  if self of CollectionCell:
    return self.CollectionCell.visibleHigh
  let noSpaceRight = NoSpaceRight in self.flags or (self.style.isNotNil and self.style.noSpaceRight)
  if not ignoreStyle and noSpaceRight and self.currentText.len > 0:
    return self.high
  return self.high + 1

proc previousDirect*(self: Cell): Option[Cell] =
  ### Returns the previous cell before self in the parents children, or nil.
  let i = self.index
  if i == -1 or i < 1:
    return Cell.none
  return self.parent.CollectionCell.children[i - 1].some

proc nextDirect*(self: Cell): Option[Cell] =
  ### Returns the next cell after self in the parents children, or nil.
  let i = self.index
  if i == -1 or i >= self.parent.CollectionCell.children.high:
    return Cell.none
  return self.parent.CollectionCell.children[i + 1].some

proc rootPath*(cell: Cell): tuple[root: Cell, path: seq[int]] =
  var cell = cell
  var path: seq[int] = @[]
  while cell.parent.isNotNil:
    if cell.parent of CollectionCell:
      path.add cell.parent.CollectionCell.children.find(cell)

    cell = cell.parent

  path.reverse()

  return (cell, path)

proc targetNode*(cell: Cell): AstNode =
  if cell.referenceNode.isNotNil:
    return cell.referenceNode
  return cell.node

proc isLeaf*(self: Cell): bool =
  if self of CollectionCell:
    return false
  return true

proc isFullyContained*(cell: Cell, left: openArray[int], right: openArray[int]): bool =
  # debugf"isFullyContained {cell}, {left}, {right}"
  # defer:
  #   echo " -> ", result

  if left.len == 0 and right.len == 0:
    return true

  let firstIndex = if left.len > 0: left[0] else: cell.editableLow
  let lastIndex = if right.len > 0: right[0] else: cell.editableHigh
  # echo firstIndex, "/", cell.editableLow, ", ", lastIndex, "/", cell.editableHigh

  if firstIndex > cell.editableLow or lastIndex < cell.editableHigh:
    # echo "x"
    return false

  if cell of CollectionCell:
    let cell = cell.CollectionCell

    if not cell.children[0].isFullyContained(
      if firstIndex == cell.editableLow and left.len > 0: left[1..^1] else: @[],
      if lastIndex == cell.editableLow and right.len > 0: right[1..^1] else: @[]
    ):
      # echo "x2"
      return false

    if not cell.children.last.isFullyContained(
      if firstIndex == cell.editableHigh and left.len > 0: left[1..^1] else: @[],
      if lastIndex == cell.editableHigh and right.len > 0: right[1..^1] else: @[]
    ):
      # echo "x3"
      return false

  return true

method getChildAt*(self: CollectionCell, index: int, clamp: bool): Option[Cell] =
  let index = if clamp: index.clamp(0..self.children.high) else: index
  if index < 0 or index > self.children.high:
    return Cell.none
  return self.children[index].some

proc replaceText*(cell: Cell, slice: Slice[int], text: string): int =
  var newText = cell.currentText
  if slice.b > slice.a:
    newText.delete(slice.a..<slice.b)
  newText.insert(text, slice.a)
  cell.setText(newText, slice)
  return slice.a + text.len

proc insertText*(cell: Cell, index: int, text: string): int =
  var newText = cell.currentText
  newText.insert(text, index)
  cell.setText(newText, index..index)
  return index + text.len

method setText*(cell: CollectionCell, text: string, slice: Slice[int] = 0..0) = cell.currentText = text

method setText*(cell: ConstantCell, text: string, slice: Slice[int] = 0..0) = cell.currentText = text

method setText*(cell: PropertyCell, text: string, slice: Slice[int] = 0..0) =
  cell.currentText = text
  try:
    if cell.targetNode.propertyDescription(cell.property).getSome(prop):

      case prop.typ
      of String:
        cell.targetNode.setProperty(cell.property, PropertyValue(kind: PropertyType.String, stringValue: text), slice)
      of Int:
        let intValue = text.parseBiggestInt
        cell.targetNode.setProperty(cell.property, PropertyValue(kind: PropertyType.Int, intValue: intValue), slice)
      of Bool:
        let boolValue = text.parseBool
        cell.targetNode.setProperty(cell.property, PropertyValue(kind: PropertyType.Bool, boolValue: boolValue), slice)

      cell.displayText = string.none

  except CatchableError:
    discard

method setText*(cell: AliasCell, text: string, slice: Slice[int] = 0..0) =
  cell.currentText = text

method setText*(cell: PlaceholderCell, text: string, slice: Slice[int] = 0..0) =
  cell.currentText = text

method getText*(cell: CollectionCell): string = "<>"

method getText*(cell: ConstantCell): string = cell.text

method getText*(cell: PropertyCell): string =
  let value = cell.targetNode.property(cell.property)
  if value.getSome(value):
    case value.kind
    of String:
      return value.stringValue
    of Int:
      return $value.intValue
    of Bool:
      return $value.boolValue
  else:
    return fmt"<{cell.targetNode}>"

method getText*(cell: AliasCell): string =
  let class = cell.targetNode.nodeClass
  if class.isNotNil:
    return class.alias
  else:
    return $cell.targetNode.class

method getText*(cell: PlaceholderCell): string = cell.displayText.get("")

method dump(self: CollectionCell, recurse: bool = false): string =
  result = fmt"CollectionCell(inline: {self.inline}, uiFlags: {self.uiFlags}): {self.node}, {self.referenceNode}"
  if recurse:
    result.add "\n"
    if self.filled or self.fillChildren.isNil:
      for c in self.children:
        for c in c.dump(recurse).indent(4):
          result.add c
        result.add "\n"
    else:
      result.add "...".indent(4)

method dump(self: ConstantCell, recurse: bool = false): string =
  result.add fmt"ConstantCell(node: {self.node.id}, text: {self.text}): {self.node}, {self.referenceNode}"

method dump(self: PropertyCell, recurse: bool = false): string =
  result.add fmt"PropertyCell(node: {self.node.id}, property: {self.property}): {self.node}, {self.referenceNode}"

method dump(self: AliasCell, recurse: bool = false): string =
  result.add fmt"AliasCell(node: {self.node.id}): {self.node}, {self.referenceNode}"

method dump(self: PlaceholderCell, recurse: bool = false): string =
  result.add fmt"PlaceholderCell(node: {self.node.id}, role: {self.role}): {self.node}, {self.referenceNode}"

proc invalidate*(map: NodeCellMap) =
  map.map.clear()
  map.cells.clear()

proc fill*(map: NodeCellMap, self: Cell) =
  if self.fillChildren.isNil or self.filled:
    return
  self.fillChildren(map)
  self.filled = true
  when defined(js):
    self.aDebug = cstring $self

proc expand*(map: NodeCellMap, self: Cell, path: openArray[int]) =
  map.fill(self)
  if path.len > 0 and self.getChildAt(path[0], true).getSome(child):
    map.expand child, path[1..^1]

proc cell*(map: NodeCellMap, node: AstNode, useDefault: bool = false): Cell =
  assert node.model.isNotNil, fmt"Trying to get cell for node which is not in a model: {node}"
  defer:
    if result.isNotNil:
      map.fill(result)

  if map.map.contains(node.id):
    # debugf"cell for {node} already exists"
    return map.map[node.id]

  if node.parent.isNotNil:
    # debugf"get parent cell for {node}"
    let parentCell = map.cell(node.parent, useDefault)
    map.fill(parentCell)
    softAssert map.map.contains(node.id), fmt"Generating parent cell for {node.parent} didn't generate cells for {node}"
    return map.map[node.id]

  # root node
  # debugf"get cell for root node {node}"
  let cell = buildCell(map, node, useDefault)
  map.map[node.id] = cell
  map.cells[cell.id] = cell
  return cell

proc findBuilder(self: CellBuilder, class: NodeClass, preferred: Id, isBase: bool = false): CellBuilderFunction =
  if not self.builders.contains(class.id):
    if class.base.isNotNil:
      return self.findBuilder(class.base, preferred, true)
    return nil

  let builders = self.builders[class.id]
  if builders.len == 0:
    if class.base.isNotNil:
      return self.findBuilder(class.base, preferred, true)
    return nil

  if builders.len == 1:
    if isBase and OnlyExactMatch in builders[0].flags:
      return nil
    return builders[0].impl

  let preferredBuilder = self.preferredBuilders.getOrDefault(class.id, idNone())
  for builder in builders:
    if isBase and OnlyExactMatch in builder.flags:
      continue
    if builder.builderId == preferredBuilder:
      return builder.impl

  if isBase and OnlyExactMatch in builders[0].flags:
    return nil

  return builders[0].impl

proc findBuilder2(self: CellBuilder, class: NodeClass, preferred: Id, isBase: bool = false): CellBuilderCommands =
  if not self.builders2.contains(class.id):
    if class.base.isNotNil:
      return self.findBuilder2(class.base, preferred, true)
    return nil

  let builders = self.builders2[class.id]
  if builders.len == 0:
    if class.base.isNotNil:
      return self.findBuilder2(class.base, preferred, true)
    return nil

  if builders.len == 1:
    if isBase and OnlyExactMatch in builders[0].flags:
      return nil
    return builders[0].impl

  let preferredBuilder = self.preferredBuilders.getOrDefault(class.id, idNone())
  for builder in builders:
    if isBase and OnlyExactMatch in builder.flags:
      continue
    if builder.builderId == preferredBuilder:
      return builder.impl

  if isBase and OnlyExactMatch in builders[0].flags:
    return nil

  return builders[0].impl

template horizontalCell(cell: Cell, node: AstNode, owner: AstNode, childCell: untyped, body: untyped) =
  var childCell {.inject.} = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  try:
    body
  finally:
    cell.add childCell

proc newCellBuilder*(sourceLanguageId: LanguageId): CellBuilder =
  new result
  result.sourceLanguage = sourceLanguageId

proc clear*(self: CellBuilder) =
  self.builders.clear()
  self.preferredBuilders.clear()
  self.forceDefault = false

proc addBuilderFor*(self: CellBuilder, classId: ClassId, builderId: Id, flags: CellBuilderFlags, builder: CellBuilderFunction, sourceLanguage = LanguageId.none) =
  # log lvlWarn, fmt"addBuilderFor {classId}"
  if self.builders.contains(classId):
    self.builders[classId].add (builderId, builder, flags, self.sourceLanguage)
  else:
    self.builders[classId] = @[(builderId, builder, flags, self.sourceLanguage)]

proc addBuilderFor*(self: CellBuilder, classId: ClassId, builderId: Id, builder: CellBuilderFunction, sourceLanguage = LanguageId.none) =
  self.addBuilderFor(classId, builderId, 0.CellBuilderFlags, builder, sourceLanguage)

proc addBuilderFor*(self: CellBuilder, classId: ClassId, builderId: Id, flags: CellBuilderFlags, commands: openArray[CellBuilderCommand], sourceLanguage = LanguageId.none) =
  # log lvlWarn, fmt"addBuilderFor {classId}"
  var builder = CellBuilderCommands(commands: @commands)
  if self.builders2.contains(classId):
    self.builders2[classId].add (builderId, builder, flags, sourceLanguage.get(self.sourceLanguage))
  else:
    self.builders2[classId] = @[(builderId, builder, flags, sourceLanguage.get(self.sourceLanguage))]

proc addBuilderFor*(self: CellBuilder, classId: ClassId, builderId: Id, commands: openArray[CellBuilderCommand], sourceLanguage = LanguageId.none) =
  self.addBuilderFor(classId, builderId, 0.CellBuilderFlags, commands, sourceLanguage)

proc addBuilder*(self: CellBuilder, other: CellBuilder) =
  # remove existing builders for the other source language
  for (classId, builders) in self.builders.mpairs:
    builders = builders.filterIt(it.sourceLanguage != other.sourceLanguage)
    # todo: remove from preferredBuilders

  for (classId, builders) in self.builders2.mpairs:
    builders = builders.filterIt(it.sourceLanguage != other.sourceLanguage)
    # todo: remove from preferredBuilders

  for pair in other.builders.pairs:
    for builder in pair[1]:
      self.addBuilderFor(pair[0], builder.builderId, builder.flags, builder.impl, builder.sourceLanguage.some)
  for pair in other.builders2.pairs:
    for builder in pair[1]:
      self.addBuilderFor(pair[0], builder.builderId, builder.flags, builder.impl.commands, builder.sourceLanguage.some)
  for pair in other.preferredBuilders.pairs:
    self.preferredBuilders[pair[0]] = pair[1]

proc buildCellDefault*(map: NodeCellMap, node: AstNode, useDefaultRecursive: bool, owner: AstNode = nil): Cell =
  let class = node.nodeClass

  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(m: NodeCellMap) =
    var hasAnyChildren = node.properties.len > 0 or node.references.len > 0 or node.childLists.len > 0
    for prop in node.childLists:
      if node.children(prop.role).len > 0:
        hasAnyChildren = true
        break

    cell.horizontalCell(node, owner, header):
      # header.increaseIndentAfter = true
      let name = if class.isNil:
        fmt"<unkown {node.class}>"
      else:
        class.name
      header.add ConstantCell(node: owner ?? node, referenceNode: node, text: name, disableEditing: true)
      header.add ConstantCell(node: owner ?? node, referenceNode: node, text: "{", disableEditing: true)

      if not hasAnyChildren:
        header.add ConstantCell(node: owner ?? node, referenceNode: node, text: "}", disableEditing: true)

    var childrenCell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutVertical}, flags: &{IndentChildren, OnNewLine}, inline: true)
    for prop in node.properties:
      # var propCell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
      childrenCell.horizontalCell(node, owner, propCell):
        let name: string = if class.isNil:
          fmt"<unkown {prop.role}>"
        else:
          class.propertyDescription(prop.role).map(proc(decs: PropertyDescription): string = decs.role).get($prop.role)
        propCell.add ConstantCell(node: owner ?? node, referenceNode: node, text: name, disableEditing: true)
        propCell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", style: CellStyle(noSpaceLeft: true), disableEditing: true)
        propCell.add PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: node, property: prop.role)
      # childrenCell.add propCell

    for prop in node.references:
      # var propCell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
      childrenCell.horizontalCell(node, owner, propCell):
        let name: string = if class.isNil:
          fmt"<unkown {prop.role}>"
        else:
          class.nodeReferenceDescription(prop.role).map(proc(decs: NodeReferenceDescription): string = decs.role).get($prop.role)
        propCell.add ConstantCell(node: owner ?? node, referenceNode: node, text: name, disableEditing: true)
        propCell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", style: CellStyle(noSpaceLeft: true), disableEditing: true)

        var nodeRefCell = if node.resolveReference(prop.role).getSome(targetNode):
          PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: targetNode, property: IdINamedName, themeForegroundColors: @["variable", "&editor.foreground"])
        else:
          ConstantCell(id: newId().CellId, node: owner ?? node, referenceNode: node, text: $node.reference(IdNodeReferenceTarget))
        # var nodeRefCell = NodeReferenceCell(id: newId().CellId, node: owner ?? node, referenceNode: node, reference: prop.role, property: IdINamedName)

        propCell.add nodeRefCell

      # childrenCell.add propCell

    for prop in node.childLists:
      let children = node.children(prop.role)

      # var propCell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
      childrenCell.horizontalCell(node, owner, propCell):

        let name: string = if class.isNil:
          fmt"<unkown {prop.role}>"
        else:
          class.nodeChildDescription(prop.role).map(proc(decs: NodeChildDescription): string = decs.role).get($prop.role)
        propCell.add ConstantCell(node: owner ?? node, referenceNode: node, text: name, disableEditing: true)
        propCell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", style: CellStyle(noSpaceLeft: true), disableEditing: true) #, increaseIndentAfter: children.len > 1)

        var hasChildren = false
        for i, c in children:
          hasAnyChildren = true
          var childCell = buildCell(map, c, useDefaultRecursive, owner=owner)
          if childCell.style.isNil:
            childCell.style = CellStyle()
          if children.len > 0:
            childCell.flags.incl OnNewLine
          # if children.len > 1 and i == children.high:
          #   childCell.decreaseIndentAfter = true
          propCell.add childCell
          hasChildren = true

        if not hasChildren:
          propCell.add PlaceholderCell(node: owner ?? node, referenceNode: node, role: prop.role, shadowText: "...")

      # childrenCell.add propCell

    cell.add childrenCell

    if hasAnyChildren:
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "}", flags: &{OnNewLine}, style: CellStyle(noSpaceLeft: true), disableEditing: true)

  return cell

proc buildCellWithCommands*(map: NodeCellMap, node: AstNode, owner: AstNode, commands: CellBuilderCommands, parent: CollectionCell = nil, startIndex: int = 0): Cell =
  assert commands.commands.len > 0
  let builder = map.builder

  var stack: seq[CollectionCell] = @[]
  var currentCollectionCell = parent

  if parent.isNil and commands.commands[0].kind == CellBuilderCommandKind.CollectionCell:
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: commands.commands[0].uiFlags)

    if parent.isNil: # root
      assert stack.len == 0
      assert currentCollectionCell.isNil
      cell.fillChildren = proc(m: NodeCellMap) =
        discard map.buildCellWithCommands(node, owner, commands, cell, 1)
      return cell

  for i in startIndex..commands.commands.high:
    let command = commands.commands[i]
    case command.kind
    of CollectionCell:
      var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: command.uiFlags, shadowText: command.shadowText, flags: command.flags, inline: command.inline)

      if currentCollectionCell.isNotNil:
        currentCollectionCell.add cell
        stack.add currentCollectionCell
        currentCollectionCell = cell
      else:
        return cell

    of EndCollectionCell:
      currentCollectionCell = stack.pop

    of ConstantCell:
      var cell = ConstantCell(node: owner ?? node, referenceNode: node, text: command.text, shadowText: command.shadowText, flags: command.flags,
        themeForegroundColors: command.themeForegroundColors, themeBackgroundColors: command.themeBackgroundColors,
        disableEditing: command.disableEditing, disableSelection: command.disableSelection, deleteNeighbor: command.deleteNeighbor)
      if currentCollectionCell.isNotNil:
        currentCollectionCell.add cell
      else:
        return cell

    of PropertyCell:
      var cell = PropertyCell(node: owner ?? node, referenceNode: node, property: command.propertyRole, shadowText: command.shadowText, flags: command.flags,
        themeForegroundColors: command.themeForegroundColors, themeBackgroundColors: command.themeBackgroundColors,
        disableEditing: command.disableEditing, disableSelection: command.disableSelection, deleteNeighbor: command.deleteNeighbor)
      if currentCollectionCell.isNotNil:
        currentCollectionCell.add cell
      else:
        return cell

    of ReferenceCell:
      let cell = if node.resolveReference(command.referenceRole).getSome(targetNode):
        if command.targetProperty.getSome(targetProperty) and targetNode.hasProperty(targetProperty):
          PropertyCell(node: owner ?? node, referenceNode: targetNode, property: targetProperty, shadowText: command.shadowText, flags: command.flags,
            themeForegroundColors: command.themeForegroundColors, themeBackgroundColors: command.themeBackgroundColors,
            disableEditing: command.disableEditing, disableSelection: command.disableSelection, deleteNeighbor: command.deleteNeighbor)
        else:
          var cell = CollectionCell(node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
          cell.fillChildren = proc(map: NodeCellMap) =
            cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "<", flags: &{NoSpaceRight})
            cell.add map.buildCell(targetNode, owner=node)
            cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ">", flags: &{NoSpaceLeft})
          cell
      else:
        PlaceholderCell(node: owner ?? node, referenceNode: node, role: command.referenceRole, shadowText: fmt"<unknown {node.reference(command.referenceRole)}>")

      if currentCollectionCell.isNotNil:
        currentCollectionCell.add cell
      else:
        return cell

    of PlaceholderCell:
      discard

    of AliasCell:
      var cell = AliasCell(node: owner ?? node, referenceNode: node, shadowText: command.shadowText, flags: command.flags,
        themeForegroundColors: command.themeForegroundColors, themeBackgroundColors: command.themeBackgroundColors,
        disableEditing: command.disableEditing, disableSelection: command.disableSelection, deleteNeighbor: command.deleteNeighbor)
      if currentCollectionCell.isNotNil:
        currentCollectionCell.add cell
      else:
        return cell

    of Children:
      var separator: proc(builder: CellBuilder): Cell
      var placeholder: proc(builder: CellBuilder, node: AstNode, owner: AstNode, role: RoleId, flags: CellFlags): Cell
      if command.separator.isSome:
        separator = proc(builder: CellBuilder): Cell =
          ConstantCell(node: owner ?? node, referenceNode: node, text: command.separator.get, flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)

      if command.placeholder.isSome:
        let text = command.placeholder.get
        placeholder = proc(builder: CellBuilder, node: AstNode, owner: AstNode, role: RoleId, flags: CellFlags): Cell =
          PlaceholderCell(node: owner ?? node, referenceNode: node, role: role, shadowText: text, flags: flags)
      else:
        placeholder = buildDefaultPlaceholder

      var cell = builder.buildChildren(map, node, owner, command.childrenRole, command.uiFlags, command.flags, customIsVisible=nil, separator, placeholder, builderFunc=command.builderFunc)
      if currentCollectionCell.isNotNil:
        currentCollectionCell.add cell
      else:
        return cell

proc buildCell*(map: NodeCellMap, node: AstNode, useDefault: bool = false, builderFunc: CellBuilderFunction = nil, owner: AstNode = nil): Cell =
  let class = node.nodeClass

  # echo fmt"build {node}"
  let useDefault = class.isNil or map.builder.forceDefault or useDefault

  block blk:
    if not useDefault:
      assert class.isNotNil
      if builderFunc.isNotNil:
        result = builderFunc(map, map.builder, node, owner)
        break blk

      if map.builder.findBuilder2(class, idNone()).isNotNil(commands) and commands.commands.len > 0:
        result = map.buildCellWithCommands(node, owner, commands)
        break blk

      if map.builder.findBuilder(class, idNone()).isNotNil(builderFunc):
        result = builderFunc(map, map.builder, node, owner)
        break blk

    if not useDefault:
      log lvlWarn, fmt"Unknown builder for {class.name}, using default"
    result = buildCellDefault(map, node, useDefault, owner)

  # debugf"store cell for {node}"
  let owner = owner ?? node
  map.map[owner.id] = result
  map.cells[result.id] = result

proc buildCell*(builder: CellBuilder, map: NodeCellMap, node: AstNode, useDefault: bool = false, builderFunc: CellBuilderFunction = nil, owner: AstNode = nil): Cell =
  return buildCell(map, node, useDefault, builderFunc, owner)

proc buildDefaultPlaceholder*(builder: CellBuilder, node: AstNode, owner: AstNode, role: RoleId, flags: CellFlags = 0.CellFlags): Cell =
  return PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, flags: flags, shadowText: "...")

proc buildReference*(map: NodeCellMap, node: AstNode, owner: AstNode, role: RoleId, builderFunc: CellBuilderFunction = nil): Cell =

  if node.resolveReference(role).getSome(target):
    result = buildCell(map, target, builderFunc=builderFunc, owner=node)

  else:
    return ConstantCell(id: newId().CellId, node: owner ?? node, referenceNode: node, text: $node.reference(role))

proc buildChildren*(builder: CellBuilder, map: NodeCellMap, node: AstNode, owner: AstNode, role: RoleId, uiFlags: UINodeFlags = 0.UINodeFlags, flags: CellFlags = 0.CellFlags,
    customIsVisible: proc(node: AstNode): bool = nil,
    separatorFunc: proc(builder: CellBuilder): Cell = nil,
    placeholderFunc: proc(builder: CellBuilder, node: AstNode, owner: AstNode, role: RoleId, flags: CellFlags): Cell = buildDefaultPlaceholder,
    builderFunc: CellBuilderFunction = nil): Cell =

  let children = node.children(role)

  if children.len == 1 and node.nodeClass.nodeChildDescription(role).get.count in {ZeroOrOne, One}:
    result = buildCell(map, children[0], builderFunc=builderFunc, owner=owner)
  elif children.len > 0:
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: uiFlags, flags: flags)
    for i, c in children:
      if i > 0 and separatorFunc.isNotNil:
        cell.add separatorFunc(builder)
      cell.add buildCell(map, c, builderFunc=builderFunc, owner=owner)
    result = cell
  else:
    result = placeholderFunc(builder, node, owner, role, 0.CellFlags)

  result.customIsVisible = customIsVisible

template buildChildrenT*(b: CellBuilder, map: NodeCellMap, n: AstNode, inOwner: AstNode, r: RoleId, uiFlags: UINodeFlags, cellFlags: CellFlags, body: untyped): Cell =
  var isVisibleFunc: proc(node: AstNode): bool = nil
  var separatorFunc: proc(builder: CellBuilder): Cell = nil
  var placeholderFunc: proc(builder: CellBuilder, node: AstNode, owner: AstNode, role: RoleId, childFlags: CellFlags): Cell = nil

  var builder {.inject.} = b
  var node {.inject.} = n
  var role {.inject.} = r

  template separator(bod: untyped): untyped {.used.} =
    separatorFunc = proc(builder {.inject.}: CellBuilder): Cell =
      return bod

  template placeholder(bod: untyped): untyped {.used.} =
    placeholderFunc = proc(builder {.inject.}: CellBuilder, node {.inject.}: AstNode, owner {.inject.}: AstNode, role {.inject.}: RoleId, childFlags: CellFlags): Cell =
      return bod

  template placeholder(text: string): untyped {.used.} =
    placeholderFunc = proc(builder {.inject.}: CellBuilder, node {.inject.}: AstNode, owner {.inject.}: AstNode, role {.inject.}: RoleId, childFlags: CellFlags): Cell =
      return PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: text, flags: childFlags)

  template visible(bod: untyped): untyped {.used.} =
    isVisibleFunc = proc(node {.inject.}: AstNode): bool =
      return bod

  placeholder("...")

  body

  builder.buildChildren(map, node, inOwner, role, uiFlags, cellFlags, isVisibleFunc, separatorFunc, placeholderFunc, nil)

template visitFromCenter*(inCell: Cell, inPath: openArray[int], inForwards: bool, onTarget, onCenterVertical, onCenterHorizontal, onForwards, onBackwards, onHorizontal, onLeaf: untyped) =
  if inCell of CollectionCell:
    let cell = inCell.CollectionCell
    let vertical = LayoutVertical in cell.uiFlags
    let centerIndex = if inPath.len > 0: inPath[0].clamp(0, cell.children.high) elif inForwards: 0 else: cell.children.high

    if vertical: # Vertical collection
      if cell.children.len > 0: # center
        let c = cell.children[centerIndex]
        onCenterVertical(centerIndex, c, if inPath.len > 1: inPath[1..^1] else: @[])

        if inPath.len == 1:
          onTarget(c)

      for i in (centerIndex + 1)..cell.children.high: # forwards
        let c = cell.children[i]
        onForwards(i, c, @[])

      if centerIndex > 0: # backwards
        for i in countdown(centerIndex - 1, 0):
          let c = cell.children[i]
          onBackwards(i, c, @[])

    else: # Horizontal collection
      for i in 0..cell.children.high:
        let c = cell.children[i]

        if i == centerIndex:
          onCenterHorizontal(i, c, if inPath.len > 1: inPath[1..^1] else: @[])
        else:
          onHorizontal(i, c, @[])

        if i == centerIndex and inPath.len == 1:
          onTarget(c)

  else: # Leaf cell
    onLeaf

template addHorizontal*(cell: Cell, inNode: AstNode, inFlags: CellFlags, body: untyped): untyped =
  block:
    var sub {.inject.} = CollectionCell(id: newId().CellId, node: inNode, uiFlags: &{LayoutHorizontal}, flags: inFlags)
    body
    cell.add sub

method dump*(self: EmptyCell, recurse: bool = false): string =
  result.add fmt"EmptyCell(node: {self.node.id})"