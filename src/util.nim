import std/[options]
export options

{.used.}

template getSome*[T](opt: Option[T], injected: untyped): bool =
  ((let o = opt; o.isSome())) and ((let injected {.inject.} = o.get(); true))

template isNotNil*(v: untyped): untyped = not v.isNil
template toOpenArray*(s: string): auto = s.toOpenArray(0, s.high)
