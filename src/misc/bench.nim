import std/[strutils, strformat, sequtils]
import timer, util

type
  Bench* = object
    start: Timer
    scopes: seq[tuple[name: string, elapsed: float]]

func initBench*(): Bench = Bench(start: startTimer())

template scope*(self: Bench, name: string, body: untyped): untyped =
  var t = startTimer()
  body
  self.scopes.add (name, t.elapsed.ms)

func `$`*(self: Bench): string = self.scopes.mapIt(&"{it.name}: {it.elapsed} ms").join(", ") & ", total: {self.start.elapsed.ms} ms"
