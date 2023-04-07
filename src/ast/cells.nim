import std/[tables, strutils, strformat, options]
import platform/[widgets]
import types, id

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

method getChildAt*(self: CollectionCell, index: int, clamp: bool): Option[Cell] =
  let index = if clamp: index.clamp(0..self.children.high) else: index
  if index < 0 or index > self.children.high:
    return Cell.none
  return self.children[index].some

method dump(self: CollectionCell): string =
  result.add &"CollectionCell(inline: {self.inline}, layout: {self.layout}): {self.node}\n"
  if self.filled or self.fillChildren.isNil:
    for c in self.children:
      result.add c.dump.indent(4)
      result.add "\n"
  else:
    result.add "...".indent(4)

method dump(self: ConstantCell): string =
  result.add fmt"ConstantCell(node: {self.node.id}, text: {self.text})"

method dump(self: PropertyCell): string =
  result.add fmt"PropertyCell(node: {self.node.id}, property: {self.property})"

method dump(self: NodeReferenceCell): string =
  result.add fmt"NodeReferenceCell(node: {self.node.id}, target: {self.reference}, target property: {self.property})"

method dump(self: AliasCell): string =
  result.add fmt"AliasCell(node: {self.node.id})"