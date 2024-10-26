import std/[options, strutils, macros, genasts, tables]
import results
export options, results

{.used.}

{.push gcsafe.}
{.push raises: [].}
{.push warning[ProveInit]:off.}

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
  if self.isSome:
    let it {.inject.} = self.get
    some(op)
  else:
    OutType.none

template applyIt*[T, E](self: Result[T, E], op: untyped, opErr: untyped): untyped =
  let s = self
  if s.isOk:
    template it: untyped {.inject.} = s.unsafeValue
    op
  else:
    template it: untyped {.inject.} = s.unsafeError
    opErr

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
