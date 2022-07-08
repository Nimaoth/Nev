import std/sugar

import std/[sets, tables]

let data = @["bird", "word"]

## seq:
let k = collect(newSeq):
  for i, d in data.pairs:
    if i mod 2 == 0: d
assert k == @["bird"]

## seq with initialSize:
let x = collect(newSeqOfCap(4)):
  for i, d in data.pairs:
    if i mod 2 == 0: d
assert x == @["bird"]

## HashSet:
let y = collect(initHashSet()):
  for d in data.items: {d}
assert y == data.toHashSet

## Table:
let z = collect(initTable(2)):
  for i, d in data.pairs: {i: d}
assert z == {0: "bird", 1: "word"}.toTable

