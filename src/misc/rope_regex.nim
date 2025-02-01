import std/[options, strutils, atomics, strformat, sequtils, tables, algorithm]
import nimsumtree/[rope, sumtree, buffer, clock]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import custom_async, custom_unicode, util, text/custom_treesitter, regex, timer, event
import text/diff

import regex/common
import regex/nodematch
import regex/types
import regex/nfatype
when not defined(noRegexOpt):
  import regex/litopt

type
  AheadSig = proc (
    smA, smB: var Submatches,
    capts: var Capts3,
    captIdx: var int32,
    text: RopeSlice[int],
    nfa: Nfa,
    look: var Lookaround,
    start: int,
    flags: MatchFlags
  ): bool {.noSideEffect, raises: [].}
  BehindSig = proc (
    smA, smB: var Submatches,
    capts: var Capts3,
    captIdx: var int32,
    text: RopeSlice[int],
    nfa: Nfa,
    look: var Lookaround,
    start, limit: int,
    flags: MatchFlags
  ): int {.noSideEffect, raises: [].}
  Lookaround* = object
    ahead*: AheadSig
    behind*: BehindSig
    smL*: SmLookaround

func lookAround*(
  ntn: types.Node,
  capts: var Capts3,
  captIdx: var int32,
  text: RopeSlice[int],
  look: var Lookaround,
  start: int,
  flags: MatchFlags
): bool =
  template smL: untyped = look.smL
  template smLa: untyped = smL.lastA
  template smLb: untyped = smL.lastB
  template subNfa: untyped = ntn.subExp.nfa
  var flags2 = {mfAnchored}
  if ntn.subExp.reverseCapts:
    flags2.incl mfReverseCapts
  if mfBytesInput in flags:
    flags2.incl mfBytesInput
  smL.grow()
  smL.last.setLen subNfa.s.len
  result = case ntn.kind
  of reLookahead:
    look.ahead(
      smLa, smLb, capts, captIdx, text, subNfa, look, start, flags2
    )
  of reNotLookahead:
    not look.ahead(
      smLa, smLb, capts, captIdx, text, subNfa, look, start, flags2
    )
  of reLookbehind:
    look.behind(
      smLa, smLb, capts, captIdx, text, subNfa, look, start, 0, flags2
    ) != -1
  of reNotLookbehind:
    look.behind(
      smLa, smLb, capts, captIdx, text, subNfa, look, start, 0, flags2
    ) == -1
  else:
    doAssert false
    false
  smL.removeLast()

template nextStateTpl(bwMatch = false): untyped {.dirty.} =
  template bounds2: untyped =
    when bwMatch: i .. bounds.b else: bounds.a .. i-1
  template captElm: untyped =
    capts[captx, nfa.s[nt].idx]
  template nt: untyped = nfa.s[n].next[nti]
  template ntn: untyped = nfa.s[nt]
  smB.clear()
  for n, capt, bounds in items smA:
    if capt != -1:
      capts.keepAlive capt
    if anchored and nfa.s[n].kind == reEoe:
      if not smB.hasState n:
        smB.add (n, capt, bounds)
      break
    var nti = 0
    while nti <= nfa.s[n].next.len-1:
      matched = true
      captx = capt
      while isEpsilonTransition(ntn):
        if matched:
          case ntn.kind
          of reGroupStart:
            # XXX this can be avoided in some cases?
            captx = capts.diverge captx
            if mfReverseCapts notin flags or
                captElm.a == nonCapture.a:
              captElm.a = i
          of reGroupEnd:
            captx = capts.diverge captx
            if mfReverseCapts notin flags or
                captElm.b == nonCapture.b:
              captElm.b = i-1
          of assertionKind - lookaroundKind:
            when bwMatch:
              matched = match(ntn, c, cPrev.Rune)
            else:
              matched = match(ntn, cPrev.Rune, c)
          of lookaroundKind:
            let freezed = capts.freeze()
            matched = lookAround(ntn, capts, captx, text, look, i, flags)
            capts.unfreeze freezed
            if captx != -1:
              capts.keepAlive captx
          else:
            doAssert false
            discard
        inc nti
      if matched and
          not smB.hasState(nt) and
          (ntn.match(c) or (anchored and ntn.kind == reEoe)):
        smB.add (nt, captx, bounds2)
      inc nti
  swap smA, smB
  capts.recycle()

func matchImpl(
  smA, smB: var Submatches,
  capts: var Capts3,
  captIdx: var int32,
  text: RopeSlice[int],
  nfa: Nfa,
  look: var Lookaround,
  start = 0,
  flags: MatchFlags = {}
): bool =
  var
    c = Rune(-1)
    cPrev = -1'i32
    i = start
    iNext = start
    captx = -1'i32
    matched = false
  let
    anchored = mfAnchored in flags
    binFlag = mfBytesInput in flags
  var cursor = text.cursor(int)
  if start-1 in 0 .. text.len-1:
    cursor.seekForward(start-1)
    cPrev = if binFlag:
      cursor.currentChar().int32
    else:
      cursor.currentRune().int32
  smA.clear()
  smA.add (0'i16, captIdx, i .. i-1)
  cursor.seekForward(start)
  while cursor.offset < text.len:
    if binFlag:
      c = cursor.currentChar().Rune
      cursor.seekNextChar()
      iNext = cursor.offset
    else:
      c = cursor.currentRune()
      cursor.seekNextChar()
      iNext = cursor.offset
    nextStateTpl()
    if smA.len == 0:
      return false
    if anchored and nfa.s[smA[0].ni].kind == reEoe:
      break
    i = iNext
    cPrev = c.int32
  c = Rune(-1)
  nextStateTpl()
  if smA.len > 0:
    captIdx = smA[0].ci
  return smA.len > 0

func reversedMatchImpl(
  smA, smB: var Submatches,
  capts: var Capts3,
  captIdx: var int32,
  text: RopeSlice[int],
  nfa: Nfa,
  look: var Lookaround,
  start: int,
  limit = 0,
  flags: MatchFlags = {}
): int =
  #doAssert start < len(text)
  doAssert start >= limit
  var
    c = Rune(-1)
    cPrev = -1'i32
    i = start
    iNext = start
    captx: int32
    matched = false
    anchored = true
  var cursor = text.cursor(int)
  let binFlag = mfBytesInput in flags
  if start in 0 .. text.len-1:
    cursor.seekForward(start)
    cPrev = if binFlag:
      cursor.currentChar().int32
    else:
      cursor.currentChar().int32
  smA.clear()
  smA.add (0'i16, captIdx, i .. i-1)
  cursor.resetCursor()
  cursor.seekForward(start - 1)
  while iNext > limit:
    if binFlag:
      if iNext != start:
        cursor.seekPrevChar()
      c = cursor.currentChar().Rune
      iNext = cursor.offset
    else:
      if iNext != start:
        cursor.seekPrevRune()
      c = cursor.currentRune()
      iNext = cursor.offset
    nextStateTpl(bwMatch = true)
    if smA.len == 0:
      return -1
    if nfa.s[smA[0].ni].kind == reEoe:
      break
    i = iNext
    cPrev = c.int32
  c = Rune(-1)
  if iNext > 0:
    if binFlag:
      cursor.seekPrevChar()
      c = cursor.currentChar().Rune
      iNext = cursor.offset
    else:
      cursor.seekPrevRune()
      c = cursor.currentRune()
      iNext = cursor.offset
  nextStateTpl(bwMatch = true)
  for n, capt, bounds in items smA:
    if nfa.s[n].kind == reEoe:
      captIdx = capt
      return bounds.a
  return -1

func reversedMatchImpl*(
  smA, smB: var Submatches,
  text: RopeSlice[int],
  nfa: Nfa,
  look: var Lookaround,
  groupsLen: int,
  start, limit: int,
  flags: MatchFlags = {}
): int =
  var capts = initCapts3(groupsLen)
  var captIdx = -1'i32
  reversedMatchImpl(
    smA, smB, capts, captIdx, text, nfa, look, start, limit, flags
  )

template initLook*: Lookaround =
  Lookaround(
    ahead: matchImpl,
    behind: reversedMatchImpl
  )

func matchImpl*(
  text: RopeSlice[int],
  r: nfatype.Regex,
  m: var RegexMatch2,
  start = 0,
  f: MatchFlags = {}
): bool =
  m.clear()
  let flags = r.flags.toMatchFlags + f
  var
    smA = newSubmatches(r.nfa.s.len)
    smB = newSubmatches(r.nfa.s.len)
    capts = initCapts3(r.groupsCount)
    captIdx = -1'i32
    look = initLook()
  result = matchImpl(
    smA, smB, capts, captIdx, text, r.nfa, look, start, flags
  )
  if result:
    m.captures.setLen r.groupsCount
    if captIdx != -1:
      for i in 0 .. m.captures.len-1:
        m.captures[i] = capts[captIdx, i]
    else:
      for i in 0 .. m.captures.len-1:
        m.captures[i] = nonCapture
    if r.namedGroups.len > 0:
      m.namedGroups = r.namedGroups
    m.boundaries = smA[0].bounds

func startsWithImpl2*(
  text: RopeSlice[int],
  r: nfatype.Regex,
  start: int
): bool =
  # XXX optimize mfShortestMatch, mfNoCaptures
  let flags = r.flags.toMatchFlags + {mfAnchored, mfShortestMatch, mfNoCaptures}
  var
    smA = newSubmatches(r.nfa.s.len)
    smB = newSubmatches(r.nfa.s.len)
    capts = initCapts3(r.groupsCount)
    captIdx = -1'i32
    look = initLook()
  result = matchImpl(
    smA, smB, capts, captIdx, text, r.nfa, look, start, flags
  )

type
  MatchItemIdx = int
  MatchItem = tuple
    capt: CaptIdx
    bounds: Bounds
  Matches = seq[MatchItem]
  RegexMatches2* = object
    a, b: Submatches
    m: Matches
    c: Capts3
    look: Lookaround

template initMaybeImpl(
  ms: var RegexMatches2,
  size, groupsLen: int
) =
  if ms.a == nil:
    assert ms.b == nil
    ms.a = newSubmatches size
    ms.b = newSubmatches size
    ms.c = initCapts3 groupsLen
    ms.look = initLook()
  doAssert ms.a.cap >= size and
    ms.b.cap >= size

template initMaybeImpl(
  ms: var RegexMatches2,
  regex: nfatype.Regex
) =
  initMaybeImpl(ms, regex.nfa.s.len, regex.groupsCount)

func add(ms: var RegexMatches2, m: MatchItem) {.inline.} =
  ## Add `m` to `ms.m`. Remove all overlapped matches.
  template msm: untyped = ms.m
  template capts: untyped = ms.c
  var size = 0
  for i in countdown(msm.len-1, 0):
    if max(msm[i].bounds.b, msm[i].bounds.a) < m.bounds.a:
      size = i+1
      break
  #for i in size .. msm.len-1:
    if msm[i].capt != -1:
      capts.recyclable msm[i].capt
  msm.setLen size
  msm.add m
  if m.capt != -1:
    capts.notRecyclable m.capt

func hasMatches(ms: RegexMatches2): bool {.inline.} =
  return ms.m.len > 0

func clear(ms: var RegexMatches2) {.inline.} =
  ms.a.clear()
  ms.b.clear()
  ms.m.setLen 0
  ms.c.clear()

iterator bounds*(ms: RegexMatches2): Slice[int] {.inline.} =
  for i in 0 .. ms.m.len-1:
    yield ms.m[i].bounds

iterator items*(ms: RegexMatches2): MatchItemIdx {.inline.} =
  for i in 0 .. ms.m.len-1:
    yield i

func fillMatchImpl*(
  m: var RegexMatch2,
  mi: MatchItemIdx,
  ms: RegexMatches2,
  regex: nfatype.Regex
) =
  template capt: untyped = ms.m[mi].capt
  if m.namedGroups.len != regex.namedGroups.len:
    m.namedGroups = regex.namedGroups
  m.captures.setLen regex.groupsCount
  if capt != -1:
    for i in 0 .. m.captures.len-1:
      m.captures[i] = ms.c[capt, i]
  else:
    for i in 0 .. m.captures.len-1:
      m.captures[i] = nonCapture
  m.boundaries = ms.m[mi].bounds

func dummyMatch*(ms: var RegexMatches2, i: int) =
  ## hack to support `split` last value.
  ## we need to add the end boundary if
  ## it has not matched the end
  ## (no match implies this too)
  template ab: untyped = ms.m[^1].bounds
  if ms.m.len == 0 or max(ab.a, ab.b) < i:
    ms.add (-1'i32, i+1 .. i)

func submatch(
  ms: var RegexMatches2,
  text: RopeSlice[int],
  regex: nfatype.Regex,
  i: int,
  cPrev, c: int32,
  flags: MatchFlags
) {.inline.} =
  template nfa: untyped = regex.nfa.s
  template smA: untyped = ms.a
  template smB: untyped = ms.b
  template capts: untyped = ms.c
  template n: untyped = ms.a[smi].ni
  template capt: untyped = ms.a[smi].ci
  template bounds: untyped = ms.a[smi].bounds
  template look: untyped = ms.look
  template nt: untyped = nfa[n].next[nti]
  template ntn: untyped = nfa[nt]
  smB.clear()
  var captx: int32
  var matched = true
  var eoeFound = false
  var smi = 0
  while smi < smA.len:
    if capt != -1:
      capts.keepAlive capt
    var nti = 0
    while nti <= nfa[n].next.len-1:
      matched = true
      captx = capt
      while isEpsilonTransition(ntn):
        if matched:
          case ntn.kind
          of reGroupStart:
            if mfNoCaptures notin flags:
              captx = capts.diverge captx
              capts[captx, ntn.idx].a = i
          of reGroupEnd:
            if mfNoCaptures notin flags:
              captx = capts.diverge captx
              capts[captx, ntn.idx].b = i-1
          of assertionKind - lookaroundKind:
            matched = match(ntn, cPrev.Rune, c.Rune)
          of lookaroundKind:
            let freezed = capts.freeze()
            matched = lookAround(ntn, capts, captx, text, look, i, flags)
            capts.unfreeze freezed
            if captx != -1:
              capts.keepAlive captx
          else:
            doAssert false
            discard
        inc nti
      if matched and
          not smB.hasState(nt) and
          (ntn.match(c.Rune) or ntn.kind == reEoe):
        if ntn.kind == reEoe:
          #debugEcho "eoe ", bounds, " ", ms.m
          ms.add (captx, bounds.a .. i-1)
          smA.clear()
          if not eoeFound:
            eoeFound = true
            smA.add (0'i16, -1'i32, i .. i-1)
          smi = -1
          break
        smB.add (nt, captx, bounds.a .. i-1)
      inc nti
    inc smi
  swap smA, smB
  capts.recycle()

func findSomeImpl*(
  text: RopeSlice[int],
  regex: nfatype.Regex,
  ms: var RegexMatches2,
  start: Natural = 0,
  flags: MatchFlags = {}
): int =
  template smA: untyped = ms.a
  initMaybeImpl(ms, regex)
  ms.clear()
  var
    c = Rune(-1)
    cPrev = -1'i32
    i = start.int
    iPrev = start.int
  let
    flags = regex.flags.toMatchFlags + flags
    optFlag = mfFindMatchOpt in flags
    binFlag = mfBytesInput in flags
  smA.add (0'i16, -1'i32, i .. i-1)
  var cursor = text.cursor(int)
  if start-1 in 0 .. text.len-1:
    cursor.seekForward(start-1)
    cPrev = if binFlag:
      cursor.currentChar().int32
    else:
      cursor.currentRune().int32
  cursor.seekForward(start)
  # while i < text.len:
  while cursor.offset < text.len:
    if binFlag:
      c = cursor.currentChar().Rune
      cursor.seekNextChar()
    else:
      c = cursor.currentRune()
      cursor.seekNextRune()
    submatch(ms, text, regex, iPrev, cPrev, c.int32, flags)
    if smA.len == 0:
      # avoid returning right before final zero-match
      if cursor.offset < text.len:
        if ms.hasMatches():
          #debugEcho "m= ", ms.m
          #debugEcho "sma=0=", i
          return cursor.offset
        if optFlag:
          return cursor.offset
    smA.add (0'i16, -1'i32, cursor.offset .. cursor.offset-1)
    iPrev = cursor.offset
    cPrev = c.int32
  submatch(ms, text, regex, iPrev, cPrev, -1'i32, flags)
  doAssert smA.len == 0
  if ms.hasMatches():
    #debugEcho "m= ", ms.m.s
    return cursor.offset
  #debugEcho "noMatch"
  return -1

# findAll with literal optimization below,
# there is an explanation of how this work
# in litopt.nim

func findSomeOptImpl*(
  text: RopeSlice[int],
  regex: nfatype.Regex,
  ms: var RegexMatches2,
  start: Natural,
  flags: MatchFlags = {}
): int =
  template regexSize: untyped =
    max(regex.litOpt.nfa.s.len, regex.nfa.s.len)
  template opt: untyped = regex.litOpt
  template groupsLen: untyped = regex.groupsCount
  template smA: untyped = ms.a
  template smB: untyped = ms.b
  template look: untyped = ms.look
  doAssert opt.nfa.s.len > 0
  initMaybeImpl(ms, regexSize, groupsLen)
  ms.clear()
  let flags = regex.flags.toMatchFlags + flags + {mfFindMatchOpt}
  let hasLits = opt.lits.len > 0
  let step = max(1, opt.lits.len)
  var limit = start.int
  var i = start.int
  var i2 = -1
  while i < text.len:
    doAssert i > i2; i2 = i
    #debugEcho "lit=", opt.lit
    #debugEcho "i=", i
    let litIdx = if hasLits:
      text.find(opt.lits, i)
    else:
      text.find($opt.lit.char, i) # todo: find char instead of find string
    if litIdx == -1:
      return -1
    #debugEcho "litIdx=", litIdx
    doAssert litIdx >= i
    i = litIdx
    i = reversedMatchImpl(smA, smB, text, opt.nfa, look, groupsLen, i, limit, flags)
    if i == -1:
      #debugEcho "not.Match=", i
      i = litIdx+step
    else:
      doAssert i <= litIdx
      #debugEcho "bounds.a=", i
      i = findSomeImpl(text, regex, ms, i, flags)
      #debugEcho "bounds.b=", i
      if ms.hasMatches:
        return i
      if i == -1:
        return -1
  return -1


when defined(noRegexOpt):
  template findSomeOptTpl(s, pattern, ms, i): untyped =
    findSomeImpl(s, pattern, ms, i)
  template findSomeOptTpl(s, pattern, ms, i, flags): untyped =
    findSomeImpl(s, pattern, ms, i, flags)
else:
  template findSomeOptTpl(s, pattern, ms, i): untyped =
    if pattern.litOpt.canOpt:
      findSomeOptImpl(s, pattern, ms, i)
    else:
      findSomeImpl(s, pattern, ms, i)
  template findSomeOptTpl(s, pattern, ms, i, flags): untyped =
    if pattern.litOpt.canOpt:
      findSomeOptImpl(s, pattern, ms, i, flags)
    else:
      findSomeImpl(s, pattern, ms, i, flags)

iterator findAllBounds*(
  s: RopeSlice[int],
  pattern: Regex2,
  start = 0
): Slice[int] {.inline, raises: [].} =
  ## search through the string and
  ## return each match. Empty matches
  ## (start > end) are included
  runnableExamples:
    let text = "abcabc"
    var bounds = newSeq[Slice[int]]()
    for bd in findAllBounds(text, re2"bc"):
      bounds.add bd
    doAssert bounds == @[1 .. 2, 4 .. 5]

  var i = start
  var i2 = start-1
  var ms: RegexMatches2
  let flags = {mfNoCaptures}
  while i <= s.len:
    doAssert(i > i2); i2 = i
    let oldI = i
    i = findSomeOptTpl(s, pattern.toRegex, ms, i, flags)
    # echo &"findAllBounds {s.range}, {oldI} -> {i}"
    #debugEcho i
    if i < 0: break
    for ab in ms.bounds:
      yield ab
    if i == s.len:
      break

proc findAll*(text: RopeSlice[int], searchQuery: string, res: var seq[Range[Point]]) =
  try:
    let r = re(searchQuery)

    for line in 0..text.summary.lines.row.int:
      let lineRange = text.lineRange(line, int)
      let slice = text.slice(lineRange)
      for b in findAllBounds(slice, r, 0):
        res.add point(line, b.a)...point(line, b.b + 1)

      # let selections = ($text.slice(lineRange)).findAllBounds(line, r)
      # for s in selections:
      #   res.add s.first.toPoint...s.last.toPoint
  except RegexError:
    discard

proc findAll*(text: RopeSlice[int], searchQuery: string): seq[Range[Point]] =
  findAll(text, searchQuery, result)

proc findAllThread(args: tuple[text: ptr RopeSlice[int], query: string, res: ptr seq[Range[Point]]]) =
  findAll(args.text[].clone(), args.query, args.res[])

proc findAllAsync*(text: sink RopeSlice[int], searchQuery: string): Future[seq[Range[Point]]] {.async.} =
  ## Returns `some(index)` if the string contains invalid utf8 at `index`
  var res = newSeq[Range[Point]]()
  var text = text.move
  await spawnAsync(findAllThread, (text.addr, searchQuery, res.addr))
  return res
