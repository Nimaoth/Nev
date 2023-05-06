import std/[options]
export options

template getSome*[T](opt: Option[T], injected: untyped): bool =
  ((let o = opt; o.isSome())) and ((let injected {.inject.} = o.get(); true))

template isNotNil*(v: untyped): untyped = not v.isNil