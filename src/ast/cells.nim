import std/[tables]
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
