discard """
  action: "run"
  cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 60
  targets: "c js"
  matrix: ""
"""

import std/[unittest, options, json, sequtils]
import util, rect_utils

suite "Rect Utils":

  test "Area":
    check rect(0, 0, 0, 2).area == 0.float32
    check rect(0, 0, 2, 3).area == 6.float32

  test "Invalidation Rect":
    # completely outside
    check invalidationRect(rect(0, 0, 10, 10), rect(15, 15, 10, 10)) == rect(0, 0, 10, 10)

    # corner ovelapping
    check invalidationRect(rect(0, 0, 10, 10), rect(5, 5, 10, 10)) == rect(0, 0, 10, 10)

    # completely inside
    check invalidationRect(rect(0, 0, 10, 10), rect(5, 5, 1, 1)) == rect(0, 0, 10, 10)

    # right
    check invalidationRect(rect(0, 0, 10, 10), rect(0, 0, 5, 10)) == rect(5, 0, 5, 10)
    check invalidationRect(rect(0, 0, 10, 10), rect(0, 0, 5, 9)) == rect(0, 0, 10, 10)
    check invalidationRect(rect(0, 0, 10, 10), rect(-1, -1, 6, 12)) == rect(5, 0, 5, 10)

    # left
    check invalidationRect(rect(0, 0, 10, 10), rect(5, 0, 5, 10)) == rect(0, 0, 5, 10)
    check invalidationRect(rect(0, 0, 10, 10), rect(5, 0, 5, 9)) == rect(0, 0, 10, 10)
    check invalidationRect(rect(0, 0, 10, 10), rect(5, -1, 6, 12)) == rect(0, 0, 5, 10)

    # top
    check invalidationRect(rect(0, 0, 10, 10), rect( 0,  0, 10, 5)) == rect(0, 5, 10,  5)
    check invalidationRect(rect(0, 0, 10, 10), rect( 0,  0,  9, 5)) == rect(0, 0, 10, 10)
    check invalidationRect(rect(0, 0, 10, 10), rect(-1, -1, 12, 6)) == rect(0, 5, 10,  5)

    # left
    check invalidationRect(rect(0, 0, 10, 10), rect( 0, 5, 10, 5)) == rect(0, 0, 10,  5)
    check invalidationRect(rect(0, 0, 10, 10), rect( 0, 5,  9, 5)) == rect(0, 0, 10, 10)
    check invalidationRect(rect(0, 0, 10, 10), rect(-1, 5, 12, 6)) == rect(0, 0, 10,  5)