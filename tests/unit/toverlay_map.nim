
discard """
  action: "run"
  cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 60
  targets: "c"
  matrix: ""
"""

import std/[unittest, options, json, sequtils, strformat]
import misc/[util, rope_utils]
import nimsumtree/[rope, sumtree, buffer, clock]
import text/[wrap_map, overlay_map]

var debug = false
template log(msg: untyped) =
  if debug:
    echo msg

const file = """
line one
line two
line three
"""
const fileMapRanges = @[
  WrapMapChunk(src: Point.init(1, 122), dst: Point.init(1, 122)),
  WrapMapChunk(src: Point.init(0, 0), dst: Point.init(1, 4)),
  WrapMapChunk(src: Point.init(0, 122), dst: Point.init(0, 122)),
  WrapMapChunk(src: Point.init(0, 0), dst: Point.init(1, 4)),
  WrapMapChunk(src: Point.init(3, 0), dst: Point.init(3, 0)),
]

suite "Overlay map":
  proc prepareData(content: string): (Buffer, WrapMap) =
    var b = initBuffer(content = content)
    check $b.visibleText == content

    var wm = WrapMap.new()
    wm.setBuffer(b.snapshot.clone())
    wm.wrapWidth = 122
    wm.wrappedIndent = 4
    wm.snapshot.update(b.snapshot.clone(), wm.wrapWidth, wm.wrappedIndent)
    (b, wm)

  proc testEdit(content: string, edits: openArray[(Range[Point], string)], expect: seq[WrapMapChunk]): bool =
    log &"===================== testEdit {edits}"
    log content
    log "====================="
    var (b, wm) = prepareData(content)
    discard b.edit edits
    log b.visibleText
    log "====================="
    for p in b.patches:
      let patch = p.patch.convert(Point, wm.snapshot.buffer.visibleText, b.visibleText)
      log patch
      wm.snapshot.edit(b.snapshot.clone(), patch)
      log wm.snapshot
      let actual = wm.snapshot.map.toSeq()
      check actual == expect
      if actual != expect:
        return false

    return true

  proc testEdit(content: string, edits: openArray[(Range[Point], string)], expect: seq[(Point, Point)]): bool =
    let expect = expect.mapIt(WrapMapChunk(src: it[0], dst: it[1]))
    testEdit(content, edits, expect)

  test "Initial update":
    let (b, wm) = prepareData(file)
    check wm.snapshot.map.toSeq() == fileMapRanges

  test "Insert 0:0 'x'":
    check testEdit(file,
      edits = [(point(0, 0)...point(0, 0), "x")],
      expect = fileMapRanges)

  test "Insert 1:0 'x'":
    check testEdit(file,
      edits = [(point(1, 0)...point(1, 0), "x")],
      expect = @[
        (point(1, 123), point(1, 123)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])
