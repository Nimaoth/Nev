include system/timers

import std/times

type Seconds* = distinct float64

proc `+`*(a, b: Seconds): Seconds {.borrow.}
proc `+=`*(a: var Seconds, b: Seconds) {.borrow.}
proc `-`*(a, b: Seconds): Seconds {.borrow.}

func ms*(seconds: Seconds): float64 = seconds.float64 * 1_000

when defined(js):
  type Timer* = Seconds

  proc myGetTime*(): int32 {.importjs: "Date.now()" .}
  proc myGetTicks(): Seconds {.importjs: "(Date.now() / 1000)".}
    # let time = getTime()
    # return time.toUnixFloat.Seconds

  proc elapsed*(timer: Timer): Seconds = myGetTicks() - timer

  proc startTimer*(): Timer = myGetTicks()

else:
  type Timer* = object
    start: Ticks

  proc myGetTime*(): int32 = getTime().toUnix.int32
  proc myGetTicks(): Ticks = getTicks()
  proc elapsed*(timer: Timer): Seconds = ((myGetTicks() - timer.start).float64 / 1_000_000_000).Seconds

  proc startTimer*(): Timer = Timer(start: myGetTicks())