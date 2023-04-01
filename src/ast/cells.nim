import std/[tables, strutils, strformat, options]
import platform/[widgets]
import types, id

type
  CollectionCell* = ref object of Cell
    children*: seq[Cell]

  ConstantCell* = ref object of Cell
    text*: string

  PropertyCell* = ref object of Cell
    property*: Id

  NodeReferenceCell* = ref object of Cell
    reference*: Id

method updateWidget(self: Cell, widget: var WWidget, frameIndex: int) {.base.} = discard

method updateWidget(self: ConstantCell, widget: var WWidget, frameIndex: int) =
  if widget.isNil or not (widget of WText):
    widget = WText()

  widget.WText.text = self.text
  widget.updateLastHierarchyChangeFromChildren(frameIndex)

method getChildAt*(self: CollectionCell, index: int, clamp: bool): Option[Cell] =
  let index = if clamp: index.clamp(0..self.children.high) else: index
  if index < 0 or index > self.children.high:
    return Cell.none
  return self.children[index].some

method dump(self: CollectionCell): string =
  result.add &"CollectionCell(node: {self.node.id}):\n"
  if self.filled or self.fillChildren.isNil:
    for c in self.children:
      result.add c.dump.indent(4)
      result.add "\n"
  else:
    result.add "...".indent(4)

method dump(self: ConstantCell): string =
  result.add fmt"ConstantCell(node: {self.node.id}, text: {self.text})"

method dump(self: PropertyCell): string =
  result.add fmt"PropertyCell(node: {self.node.id}, text: {self.property})"

method dump(self: NodeReferenceCell): string =
  result.add fmt"NodeReferenceCell(node: {self.node.id}, text: {self.reference})"