when not defined(nimscript):
  include system/timers
else:
  type
    Ticks* = distinct int64
    Nanos* = int64

type Seconds* = distinct float64

proc `+`*(a, b: Seconds): Seconds {.borrow.}
proc `+=`*(a: var Seconds, b: Seconds) {.borrow.}
proc `-`*(a, b: Seconds): Seconds {.borrow.}

func ms*(seconds: Seconds): float64 = seconds.float64 * 1_000

when defined(js):
  type Timer* = Seconds

  type NanosecondRange* = range[0..999_999_999]

  proc myGetTime*(): int32 {.importjs: "Date.now()" .}
  proc myGetTicks(): Seconds {.importjs: "(Date.now() / 1000)".}

  proc elapsed*(timer: Timer): Seconds = myGetTicks() - timer
  proc startTimer*(): Timer = myGetTicks()

else:
  when defined(nimscript):
    proc myGetTime*(): int32 = discard
    proc myGetTicks(): Ticks = discard
    proc mySubtractTicks(a, b: Ticks): Nanos = discard
    proc `-`*(a, b: Ticks): Nanos = mySubtractTicks(a, b)

    type NanosecondRange* = range[0..999_999_999]
    type Time* = object ## Represents a point in time.
      seconds: int64
      nanosecond: NanosecondRange

    proc fromUnix*(unix: int64): Time =
      result.seconds = unix
      result.nanosecond = 0

  else:
    import std/times
    proc myGetTime*(): int32 = getTime().toUnix.int32
    proc myGetTicks(): Ticks = getTicks()

  type Timer* = object
    start: Ticks

  proc elapsed*(timer: Timer): Seconds = ((myGetTicks() - timer.start).float64 / 1_000_000_000).Seconds
  proc startTimer*(): Timer = Timer(start: myGetTicks())