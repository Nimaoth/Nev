import std/[algorithm]

export algorithm

proc combSort*[T](a: var openArray[T],
              cmp: proc (x, y: T): int {.closure.},
              order = SortOrder.Ascending, steps: int = -1, gap: int = 15, shrink: float = 1.3): bool {.effectsOf: cmp.} =

  runnableExamples:
    import std/[algorithm, random]

    var a: array[0, int] = []
    var b = [5]
    var c = [5, 3]
    var d = [5, 3, 4]
    var e = [5, 3, 4, 8]
    var f = [5, 3, 4, 8, 2]
    var g = [5, 3, 4, 8, 2]
    var k = [5, 3, 4, 8, 2]
    var l = [5, 3, 4, 8, 2]

    var h: seq[int] = @[]
    for i in 0..20: h.add i
    h.shuffle()
    assert not h.isSorted

    assert a.combSort(system.cmp[int])
    assert b.combSort(system.cmp[int])
    assert c.combSort(system.cmp[int])
    assert d.combSort(system.cmp[int])
    assert e.combSort(system.cmp[int])
    assert f.combSort(system.cmp[int])
    assert g.combSort(system.cmp[int], SortOrder.Descending)
    assert h.combSort(system.cmp[int])
    assert not k.combSort(system.cmp[int], steps = 1, gap = 3)
    assert not l.combSort(system.cmp[int], steps = 1, gap = 2)

    assert a == []
    assert b == [5]
    assert c == [3, 5]
    assert d == [3, 4, 5]
    assert e == [3, 4, 5, 8]
    assert f == [2, 3, 4, 5, 8]
    assert g == [8, 5, 4, 3, 2]
    assert k == [5, 2, 4, 8, 3]
    assert l == [4, 3, 2, 8, 5]
    assert h.isSorted

  assert gap > 0
  assert shrink > 1

  if a.len < 2:
    return true

  var gap = min(a.high, gap)
  var i = 0
  while steps == -1 or i < steps:
    var k = 0
    var noSwaps = true
    while k + gap < a.len:
      if cmp(a[k], a[k + gap]) * order > 0:
        swap(a[k], a[k + gap])
        noSwaps = false
      k += 1
    if gap == 1 and noSwaps:
      return true
    if gap > 1:
      gap = int(gap.float / shrink)
    i += 1
  result = a.isSorted(cmp)

proc combSort*[T](a: var openArray[T],
              order = SortOrder.Ascending, steps: int = -1, gap: int = 15, shrink: float = 1.3): bool =
  return a.compSort(system.cmp[T], order, steps, gap, shrink)
