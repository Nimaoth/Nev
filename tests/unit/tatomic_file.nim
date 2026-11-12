import std/[os, tempfiles, unittest]
import misc/atomic_file

suite "Atomic file replacement":
  setup:
    let dir = createTempDir("nev-atomic-file-", "")
    let source = dir / "capture.tmp"
    let dest = dir / "capture.txt"

  teardown:
    removeDir(dir)

  test "publishes and replaces captures":
    writeFile(source, "first")
    moveFileAtomic(source, dest)
    check readFile(dest) == "first"
    check not fileExists(source)

    writeFile(source, "second")
    moveFileAtomic(source, dest)
    check readFile(dest) == "second"
    check not fileExists(source)

  test "failed rename preserves the previous capture":
    writeFile(dest, "previous")
    expect OSError:
      moveFileAtomic(source, dest)
    check readFile(dest) == "previous"
