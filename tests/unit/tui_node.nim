discard """
  action: "run"
  cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 60
  targets: "c js"
  matrix: ""
"""

import std/[unittest, options, json, sequtils]
import util, ui/node

template frame(builder: UINodeBuilder, body: untyped) =
  block:
    builder.beginFrame(vec2(100, 100))
    defer:
      builder.endFrame()
    body

suite "UI Nodes":
  test "create builder":
    let builder = newNodeBuilder()
    check builder.isNotNil
    check builder.frameIndex == 0
    check builder.root.isNotNil
    check builder.root.first.isNil
    check builder.root.last.isNil
    check builder.root.next.isNil
    check builder.root.prev.isNil
    check builder.root.len == 0

  test "[] operator":
    let builder = newNodeBuilder()
    let id = newId()

    builder.frame:
      builder.panel(&{}, userId = newSecondaryId(id, 0))
      builder.panel(&{}, userId = newSecondaryId(id, 1))
      builder.panel(&{}, userId = newSecondaryId(id, 2))

    check builder.root.first.isNotNil
    check builder.root.last.isNotNil
    check builder.root.first != builder.root.last
    check builder.root.first.next == builder.root.last.prev
    check builder.root.first.next.isNotNil

    let node0 = builder.root.first
    let node1 = builder.root.first.next
    let node2 = builder.root.first.next.next

    check builder.root[0] == node0
    check builder.root[1] == node1
    check builder.root[2] == node2

  test "sub id":
    let builder = newNodeBuilder()
    let id = newId()

    let id0 = newSecondaryId(id, 0)
    let id1 = newSecondaryId(id, 1)
    let id2 = newSecondaryId(id, 2)
    let id3 = newSecondaryId(id, 3)

    # frame 1: first ui
    builder.frame:
      builder.panel(&{}, userId = id0, w = 1)
      builder.panel(&{}, userId = id1, w = 1)
      builder.panel(&{}, userId = id2, w = 1)

    let node10 = builder.root[0]
    let node11 = builder.root[1]
    let node12 = builder.root[2]
    check builder.root.lastChange == 1
    check node10.lastChange == 1
    check node11.lastChange == 1
    check node12.lastChange == 1

    # frame 2: insert id3
    builder.frame:
      builder.panel(&{}, userId = id0, w = 1)
      builder.panel(&{}, userId = id1, w = 1)
      builder.panel(&{}, userId = id3, w = 1)
      builder.panel(&{}, userId = id2, w = 1)

    let node20 = builder.root[0]
    let node21 = builder.root[1]
    let node22 = builder.root[2]
    let node23 = builder.root[3]

    check node10 == node20
    check node11 == node21
    check node12 == node23
    check builder.root.lastChange == 2
    check node20.lastChange == 1
    check node21.lastChange == 1
    check node22.lastChange == 2
    check node23.lastChange == 1

    # frame 3: remove id1
    builder.frame:
      builder.panel(&{}, userId = id0, w = 1)
      builder.panel(&{}, userId = id3, w = 1)
      builder.panel(&{}, userId = id2, w = 1)

    let node30 = builder.root[0]
    let node31 = builder.root[1]
    let node32 = builder.root[2]

    check node20 == node30
    check node22 == node31
    check node23 == node32
    check builder.root.lastChange == 3
    check node30.lastChange == 1
    check node31.lastChange == 2
    check node32.lastChange == 1

    # frame 4: no changes
    builder.frame:
      builder.panel(&{}, userId = id0, w = 1)
      builder.panel(&{}, userId = id3, w = 1)
      builder.panel(&{}, userId = id2, w = 1)

    let node40 = builder.root[0]
    let node41 = builder.root[1]
    let node42 = builder.root[2]

    check node30 == node40
    check node31 == node41
    check node32 == node42
    check builder.root.lastChange == 3
    check node40.lastChange == 1
    check node41.lastChange == 2
    check node42.lastChange == 1

  test "no sub id":
    let builder = newNodeBuilder()

    # frame 1: first ui
    builder.frame:
      builder.panel(&{}, w = 1)
      builder.panel(&{}, w = 2)
      builder.panel(&{}, w = 3)

    let node10 = builder.root[0]
    let node11 = builder.root[1]
    let node12 = builder.root[2]
    check builder.root.lastChange == 1
    check node10.lastChange == 1
    check node11.lastChange == 1
    check node12.lastChange == 1

    # frame 2: insert id3
    builder.frame:
      builder.panel(&{}, w = 1)
      builder.panel(&{}, w = 2)
      builder.panel(&{}, w = 4)
      builder.panel(&{}, w = 3)

    let node20 = builder.root[0]
    let node21 = builder.root[1]
    let node22 = builder.root[2]
    let node23 = builder.root[3]

    check node10 == node20
    check node11 == node21
    check node12 == node22
    check builder.root.lastChange == 2
    check node20.lastChange == 1
    check node21.lastChange == 1
    check node22.lastChange == 2
    check node23.lastChange == 2

    # frame 3: remove id1
    builder.frame:
      builder.panel(&{}, w = 1)
      builder.panel(&{}, w = 4)
      builder.panel(&{}, w = 3)

    let node30 = builder.root[0]
    let node31 = builder.root[1]
    let node32 = builder.root[2]

    check node20 == node30
    check node21 == node31
    check node22 == node32
    check builder.root.lastChange == 3
    check node30.lastChange == 1
    check node31.lastChange == 3
    check node32.lastChange == 3

    # frame 4: no changes
    builder.frame:
      builder.panel(&{}, w = 1)
      builder.panel(&{}, w = 4)
      builder.panel(&{}, w = 3)

    let node40 = builder.root[0]
    let node41 = builder.root[1]
    let node42 = builder.root[2]

    check node30 == node40
    check node31 == node41
    check node32 == node42
    check builder.root.lastChange == 3
    check node40.lastChange == 1
    check node41.lastChange == 3
    check node42.lastChange == 3

  test "FillX, LayoutHorizontalReverse":
    let builder = newNodeBuilder()

    builder.frame:
      builder.panel(&{FillX, LayoutHorizontalReverse}):
        builder.panel(&{}, w = 10, pivot = vec2(1, 0))
        builder.panel(&{}, w = 10, pivot = vec2(1, 0))
        builder.panel(&{FillX}, pivot = vec2(1, 0))

    check builder.root[0][0].bounds == rect(90, 0, 10, 0)
    check builder.root[0][0].boundsRaw == rect(100, 0, 10, 0)

    check builder.root[0][1].bounds == rect(80, 0, 10, 0)
    check builder.root[0][1].boundsRaw == rect(90, 0, 10, 0)

    check builder.root[0][2].bounds == rect(0, 0, 80, 0)
    check builder.root[0][2].boundsRaw == rect(80, 0, 80, 0)

  test "FillY, LayoutVerticalReverse":
    let builder = newNodeBuilder()

    builder.frame:
      builder.panel(&{FillY, LayoutVerticalReverse}):
        builder.panel(&{}, h = 10, pivot = vec2(0, 1))
        builder.panel(&{}, h = 10, pivot = vec2(0, 1))
        builder.panel(&{FillY}, pivot = vec2(0, 1))

    check builder.root[0][0].bounds == rect(0, 90, 0, 10)
    check builder.root[0][0].boundsRaw == rect(0, 100, 0, 10)

    check builder.root[0][1].bounds == rect(0, 80, 0, 10)
    check builder.root[0][1].boundsRaw == rect(0, 90, 0, 10)

    check builder.root[0][2].bounds == rect(0, 0, 0, 80)
    check builder.root[0][2].boundsRaw == rect(0, 80, 0, 80)

  test "LayoutHorizontalReverse, SizeToContentX":
    let builder = newNodeBuilder()

    builder.frame:
      builder.panel(&{LayoutHorizontalReverse, SizeToContentX}):
        builder.panel(&{}, w = 15, pivot = vec2(1, 0))
        builder.panel(&{}, w = 10, pivot = vec2(1, 0))
        builder.panel(&{}, w = 5, pivot = vec2(1, 0))

    check builder.root[0].boundsRaw == rect(0, 0, 30, 0)

    check builder.root[0][0].bounds == rect(15, 0, 15, 0)
    check builder.root[0][0].boundsRaw == rect(30, 0, 15, 0)

    check builder.root[0][1].bounds == rect(5, 0, 10, 0)
    check builder.root[0][1].boundsRaw == rect(15, 0, 10, 0)

    check builder.root[0][2].bounds == rect(0, 0, 5, 0)
    check builder.root[0][2].boundsRaw == rect(5, 0, 5, 0)

  test "LayoutVerticalReverse, SizeToContentY":
    let builder = newNodeBuilder()

    builder.frame:
      builder.panel(&{LayoutVerticalReverse, SizeToContentY}):
        builder.panel(&{}, h = 15, pivot = vec2(0, 1))
        builder.panel(&{}, h = 10, pivot = vec2(0, 1))
        builder.panel(&{}, h = 5, pivot = vec2(0, 1))

    check builder.root[0].boundsRaw == rect(0, 0, 0, 30)

    check builder.root[0][0].bounds == rect(0, 15, 0, 15)
    check builder.root[0][0].boundsRaw == rect(0, 30, 0, 15)

    check builder.root[0][1].bounds == rect(0, 5, 0, 10)
    check builder.root[0][1].boundsRaw == rect(0, 15, 0, 10)

    check builder.root[0][2].bounds == rect(0, 0, 0, 5)
    check builder.root[0][2].boundsRaw == rect(0, 5, 0, 5)

  test "LayoutHorizontal, FillX":
    let builder = newNodeBuilder()

    builder.frame:
      builder.panel(&{LayoutHorizontal, FillX}):
        builder.panel(&{}, w = 10)
        builder.panel(&{}, w = 20)
        builder.panel(&{FillX})

    check builder.root[0].boundsRaw == rect(0, 0, 100, 0)

    check builder.root[0][0].bounds == rect(0, 0, 10, 0)
    check builder.root[0][0].boundsRaw == rect(0, 0, 10, 0)

    check builder.root[0][1].bounds == rect(10, 0, 20, 0)
    check builder.root[0][1].boundsRaw == rect(10, 0, 20, 0)

    check builder.root[0][2].bounds == rect(30, 0, 70, 0)
    check builder.root[0][2].boundsRaw == rect(30, 0, 70, 0)

  test "LayoutHorizontal, SizeToContentX":
    let builder = newNodeBuilder()

    builder.frame:
      builder.panel(&{LayoutHorizontal, SizeToContentX}):
        builder.panel(&{}, w = 10)
        builder.panel(&{}, w = 20)
        builder.panel(&{FillX})

    check builder.root[0].boundsRaw == rect(0, 0, 30, 0)

    check builder.root[0][0].bounds == rect(0, 0, 10, 0)
    check builder.root[0][0].boundsRaw == rect(0, 0, 10, 0)

    check builder.root[0][1].bounds == rect(10, 0, 20, 0)
    check builder.root[0][1].boundsRaw == rect(10, 0, 20, 0)

    check builder.root[0][2].bounds == rect(30, 0, 0, 0)
    check builder.root[0][2].boundsRaw == rect(30, 0, 0, 0)

  test "LayoutVertical, FillY":
    let builder = newNodeBuilder()

    builder.frame:
      builder.panel(&{LayoutVertical, FillY}):
        builder.panel(&{}, h = 10)
        builder.panel(&{}, h = 20)
        builder.panel(&{FillY})

    check builder.root[0].boundsRaw == rect(0, 0, 0, 100)

    check builder.root[0][0].bounds == rect(0, 0, 0, 10)
    check builder.root[0][0].boundsRaw == rect(0, 0, 0, 10)

    check builder.root[0][1].bounds == rect(0, 10, 0, 20)
    check builder.root[0][1].boundsRaw == rect(0, 10, 0, 20)

    check builder.root[0][2].bounds == rect(0, 30, 0, 70)
    check builder.root[0][2].boundsRaw == rect(0, 30, 0, 70)

  test "LayoutVertical, SizeToContentY":
    let builder = newNodeBuilder()

    builder.frame:
      builder.panel(&{LayoutVertical, SizeToContentY}):
        builder.panel(&{}, h = 10)
        builder.panel(&{}, h = 20)
        builder.panel(&{FillY})

    check builder.root[0].boundsRaw == rect(0, 0, 0, 30)

    check builder.root[0][0].bounds == rect(0, 0, 0, 10)
    check builder.root[0][0].boundsRaw == rect(0, 0, 0, 10)

    check builder.root[0][1].bounds == rect(0, 10, 0, 20)
    check builder.root[0][1].boundsRaw == rect(0, 10, 0, 20)

    check builder.root[0][2].bounds == rect(0, 30, 0, 0)
    check builder.root[0][2].boundsRaw == rect(0, 30, 0, 0)