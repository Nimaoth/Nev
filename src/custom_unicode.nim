import std/unicode

export Rune
export runeLenAt, runeAt, strip, validateUtf8, graphemeLen, lastRune, `$`

type
  RuneIndex* = distinct int
  RuneCount* = distinct int

func `-`*(a, b: RuneIndex): RuneCount = RuneCount(a.int - b.int)
func `-`*(a: RuneIndex, b: RuneCount): RuneIndex = RuneIndex(a.int - b.int)
func `+`*(a: RuneIndex, b: RuneCount): RuneIndex = RuneIndex(a.int + b.int)
func `+=`*(a: var RuneIndex, b: RuneCount) = a = a + b
func `<`*(a, b: RuneIndex): bool {.borrow.}
func `<=`*(a, b: RuneIndex): bool {.borrow.}
func `==`*(a, b: RuneIndex): bool {.borrow.}
func `<`*(a: RuneIndex, b: RuneCount): bool = a < b.RuneIndex
func `<=`*(a: RuneIndex, b: RuneCount): bool = a <= b.RuneIndex
func `==`*(a: RuneIndex, b: RuneCount): bool = a == b.RuneIndex
func pred*(a: RuneIndex): RuneIndex {.borrow.}
func succ*(a: RuneIndex): RuneIndex {.borrow.}

func `+`*(a, b: RuneCount): RuneCount {.borrow.}
func `-`*(a, b: RuneCount): RuneCount {.borrow.}

proc `[]`*(s: openArray[char], slice: Slice[RuneIndex]): string = unicode.runeSubStr(s, slice.a.int, slice.b.int - slice.a.int + 1)
proc `[]`*(s: string, slice: Slice[RuneIndex]): string = unicode.runeSubStr(s, slice.a.int, slice.b.int - slice.a.int + 1)
proc `[]`*(s: openArray[char], pos: RuneIndex): Rune = unicode.runeAtPos(s, pos.int)
proc `[]`*(s: string, pos: RuneIndex): Rune = unicode.runeAtPos(s, pos.int)

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

proc runeIndex*(s: openArray[char], offset: Natural): RuneIndex =
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
    doAssert a.runePos(1) == 1
    doAssert a.runePos(4) == 3
    doAssert a.runePos(6) == 4
    doAssert a.runePos(9) == -1

  if offset >= s.len:
    return RuneIndex(-1)

  var o = 0
  while true:
    o += runeLenAt(s, o)
    if o > offset:
      return
    inc result