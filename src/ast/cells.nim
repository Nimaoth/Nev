import std/[tables, strutils, strformat, options, sugar]
import ui/node
import types, id, util, custom_logger
import ast_ids

logCategory "cells"

type
  CollectionCell* = ref object of Cell
    flags*: UINodeFlags
    inline*: bool
    children*: seq[Cell]

  ConstantCell* = ref object of Cell
    text*: string

  PropertyCell* = ref object of Cell
    property*: Id

  NodeReferenceCell* = ref object of Cell
    reference*: Id
    property*: Id
    child: Cell

  AliasCell* = ref object of Cell
    discard

  PlaceholderCell* = ref object of Cell
    role*: Id

proc buildCell*(self: CellBuilder, map: NodeCellMap, node: AstNode, useDefault: bool = false): Cell

proc child*(cell: NodeReferenceCell): Cell = cell.child
proc `child=`*(cell: NodeReferenceCell, c: Cell) =
  cell.child = c
  c.parent = cell

method getText*(cell: Cell): string {.base.} = discard
method setText*(cell: Cell, text: string, slice: Slice[int] = 0..0) {.base.} = discard

proc currentText*(cell: Cell): string =
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

proc isDecendant*(cell: Cell, ancestor: Cell): bool =
  ### Returns true if cell has ancestor in it's parent chain
  result = false
  var temp = cell
  while temp.isNotNil:
    if temp == ancestor:
      return true
    temp = temp.parent

proc add*(self: CollectionCell, cell: Cell) =
  if cell.id == idNone():
    cell.id = newId()
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

proc low*(self: Cell): int =
  if self of CollectionCell:
    return self.CollectionCell.children.low
  else:
    return self.currentText.low

proc editableLow*(self: Cell, ignoreStyle: bool = false): int =
  if not ignoreStyle and self.style.isNotNil and self.style.noSpaceLeft and self.currentText.len > 0:
    return self.low + 1
  return self.low

proc high*(self: Cell): int =
  if self of CollectionCell:
    return self.CollectionCell.children.high
  else:
    return self.currentText.high

proc editableHigh*(self: Cell, ignoreStyle: bool = false): int =
  if self of CollectionCell:
    return self.CollectionCell.children.high
  if not ignoreStyle and self.style.isNotNil and self.style.noSpaceRight and self.currentText.len > 0:
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

proc isLeaf*(self: Cell): bool =
  if self of CollectionCell and self.CollectionCell.children.len > 0:
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

method setText*(cell: NodeReferenceCell, text: string, slice: Slice[int] = 0..0) =
  cell.currentText = text

method setText*(cell: PropertyCell, text: string, slice: Slice[int] = 0..0) =
  cell.currentText = text
  try:
    if cell.node.propertyDescription(cell.property).getSome(prop):

      case prop.typ
      of String:
        cell.node.setProperty(cell.property, PropertyValue(kind: PropertyType.String, stringValue: cell.currentText), slice)
      of Int:
        let intValue = cell.currentText.parseInt
        cell.node.setProperty(cell.property, PropertyValue(kind: PropertyType.Int, intValue: intValue), slice)
      of Bool:
        let boolValue = cell.currentText.parseBool
        cell.node.setProperty(cell.property, PropertyValue(kind: PropertyType.Bool, boolValue: boolValue), slice)

  except CatchableError:
    discard

method setText*(cell: AliasCell, text: string, slice: Slice[int] = 0..0) =
  cell.currentText = text

method setText*(cell: PlaceholderCell, text: string, slice: Slice[int] = 0..0) =
  cell.currentText = text

method getText*(cell: CollectionCell): string = "<>"

method getText*(cell: ConstantCell): string = cell.text

method getText*(cell: NodeReferenceCell): string =
  if cell.child.isNil:
    let reference = cell.node.reference(cell.reference)
    return $reference
  else:
    return cell.child.getText()

method getText*(cell: PropertyCell): string =
  let value = cell.node.property(cell.property)
  if value.getSome(value):
    case value.kind
    of String:
      return value.stringValue
    of Int:
      return $value.intValue
    of Bool:
      return $value.boolValue
  else:
    return "<empty>"


method getText*(cell: AliasCell): string =
  let class = cell.node.nodeClass
  if class.isNotNil:
    return class.alias
  else:
    return $cell.node.class

method getText*(cell: PlaceholderCell): string = cell.displayText.get("")

method dump(self: CollectionCell, recurse: bool = false): string =
  result = fmt"CollectionCell(inline: {self.inline}, flags: {self.flags}): {self.node}"
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
  result.add fmt"ConstantCell(node: {self.node.id}, text: {self.text})"

method dump(self: PropertyCell, recurse: bool = false): string =
  result.add fmt"PropertyCell(node: {self.node.id}, property: {self.property})"

method dump(self: NodeReferenceCell, recurse: bool = false): string =
  result.add fmt"NodeReferenceCell(node: {self.node.id}, target: {self.reference}, target property: {self.property})"

method dump(self: AliasCell, recurse: bool = false): string =
  result.add fmt"AliasCell(node: {self.node.id})"

method dump(self: PlaceholderCell, recurse: bool = false): string =
  result.add fmt"PlaceholderCell(node: {self.node.id}, role: {self.role})"

proc invalidate*(map: NodeCellMap) =
  map.map.clear()
  map.cells.clear()

proc fill*(map: NodeCellMap, self: Cell) =
  if self.fillChildren.isNil or self.filled:
    return
  self.fillChildren(map)
  self.filled = true

proc expand*(map: NodeCellMap, self: Cell, path: openArray[int]) =
  map.fill(self)
  if path.len > 0 and self.getChildAt(path[0], true).getSome(child):
    map.expand child, path[1..^1]

proc cell*(map: NodeCellMap, node: AstNode): Cell =
  if map.map.contains(node.id):
    return map.map[node.id]
  let cell = map.builder.buildCell(map, node, false)
  map.map[node.id] = cell
  return cell

proc findBuilder(self: CellBuilder, class: NodeClass, preferred: Id): CellBuilderFunction =
  if not self.builders.contains(class.id):
    if class.base.isNotNil:
      return self.findBuilder(class.base, preferred)
    return nil

  let builders = self.builders[class.id]
  if builders.len == 0:
    if class.base.isNotNil:
      return self.findBuilder(class.base, preferred)
    return nil

  if builders.len == 1:
    return builders[0].impl

  let preferredBuilder = self.preferredBuilders.getOrDefault(class.id, idNone())
  for builder in builders:
    if builder.builderId == preferredBuilder:
      return builder.impl

  return builders[0].impl

proc buildCellDefault*(self: CellBuilder, m: NodeCellMap, node: AstNode, useDefaultRecursive: bool): Cell =
  let class = node.nodeClass

  var cell = CollectionCell(id: newId(), node: node, flags: &{LayoutHorizontal})
  cell.fillChildren = proc(m: NodeCellMap) =
    cell.add ConstantCell(node: node, text: class.name, disableEditing: true)
    cell.add ConstantCell(node: node, text: "{", increaseIndentAfter: true, disableEditing: true)

    var hasAnyChildren = false

    for prop in node.properties:
      hasAnyChildren = true
      let name: string = class.propertyDescription(prop.role).map((decs) => decs.role).get($prop.role)
      cell.add ConstantCell(node: node, text: name, style: CellStyle(onNewLine: true), disableEditing: true)
      cell.add ConstantCell(node: node, text: ":", style: CellStyle(noSpaceLeft: true), disableEditing: true)
      cell.add PropertyCell(id: newId(), node: node, property: prop.role)

    for prop in node.references:
      hasAnyChildren = true
      let name: string = class.nodeReferenceDescription(prop.role).map((decs) => decs.role).get($prop.role)
      cell.add ConstantCell(node: node, text: name, style: CellStyle(onNewLine: true), disableEditing: true)
      cell.add ConstantCell(node: node, text: ":", style: CellStyle(noSpaceLeft: true), disableEditing: true)

      var nodeRefCell = NodeReferenceCell(id: newId(), node: node, reference: prop.role, property: IdINamedName)
      if node.resolveReference(prop.role).getSome(targetNode):
        nodeRefCell.child = PropertyCell(id: newId(), node: targetNode, property: IdINamedName)

      cell.add nodeRefCell

    for prop in node.childLists:
      hasAnyChildren = true
      let children = node.children(prop.role)

      let name: string = class.nodeChildDescription(prop.role).map((decs) => decs.role).get($prop.role)
      cell.add ConstantCell(node: node, text: name, style: CellStyle(onNewLine: true), disableEditing: true)
      cell.add ConstantCell(node: node, text: ":", style: CellStyle(noSpaceLeft: true), disableEditing: true, increaseIndentAfter: children.len > 1)

      var hasChildren = false
      for i, c in children:
        var childCell = self.buildCell(m, c, useDefaultRecursive)
        if childCell.style.isNil:
          childCell.style = CellStyle()
        childCell.style.onNewLine = children.len > 1
        if children.len > 1 and i == children.high:
          childCell.decreaseIndentAfter = true
        cell.add childCell
        hasChildren = true

      if not hasChildren:
        cell.add PlaceholderCell(node: node, role: prop.role, shadowText: "...")

    cell.add ConstantCell(node: node, text: "}", decreaseIndentBefore: true, style: CellStyle(onNewLine: hasAnyChildren), disableEditing: true)

  return cell

proc buildCell*(self: CellBuilder, map: NodeCellMap, node: AstNode, useDefault: bool = false): Cell =
  let class = node.nodeClass
  if class.isNil:
    debugf"Unknown class {node.class}"
    return EmptyCell(node: node)

  if not useDefault and (let builder = self.findBuilder(class, idNone()); builder.isNotNil):
    result = builder(self, node)
    # result.fill()
  else:
    if not useDefault:
      debugf"Unknown builder for {class.name}, using default"
    result = self.buildCellDefault(map, node, useDefault)
    # result.fill()

  map.map[node.id] = result
  map.cells[result.id] = result

proc buildDefaultPlaceholder*(builder: CellBuilder, node: AstNode, role: Id): Cell =
  return PlaceholderCell(id: newId(), node: node, role: role, shadowText: "...")

proc buildChildren*(builder: CellBuilder, map: NodeCellMap, node: AstNode, role: Id, flags: UINodeFlags,
    isVisible: proc(node: AstNode): bool = nil,
    separatorFunc: proc(builder: CellBuilder): Cell = nil,
    placeholderFunc: proc(builder: CellBuilder, node: AstNode, role: Id): Cell = buildDefaultPlaceholder): Cell =

  let children = node.children(role)
  if children.len > 1 or (children.len == 0 and placeholderFunc.isNil):
    var cell = CollectionCell(id: newId(), node: node, flags: flags)
    for i, c in node.children(role):
      if i > 0 and separatorFunc.isNotNil:
        cell.add separatorFunc(builder)
      cell.add builder.buildCell(map, c)
    result = cell
  elif children.len == 1:
    result = builder.buildCell(map, children[0])
  else:
    result = placeholderFunc(builder, node, role)
  result.isVisible = isVisible

template buildChildrenT*(b: CellBuilder, map: NodeCellMap, n: AstNode, r: Id, flags: UINodeFlags, body: untyped): Cell =
  var isVisibleFunc: proc(node: AstNode): bool = nil
  var separatorFunc: proc(builder: CellBuilder): Cell = nil
  var placeholderFunc: proc(builder: CellBuilder, node: AstNode, role: Id): Cell = nil

  var builder {.inject.} = b
  var node {.inject.} = n
  var role {.inject.} = r

  template separator(bod: untyped): untyped {.used.} =
    separatorFunc = proc(builder {.inject.}: CellBuilder): Cell =
      return bod

  template placeholder(bod: untyped): untyped {.used.} =
    placeholderFunc = proc(builder {.inject.}: CellBuilder, node {.inject.}: AstNode, role {.inject.}: Id): Cell =
      return bod

  template placeholder(text: string): untyped {.used.} =
    placeholderFunc = proc(builder {.inject.}: CellBuilder, node {.inject.}: AstNode, role {.inject.}: Id): Cell =
      return PlaceholderCell(id: newId(), node: node, role: role, shadowText: text)

  template visible(bod: untyped): untyped {.used.} =
    isVisibleFunc = proc(node {.inject.}: AstNode): bool =
      return bod

  placeholder("...")

  body

  builder.buildChildren(map, node, role, flags, isVisibleFunc, separatorFunc, placeholderFunc)

template visitFromCenter*(inCell: Cell, inPath: openArray[int], inForwards: bool, onTarget, onCenterVertical, onCenterHorizontal, onForwards, onBackwards, onHorizontal, onLeaf: untyped) =
  if inCell of CollectionCell:
    let cell = inCell.CollectionCell
    let vertical = LayoutVertical in cell.flags
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