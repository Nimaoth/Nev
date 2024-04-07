import std/[options]

type
  LineMapping* = object
    source*: tuple[first: int, last: int]
    target*: tuple[first: int, last: int]
    lines*: seq[string]

proc contains(r: (int, int), line: int): bool = line >= r[0] and line < r[1]

proc mapLineTargetToSource*(mappings: openArray[LineMapping], line: int): Option[tuple[line: int, changed: bool]] =
  # todo: binary search
  if mappings.len == 0:
    return (line, false).some

  if line < mappings[0].target.first:
    return (line, false).some

  var lastSource = 0
  var lastTarget = 0
  for i in 0..mappings.high:
    if mappings[i].target.contains(line):
      let sourceLine = mappings[i].source.first + (line - mappings[i].target.first)
      if mappings[i].source.contains(sourceLine):
        return (sourceLine, true).some
      return (int, bool).none

    if line < mappings[i].target.first:
      let sourceLine = mappings[i].source.first + (line - mappings[i].target.first)
      return (sourceLine, false).some

    lastSource = mappings[i].source.last
    lastTarget = mappings[i].target.last

  return some (lastSource + (line - lastTarget), false)

static:
  let mappings = [
    LineMapping(source: (10, 10), target: (10, 20)),
    LineMapping(source: (20, 30), target: (30, 40)),
    LineMapping(source: (40, 50), target: (50, 50)),
  ]

  assert mappings.mapLineTargetToSource(9) == (9, false).some
  assert mappings.mapLineTargetToSource(10) == (int, bool).none
  assert mappings.mapLineTargetToSource(11) == (int, bool).none
  assert mappings.mapLineTargetToSource(19) == (int, bool).none
  assert mappings.mapLineTargetToSource(20) == (10, false).some
  assert mappings.mapLineTargetToSource(21) == (11, false).some
  assert mappings.mapLineTargetToSource(29) == (19, false).some
  assert mappings.mapLineTargetToSource(30) == (20, true).some
  assert mappings.mapLineTargetToSource(31) == (21, true).some
  assert mappings.mapLineTargetToSource(39) == (29, true).some
  assert mappings.mapLineTargetToSource(40) == (30, false).some
  assert mappings.mapLineTargetToSource(41) == (31, false).some
  assert mappings.mapLineTargetToSource(49) == (39, false).some
  assert mappings.mapLineTargetToSource(50) == (50, false).some
  assert mappings.mapLineTargetToSource(51) == (51, false).some