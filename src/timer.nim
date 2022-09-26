include system/timers


export Nanos

type Timer* = object
  start: Ticks

func ms*(nanos: Nanos): float64 = nanos.float64 / 1000000
proc startTimer*(): Timer = Timer(start: getTicks())
proc elapsed*(timer: Timer): Nanos = getTicks() - timer.start