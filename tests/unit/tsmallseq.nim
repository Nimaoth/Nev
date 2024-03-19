discard """
  action: "run"
  cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 60
  targets: "c"
  matrix: ""
"""

import std/[tables, unittest, strformat]
import input

import misc/smallseq


suite "SmallSeq":

  proc testAdd[T]() =
    var s = initSmallSeq(T, 23)

    assert s.isInline
    assert s.len == 0

    s.add 0

    assert s.isInline
    assert s.len == 1

    for i in 1..22:
      s.add i.T

      assert s.isInline

    assert s.len == 23
    assert @(s[0..<23]) == @[0.T, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22]

    s.add 23

    assert not s.isInline
    assert s.len == 24

    for i in 0..<24:
      assert s[i] == i.T

    assert @(s[0..<24]) == @[0.T, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]

    for i in 24..256:
      s.add i.T
      assert s[i] == i.T

  test "add int8":
    testAdd[uint8]()

  test "add int32":
    testAdd[int32]()

  test "inline capacity":
    assert initSmallSeq(int8, 10).capacity == 23
    assert initSmallSeq(int32, 10).capacity == 10
    assert initSmallSeq(int8, 23).capacity == 23
    assert initSmallSeq(int32, 23).capacity == 23
    assert initSmallSeq(int8, 24).capacity == 24
    assert initSmallSeq(int32, 24).capacity == 24

  proc testShrink[T]() =
    var s = initSmallSeq(T, 30)
    for i in 0..<40:
      s.add i.T

    assert not s.isInline
    assert s.len == 40
    assert s.capacity == 60

    s.shrink(1)

    assert not s.isInline
    assert s.len == 40
    assert s.capacity == 41

    s.delete(0..<15, shrink=true)

    assert s.isInline
    assert s.len == 25
    assert s.capacity ==  30

  test "shrink int8":
    testShrink[int8]()

  test "shrink int32":
    testShrink[int32]()

  proc testDelete[T]() =
    var s = initSmallSeq(T, 30)
    for i in 0..<50:
      s.add i.T

    assert s.len == 50

    for i in 0..s.high:
      assert s[i] == i.T

    s.delete 10..<15
    assert s.len == 45
    assert not s.isInline

    for i in 0..<10:
      assert s[i] == i.T

    for i in 10..<45:
      assert s[i] == i.T + 5

    s.delete 25..<44
    assert s.len == 26
    assert s.isInline

    for i in 0..<10:
      assert s[i] == i.T

    for i in 10..<25:
      assert s[i] == i.T + 5

    for i in 25..<s.len:
      assert s[i] == i.T + 24

    s.delete 0..<10
    echo s
    assert s.len == 16
    assert s.isInline

    for i in 0..<15:
      assert s[i] == i.T + 15

    for i in 15..<s.len:
      assert s[i] == i.T + 34

  test "delete int8":
    testDelete[int8]()

  test "delete int32":
    testDelete[int32]()