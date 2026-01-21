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

# Implementation
when implModule:
  import misc/[util, custom_logger]
  import nimsumtree/[clock]

  logCategory "text-component"

  TextComponentId = componentGenerateTypeId()

  type TextComponentImpl* = ref object of TextComponent
    buffer*: Buffer

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

proc buffer*(self: TextComponent): lent Buffer {.inline.} = self.textComponentBuffer()
