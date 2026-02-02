import std/[options]
import nimsumtree/[rope, buffer]
import misc/[event]
import component

export component

include dynlib_export

type TextComponent* = ref object of Component
  onEdit*: Event[Patch[Point]]

# DLL API
var TextComponentId* {.apprtl.}: ComponentTypeId

proc textComponentContent*(self: TextComponent): Rope {.apprtl, gcsafe, raises: [].}
proc textComponentBuffer*(self: TextComponent): lent Buffer {.apprtl, gcsafe, raises: [].}
proc getTextComponent*(self: ComponentOwner): Option[TextComponent] {.apprtl, gcsafe, raises: [].}
proc textComponentEditString(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[string], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] {.apprtl, gcsafe, raises: [].}
proc textComponentEditRope(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[Rope], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] {.apprtl, gcsafe, raises: [].}

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

# Implementation
when implModule:
  import std/[sequtils]
  import misc/[util, custom_logger, rope_utils]
  import nimsumtree/[clock]
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor

  logCategory "text-component"

  TextComponentId = componentGenerateTypeId()

  type TextComponentImpl* = ref object of TextComponent
    buffer*: Buffer
    editString*: proc(selections: openArray[Selection], oldSelections: openArray[Selection], texts: openArray[string], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Selection] {.gcsafe, raises: [].}
    editRope*: proc(selections: openArray[Selection], oldSelections: openArray[Selection], texts: openArray[Rope], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Selection] {.gcsafe, raises: [].}

  var nextBufferId = 1.BufferId
  proc getNextBufferId*(): BufferId =
    result = nextBufferId
    inc nextBufferId

  proc getTextComponent*(self: ComponentOwner): Option[TextComponent] {.gcsafe, raises: [].} =
    return self.getComponent(TextComponentId).mapIt(it.TextComponent)

  proc newTextComponent*(): TextComponentImpl =
    return TextComponentImpl(typeId: TextComponentId, buffer: initBuffer(content = "", remoteId = getNextBufferId()))

  proc textComponentContent*(self: TextComponent): Rope =
    return self.TextComponentImpl.buffer.visibleText

  proc textComponentBuffer*(self: TextComponent): lent Buffer =
    return self.TextComponentImpl.buffer

  proc initBuffer*(self: TextComponent, replicaId: ReplicaId = 0.ReplicaId, content: string = "", remoteId: BufferId = 1.BufferId) =
    self.TextComponentImpl.buffer = initBuffer(replicaId, content, remoteId)

  proc initBuffer*(self: TextComponent, replicaId: ReplicaId, content: sink Rope, remoteId: BufferId = 1.BufferId) =
    self.TextComponentImpl.buffer = initBuffer(replicaId, content, remoteId)

  proc textComponentEditString(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[string], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] =
    self.TextComponentImpl.editString(selections.mapIt(it.toSelection), oldSelections.mapIt(it.toSelection), texts, notify, record, inclusiveEnd, checkpoint).mapIt(it.toRange)
  proc textComponentEditRope(self: TextComponent, selections: openArray[Range[Point]], oldSelections: openArray[Range[Point]], texts: openArray[Rope], notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Range[Point]] =
    self.TextComponentImpl.editRope(selections.mapIt(it.toSelection), oldSelections.mapIt(it.toSelection), texts, notify, record, inclusiveEnd, checkpoint).mapIt(it.toRange)

proc buffer*(self: TextComponent): lent Buffer {.inline.} = self.textComponentBuffer()
