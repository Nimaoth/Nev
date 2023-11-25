import std/[options, strutils, macros, genasts]
export options

{.used.}

template getSome*[T](opt: Option[T], injected: untyped): bool =
  ((let o = opt; o.isSome())) and ((let injected {.inject.} = o.get(); true))

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

proc `??`*[T: ref object](self: T, els: T): T =
  return if not self.isNil: self else: els

macro `.?`*(self: untyped, value: untyped): untyped =
  let member = nnkDotExpr.newTree(self, value)
  return genAst(self, member):
    if not self.isNil: member else: default(typeof(member))

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
  except CatchableError:
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

func myNormalizedPath*(path: string): string = path.replace('\\', '/').strip(chars={'/'})

# type ArrayLike*[T] {.explain.} = concept x, var v
#   x.low is int
#   x.high is int
  # x[int] is T
  # v[int] = T

template first*(x: untyped): untyped = x[x.low]
template last*(x: untyped): untyped = x[x.high]
proc `first=`*[S, T](x: var S, value: T) = x[x.low] = value
proc `last=`*[S, T](x: var S, value: T) = x[x.high] = value

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
      var it{.inject.}: typeof(self.get, typeOfProc);
      op), typeOfProc)
  if self.isSome:
    let it {.inject.} = self.get
    some(op)
  else:
    OutType.none

template maybeFlatten*[T](self: Option[T]): Option[T] = self
template maybeFlatten*[T](self: Option[Option[T]]): Option[T] = self.flatten

proc neww*[T](value: T): ref T =
  new result
  result[] = value

when defined(js):
  func jsRound(x: float): float {.importc: "Math.round", nodecl.}
  func roundPositive*[T: float64 | float32](x: T): T =
    jsRound(x)
else:
  import std/math
  func roundPositive*[T: float64 | float32](x: T): T = round(x)

template yieldAll*(iter: untyped): untyped =
  for i in iter:
    yield i

proc resetOption*[T](self: var Option[T]) =
  when defined(js):
    proc resetOptionJs[T](self: var Option[T]) {.importJs: "#.has = false;".}
    resetOptionJs(self)
  else:
    self = none(T)

proc safeIntCast*[T: SomeSignedInt](x: T, Target: typedesc[SomeUnsignedInt]): Target {.inline.} =
  ## Cast signed integer to unsigned integer.
  ## Same as cast[Target](x), but on js backend doesn't use BigInt
  static:
    assert sizeof(T) == sizeof(Target)

  when defined(js):
    const signBitMask = T.high
    let b = (x and 1).Target # last bit
    let y = ((x shr 1) and signBitMask).Target shl 1 # every bit except last
    result = b or y
  else:
    result = cast[Target](x)

static:
  assert cast[uint32](0) == 0.int32.safeIntCast(uint32)
  assert cast[uint32](1) == 1.int32.safeIntCast(uint32)
  assert cast[uint32](-1) == -1.int32.safeIntCast(uint32)
  assert cast[uint16](-1) == -1.int16.safeIntCast(uint16)
  assert cast[uint8](-1) == -1.int8.safeIntCast(uint8)

proc align*[T](address, alignment: T): T =
  if alignment == 0: # Actually, this is illegal. This branch exists to actively
                     # hide problems.
    result = address
  else:
    result = (address + (alignment - 1)) and not (alignment - 1)
