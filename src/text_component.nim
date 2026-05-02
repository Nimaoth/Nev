import std/[options]
import nimsumtree/[rope, buffer, clock]
import misc/[event, custom_async]
import component

export component

include dynlib_export

type TextComponent* = ref object of Component
  buffer*: Buffer
  editString*: proc(selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[string], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] {.gcsafe, raises: [].}
  editRope*: proc(selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[Rope], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] {.gcsafe, raises: [].}
  editRopeSlice*: proc(selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[RopeSlice[int]], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] {.gcsafe, raises: [].}
  setFileAndContentImpl*: proc(filename: string, content: sink Rope) {.gcsafe, raises: [].}
  onEdit*: Event[tuple[oldText: Rope, patch: Patch[Point]]]
  savedVersion*: TransactionId
  onEditTransaction*: Event[Transaction]
  onUndoTransaction*: Event[Transaction]
  onRedoTransaction*: Event[Transaction]

# DLL API

{.push apprtl, gcsafe, raises: [].}
proc newTextComponent*(): TextComponent
proc textComponentContent*(self: TextComponent): Rope
proc textComponentBuffer*(self: TextComponent): var Buffer
proc getTextComponent*(self: ComponentOwner): Option[TextComponent]
proc textComponentEditString(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[string], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]]
proc textComponentEditRope(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[Rope], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]]
proc textComponentEditRopeSlice(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[RopeSlice[int]], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]]
proc textComponentStartTransaction(self: TextComponent)
proc textComponentEndTransaction(self: TextComponent)
proc textComponentReplaceAllRope(self: TextComponent, value: sink Rope)
proc textComponentReplaceAll(self: TextComponent, value: sink string)
proc textComponentReloadFromRope(self: TextComponent, rope: sink Rope) {.async.}
proc textComponentSetFileAndContent(self: TextComponent, filename: string, content: sink Rope)
proc textComponentInitBuffer(self: TextComponent, replicaId: ReplicaId, content: sink Rope, remoteId: BufferId = 1.BufferId)
proc textComponentGetNextBufferId(): BufferId
{.pop.}

proc initBuffer*(self: TextComponent, replicaId: ReplicaId, content: sink Rope, remoteId: BufferId = 1.BufferId) = textComponentInitBuffer(self, replicaId, content, remoteId)
proc getNextBufferId*(): BufferId = textComponentGetNextBufferId()

template withTransaction*(self: TextComponent, body: untyped): untyped =
  try:
    self.startTransaction()
    body
  finally:
    self.endTransaction()

# Nice wrappers
proc normalized*(r: Range[Point]): Range[Point] =
  if r.a > r.b:
    r.b...r.a
  else:
    r

proc content*(self: TextComponent): Rope {.inline.} = self.textComponentContent()

proc content*(self: TextComponent, selection: Range[Point], inclusiveEnd: bool = false): string =
  let selection = selection.normalized

  let rope = self.content
  var c = rope.cursorT(selection.a)
  var target = selection.b
  if inclusiveEnd and target.column.int < rope.lineLen(target.row.int):
    target.column += 1

  let res = c.slice(target, Bias.Right)
  return $res

proc edit*(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[string], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] {.inline.} =
  self.textComponentEditString(selections, oldSelections, texts, notify, record, inclusiveEnd, checkpoint)
proc edit*(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[Rope], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] {.inline.} =
  self.textComponentEditRope(selections, oldSelections, texts, notify, record, inclusiveEnd, checkpoint)
proc edit*(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[RopeSlice[int]], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] {.inline.} =
  self.textComponentEditRopeSlice(selections, oldSelections, texts, notify, record, inclusiveEnd, checkpoint)
proc startTransaction*(self: TextComponent) = textComponentStartTransaction(self)
proc endTransaction*(self: TextComponent) = textComponentEndTransaction(self)

proc `content=`*(self: TextComponent, text: string) =
  self.startTransaction()
  let fullRange = point(0, 0)...self.content.endPoint
  discard self.edit([fullRange], [fullRange], [text])
  self.endTransaction()

proc replaceAll*(self: TextComponent, value: sink Rope) = textComponentReplaceAllRope(self, value)
proc replaceAll*(self: TextComponent, value: sink string) = textComponentReplaceAll(self, value)
proc reloadFromRope*(self: TextComponent, rope: sink Rope) {.async.} = await textComponentReloadFromRope(self, rope)

proc setFileAndContent*(self: TextComponent, filename: string, content: sink Rope) = textComponentSetFileAndContent(self, filename, content)

# Implementation
when implModule:
  import std/[sequtils, unicode]
  import misc/[util, custom_logger, rope_utils, timer]
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
  import text/diff

  logCategory "text-component"

  let TextComponentId = componentGenerateTypeId()

  type TextComponentImpl* = ref object of TextComponent

  var nextBufferId = 1.BufferId
  proc textComponentGetNextBufferId(): BufferId =
    result = nextBufferId
    inc nextBufferId

  proc getTextComponent*(self: ComponentOwner): Option[TextComponent] {.gcsafe, raises: [].} =
    return self.getComponent(TextComponentId).mapIt(it.TextComponent)

  proc newTextComponent*(): TextComponent =
    return TextComponentImpl(typeId: TextComponentId, buffer: initBuffer(content = "", remoteId = getNextBufferId()))

  proc textComponentContent*(self: TextComponent): Rope =
    return self.TextComponentImpl.buffer.visibleText

  proc textComponentBuffer*(self: TextComponent): var Buffer =
    return self.TextComponentImpl.buffer

  proc initBuffer*(self: TextComponent, replicaId: ReplicaId = 0.ReplicaId, content: string = "", remoteId: BufferId = 1.BufferId) =
    self.TextComponentImpl.buffer = initBuffer(replicaId, content, remoteId)
    self.TextComponentImpl.buffer.onEditTransaction = proc(buffer: Buffer, transaction: Transaction) {.gcsafe, raises: [].} =
      self.TextComponentImpl.onEditTransaction.invoke transaction
    self.TextComponentImpl.buffer.onUndoTransaction = proc(buffer: Buffer, transaction: Transaction) {.gcsafe, raises: [].} =
      self.TextComponentImpl.onUndoTransaction.invoke transaction
    self.TextComponentImpl.buffer.onRedoTransaction = proc(buffer: Buffer, transaction: Transaction) {.gcsafe, raises: [].} =
      self.TextComponentImpl.onRedoTransaction.invoke transaction

  proc textComponentInitBuffer(self: TextComponent, replicaId: ReplicaId, content: sink Rope, remoteId: BufferId = 1.BufferId) =
    self.TextComponentImpl.buffer = initBuffer(replicaId, content, remoteId)
    self.TextComponentImpl.buffer.onEditTransaction = proc(buffer: Buffer, transaction: Transaction) {.gcsafe, raises: [].} =
      self.TextComponentImpl.onEditTransaction.invoke transaction
    self.TextComponentImpl.buffer.onUndoTransaction = proc(buffer: Buffer, transaction: Transaction) {.gcsafe, raises: [].} =
      self.TextComponentImpl.onUndoTransaction.invoke transaction
    self.TextComponentImpl.buffer.onRedoTransaction = proc(buffer: Buffer, transaction: Transaction) {.gcsafe, raises: [].} =
      self.TextComponentImpl.onRedoTransaction.invoke transaction

  proc textComponentEditString(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[string], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] =
    self.TextComponentImpl.editString(selections, oldSelections, texts, notify, record, inclusiveEnd, checkpoint)
  proc textComponentEditRope(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[Rope], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] =
    self.TextComponentImpl.editRope(selections, oldSelections, texts, notify, record, inclusiveEnd, checkpoint)
  proc textComponentEditRopeSlice(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[RopeSlice[int]], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] =
    self.TextComponentImpl.editRopeSlice(selections, oldSelections, texts, notify, record, inclusiveEnd, checkpoint)

  proc textComponentStartTransaction(self: TextComponent) =
    discard self.TextComponentImpl.buffer.startTransaction()

  proc textComponentEndTransaction(self: TextComponent) =
    discard self.TextComponentImpl.buffer.endTransaction()

  proc textComponentReplaceAllRope(self: TextComponent, value: sink Rope) =
    let self = self.TextComponentImpl
    let fullRange = point(0, 0)...self.content.summary().lines
    discard self.edit([fullRange], [], [value])
    discard self.buffer.endTransaction()

  proc textComponentReplaceAll(self: TextComponent, value: sink string) =
    let self = self.TextComponentImpl
    let invalidUtf8Index = value.validateUtf8
    if invalidUtf8Index >= 0:
      log lvlError, &"[replace] Trying to set content with invalid utf-8 string (invalid byte at {invalidUtf8Index})"
      return

    var index = 0
    const utf8_bom = "\xEF\xBB\xBF"
    if value.len >= 3 and value.startsWith(utf8_bom):
      log lvlInfo, &"[content=] Skipping utf8 bom"
      index = 3

    let fullRange = point(0, 0)...self.content.summary().lines
    discard self.edit([fullRange], [], [value[index..^1]])
    discard self.buffer.endTransaction()

  proc textComponentReloadFromRope(self: TextComponent, rope: sink Rope) {.async.} =
    let self = self.TextComponentImpl
    let t = startTimer()

    try:
      let oldRope = self.content.clone()
      var diff = RopeDiff[int]()
      await diffRopeAsync(oldRope.clone(), rope.clone(), diff.addr).wait(300.milliseconds)
      if self.owner.isNil:
        return

      if diff.edits.len > 0:
        var selections = newSeq[Range[Point]]()
        var texts = newSeq[RopeSlice[int]]()
        for edit in diff.edits:
          let a = oldRope.convert(edit.old.a, Point)
          let b = oldRope.convert(edit.old.b, Point)
          selections.add a...b
          texts.add edit.text.clone()

        discard self.edit(selections, [], texts)
        discard self.buffer.endTransaction()

        if self.content != rope:
          self.replaceAll(rope.move)

    except AsyncTimeoutError:
      log lvlWarn, &"reloadFromRope: diff timed out after {t.elapsed.ms} ms"
      self.replaceAll(rope.move)

  proc textComponentSetFileAndContent(self: TextComponent, filename: string, content: sink Rope) =
    self.TextComponentImpl.setFileAndContentImpl(filename, content)

proc buffer*(self: TextComponent): var Buffer {.inline.} = self.textComponentBuffer()
