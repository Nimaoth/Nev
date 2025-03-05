
discard """
  action: "run"
  cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 60
  targets: "c"
  matrix: ""
"""

import std/[unittest, options, json, sequtils, strformat, strutils]
import misc/[util, rope_utils]
import nimsumtree/[rope, sumtree, buffer, clock]
import text/[overlay_map]

var debug = true
template log(msg: untyped) =
  if debug:
    echo msg

const file = """
line one
line two
line three"""

const defaultOverlays = [
  (point(0, 5)...point(0, 5), "test", 1, Bias.Left),
  (point(1, 4)...point(1, 4), "xvlc", 1, Bias.Right),
]

# suite "Overlay map":
proc prepareData(content: string): (Buffer, OverlayMap) =
  var b = initBuffer(content = content)
  check $b.visibleText == content

  var om = OverlayMap.new()
  om.setBuffer(b.snapshot.clone())
  (b, om)

# test "Initial update":
proc test(edits: openArray[(Range[Point], string)], content: string = file, overlays: openArray[(Range[Point], string, int, Bias)] = defaultOverlays) =
  let edits = @edits
  log &"================================================== testEdit {edits}"
  log content
  log "---------------------"
  var (b, om) = prepareData(content)
  echo &"initial snapshot: {om.snapshot}"
  log "----------"
  echo om.snapshot.renderString()
  log "----------"
  for overlay in overlays:
    om.addOverlay(overlay[0], overlay[1], overlay[2], bias = overlay[3])

  # om.addOverlay(point(0, 5)...point(0, 5), "test", 1)
  # om.addOverlay(point(1, 4)...point(1, 4), "xvlc", 1)
  echo &"overlay snapshot: {om.snapshot}"
  log "----------"
  echo om.snapshot.renderString()
  log "----------"
  log "---------------------"
  discard b.edit edits
  log b.visibleText
  log "---------------------"
  for p in b.patches:
    let patch = p.patch.convert(Point, om.snapshot.buffer.visibleText, b.visibleText)
    log &"edit patch: {patch}"
    let overlayPatch = om.snapshot.edit(b.snapshot.clone(), patch)
    log &"new snapshot: {om.snapshot}"
    log &"overlay patch: {overlayPatch}"
    log "----------"
    echo om.snapshot.renderString()
    log "----------"
    let actual = om.snapshot.map.toSeq()

  log ""

# insert
test([(point(0, 1)...point(0, 1), "x")])
test([(point(0, 5)...point(0, 5), "x")])
test([(point(0, 6)...point(0, 6), "x")])

test([(point(1, 1)...point(1, 1), "x")])
test([(point(1, 4)...point(1, 4), "x")])
test([(point(1, 5)...point(1, 5), "x")])

test([(point(0, 3)...point(0, 3), "\n")])
test([(point(1, 3)...point(1, 3), "\n")])
test([(point(2, 5)...point(2, 5), "\n")])

# delete
test([(point(0, 1)...point(0, 2), "")])
test([(point(0, 3)...point(0, 5), "")])
test([(point(0, 4)...point(0, 6), "")])
test([(point(0, 4)...point(0, 6), "y")])
test([(point(0, 0)...point(2, 10), file)])

# insert into empty
test([(point(0, 0)...point(0, 0), "\n")], "", [])

# multiple overlays per line
const defaultOverlays2 = [
  (point(0, 3)...point(0, 3), "12", 1, Bias.Left),
  (point(0, 6)...point(0, 6), "34", 1, Bias.Left),
  (point(2, 3)...point(2, 3), "12", 1, Bias.Right),
  (point(2, 6)...point(2, 6), "34", 1, Bias.Right),
]

test([(point(2, 2)...point(2, 4), "")], file, defaultOverlays2)

# overlay replacing some text
const defaultOverlays3 = [
  (point(0, 1)...point(0, 4), "ack", 1, Bias.Left),
]

# debugOverlayMapNext = true
test([(point(0, 2)...point(0, 2), "+")], file, defaultOverlays3)
test([(point(0, 2)...point(0, 3), "")], file, defaultOverlays3)
test([(point(0, 2)...point(0, 3), "+")], file, defaultOverlays3)
test([(point(0, 0)...point(0, 3), "")], file, defaultOverlays3)
test([(point(0, 2)...point(0, 5), "")], file, defaultOverlays3)
test([(point(0, 0)...point(0, 3), "+-")], file, defaultOverlays3)
test([(point(0, 2)...point(0, 5), "+-")], file, defaultOverlays3)

# all kind of overlays
const defaultOverlays4 = [
  (point(0, 1)...point(0, 1), "XYZ", 1, Bias.Left),
  (point(0, 3)...point(0, 5), "W ", 1, Bias.Left),
  (point(0, 6)...point(0, 8), "", 1, Bias.Left),
  (point(1, 1)...point(1, 1), "XYZ", 1, Bias.Left),
  (point(1, 3)...point(1, 5), "W ", 1, Bias.Left),
  (point(1, 6)...point(1, 8), "", 1, Bias.Left),
  # (point(2, 1)...point(2, 1), "XYZ", 1, Bias.Left),
  # (point(2, 3)...point(2, 5), "W ", 1, Bias.Left),
  # (point(2, 6)...point(2, 8), "", 1, Bias.Left),
]

# multiple edits
test([
    (point(0, 1)...point(0, 1), "+"),
    (point(0, 3)...point(0, 3), "-"),
  ])

test([
    (point(0, 1)...point(0, 1), "+"),
    (point(0, 6)...point(0, 6), "-"),
  ])

test([
    (point(0, 6)...point(0, 6), "+"),
    (point(0, 8)...point(0, 8), "-"),
  ])

test([
    (point(1, 0)...point(1, 0), "+"),
    (point(1, 2)...point(1, 2), "-"),
    (point(1, 7)...point(1, 7), "+"),
  ], file, defaultOverlays4)

test([
    (point(1, 0)...point(1, 1), ""),
    (point(1, 2)...point(1, 3), ""),
    (point(1, 7)...point(1, 8), ""),
  ], file, defaultOverlays4)

# Basic
test([
    (point(0, 0)...point(0, 0), "a"),
  ], "", [])

test([
    (point(0, 0)...point(0, 1), ""),
  ], "a", [])
