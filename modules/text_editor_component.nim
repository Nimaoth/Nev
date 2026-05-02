#use
import std/[options]
import vmath
import nimsumtree/[rope, buffer]
import misc/[event]
import text/[display_map]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import scroll_box, document, component

export component

const currentSourcePath2 = currentSourcePath()
include module_base

type TextEditorComponent* = ref object of Component
  scrollBox*: ScrollBox
  lineNumberBounds*: Vec2
  targetColumn*: int
  displayMap*: DisplayMap
  onSelectionsChanged2*: Event[tuple[editor: TextEditorComponent, old: seq[Range[Point]]]]
  onScroll*: Event[void]
  onOverlaysChanged*: Event[tuple[ids: seq[int]]]
  onEdit*: Event[tuple[oldText: Rope, patch: Patch[Point]]]

# DLL API
var TextEditorComponentId* {.rtl.}: ComponentTypeId

{.push rtl, gcsafe, raises: [].}
proc newTextEditorComponent*(document: Document = nil): TextEditorComponent
proc textEditorComponentSelections(self: TextEditorComponent): lent seq[Range[Point]]
proc textEditorComponentSetSelections(self: TextEditorComponent, selections: sink seq[Range[Point]], addToHistory: Option[bool] = bool.none)
proc textEditorComponentSetTargetSelections(self: TextEditorComponent, selections: sink seq[Range[Point]])
proc textEditorComponentGetTargetSelections(self: TextEditorComponent): Option[seq[Range[Point]]]
proc textEditorComponentClearTargetSelections(self: TextEditorComponent)

proc getTextEditorComponent*(self: ComponentOwner): Option[TextEditorComponent]
proc textEditorComponentCenterCursor(self: TextEditorComponent, point: Point, relativePosition: float = 0.5, snap: bool = false)
proc textEditorComponentScrollToCursor(self: TextEditorComponent, point: Point, scrollBehaviour: ScrollBehaviour, snap: bool = false)
proc textEditorVisibleTextRange(self: TextEditorComponent, buffer: int = 0): Range[Point]
proc textEditorToDisplayPoint(self: TextEditorComponent, point: Point, bias: Bias = Bias.Right): Point
proc textEditorStartTransaction(self: TextEditorComponent)
proc textEditorEndTransaction(self: TextEditorComponent)
proc textEditorComponentSetCursorScrollOffset(self: TextEditorComponent, point: Point, offset: float)
proc textEditorComponentScrollToCursor2(self: TextEditorComponent, point: Point, center: bool = false, centerOffscreen: bool = false)
proc textEditorComponentUpdateTargetColumn(self: TextEditorComponent, point: Point)
proc textEditorComponentGetTargetColumn(self: TextEditorComponent): int
proc textEditorScreenLineCount*(self: TextEditorComponent): int
proc textEditorComponentEditString(self: TextEditorComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[string], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]]
proc textEditorComponentEditRope(self: TextEditorComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[Rope], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]]
proc textEditorComponentSelectPrev(self: TextEditorComponent)
proc textEditorComponentSelectNext(self: TextEditorComponent)
proc textEditorComponentSetDocument(self: TextEditorComponent, document: Document)
{.pop.}

# Nice wrappers
proc selection*(self: TextEditorComponent): Range[Point] {.inline.} = textEditorComponentSelections(self)[^1]
proc selections*(self: TextEditorComponent): lent seq[Range[Point]] {.inline.} = textEditorComponentSelections(self)
proc setSelections*(self: TextEditorComponent, selections: sink seq[Range[Point]], addToHistory: Option[bool] = bool.none) {.inline.} = textEditorComponentSetSelections(self, selections.ensureMove, addToHistory)
proc `selections=`*(self: TextEditorComponent, selections: sink seq[Range[Point]]) {.inline.} = textEditorComponentSetSelections(self, selections.ensureMove)
proc `selection=`*(self: TextEditorComponent, selection: Range[Point]) {.inline.} = textEditorComponentSetSelections(self, @[selection])
proc `selection=`*(self: TextEditorComponent, cursor: Point) {.inline.} = textEditorComponentSetSelections(self, @[cursor...cursor])
proc setTargetSelections*(self: TextEditorComponent, selections: sink seq[Range[Point]]) {.inline.} = textEditorComponentSetTargetSelections(self, selections.ensureMove)
proc setTargetSelection*(self: TextEditorComponent, selection: Range[Point]) {.inline.} = textEditorComponentSetTargetSelections(self, @[selection])
proc targetSelections*(self: TextEditorComponent): Option[seq[Range[Point]]] {.inline.} = textEditorComponentGetTargetSelections(self)
proc clearTargetSelections*(self: TextEditorComponent) {.inline.} = textEditorComponentClearTargetSelections(self)
proc `targetSelections=`*(self: TextEditorComponent, selections: sink seq[Range[Point]]) {.inline.} = textEditorComponentSetTargetSelections(self, selections.ensureMove)
proc `targetSelection=`*(self: TextEditorComponent, selection: Range[Point]) {.inline.} = textEditorComponentSetTargetSelections(self, @[selection])
proc centerCursor*(self: TextEditorComponent, point: Point, relativePosition: float = 0.5, snap: bool = false) {.inline.} = textEditorComponentCenterCursor(self, point, relativePosition, snap)
proc scrollToCursor*(self: TextEditorComponent, point: Point, scrollBehaviour: ScrollBehaviour, snap: bool = false) {.inline.} = textEditorComponentScrollToCursor(self, point, scrollBehaviour, snap)
proc visibleTextRange*(self: TextEditorComponent, buffer: int = 0): Range[Point] = textEditorVisibleTextRange(self, buffer)
proc toDisplayPoint*(self: TextEditorComponent, point: Point, bias: Bias = Bias.Right): Point = textEditorToDisplayPoint(self, point, bias)
proc startTransaction*(self: TextEditorComponent) = textEditorStartTransaction(self)
proc endTransaction*(self: TextEditorComponent) = textEditorEndTransaction(self)
proc setCursorScrollOffset*(self: TextEditorComponent, point: Point, offset: float) = textEditorComponentSetCursorScrollOffset(self, point, offset)
proc scrollToCursor*(self: TextEditorComponent, point: Point, center: bool = false, centerOffscreen: bool = false) = textEditorComponentScrollToCursor2(self, point, center, centerOffscreen)
proc updateTargetColumn*(self: TextEditorComponent, point: Point) = textEditorComponentUpdateTargetColumn(self, point)

proc edit*(self: TextEditorComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[string], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] {.inline.} =
  self.textEditorComponentEditString(selections, oldSelections, texts, notify, record, inclusiveEnd, checkpoint)
proc edit*(self: TextEditorComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[Rope], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] {.inline.} =
  self.textEditorComponentEditRope(selections, oldSelections, texts, notify, record, inclusiveEnd, checkpoint)

proc getTargetColumn*(self: TextEditorComponent): int = textEditorComponentGetTargetColumn(self)
proc screenLineCount*(self: TextEditorComponent): int = textEditorScreenLineCount(self)
proc selectPrev*(self: TextEditorComponent) = textEditorComponentSelectPrev(self)
proc selectNext*(self: TextEditorComponent) = textEditorComponentSelectNext(self)
proc setDocument*(self: TextEditorComponent, document: Document) = textEditorComponentSetDocument(self, document)

template withTransaction*(self: TextEditorComponent, body: untyped): untyped =
  try:
    self.startTransaction()
    body
  finally:
    self.endTransaction()

# Implementation
when implModule:
  import std/[sequtils, deques]
  import misc/[util, custom_logger, rope_utils]
  import document_editor, text_component
  import service, platform_service

  logCategory "text-editor-component"

  TextEditorComponentId = componentGenerateTypeId()

  type TextEditorComponentImpl* = ref object of TextEditorComponent
    document: Document
    mSelections: seq[Range[Point]]
    mSelectionsOld: seq[Selection]
    mTargetSelections*: Option[seq[Range[Point]]]
    selectionHistory*: Deque[Selections]

    onSelectionsChanged*: Event[tuple[editor: TextEditorComponent, old: seq[Selection]]]
    onDocumentChanged*: Event[tuple[editor: TextEditorComponent]]

  proc getTextEditorComponent*(self: ComponentOwner): Option[TextEditorComponent] {.gcsafe, raises: [].} =
    return self.getComponent(TextEditorComponentId).mapIt(it.TextEditorComponent)

  proc newTextEditorComponent*(document: Document = nil): TextEditorComponent =
    return TextEditorComponentImpl(
      typeId: TextEditorComponentId,
      document: document,
      mSelectionsOld: @[(0, 0).toSelection],
      mSelections: @[point(0, 0)...point(0, 0)]
    )

  proc markDirty(self: TextEditorComponent) =
    self.owner.DocumentEditor.markDirty()

  proc textEditorComponentSetDocument(self: TextEditorComponent, document: Document) =
    let self = self.TextEditorComponentImpl
    if self.document == document:
      return
    self.document = document
    self.selectionHistory.clear()
    self.onDocumentChanged.invoke((self.TextEditorComponent,))

  proc selectionsOld*(self: TextEditorComponent): var seq[Selection] =
    return self.TextEditorComponentImpl.mSelectionsOld

  proc shouldAddToHistory(old, new: openArray[Selection]): bool =
    if old.len != new.len:
      return true
    if abs(new[^1].last.line - old[^1].last.line) > 1:
      return true
    for i in 0..old.high:
      if not old[i].isEmpty and old[i].first != new[i].first and old[i].last != new[i].last:
        return true
    return false

  proc handleSelectionsChanged(self: TextEditorComponentImpl, old: openArray[Selection], addToHistory: Option[bool] = bool.none) =
    let addToHistory2 = self.selectionHistory.len == 0 or addToHistory.get(shouldAddToHistory(old, self.mSelectionsOld))
    if addToHistory2:
      let old = @old
      if self.selectionHistory.len > 0 and self.selectionHistory.peekLast == old:
        return
      self.selectionHistory.addLast old
      if self.selectionHistory.len > 100:
        discard self.selectionHistory.popFirst

  proc setSelectionsOld*(self: TextEditorComponent, selections: sink seq[Selection], addToHistory: Option[bool] = bool.none) =
    if selections.len == 0:
      return
    let self = self.TextEditorComponentImpl
    var old = seq[Selection].default
    var old2 = seq[Range[Point]].default
    swap(old, self.mSelectionsOld)
    swap(old2, self.mSelections)
    self.mSelectionsOld = selections.ensureMove
    self.mSelections = self.mSelectionsOld.mapIt(it.toRange)
    self.handleSelectionsChanged(old, addToHistory)
    self.onSelectionsChanged.invoke((self.TextEditorComponent, old))
    self.onSelectionsChanged2.invoke((self.TextEditorComponent, old2))

  proc textEditorComponentSelections(self: TextEditorComponent): lent seq[Range[Point]] =
    return self.TextEditorComponentImpl.mSelections

  proc textEditorComponentSetSelections(self: TextEditorComponent, selections: sink seq[Range[Point]], addToHistory: Option[bool] = bool.none) =
    if selections.len == 0:
      return
    let self = self.TextEditorComponentImpl
    var old = seq[Selection].default
    var old2 = seq[Range[Point]].default
    swap(old, self.mSelectionsOld)
    swap(old2, self.mSelections)
    self.mSelections = selections.ensureMove
    self.mSelectionsOld = self.mSelections.mapIt(it.toSelection)
    self.handleSelectionsChanged(old, addToHistory)
    self.onSelectionsChanged.invoke((self.TextEditorComponent, old))
    self.onSelectionsChanged2.invoke((self.TextEditorComponent, old2))

  proc textEditorComponentGetTargetSelections(self: TextEditorComponent): Option[seq[Range[Point]]] =
    let self = self.TextEditorComponentImpl
    return self.mTargetSelections

  proc textEditorComponentClearTargetSelections(self: TextEditorComponent) =
    let self = self.TextEditorComponentImpl
    self.mTargetSelections = seq[Range[Point]].none

  proc textEditorComponentSetTargetSelections(self: TextEditorComponent, selections: sink seq[Range[Point]]) =
    let self = self.TextEditorComponentImpl
    if self.document == nil:
      return

    if self.document.isLoadingAsync or self.document.requiresLoad:
      self.mTargetSelections = selections.some
    else:
      self.textEditorComponentSetSelections(selections)
      # self.updateTargetColumn(Last) # todo

  proc textEditorComponentCenterCursor(self: TextEditorComponent, point: Point, relativePosition: float = 0.5, snap: bool = false) =
    let self = self.TextEditorComponentImpl
    let displayPoint = self.displayMap.toDisplayPoint(point)
    if snap and self.scrollBox.size.y != 0:
      self.scrollBox.scrollToY(displayPoint.row.int, self.scrollBox.size.y * relativePosition)
    else:
      self.scrollBox.scrollTo(displayPoint.row.int, center = true, snap = snap)

  proc textEditorComponentScrollToCursor(self: TextEditorComponent, point: Point, scrollBehaviour: ScrollBehaviour, snap: bool = false) =
    let self = self.TextEditorComponentImpl
    let displayPoint = self.displayMap.toDisplayPoint(point)
    let (centerY, centerOffscreenY) = case scrollBehaviour
      of CenterAlways: (true, false)
      of CenterOffscreen: (false, true)
      of CenterMargin: (false, false)
      of ScrollToMargin: (false, false)
      of TopOfScreen: (false, false)

    self.scrollBox.scrollTo(displayPoint.row.int, center = centerY, centerOffscreen = centerOffscreenY, snap = snap)

  proc numDisplayLines*(self: TextEditorComponent): int =
    let self = self.TextEditorComponentImpl
    return self.displayMap.endDisplayPoint.row.int + 1

  proc textEditorScreenLineCount(self: TextEditorComponent): int =
    ## Returns the number of lines that can be shown on the screen
    ## This value depends on the size of the view this editor is in and the font size
    let self = self.TextEditorComponentImpl
    return self.scrollBox.items.len

  proc visibleDisplayRange*(self: TextEditorComponent, buffer: int = 0): Range[DisplayPoint] =
    let self = self.TextEditorComponentImpl
    assert self.numDisplayLines > 0
    if self.scrollBox.items.len > 0:
      let firstDisplayLine = self.scrollBox.items[0].index
      let lastDisplayLine = self.scrollBox.items[^1].index
      return displayPoint(firstDisplayLine, 0)...displayPoint(lastDisplayLine + 1, 0).clamp(displayPoint(), self.displayMap.endDisplayPoint)

    return displayPoint(0, 0)...displayPoint(0, 0)

  proc textEditorVisibleTextRange(self: TextEditorComponent, buffer: int = 0): Range[Point] =
    let self = self.TextEditorComponentImpl
    let displayRange = self.visibleDisplayRange(buffer)
    result.a = self.displayMap.toPoint(displayRange.a)
    result.b = self.displayMap.toPoint(displayRange.b)

  proc textEditorToDisplayPoint(self: TextEditorComponent, point: Point, bias: Bias = Bias.Right): Point =
    let self = self.TextEditorComponentImpl
    return self.displayMap.toDisplayPoint(point, bias).Point

  proc textEditorStartTransaction(self: TextEditorComponent) =
    let self = self.TextEditorComponentImpl
    if self.document != nil and self.document.getTextComponent().getSome(text):
      text.startTransaction()

  proc textEditorEndTransaction(self: TextEditorComponent) =
    let self = self.TextEditorComponentImpl
    if self.document != nil and self.document.getTextComponent().getSome(text):
      text.endTransaction()

  proc textEditorComponentEditString(self: TextEditorComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]],
     texts: openArray[string], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] =
    if self.TextEditorComponentImpl.document.getTextComponent().getSome(text):
      return text.editString(selections, oldSelections, texts, notify, record, inclusiveEnd, checkpoint)
    return newSeq[Range[Point]]()
  proc textEditorComponentEditRope(self: TextEditorComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]],
     texts: openArray[Rope], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] =
    if self.TextEditorComponentImpl.document.getTextComponent().getSome(text):
      return text.editRope(selections, oldSelections, texts, notify, record, inclusiveEnd, checkpoint)
    return newSeq[Range[Point]]()

  proc textEditorComponentSetCursorScrollOffset(self: TextEditorComponent, point: Point, offset: float) =
    let self = self.TextEditorComponentImpl
    let displayPoint = self.displayMap.toDisplayPoint(point)
    self.scrollBox.scrollToY(displayPoint.row.int, offset * self.scrollBox.defaultItemHeight)
    self.markDirty()

  proc textEditorComponentScrollToCursor2(self: TextEditorComponent, point: Point, center: bool = false, centerOffscreen: bool = false) =
    let self = self.TextEditorComponentImpl
    let displayPoint = self.displayMap.toDisplayPoint(point)
    self.scrollBox.scrollTo(displayPoint.row.int, center = center, centerOffscreen = centerOffscreen)

    if self.scrollBox.offset.x != 0 or self.displayMap.wrapMap.wrapWidth == 0:
      let charWidth = getServiceChecked(PlatformService).platform.charWidth
      let cursorX = displayPoint.column.float * charWidth
      let currentX = self.scrollBox.currentOffset.x
      if center:
        self.scrollBox.scrollToX(cursorX - self.scrollBox.size.x * 0.5 + charWidth * 0.5)
      else:
        if cursorX + currentX < self.scrollBox.margin:
          self.scrollBox.scrollWithMomentum(vec2(self.scrollBox.margin - cursorX - currentX, 0))
        elif cursorX + currentX + charWidth > self.scrollBox.size.x - self.lineNumberBounds.x.ceil - self.scrollBox.margin:
          self.scrollBox.scrollWithMomentum(vec2(self.scrollBox.size.x - self.lineNumberBounds.x.ceil - self.scrollBox.margin - charWidth - cursorX - currentX, 0))

  proc textEditorComponentSelectPrev(self: TextEditorComponent) =
    let self = self.TextEditorComponentImpl
    if self.selectionHistory.len > 0:
      let selection = self.selectionHistory.popLast
      assert selection.len > 0, "[selectPrev] Empty selection"
      self.selectionHistory.addFirst self.selectionsOld
      self.setSelections(selection.mapIt(it.toRange), addToHistory = false.some)
    self.updateTargetColumn(self.selections.last.b)
    self.scrollToCursor(self.selection.b)

  proc textEditorComponentSelectNext(self: TextEditorComponent) =
    let self = self.TextEditorComponentImpl
    if self.selectionHistory.len > 0:
      let selection = self.selectionHistory.popFirst
      assert selection.len > 0, "[selectNext] Empty selection"
      self.selectionHistory.addLast self.selectionsOld
      self.setSelections(selection.mapIt(it.toRange), addToHistory = false.some)
    self.updateTargetColumn(self.selections.last.b)
    self.scrollToCursor(self.selection.b)

  import move_component
  proc textEditorComponentUpdateTargetColumn(self: TextEditorComponent, point: Point) =
    let self = self.TextEditorComponentImpl
    let wrapPoint = self.displayMap.toWrapPoint(point)
    self.targetColumn = wrapPoint.column.int
    if self.owner.getMoveComponent().getSome(moves):
      moves.targetColumn = self.targetColumn

  proc textEditorComponentGetTargetColumn(self: TextEditorComponent): int =
    let self = self.TextEditorComponentImpl
    return self.targetColumn
