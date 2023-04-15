import std/[tables, strutils, strformat, options, sequtils]
import platform/[widgets]
import types, id, util

type
  CollectionCell* = ref object of Cell
    layout*: WPanelLayout
    inline*: bool
    children*: seq[Cell]

  ConstantCell* = ref object of Cell
    text*: string

  PropertyCell* = ref object of Cell
    property*: Id

  NodeReferenceCell* = ref object of Cell
    reference*: Id
    property*: Id
    child*: Cell

  AliasCell* = ref object of Cell
    discard

method getText*(cell: Cell): string {.base.} = discard
method setText*(cell: Cell, text: string) {.base.} = discard

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
  result = 0
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
    return self.getText().low

proc editableLow*(self: Cell): int =
  if self.style.isNotNil and self.style.noSpaceLeft:
    return self.low + 1
  return self.low

proc high*(self: Cell): int =
  if self of CollectionCell:
    return self.CollectionCell.children.high
  else:
    return self.getText().high

proc editableHigh*(self: Cell): int =
  if self.style.isNotNil and self.style.noSpaceRight:
    return self.high - 1
  return self.high

proc previousDirect*(self: Cell): Cell =
  ### Returns the previous cell before self in the parents children, or nil.
  let i = self.index
  if i == -1 or i < 1:
    return nil
  return self.parent.CollectionCell.children[i - 1]

proc nextDirect*(self: Cell): Cell =
  ### Returns the next cell after self in the parents children, or nil.
  let i = self.index
  if i == -1 or i >= self.parent.CollectionCell.children.high:
    return nil
  return self.parent.CollectionCell.children[i + 1]

method getChildAt*(self: CollectionCell, index: int, clamp: bool): Option[Cell] =
  let index = if clamp: index.clamp(0..self.children.high) else: index
  if index < 0 or index > self.children.high:
    return Cell.none
  return self.children[index].some

proc insertText*(cell: Cell, index: int, text: string): int =
  var currentText = cell.getText()
  currentText.insert(text, index)
  cell.setText(currentText)
  if cell.getText() == currentText:
    return index + text.len
  return index

method setText*(cell: CollectionCell, text: string) = discard

method setText*(cell: ConstantCell, text: string) = discard

method setText*(cell: NodeReferenceCell, text: string) =
  # @todo
  discard

method setText*(cell: PropertyCell, text: string) =
  if cell.node.propertyDescription(cell.property).getSome(prop):
    case prop.typ
    of String:
      cell.node.setProperty(cell.property, PropertyValue(kind: PropertyType.String, stringValue: text))
    of Int:
      try:
        let intValue = text.parseInt
        cell.node.setProperty(cell.property, PropertyValue(kind: PropertyType.Int, intValue: intValue))
      except CatchableError:
        discard
    of Bool:
      try:
        let boolValue = text.parseBool
        cell.node.setProperty(cell.property, PropertyValue(kind: PropertyType.Bool, boolValue: boolValue))
      except CatchableError:
        discard

method setText*(cell: AliasCell, text: string) = discard

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

method dump(self: CollectionCell, recurse: bool = false): string =
  result = fmt"CollectionCell(inline: {self.inline}, layout: {self.layout}): {self.node}"
  if recurse:
    result.add "\n"
    if self.filled or self.fillChildren.isNil:
      for c in self.children:
        result.add c.dump.indent(4)
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