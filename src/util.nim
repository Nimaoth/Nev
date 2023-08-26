import std/[options, strutils]
export options

{.used.}

template getSome*[T](opt: Option[T], injected: untyped): bool =
  ((let o = opt; o.isSome())) and ((let injected {.inject.} = o.get(); true))

template isNotNil*(v: untyped): untyped = not v.isNil
template toOpenArray*(s: string): auto = s.toOpenArray(0, s.high)

proc `??`*[T: ref object](self: T, els: T): T =
  return if not self.isNil: self else: els

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
    return some a.get + b.get
  if a.isSome:
    return a
  when U is T:
    return b
  else:
    return T.none