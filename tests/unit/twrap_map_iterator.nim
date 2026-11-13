discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

import std/[unittest, options, strutils]
import nimsumtree/[rope, buffer]
import misc/[util, arena]
import text/[overlay_map, tab_map, wrap_map, syntax_map]
import chroma

proc newSnapshot(content: string, width = 0, indent = 2): WrapMapSnapshot =
  var buffer = initBuffer(content = content)
  let overlay = OverlayMap.new()
  overlay.setBuffer(buffer.snapshot.clone())
  let tabs = TabMapSnapshot(input: overlay.snapshot.clone())
  result.update(tabs, width, indent)

proc checkUnchanged(actual, expected: TabChunk) =
  var comparable = expected
  if expected.wasTab:
    check bool(actual.toOpenArray == expected.toOpenArray)
    # Each iterator owns its own tab expansion buffer.
    comparable.chunk.data = actual.chunk.data
  check actual == comparable

proc render(iter: var WrapChunkIterator, snapshot: WrapMapSnapshot): string =
  var row = iter.wrapPoint.row
  var column = iter.wrapPoint.column
  var count = 0
  while iter.next().getSome(chunk):
    inc count
    doAssert count < 10000, "Wrap iterator did not terminate"
    check chunk.wrapPoint == snapshot.toWrapPoint(chunk.inputChunk.outputPoint)
    for i in 0..<chunk.len:
      check snapshot.toWrapPoint(chunk.inputChunk.outputPoint + tabPoint(0, i)) ==
        wrapPoint(chunk.wrapPoint.row, chunk.wrapPoint.column + i.uint32)
    while row < chunk.wrapPoint.row:
      result.add '\n'
      inc row
      column = 0
    while column < chunk.wrapPoint.column:
      result.add ' '
      inc column
    for c in chunk.toOpenArray:
      result.add c
      inc column
  check iter.next().isNone

suite "Wrap iterator identity lines":
  test "unwrapped chunks pass through unchanged across leaves, tabs and empty lines":
    let content = "a(b)\t{c}\n\n" & "x".repeat(2000) & "\nlast\n"
    var snapshot = newSnapshot(content)
    var arena = initArena()
    var iter = snapshot.iter(arena.addr)
    var input = snapshot.input.iter(arena.addr)
    let foreground = color(0.2, 0.4, 0.6)
    iter.styledChunks.setThemeColors(foreground, foreground, foreground, foreground, foreground, @[])
    input.styledChunks.setThemeColors(foreground, foreground, foreground, foreground, foreground, @[])
    iter.seekLine(0)
    input.seekLine(0)
    var count = 0
    while input.next().getSome(expected):
      let actual = iter.next()
      require actual.isSome
      checkUnchanged(actual.get.inputChunk, expected)
      check actual.get.wrapPoint == expected.outputPoint.WrapPoint
      inc count
    check count > 10
    check iter.next().isNone

  test "transitions between unwrapped and wrapped lines preserve indentation":
    var snapshot = newSnapshot("a(b)\n0123456789abcdef\n\nshort\nabcdefghijk", 8)
    var arena = initArena()
    var iter = snapshot.iter(arena.addr)
    iter.seekLine(0)
    check iter.render(snapshot) == "a(b)\n01234567\n  89abcd\n  ef\n\nshort\nabcdefgh\n  ijk"

  test "unwrapped chunks retain mapped rows after wrapped lines":
    var snapshot = newSnapshot("0123456789abcdef0123456789abcdef\nplain(a)\t{b}\nlast", 16)
    var arena = initArena()
    var iter = snapshot.iter(arena.addr)
    var input = snapshot.input.iter(arena.addr)
    iter.seekLine(3)
    input.seekLine(1)
    while input.next().getSome(expected):
      let actual = iter.next()
      require actual.isSome
      checkUnchanged(actual.get.inputChunk, expected)
      check actual.get.wrapPoint == wrapPoint(expected.outputPoint.row + 2, expected.outputPoint.column)
    check iter.next().isNone

  test "forward source and wrap seeks reset the cached line":
    var snapshot = newSnapshot("a(b)\nplain\n0123456789abcdef\nlast", 8)
    var arena = initArena()
    for sourceSeek in [false, true]:
      var iter = snapshot.iter(arena.addr)
      iter.seekLine(0)
      require iter.next().isSome
      if sourceSeek:
        iter.seek(point(1, 2))
      else:
        iter.seek(wrapPoint(1, 2))
      check iter.render(snapshot) == "ain\n01234567\n  89abcd\n  ef\nlast"

  test "seeking into a wrapped continuation keeps the split path":
    var snapshot = newSnapshot("a(b)\n0123456789abcdef\nlast", 8)
    var arena = initArena()
    var iter = snapshot.iter(arena.addr)
    iter.seekLine(0)
    require iter.next().isSome
    iter.seek(wrapPoint(2, 4))
    check iter.render(snapshot) == "abcd\n  ef\nlast"

  test "exact wrap widths, empty buffers and trailing newlines terminate":
    for content in ["", "\n", "12345678", "12345678\n", "\n12345678\n\nlast"]:
      var snapshot = newSnapshot(content, 8)
      var arena = initArena()
      var iter = snapshot.iter(arena.addr)
      check iter.render(snapshot) == content

  test "wrapped tabs and wrapping at tabs retain their existing boundaries":
    var snapshot = newSnapshot("a\tbcdefgh\nshort", 6)
    var arena = initArena()
    var iter = snapshot.iter(arena.addr)
    iter.seekLine(0)
    check iter.render(snapshot) == "a|  bc\n  defg\n  h\nshort"

    var atTabs = newSnapshot("ab\tcd\nshort")
    atTabs.wrapAtTabs = true
    atTabs.update(atTabs.input.clone(), 20, 2)
    var tabIter = atTabs.iter(arena.addr)
    tabIter.seekLine(0)
    check tabIter.render(atTabs) == "ab\n| cd\nshort"

  test "unwrapped chunks preserve overlay metadata and row offsets":
    var snapshot = newSnapshot("first\nplain(a)\t{b}\nlast")
    discard snapshot.input.input.addOverlay(point(0, 5)...point(0, 5), "\nextra", 1,
      renderId = 42, location = OverlayRenderLocation.Below)
    snapshot.update(snapshot.input.clone(), 0, 2)
    var arena = initArena()
    var iter = snapshot.iter(arena.addr)
    var input = snapshot.input.iter(arena.addr)
    iter.seekLine(0)
    input.seekLine(0)
    var sawOverlay = false
    while input.next().getSome(expected):
      let actual = iter.next()
      require actual.isSome
      checkUnchanged(actual.get.inputChunk, expected)
      check actual.get.wrapPoint == expected.outputPoint.WrapPoint
      if expected.inputChunk.renderId == 42:
        sawOverlay = true
    check sawOverlay
    check iter.next().isNone
