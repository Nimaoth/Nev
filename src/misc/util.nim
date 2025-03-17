import std/[options, strutils, macros, genasts, tables]
import results
export options, results

{.used.}

{.push gcsafe.}
{.push raises: [].}
{.push warning[ProveInit]:off.}

# from std/sequtils
macro evalOnceAs(expAlias, exp: untyped,
                 letAssigneable: static[bool]): untyped =
  ## Injects `expAlias` in caller scope, to avoid bugs involving multiple
  ## substitution in macro arguments such as
  ## https://github.com/nim-lang/Nim/issues/7187.
  ## `evalOnceAs(myAlias, myExp)` will behave as `let myAlias = myExp`
  ## except when `letAssigneable` is false (e.g. to handle openArray) where
  ## it just forwards `exp` unchanged.
  expectKind(expAlias, nnkIdent)
  var val = exp

  result = newStmtList()
  # If `exp` is not a symbol we evaluate it once here and then use the temporary
  # symbol as alias
  if exp.kind != nnkSym and letAssigneable:
    val = genSym()
    result.add(newLetStmt(val, exp))

  result.add(
    newProc(name = genSym(nskTemplate, $expAlias), params = [getType(untyped)],
      body = val, procType = nnkTemplateDef))

template getSome*[T](opt: Option[T], injected: untyped): bool =
  ((let o = opt; o.isSome())) and ((let injected {.inject, cursor.} = o.get(); true))

template getSome*[T](opt: Opt[T], injected: untyped): bool =
  ((let o = opt; o.isOk())) and ((let injected {.inject, cursor.} = o.get(); true))

template isNotNil*(v: untyped): untyped = not v.isNil

template isNotNil*(v: untyped, injected: untyped): bool =
  (let injected {.inject.} = v; not injected.isNil)

template toOpenArray*(s: string): auto = s.toOpenArray(0, s.high)

template getOr*[T](opt: Option[T], body: untyped): T =
  let temp = opt
  if temp.isSome:
    temp.get
  else:
    body

template get*[T](opt: Option[T], otherwise: Option[T]): Option[T] =
  if opt.isSome:
    opt
  else:
    otherwise

template take*[T](opt: sink Option[T], otherwise: sink T): T =
  if opt.isSome:
    opt.get.move
  else:
    otherwise

template take*[T](opt: sink Option[T]): T =
  if opt.isSome:
    opt.get.move
  else:
    raise newException(UnpackDefect, "Can't obtain a value from a `none`")

proc take*[T](opt: var Option[T]): T =
  if opt.isSome:
    result = opt.get.move
    opt = T.none
  else:
    raise newException(UnpackDefect, "Can't obtain a value from a `none`")

func get*[T](opt: openArray[T], index: int): Option[T] =
  if index in 0..opt.high:
    opt[index].some
  else:
    T.none

proc `??`*[T: ref object](self: T, els: T): T =
  return if not self.isNil: self else: els

macro `.?`*(self: untyped, value: untyped): untyped =
  let member = nnkDotExpr.newTree(self, value)
  return genAst(self, member):
    if not self.isNil: member else: default(typeof(member))

proc del*[T](x: var seq[T], val: T) {.noSideEffect.} =
  let idx = x.find val
  if idx >= 0:
    x.del(idx)

template with*(exp, val, body: untyped): untyped =
  block:
    let oldValue = exp
    exp = val
    defer:
      exp = oldValue
    body

template catch*(exp: untyped, then: untyped): untyped =
  try:
    exp
  except Exception:
    then

template catch*(exp: untyped, error: untyped, then: untyped): untyped =
  try:
    exp
  except error:
    then

template hasPrefix*(exp: untyped, prefix: string, v: untyped): untyped =
  let temp = exp
  let matches = temp.startsWith(prefix)
  let v {.inject.} = if matches:
    temp[prefix.len..^1]
  else:
    temp

  matches

func first*[T](x: var seq[T]): var T = x[x.low]
func last*[T](x: var seq[T]): var T = x[x.high]
func first*[T](x: openArray[T]): lent T = x[x.low]
func last*[T](x: openArray[T]): lent T = x[x.high]
func `first=`*[S, T](x: var S, value: T) = x[x.low] = value
func `last=`*[S, T](x: var S, value: T) = x[x.high] = value

proc `or`*[T, U](a: Option[T], b: Option[U]): Option[T] =
  if a.isSome and b.isSome:
    return some a.get or b.get
  if a.isSome:
    return a
  when U is T:
    return b
  else:
    return T.none

proc `+`*[T, U](a: Option[T], b: Option[U]): Option[T] =
  if a.isSome and b.isSome:
    return some a.get + b.get
  if a.isSome:
    return a
  when U is T:
    return b
  else:
    return T.none

proc `-`*[T, U](a: Option[T], b: Option[U]): Option[T] =
  if a.isSome and b.isSome:
    return some a.get - b.get
  if a.isSome:
    return a
  when U is T:
    return b
  else:
    return T.none

proc someOption*[T: not Option](self: T): Option[T] = some(self)
proc someOption*[T: Option](self: T): T = self

template mapIt*[T](self: Option[T], op: untyped): untyped =
  type OutType = typeof((
    block:
      var it {.inject.}: typeof(self.get, typeOfProc);
      op), typeOfProc)
  block:
    evalOnceAs(self2, self, compiles((let _ = self)))
    if self2.isSome:
      let it {.inject.} = self2.get
      some(op)
    else:
      OutType.none

template applyIt*[T, E](self: Result[T, E], op: untyped, opErr: untyped): untyped =
  block:
    evalOnceAs(self2, self, compiles((let _ = self)))
    if self2.isOk:
      template it: untyped {.inject, used.} = self2.unsafeValue
      op
    else:
      template it: untyped {.inject, used.} = self2.unsafeError
      opErr

template applyIt*[T, E](self: Result[T, E], op: untyped): untyped =
  block:
    evalOnceAs(self2, self, compiles((let _ = self)))
    if self2.isOk:
      template it: untyped {.inject.} = self2.unsafeValue
      op

template findIt*(self: untyped, op: untyped): untyped =
  block:
    var index = -1
    for i in 0..self.high:
      let it {.cursor, inject.} = self[i]
      if op:
        index = i
        break
    index

template findItOpt*(self: untyped, op: untyped): untyped =
  block:
    type OutType = typeof(self[0], typeOfProc)
    var res = OutType.none
    for i in 0..self.high:
      let it {.cursor, inject.} = self[i]
      if op:
        res = it.some
        break
    res

template maybeFlatten*[T](self: Option[T]): Option[T] = self
template maybeFlatten*[T](self: Option[Option[T]]): Option[T] = self.flatten

template mapItIndex*(s: typed, op: untyped): untyped =
  ## Returns a new sequence with the results of the `op` proc applied to every
  ## item in the container `s`.
  ##
  ## Since the input is not modified you can use it to
  ## transform the type of the elements in the input container.
  ##
  ## The template injects the `it` variable which you can use directly in an
  ## expression.
  ##
  ## Instead of using `mapItIndex` and `filterIt`, consider using the `collect` macro
  ## from the `sugar` module.
  ##
  ## **See also:**
  ## * `sugar.collect macro<sugar.html#collect.m%2Cuntyped%2Cuntyped>`_
  ## * `map proc<#map,openArray[T],proc(T)>`_
  ## * `applyIt template<#applyIt.t,untyped,untyped>`_ for the in-place version
  ##
  runnableExamples:
    let
      nums = @[1, 2, 3, 4]
      strings = nums.mapItIndex($(4 * it))
    assert strings == @["4", "8", "12", "16"]

  type OutType = typeof((
    block:
      var it {.inject.}: typeof(items(s), typeOfIter);
      var itIndex {.inject.}: int
      op), typeOfProc)
  # Here, we avoid to create closures in loops.
  # This avoids https://github.com/nim-lang/Nim/issues/12625
  when compiles(s.len):
    block: # using a block avoids https://github.com/nim-lang/Nim/issues/8580

      # BUG: `evalOnceAs(s2, s, false)` would lead to C compile errors
      # (`error: use of undeclared identifier`) instead of Nim compile errors
      evalOnceAs(s2, s, compiles((let _ = s)))

      var i = 0
      var result = newSeq[OutType](s2.len)
      for itIndex {.inject.}, it {.inject.} in s2:
        result[i] = op
        i += 1
      result
  else:
    var result: seq[OutType]# = @[]
    # use `items` to avoid https://github.com/nim-lang/Nim/issues/12639
    for itIndex {.inject.}, it {.inject.} in items(s):
      result.add(op)
    result

proc neww*[T](value: T): ref T =
  new result
  result[] = value

import std/math
func roundPositive*[T: float64 | float32](x: T): T = round(x)

template yieldAll*(iter: untyped): untyped =
  for i in iter:
    yield i

proc align*[T](address, alignment: T): T =
  if alignment == 0: # Actually, this is illegal. This branch exists to actively
                     # hide problems.
    result = address
  else:
    result = (address + (alignment - 1)) and not (alignment - 1)

type CatchableAssertion* = object of CatchableError

template softAssert*(condition: bool, message: string): untyped =
  if not condition:
    echo message
    raise newException(CatchableAssertion, message)

func removeSwap*[T](s: var seq[T]; index: int) = s.del(index)
func removeShift*[T](s: var seq[T]; index: int) = s.delete(index)

func indentExtraLines*(s: string, count: Natural, padding: string = " "): string =
  ## Indents each line except the first in `s` by `count` amount of `padding`.
  ##
  ## **Note:** This does not preserve the new line characters used in `s`.
  ##
  ## See also:
  ## * `align func<#align,string,Natural,char>`_
  ## * `alignLeft func<#alignLeft,string,Natural,char>`_
  ## * `spaces func<#spaces,Natural>`_
  ## * `unindent func<#unindent,string,Natural,string>`_
  ## * `dedent func<#dedent,string,Natural>`_
  runnableExamples:
    doAssert indent("First line\c\l and second line.", 2) ==
             "First line\l   and second line."
  result = ""
  var i = 0
  for line in s.splitLines():
    if i != 0:
      result.add("\n")
      for j in 1..count:
        result.add(padding)
    result.add(line)
    i.inc

func find*[T](arr: openArray[T], val: T, start: int = 0): int =
  result = -1
  for i in start..<arr.len:
    if arr[i] == val:
      return i

func startsWith*[T](s, prefix: openArray[T]): bool =
  let prefixLen = prefix.len
  let sLen = s.len
  var i = 0
  while true:
    if i >= prefixLen: return true
    if i >= sLen or s[i] != prefix[i]: return false
    inc(i)

func endsWith*[T](s, suffix: openArray[T]): bool =
  let suffixLen = suffix.len
  let sLen = s.len
  var i = 0
  var j = sLen - suffixLen
  while i+j >= 0 and i+j < sLen:
    if s[i+j] != suffix[i]: return false
    inc(i)
  if i >= suffixLen: return true

iterator splitOpenArray*(s: string, sep: char, maxsplit: int = -1): tuple[p: ptr UncheckedArray[char], len: int] =
  var last = 0
  var splits = maxsplit

  while last <= len(s):
    var first = last
    while last < len(s) and s[last] != sep:
      inc(last)
    if splits == 0: last = len(s)
    let p = if s.len > 0:
      cast[ptr UncheckedArray[char]](cast[int](s[0].addr) + first)
    else:
      nil
    yield (p, last - first)
    if splits == 0: break
    dec(splits)
    inc(last, 1)
