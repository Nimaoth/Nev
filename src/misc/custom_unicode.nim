# abc ä cde .
import std/unicode

export Rune
export runeLenAt, runeAt, strip, validateUtf8, graphemeLen, lastRune, `$`, runes, `==`, isWhiteSpace

type
  RuneIndex* = distinct int
  RuneCount* = distinct int

template toOa(s: string): auto = s.toOpenArray(0, s.high)

func `-`*(a, b: RuneIndex): RuneCount = RuneCount(a.int - b.int)
func `-`*(a: RuneIndex, b: RuneCount): RuneIndex = RuneIndex(a.int - b.int)
func `+`*(a: RuneIndex, b: RuneCount): RuneIndex = RuneIndex(a.int + b.int)
func `+=`*(a: var RuneIndex, b: RuneCount) = a = a + b
func `-=`*(a: var RuneIndex, b: RuneCount) = a = a - b
func `<`*(a, b: RuneIndex): bool {.borrow.}
func `<=`*(a, b: RuneIndex): bool {.borrow.}
func `==`*(a, b: RuneIndex): bool {.borrow.}
func `<`*(a, b: RuneCount): bool {.borrow.}
func `<=`*(a, b: RuneCount): bool {.borrow.}
func `==`*(a, b: RuneCount): bool {.borrow.}
func `<`*(a: RuneIndex, b: RuneCount): bool = a < b.RuneIndex
func `<=`*(a: RuneIndex, b: RuneCount): bool = a <= b.RuneIndex
func `==`*(a: RuneIndex, b: RuneCount): bool = a == b.RuneIndex
func pred*(a: RuneIndex): RuneIndex {.borrow.}
func succ*(a: RuneIndex): RuneIndex {.borrow.}

func `+`*(a, b: RuneCount): RuneCount {.borrow.}
func `-`*(a, b: RuneCount): RuneCount {.borrow.}
func `+=`*(a: var RuneCount, b: RuneCount) = a = a + b

proc `[]`*(s: openArray[char], slice: Slice[RuneIndex]): string = unicode.runeSubStr(s, slice.a.int, slice.b.int - slice.a.int + 1)
proc `[]`*(s: string, slice: Slice[RuneIndex]): string = unicode.runeSubStr(s, slice.a.int, slice.b.int - slice.a.int + 1)
proc `[]`*(s: openArray[char], pos: RuneIndex): Rune = unicode.runeAtPos(s, pos.int)
proc `[]`*(s: string, pos: RuneIndex): Rune = unicode.runeAtPos(s, pos.int)

proc `$`*(a: RuneIndex): string {.borrow.}
proc `$`*(a: RuneCount): string {.borrow.}


proc runeLen*(s: openArray[char]): RuneCount = unicode.runeLen(s).RuneCount
proc runeLen*(s: string): RuneCount = unicode.runeLen(s).RuneCount

proc runeOffset*(s: openArray[char], pos: RuneIndex, start: Natural = 0): int {.inline.} =
  result = unicode.runeOffset(s, pos.int, start)
  if result == -1:
    result = s.len

proc runeOffset*(s: string, pos: RuneIndex, start: Natural = 0): int {.inline.} =
  result = unicode.runeOffset(s, pos.int, start)
  if result == -1:
    result = s.len

proc runeReverseOffset*(s: openArray[char], rev: RuneIndex): (int, int) {.inline.} = unicode.runeReverseOffset(s, rev.int)
proc runeReverseOffset*(s: string, rev: RuneIndex): (int, int) {.inline.} = unicode.runeReverseOffset(s, rev.int)

proc runeAtPos*(s: openArray[char], pos: RuneIndex): Rune {.inline.} = unicode.runeAtPos(s, pos.int)
proc runeAtPos*(s: string, pos: RuneIndex): Rune {.inline.} = unicode.runeAtPos(s, pos.int)

proc runeStrAtPos*(s: openArray[char], pos: RuneIndex): string {.inline.} = unicode.runeStrAtPos(s, pos.int)
proc runeStrAtPos*(s: string, pos: RuneIndex): string {.inline.} = unicode.runeStrAtPos(s, pos.int)

proc runeSubStr*(s: openArray[char], pos: RuneIndex, len: RuneCount = RuneCount.high): string {.inline.} = unicode.runeSubStr(s, pos.int, len.int)
proc runeSubStr*(s: string, pos: RuneIndex, len: RuneCount = RuneCount.high): string {.inline.} = unicode.runeSubStr(s, pos.int, len.int)

proc runeIndex*(s: openArray[char], offset: Natural, returnLen: bool = true): RuneIndex =
  ## Returns the rune position at offset
  ##
  ## **Beware:** This can lead to unoptimized code and slow execution!
  ## Most problems can be solved more efficiently by using an iterator
  ## or conversion to a seq of Rune.
  ##
  ## See also:
  ## * `runeReverseOffset proc <#runeReverseOffset,string,Positive>`_
  runnableExamples:
    let a = "añyóng"
    doAssert a.runeIndex(1) == 1.RuneIndex
    doAssert a.runeIndex(4) == 3.RuneIndex
    doAssert a.runeIndex(6) == 4.RuneIndex
    doAssert a.runeIndex(9) == -1.RuneIndex

  if offset >= s.len:
    if returnLen:
      return s.runeLen.RuneIndex
    return RuneIndex(-1)

  var o = 0
  while true:
    o += runeLenAt(s, o)
    if o > offset:
      return
    inc result

proc runeSize*(s: openArray[char], offset: Natural): Natural =
  if s[offset] <= chr(127):
    result = 1
  else:
    var L = 1
    var R = 1
    while offset - L >= 0 and uint(s[offset - L]) shr 6 == 0b10: inc(L)
    while offset + L <= s.high and uint(s[offset + L]) shr 6 == 0b10: inc(L)
    result = R - L

proc runeStart*(s: openArray[char], offset: Natural): Natural =
  if s[offset] <= chr(127):
    result = offset
  else:
    var L = 0
    while offset - L >= 0 and uint(s[offset - L]) shr 6 == 0b10: inc(L)
    result = offset - L

proc nextRuneStart*(s: openArray[char], offset: Natural): Natural =
  if s[offset] <= chr(127):
    result = offset + 1
  else:
    var L = 1
    while offset + L <= s.high and uint(s[offset + L]) shr 6 == 0b10: inc(L)
    result = offset + L

proc runeStart*(s: string, offset: Natural): Natural =
  runnableExamples:
    assert "aäb".runeStart(0) == 0
    assert "aäb".runeStart(1) == 1
    assert "aäb".runeStart(2) == 1
    assert "aäb".runeStart(3) == 3
  return s.toOA.runeStart(offset)

proc nextRuneStart*(s: string, offset: Natural): Natural =
  runnableExamples:
    assert "aäb".nextRuneStart(0) == 1
    assert "aäb".nextRuneStart(1) == 3
    assert "aäb".nextRuneStart(2) == 3
    assert "aäb".nextRuneStart(3) == 4
  return s.toOA.nextRuneStart(offset)

proc runeSize*(s: string, offset: Natural): Natural =
  return s.toOA.runeSize(offset)