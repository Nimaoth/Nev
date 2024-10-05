{.push gcsafe.}
{.push raises: [].}

when defined(nimscript):
  type
    Ticks* = distinct int64
    Nanos* = int64

type Seconds* = distinct float64

proc `+`*(a, b: Seconds): Seconds {.borrow.}
proc `+=`*(a: var Seconds, b: Seconds) {.borrow.}
proc `-`*(a, b: Seconds): Seconds {.borrow.}

func ms*(seconds: Seconds): float64 = seconds.float64 * 1_000

when defined(nimscript):
  proc myGetTime*(): int32 = discard
  proc myGetTicks(): int64 = discard
  proc mySubtractTicks(a: int64, b: int64): int64 = discard
  proc `-`*(a, b: Ticks): Nanos = mySubtractTicks(a.int64, b.int64).Nanos

  type NanosecondRange* = range[0..999_999_999]
  type Time* = object ## Represents a point in time.
    seconds: int64
    nanosecond: NanosecondRange

  proc fromUnix*(unix: int64): Time =
    result.seconds = unix
    result.nanosecond = 0

else:
  include system/timers
  import std/times
  export Ticks, Nanos
  proc myGetTime*(): int32 = getTime().toUnix.int32
  proc myGetTicks*(): int64 = getTicks().int64
  proc mySubtractTicks*(a: int64, b: int64): int64 = a.Ticks - b.Ticks

type Timer* = object
  start: Ticks

proc elapsed*(timer: Timer): Seconds = ((myGetTicks().Ticks - timer.start).float64 / 1_000_000_000).Seconds
proc startTimer*(): Timer = Timer(start: myGetTicks().Ticks)