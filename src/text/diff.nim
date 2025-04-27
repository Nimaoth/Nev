import std/[options, atomics]
import std/[random]
import nimsumtree/[buffer, rope, sumtree]
import misc/[custom_unicode]

type
  LineMapping* = object
    source*: tuple[first: int, last: int]
    target*: tuple[first: int, last: int]
    lines*: seq[string]

proc contains(r: (int, int), line: int): bool = line >= r[0] and line < r[1]

proc mapLineTargetToSource*(mappings: openArray[LineMapping], line: int): Option[tuple[line: int, changed: bool]] =
  # todo: binary search
  if mappings.len == 0:
    return (line, false).some

  if line < mappings[0].target.first:
    return (line, false).some

  var lastSource = 0
  var lastTarget = 0
  for i in 0..mappings.high:
    if mappings[i].target.contains(line):
      let sourceLine = mappings[i].source.first + (line - mappings[i].target.first)
      if mappings[i].source.contains(sourceLine):
        return (sourceLine, true).some
      return (int, bool).none

    if line < mappings[i].target.first:
      let sourceLine = mappings[i].source.first + (line - mappings[i].target.first)
      return (sourceLine, false).some

    lastSource = mappings[i].source.last
    lastTarget = mappings[i].target.last

  return some (lastSource + (line - lastTarget), false)

proc mapLineSourceToTarget*(mappings: openArray[LineMapping], line: int): Option[tuple[line: int, changed: bool]] =
  # todo: binary search
  if mappings.len == 0:
    return (line, false).some

  if line < mappings[0].source.first:
    return (line, false).some

  var lastTarget = 0
  var lastSource = 0
  for i in 0..mappings.high:
    if mappings[i].source.contains(line):
      let targetLine = mappings[i].target.first + (line - mappings[i].source.first)
      if mappings[i].target.contains(targetLine):
        return (targetLine, true).some
      return (int, bool).none

    if line < mappings[i].source.first:
      let targetLine = mappings[i].target.first + (line - mappings[i].source.first)
      return (targetLine, false).some

    lastTarget = mappings[i].target.last
    lastSource = mappings[i].source.last

  return some (lastTarget + (line - lastSource), false)

proc mapLine*(mappings: openArray[LineMapping], line: int, reverse: bool): Option[tuple[line: int, changed: bool]] =
  if reverse:
    return mappings.mapLineTargetToSource(line)
  else:
    return mappings.mapLineSourceToTarget(line)

static:
  let mappings = [
    LineMapping(source: (10, 10), target: (10, 20)),
    LineMapping(source: (20, 30), target: (30, 40)),
    LineMapping(source: (40, 50), target: (50, 50)),
  ]

  assert mappings.mapLineTargetToSource(9) == (9, false).some
  assert mappings.mapLineTargetToSource(10) == (int, bool).none
  assert mappings.mapLineTargetToSource(11) == (int, bool).none
  assert mappings.mapLineTargetToSource(19) == (int, bool).none
  assert mappings.mapLineTargetToSource(20) == (10, false).some
  assert mappings.mapLineTargetToSource(21) == (11, false).some
  assert mappings.mapLineTargetToSource(29) == (19, false).some
  assert mappings.mapLineTargetToSource(30) == (20, true).some
  assert mappings.mapLineTargetToSource(31) == (21, true).some
  assert mappings.mapLineTargetToSource(39) == (29, true).some
  assert mappings.mapLineTargetToSource(40) == (30, false).some
  assert mappings.mapLineTargetToSource(41) == (31, false).some
  assert mappings.mapLineTargetToSource(49) == (39, false).some
  assert mappings.mapLineTargetToSource(50) == (50, false).some
  assert mappings.mapLineTargetToSource(51) == (51, false).some


type
  DiffData[T, C] = object
    # data: ptr UncheckedArray[int]
    data: C
    modified: seq[bool]
    len: int

  Operation[T] = object
    old: Range[int]
    items: seq[T]

  Diff[T] = object
    ops: seq[Operation[T]]

  RopeEdit*[T] = tuple
    old: Range[T]
    new: Range[T]
    text: RopeSlice[T]

  RopeDiff*[T] = object
    edits*: seq[RopeEdit[T]]

  SeqCursor[T] = object
    data: seq[T]
    index: int

  RuneCursor = object
    data: ptr UncheckedArray[char]
    len: int
    index: int

  RopeCursorWrapper = object
    cursor: RopeSliceCursor[Count, Count]

proc len(c: SeqCursor): int = c.data.len
proc current[T](c: SeqCursor[T]): lent T = c.data[c.index]
proc next[T](c: var SeqCursor[T]) = inc(c.index)
proc prev[T](c: var SeqCursor[T]) = dec(c.index)
proc seek[T](c: var SeqCursor[T], index: int) = c.index = index
proc slice[T](c: SeqCursor[T], first: int, last: int): seq[T] = c.data[first..<last]

proc len(c: RuneCursor): int = c.len
proc current[T](c: RuneCursor): lent T = c.data.toOpenArray(0, c.len - 1).runeAt(c.index)
proc next[T](c: var RuneCursor) = c.index = c.data.toOpenArray(0, c.len - 1).nextRuneStart(c.index)
proc prev[T](c: var RuneCursor) = c.index = c.data.toOpenArray(0, c.len - 1).runeStart(c.index - 1)
proc seek[T](c: var RuneCursor, index: int) = c.index = index
# proc slice[T](c: RuneCursor, first: int, last: int): seq[T] = c.data[first..<last]

proc `=copy`*(a: var RopeCursorWrapper, b: RopeCursorWrapper) {.error.}
proc `=dup`*(a: RopeCursorWrapper): RopeCursorWrapper {.error.}

proc len(c: RopeCursorWrapper): int = c.cursor.ropeSlice.summary.len.int
proc current(c: RopeCursorWrapper): Rune = c.cursor.currentRune()
proc next(c: var RopeCursorWrapper) = c.cursor.seekNextRune()
proc prev(c: var RopeCursorWrapper) = c.cursor.seekPrevRune()
proc seek(c: var RopeCursorWrapper, index: int) =
  var distance = c.cursor.position.int - index
  if distance > 0:
    c.cursor.resetCursor()
  c.cursor.seekForward(index.Count)
proc slice(c: RopeCursorWrapper, first, last: int): RopeSlice[Count] = c.cursor.ropeSlice.slice(first.Count...last.Count)

proc clone*[T](diff: RopeDiff[T]): RopeDiff[T] =
  result.edits.setLen(diff.edits.len)
  for i in 0..diff.edits.high:
    result.edits[i] = (diff.edits[i].old, diff.edits[i].text.clone())

proc initDiffData[T, C](data: sink C): DiffData[T, C] =
  # result.data = cast[ptr UncheckedArray[int]](data[0].addr)
  result.data = data.ensureMove
  result.modified = newSeq[bool](result.data.len + 2)
  result.len = result.data.len

proc sms[T, C1, C2](dataA: var DiffData[T, C1], lowerA, upperA: int, dataB: var DiffData[T, C2], lowerB, upperB: int, downVector, upVector: var openArray[int], cancel: ptr Atomic[bool], enableCancel: static[bool] = false): (int, int) =
  # echo "sms ", lowerA, ", ", upperA, ", ", lowerB, ", ", upperB, ", ", downVector, ", ", upVector
  let max = dataA.len + dataB.len + 1
  let downK = lowerA - lowerB
  let upK = upperA - upperB
  let delta = (upperA - lowerA) - (upperB - lowerB)
  let oddDelta = (delta and 1) != 0
  let downOffset = max - downK
  let upOffset = max - upK
  let maxD = ((upperA - lowerA + upperB - lowerB) div 2) + 1

  downVector[downOffset + downK + 1] = lowerA
  upVector[upOffset + upK - 1] = upperA

  for d in 0..maxD:
    when enableCancel:
      if cancel != nil and cancel[].load:
        return

    # Extend the forward path
    var k = downK - d
    while k <= downK + d:
      defer: k += 2
      var x = 0
      if k == downK - d:
        x = downVector[downOffset + k + 1]
      else:
        x = downVector[downOffset + k - 1] + 1
        if (k < downK + d) and downVector[downOffset + k + 1] >= x:
          x = downVector[downOffset + k + 1]

      var y = x - k
      if x < upperA and y < upperB:
        dataA.data.seek(x)
        dataB.data.seek(y)
        while x < upperA and y < upperB and dataA.data.current() == dataB.data.current():
          inc x
          inc y
          dataA.data.next()
          dataB.data.next()

      downVector[downOffset + k] = x
      if oddDelta and upK - d < k and k < upK + d:
        if upVector[upOffset + k] <= downVector[downOffset + k]:
          result[0] = downVector[downOffset + k]
          result[1] = downVector[downOffset + k] - k
          return

      when enableCancel:
        if cancel != nil and cancel[].load:
          return

    when enableCancel:
      if cancel != nil and cancel[].load:
        return

    # Extend the reverse path
    k = upK - d
    while k <= upK + d:
      defer: k += 2
      var x = 0
      if k == upK + d:
        x = upVector[upOffset + k - 1]
      else:
        x = upVector[upOffset + k + 1] - 1
        if (k > upK - d) and upVector[upOffset + k - 1] < x:
          x = upVector[upOffset + k - 1]

      var y = x - k
      if x > lowerA and y > lowerB:
        dataA.data.seek(x - 1)
        dataB.data.seek(y - 1)
        while x > lowerA and y > lowerB and dataA.data.current() == dataB.data.current():
          # echo x, ", ", y, ", ", lowerA, ", ", lowerB
          dec x
          dec y
          if x == lowerA or y == lowerB:
            break
          dataA.data.prev()
          dataB.data.prev()

      upVector[upOffset + k] = x
      if not oddDelta and downK - d <= k and k <= downK + d:
        if upVector[upOffset + k] <= downVector[downOffset + k]:
          result[0] = downVector[downOffset + k]
          result[1] = downVector[downOffset + k] - k
          return

      when enableCancel:
        if cancel != nil and cancel[].load:
          return

  assert false

proc lcs[T, C1, C2](dataA: var DiffData[T, C1], lowerA, upperA: int, dataB: var DiffData[T, C2], lowerB, upperB: int, downVector, upVector: var openArray[int], cancel: ptr Atomic[bool], enableCancel: static[bool] = false) =
  # echo "lcs ", lowerA, ", ", upperA, ", ", lowerB, ", ", upperB, ", ", downVector, ", ", upVector
  var lowerA = lowerA
  var upperA = upperA
  var lowerB = lowerB
  var upperB = upperB

  # Skip common prefix
  if lowerA < upperA and lowerB < upperB:
    dataA.data.seek(lowerA)
    dataB.data.seek(lowerB)
    while lowerA < upperA and lowerB < upperB and dataA.data.current() == dataB.data.current():
      inc lowerA
      inc lowerB
      dataA.data.next()
      dataB.data.next()

      when enableCancel:
        if cancel != nil and cancel[].load:
          return

  # Skip common suffix
  if lowerA < upperA and lowerB < upperB:
    dataA.data.seek(upperA - 1)
    dataB.data.seek(upperB - 1)
    while lowerA < upperA and lowerB < upperB and dataA.data.current() == dataB.data.current():
      dec upperA
      dec upperB
      if lowerA == upperA or lowerB == upperB:
        break
      dataA.data.prev()
      dataB.data.prev()

      when enableCancel:
        if cancel != nil and cancel[].load:
          return

  if lowerA == upperA:
    while lowerB < upperB:
      dataB.modified[lowerB] = true
      inc lowerB
  elif lowerB == upperB:
    while lowerA < upperA:
      dataA.modified[lowerA] = true
      inc lowerA
  else:
    let (x, y) = sms(dataA, lowerA, upperA, dataB, lowerB, upperB, downVector, upVector, cancel, enableCancel)
    when enableCancel:
      if cancel != nil and cancel[].load:
        return

    lcs(dataA, lowerA, x, dataB, lowerB, y, downVector, upVector, cancel, enableCancel)
    when enableCancel:
      if cancel != nil and cancel[].load:
        return

    lcs(dataA, x, upperA, dataB, y, upperB, downVector, upVector, cancel, enableCancel)

proc diff*[T](a, b: openArray[T]): Diff[T] =
  var dataA = initDiffData[T, SeqCursor[T]](SeqCursor[T](data: @a))
  var dataB = initDiffData[T, SeqCursor[T]](SeqCursor[T](data: @b))
  let max = a.len + b.len + 1
  var downVector = newSeq[int](max * 2 + 2)
  var upVector = newSeq[int](max * 2 + 2)

  var cancel: Atomic[bool]
  lcs(dataA, 0, a.len, dataB, 0, b.len, downVector, upVector, nil, false)

  var indexA = 0
  var indexB = 0
  var startA = 0
  var startB = 0

  while indexA < dataA.len or indexB < dataB.len:
    if indexA < dataA.len and indexB < dataB.len and not dataA.modified[indexA] and not dataB.modified[indexB]:
      inc indexA
      inc indexB

    startA = indexA
    startB = indexB

    while indexA < dataA.len and (indexB >= dataB.len or dataA.modified[indexA]):
      inc indexA

    while indexB < dataB.len and (indexA >= dataA.len or dataB.modified[indexB]):
      inc indexB

    if startA < indexA or startB < indexB:
      result.ops.add Operation[T](
        old: startA...indexA,
        new: startB...indexB,
        items: dataB.data.slice(startB, indexB),
      )

proc diff*[T](a, b: sink RopeSlice[T], cancel: ptr Atomic[bool] = nil, enableCancel: static[bool] = false): RopeDiff[T] =
  if a.len == 0:
    return RopeDiff[T](edits: @[(T.default...T.default, T.default...T.fromSummary(b.summary, ()), b)])
  if b.len == 0:
    return RopeDiff[T](edits: @[(T.default...T.fromSummary(a.summary, ()), T.default...T.default, Rope.new().slice(T))])

  let a = a.slice(0.Count...a.summary.len)
  let b = b.slice(0.Count...b.summary.len)
  var dataA = initDiffData[T, RopeCursorWrapper](RopeCursorWrapper(cursor: a.cursor(Count)))
  var dataB = initDiffData[T, RopeCursorWrapper](RopeCursorWrapper(cursor: b.cursor(Count)))
  let max = dataA.len + dataB.len + 1
  var downVector = newSeq[int](max * 2 + 2)
  var upVector = newSeq[int](max * 2 + 2)
  lcs(dataA, 0, dataA.len, dataB, 0, dataB.len, downVector, upVector, cancel, enableCancel)
  # echo &"A: {dataA.data.resets} resets + {dataA.data.backSeeks} back seeks + {dataA.data.noops} forward seeks = {dataA.data.seeks} seeks"
  # echo &"B: {dataB.data.resets} resets + {dataB.data.backSeeks} back seeks + {dataB.data.noops} forward seeks = {dataB.data.seeks} seeks"

  when enableCancel:
    if cancel != nil and cancel[].load:
      return

  var indexA = 0
  var indexB = 0
  var startA = 0
  var startB = 0

  while indexA < dataA.len or indexB < dataB.len:
    if indexA < dataA.len and indexB < dataB.len and not dataA.modified[indexA] and not dataB.modified[indexB]:
      inc indexA
      inc indexB

    startA = indexA
    startB = indexB

    while indexA < dataA.len and (indexB >= dataB.len or dataA.modified[indexA]):
      inc indexA

    while indexB < dataB.len and (indexA >= dataA.len or dataB.modified[indexB]):
      inc indexB

    if startA < indexA or startB < indexB:
      let start = a.convert(startA.Count, T)
      let index = a.convert(indexA.Count, T)
      let startBPoint = b.convert(startB.Count, T)
      let indexBPoint = b.convert(indexB.Count, T)
      result.edits.add (start...index, startBPoint...indexBPoint, dataB.data.slice(startB, indexB).slice(T))

proc oldToNew*[T](diff: RopeDiff[T], pos: T): T =
  var oldStart = T.default
  var newStart = T.default
  for e in diff.edits:
    if pos < e.old.a:
      let rel: T = pos - oldStart
      return newStart + rel

    oldStart = e.old.a
    newStart = e.new.a
    if pos < e.old.b:
      let rel: T = pos - oldStart
      return min(newStart + rel, e.new.b)

    oldStart = e.old.b
    newStart = e.new.b

  let rel: T = pos - oldStart
  return newStart + rel

proc newToOld*[T](diff: RopeDiff[T], pos: T): T =
  var oldStart = T.default
  var newStart = T.default
  for e in diff.edits:
    if pos < e.new.a:
      let rel: T = pos - newStart
      return oldStart + rel

    oldStart = e.old.a
    newStart = e.new.a
    if pos < e.new.b:
      let rel: T = pos - newStart
      return min(oldStart + rel, e.old.b)

    oldStart = e.old.b
    newStart = e.new.b

  let rel: T = pos - newStart
  return oldStart + rel

proc oldToNew*[T](diff: RopeDiff[T], range: Range[T]): Range[T] =
  return diff.oldToNew(range.a)...diff.oldToNew(range.b)

proc newToOld*[T](diff: RopeDiff[T], range: Range[T]): Range[T] =
  return diff.newToOld(range.a)...diff.newToOld(range.b)

# proc diff*(a: sink RopeSlice[int], b: string, cancel: ptr Atomic[bool], enableCancel: static[bool] = false): RopeDiff[int] =
#   if a.len == 0:
#     return RopeDiff[int](edits: @[(0...0, Rope.new(b).slice())])
#   if b.len == 0:
#     return RopeDiff[int](edits: @[(0...b.len, Rope.new().slice())])

#   let a = a.slice(0.Count...a.summary.len)
#   var dataA = initDiffData[int, RopeCursorWrapper](RopeCursorWrapper(cursor: a.cursor(Count)))
#   var dataB = initDiffData[int, RuneCursor](RuneCursor(data: @b))
#   let max = dataA.len + dataB.len + 1
#   var downVector = newSeq[int](max * 2 + 2)
#   var upVector = newSeq[int](max * 2 + 2)
#   lcs(dataA, 0, dataA.len, dataB, 0, dataB.len, downVector, upVector, cancel, enableCancel)
#   echo &"A: {dataA.data.resets} resets + {dataA.data.backSeeks} back seeks + {dataA.data.noops} forward seeks = {dataA.data.seeks} seeks"
#   echo &"B: {dataB.data.resets} resets + {dataB.data.backSeeks} back seeks + {dataB.data.noops} forward seeks = {dataB.data.seeks} seeks"

#   when enableCancel:
#     if cancel != nil and cancel[].load:
#       return

#   var indexA = 0
#   var indexB = 0
#   var startA = 0
#   var startB = 0

#   while indexA < dataA.len or indexB < dataB.len:
#     if indexA < dataA.len and indexB < dataB.len and not dataA.modified[indexA] and not dataB.modified[indexB]:
#       inc indexA
#       inc indexB

#     startA = indexA
#     startB = indexB

#     while indexA < dataA.len and (indexB >= dataB.len or dataA.modified[indexA]):
#       inc indexA

#     while indexB < dataB.len and (indexA >= dataA.len or dataB.modified[indexB]):
#       inc indexB

#     if startA < indexA or startB < indexB:
#       let start = a.convert(startA.Count, int)
#       let index = a.convert(indexA.Count, int)
#       result.edits.add (start...index, dataB.data.slice(startB, indexB).slice(int))

proc apply*[T](a: openArray[T], diff: Diff[T]): seq[T] =
  var last = 0
  for op in diff.ops:
    if op.old.a > last:
      result.add a[last..<op.old.a]
    result.add op.items
    last = op.old.b

  if last < a.len:
    result.add a[last..^1]

proc apply*[T](a: RopeSlice[T], diff: RopeDiff[T]): Rope =
  result = Rope.new()
  var c = a.cursor(T)
  for op in diff.edits:
    if op.old.a > c.position:
      result.add c.slice(op.old.a).toRope()
    assert not op.text.rope.tree.isNil
    result.add op.text.toRope()
    c.seekForward(op.old.b)

  result.add c.suffix().toRope()

when isMainModule:
  proc test[T](a, b: openArray[T]) =
    var diff = diff(a, b)
    var b2 = a.apply(diff)
    if b != @b2:
      echo a, ", ", b, " -> ", b2, ", ", diff

    assert b == @b2

  proc test(a, b: Rope) =
    var diff = diff(a, b, nil)
    assert not a.tree.isNil
    assert not b.tree.isNil
    var b2 = a.apply(diff)
    if $b != $b2:
      echo a, ", ", b, " -> ", b2, ", ", diff

    assert $b == $b2

  proc randArray(len: int, max: int): seq[int] =
    for i in 0..<len:
      result.add rand(max)

  const chars = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z']

  proc randCharArray(len: int): seq[char] =
    for i in 0..<len:
      result.add chars[rand(chars.high)]

  proc randRope(len: int): Rope =
    var str = ""
    for i in 0..<len:
      str.add chars[rand(chars.high)]
    return Rope.new(str)

  for i in 0..80:
    echo "i: ", i
    for k in 0..1000:
      let a = randArray(i, min(i, 64))
      let b = randArray(i, min(i, 64))
      test(a, b)

  for i in 1..80:
    echo "i: ", i
    for k in 0..1000:
      let a = randCharArray(i)
      let b = randCharArray(i)
      test(a, b)

  for i in 2..80:
    echo "i: ", i
    for k in 1..1000:
      let a = randRope(i)
      let b = randRope(i)
      test(a, b)

  echo diff(Rope.new("hello"), Rope.new("hellope"), nil, false)
  echo diff(Rope.new("hellope"), Rope.new("hello"), nil, false)
  echo diff(Rope.new("hello world"), Rope.new("hellope"), nil, false)
  echo diff(Rope.new("this is a sentence"), Rope.new("this will be a test"), nil, false)

