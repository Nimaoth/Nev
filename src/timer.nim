include system/timers

import std/times


export Nanos

type Timer* = object
  start: Ticks

when defined(js):
  proc myGetTicks(): Ticks =
    let time = getTime()
    return (time.toUnixFloat * 1_000_000_000).int64.Ticks

else:
  proc myGetTicks(): Ticks = getTicks()


func ms*(nanos: Nanos): float64 = nanos.float64 / 1000000
proc startTimer*(): Timer = Timer(start: myGetTicks())
proc elapsed*(timer: Timer): Nanos = myGetTicks() - timer.start