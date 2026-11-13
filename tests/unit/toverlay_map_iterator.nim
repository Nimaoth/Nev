discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

import std/[unittest, options, strutils]
import nimsumtree/[rope, buffer]
import misc/[util, arena]
import text/[overlay_map, syntax_map]
import chroma

proc newSnapshot(content: string): OverlayMapSnapshot =
  var buffer = initBuffer(content = content)
  let map = OverlayMap.new()
  map.setBuffer(buffer.snapshot.clone())
  map.snapshot.clone()

proc render(iter: var OverlayChunkIterator): string =
  var row = iter.overlayPoint.row
  var count = 0
  while iter.next().getSome(chunk):
    inc count
    doAssert count < 10000, "Overlay iterator did not terminate"
    while row < chunk.overlayPoint.row:
      result.add '\n'
      inc row
    for c in chunk.toOpenArray:
      result.add c
  check iter.next().isNone

suite "Overlay iterator identity lines":
  test "unaffected chunks pass through unchanged across leaves and empty lines":
    let content = "a(b)\t{c}\n\n" & "x".repeat(2000) & "\nlast\n"
    let snapshot = newSnapshot(content)
    var arena = initArena()
    var iter = snapshot.iter(arena.addr)
    var styled = StyledChunkIterator.init(snapshot.buffer.visibleText, arena.addr)
    let foreground = color(0.2, 0.4, 0.6)
    iter.styledChunks.setThemeColors(foreground, foreground, foreground, foreground, foreground, @[])
    styled.setThemeColors(foreground, foreground, foreground, foreground, foreground, @[])
    iter.seekLine(0)
    styled.seekLine(0)
    var count = 0
    while styled.next().getSome(expected):
      let actual = iter.next()
      require actual.isSome
      check actual.get.styledChunk == expected
      check actual.get.overlayPoint == expected.point.OverlayPoint
      inc count
    check count > 10
    check iter.next().isNone

  test "line transitions check overlays at line starts, middles and ends":
    var snapshot = newSnapshot("a(b)\nstart\nmiddle\nend\nplain\n")
    discard snapshot.addOverlay(point(1, 0)...point(1, 0), "<", 1)
    discard snapshot.addOverlay(point(2, 3)...point(2, 3), "!", 1)
    discard snapshot.addOverlay(point(3, 3)...point(3, 3), ">", 1)
    discard snapshot.addOverlay(point(5, 0)...point(5, 0), "tail", 1)
    var arena = initArena()
    var iter = snapshot.iter(arena.addr)
    iter.seekLine(0)
    check iter.render() == "a(b)\n<start\nmid!dle\nend>\nplain\ntail"

  test "unaffected lines retain mapped rows after multiline overlays":
    var snapshot = newSnapshot("first\nsecond\nthird\nfourth\nfifth")
    discard snapshot.addOverlay(point(0, 0)...point(0, 5), "one\ntwo", 1)
    discard snapshot.addOverlay(point(2, 0)...point(3, 6), "joined", 1)
    var arena = initArena()
    var iter = snapshot.iter(arena.addr)
    iter.seekLine(0)
    check iter.render() == "one\ntwo\nsecond\njoined\nfifth"
    var sought = snapshot.iter(arena.addr)
    sought.seekLine(2)
    check sought.render() == "second\njoined\nfifth"

  test "unaffected styled chunks keep source points after an inserted line":
    var snapshot = newSnapshot("first\nplain(a)\t{b}\nlast")
    discard snapshot.addOverlay(point(0, 5)...point(0, 5), "\nextra", 1)
    var arena = initArena()
    var iter = snapshot.iter(arena.addr)
    var styled = StyledChunkIterator.init(snapshot.buffer.visibleText, arena.addr)
    iter.seekLine(2)
    styled.seekLine(1)
    while styled.next().getSome(expected):
      let actual = iter.next()
      require actual.isSome
      check actual.get.styledChunk == expected
      check actual.get.overlayPoint == overlayPoint(expected.point.row + 1, expected.point.column)
    check iter.next().isNone

  test "forward source and overlay seeks reset the cached line":
    var snapshot = newSnapshot("a(b)\nplain\nlast")
    discard snapshot.addOverlay(point(2, 0)...point(2, 0), ">", 1)
    var arena = initArena()
    for sourceSeek in [false, true]:
      var iter = snapshot.iter(arena.addr)
      iter.seekLine(0)
      require iter.next().isSome
      if sourceSeek:
        iter.seek(point(1, 2))
      else:
        iter.seek(overlayPoint(1, 2))
      check iter.render() == "ain\n>last"

  test "iteration without a seek and empty buffers terminate":
    for content in ["", "\n", "a(b)\n\nlast"]:
      let snapshot = newSnapshot(content)
      var arena = initArena()
      var iter = snapshot.iter(arena.addr)
      check iter.render() == content

  test "deletions and empty overlays still take the overlay path":
    var snapshot = newSnapshot("plain\nabcdef\n\nlast")
    discard snapshot.addOverlay(point(1, 1)...point(1, 4), "", 1)
    discard snapshot.addOverlay(point(2, 0)...point(2, 0), "empty", 1)
    var arena = initArena()
    var iter = snapshot.iter(arena.addr)
    iter.seekLine(0)
    check iter.render() == "plain\naef\nempty\nlast"

  test "end of file overlays are not bypassed":
    for bias in [Bias.Left, Bias.Right]:
      for content in ["", "a(b)", "plain\nlast"]:
        var snapshot = newSnapshot(content)
        let last = snapshot.buffer.visibleText.endPoint
        discard snapshot.addOverlay(last...last, "!", 1, bias = bias)
        var arena = initArena()
        var iter = snapshot.iter(arena.addr)
        iter.seekLine(0)
        check iter.render() == content & "!"

  test "seeking from an identity line into overlay text resets the fast path":
    var snapshot = newSnapshot("plain\nlast")
    discard snapshot.addOverlay(point(1, 0)...point(1, 0), "overlay\n", 1)
    var arena = initArena()
    var iter = snapshot.iter(arena.addr)
    iter.seekLine(0)
    require iter.next().isSome
    iter.seek(overlayPoint(1, 2))
    check iter.render() == "erlay\nlast"
