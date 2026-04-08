import std/syncio
import std/assertions
export syncio
export assertions

when defined(nimony):

  type
    Stringable* = concept
      proc `$`(x: Self): string

  proc `@`*[T](buffer: openArray[T]): seq[T] =
    result = newSeq[T](buffer.len)
    for i in 0..buffer.high:
      result[i] = buffer[i]

  # proc alignof*[T](x: T): int {.magic: "AlignOf", noSideEffect.}
  proc alignof*[T](x: typedesc[T]): int = sizeof(x)

  type Option*[T] = object
    val: T
    has: bool

  proc some*[T](val: sink T): Option[T] =
    return Option[T](val: val, has: true)

  proc none*[T: HasDefault](x: typedesc[T]): Option[T] =
    return Option[T](has: false)

  proc `$`*[T: Stringable](opt: Option[T]): string =
    if opt.has:
      return concat("some(", $opt.val, ")")
    return "none"
