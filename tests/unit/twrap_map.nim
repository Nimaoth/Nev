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

var debug = false
template log(msg: untyped) =
  if debug:
    echo msg

const file = """

0123456789+-aaaaaaaa+bbbbbbbbbccccccccccddddddddddeeeeeeeeeeffffffffffgggggggggghhhhhhhhhhiiiiiiiiiijjjjjjjjjjkkkkkkkkkkllllllllll0123456789+-aaaaaaaa+bbbbbbbbbccccccccccddddddddddeeeeeeeeeeffffffffffgggggggggghhhhhhhhhhiiiiiiiiiijjjjjjjjjjkkkkkkkkkklllllllll

aa
"""
const fileMapRanges = @[
  WrapMapChunk(src: Point.init(1, 122), dst: Point.init(1, 122)),
  WrapMapChunk(src: Point.init(0, 0), dst: Point.init(1, 4)),
  WrapMapChunk(src: Point.init(0, 122), dst: Point.init(0, 122)),
  WrapMapChunk(src: Point.init(0, 0), dst: Point.init(1, 4)),
  WrapMapChunk(src: Point.init(3, 0), dst: Point.init(3, 0)),
]

suite "Wrap map":
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

  test "Insert 1:10 'x'":
    check testEdit(file,
      edits = [(point(1, 10)...point(1, 10), "xx")],
      expect = @[
        (point(1, 124), point(1, 124)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Insert 1:122 'x'":
    check testEdit(file,
      edits = [(point(1, 122)...point(1, 122), "x")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 123), point(0, 123)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Insert 1:244 'x'":
    check testEdit(file,
      edits = [(point(1, 244)...point(1, 244), "x")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Insert 2:0 'x'":
    check testEdit(file,
      edits = [(point(2, 0)...point(2, 0), "x")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Insert 3:0 'x'":
    check testEdit(file,
      edits = [(point(3, 0)...point(3, 0), "x")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Insert 4:0 'x'":
    check testEdit(file,
      edits = [(point(4, 0)...point(4, 0), "x")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 1), point(3, 1)),
      ])

  test "Insert 0:0 '\\n'":
    check testEdit(file,
      edits = [(point(0, 0)...point(0, 0), "\n")],
      expect = @[
        (point(2, 122), point(2, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Insert 1:0 '\\n'":
    check testEdit(file,
      edits = [(point(1, 0)...point(1, 0), "\n")],
      expect = @[
        (point(2, 122), point(2, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Insert 1:10 '\\n'":
    check testEdit(file,
      edits = [(point(1, 10)...point(1, 10), "\n")],
      expect = @[
        (point(2, 112), point(2, 112)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Insert 1:122 '\\n'":
    check testEdit(file,
      edits = [(point(1, 122)...point(1, 122), "\n")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Insert 1:244 '\\n'":
    check testEdit(file,
      edits = [(point(1, 244)...point(1, 244), "\n")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(4, 0), point(4, 0)),
      ])

  test "Insert 2:0 '\\n'":
    check testEdit(file,
      edits = [(point(2, 0)...point(2, 0), "\n")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(4, 0), point(4, 0)),
      ])

  test "Insert 3:0 '\\n'":
    check testEdit(file,
      edits = [(point(3, 0)...point(3, 0), "\n")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(4, 0), point(4, 0)),
      ])

  test "Insert 4:0 '\\n'":
    check testEdit(file,
      edits = [(point(4, 0)...point(4, 0), "\n")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(4, 0), point(4, 0)),
      ])

  test "Insert 0:0, 1:0, 1:10, 1:122, 1:244, 2:0, 3:0 'x'":
    let ps = [point(0, 0), point(1, 0), point(1, 10), point(1, 122), point(1, 244), point(2, 0), point(3, 0)]
    check testEdit(file,
      edits = ps.mapIt((it...it, "x")),
      expect = @[
        (point(1, 124), point(1, 124)),
        (point(0, 0), point(1, 4)),
        (point(0, 123), point(0, 123)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Insert 0:0, 1:0, 1:10, 1:122, 1:244, 2:0, 3:0, 4:0 'x'":
    let ps = [point(0, 0), point(1, 0), point(1, 10), point(1, 122), point(1, 244), point(2, 0), point(3, 0), point(4, 0)]
    check testEdit(file,
      edits = ps.mapIt((it...it, "x")),
      expect = @[
        (point(1, 124), point(1, 124)),
        (point(0, 0), point(1, 4)),
        (point(0, 123), point(0, 123)),
        (point(0, 0), point(1, 4)),
        (point(3, 1), point(3, 1)),
      ])

  # test "Delete 0:0 ''":
  #   check testEdit(file,
  #     edits = [(point(0, 0)...point(0, 0), "")],
  #     expect = @[
  #       (point(2, 122), point(2, 122)),
  #       (point(0, 0), point(1, 4)),
  #       (point(0, 122), point(0, 122)),
  #       (point(0, 0), point(1, 4)),
  #       (point(3, 0), point(3, 0)),
  #     ])

  test "Delete 1:0-1:1":
    check testEdit(file,
      edits = [(point(1, 0)...point(1, 1), "")],
      expect = @[
        (point(1, 121), point(1, 121)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Delete 1:10-1:11":
    check testEdit(file,
      edits = [(point(1, 10)...point(1, 11), "")],
      expect = @[
        (point(1, 121), point(1, 121)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Delete 1:122-1:123":
    check testEdit(file,
      edits = [(point(1, 122)...point(1, 123), "")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 121), point(0, 121)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Delete 1:244-1:245":
    check testEdit(file,
      edits = [(point(1, 244)...point(1, 245), "")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  # test "Delete 2:0-2:0":
  #   check testEdit(file,
  #     edits = [(point(2, 0)...point(2, 0), "")],
  #     expect = @[
  #       (point(1, 122), point(1, 122)),
  #       (point(0, 0), point(1, 4)),
  #       (point(0, 122), point(0, 122)),
  #       (point(0, 0), point(1, 4)),
  #       (point(3, 0), point(3, 0)),
  #     ])

  test "Delete 3:0-3:1":
    check testEdit(file,
      edits = [(point(3, 0)...point(3, 1), "")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  # test "Delete 4:0-4:0":
  #   check testEdit(file,
  #     edits = [(point(4, 0)...point(4, 0), "")],
  #     expect = @[
  #       (point(1, 122), point(1, 122)),
  #       (point(0, 0), point(1, 4)),
  #       (point(0, 122), point(0, 122)),
  #       (point(0, 0), point(1, 4)),
  #       (point(3, 0), point(3, 0)),
  #     ])





  test "Delete 3:0-4:0, 4:1-5:0":
    let file = """

0123456789+-aaaaaaaa+bbbbbbbbbccccccccccddddddddddeeeeeeeeeeffffffffffgggggggggghhhhhhhhhhiiiiiiiiiijjjjjjjjjjkkkkkkkkkkllllllllll0123456789+-aaaaaaaa+bbbbbbbbbccccccccccddddddddddeeeeeeeeeeffffffffffgggggggggghhhhhhhhhhiiiiiiiiiijjjjjjjjjjkkkkkkkkkklllllllll


a
a
"""

    check testEdit(file,
      edits = [(point(3, 0)...point(4, 0), ""), (point(4, 1)...point(5, 0), "")],
      expect = @[
        (point(1, 122), point(1, 122)),
        (point(0, 0), point(1, 4)),
        (point(0, 122), point(0, 122)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Delete 1:0-1:259":
    # debug = true
    # debugWrapMap = true
    let file = """

0123456789+-aaaaaaaa+bbbbbbbbbccccccccccddddddddddeeeeeeeeeeffffffffffgggggggggghhhhhhhhhhiiiiiiiiiijjjjjjjjjjkkkkkkkkkkllllllllll0123456789+-aaaaaaaa+bbbbbbbbbccccccccccddddddddddeeeeeeeeeeffffffffffgggggggggghhhhhhhhhhiiiiiiiiiijjjjjjjjjjkkkkkkkkkklllllllll

aa
"""
    check testEdit(file,
      edits = [(point(1, 0)...point(1, 259), "")],
      expect = @[
        (point(1, 0), point(1, 0)),
        (point(3, 0), point(3, 0)),
      ])

  test "Delete 1:0-1:243":
    check testEdit(file,
      edits = [(point(1, 0)...point(1, 243), "")],
      expect = @[
        (point(1, 0), point(1, 0)),
        (point(0, 1), point(0, 1)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Delete 1:0-1:244":
    check testEdit(file,
      edits = [(point(1, 0)...point(1, 244), "")],
      expect = @[
        (point(1, 0), point(1, 0)),
        (point(3, 0), point(3, 0)),
      ])

  test "Delete 1:0-1:245":
    check testEdit(file,
      edits = [(point(1, 0)...point(1, 245), "")],
      expect = @[
        (point(1, 0), point(1, 0)),
        (point(3, 0), point(3, 0)),
      ])

  test "Delete 1:1-1:243":
    check testEdit(file,
      edits = [(point(1, 1)...point(1, 243), "")],
      expect = @[
        (point(1, 1), point(1, 1)),
        (point(0, 1), point(0, 1)),
        (point(0, 0), point(1, 4)),
        (point(3, 0), point(3, 0)),
      ])

  test "Delete 1:1-1:244":
    check testEdit(file,
      edits = [(point(1, 1)...point(1, 244), "")],
      expect = @[
        (point(1, 1), point(1, 1)),
        (point(3, 0), point(3, 0)),
      ])

  test "Delete 1:1-1:245":
    check testEdit(file,
      edits = [(point(1, 1)...point(1, 245), "")],
      expect = @[
        (point(1, 1), point(1, 1)),
        (point(3, 0), point(3, 0)),
      ])
