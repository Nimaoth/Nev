discard """
  action: "run"
  cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 60
  targets: "c"
  matrix: ""
"""

import std/[unittest, options]
import nimsumtree/buffer
import text/display_map
import misc/custom_unicode
import chroma

suite "Display chunk byte offsets":
  proc checkOffsets(originalText, renderedText: string,
      expected: openArray[tuple[rendered, original: int]], replaced = true) =
    var buffer = initBuffer(content = originalText)
    var displayMap = DisplayMap.new()
    displayMap.setBuffer(buffer.snapshot.clone())
    var chunks = displayMap.iter(nil)
    var chunk = chunks.next().get
    check chunk.len == originalText.len
    if replaced:
      chunk.replacementText = cast[ptr UncheckedArray[char]](renderedText[0].unsafeAddr)
      chunk.replacementTextLen = renderedText.len
    for offsets in expected:
      check chunk.originalByteOffset(offsets.rendered) == offsets.original
      check mapRuneByteOffset(originalText, renderedText, offsets.original) == offsets.rendered

  test "two-byte whitespace glyphs map to original spaces":
    checkOffsets("   ", "\xC2\xB7\xC2\xB7\xC2\xB7",
      [(0, 0), (2, 1), (4, 2), (6, 3)])

  test "three-byte whitespace glyphs map to original spaces":
    checkOffsets("  ", "\xE2\x90\xA3\xE2\x90\xA3",
      [(0, 0), (3, 1), (6, 2)])

  test "mixed text preserves original multibyte character offsets":
    checkOffsets("a \xC3\xA9 e\xCC\x81 ", "a\xC2\xB7\xC3\xA9\xC2\xB7e\xCC\x81\xC2\xB7",
      [(0, 0), (1, 1), (3, 2), (5, 4), (7, 5), (10, 8), (12, 9)])

  test "unreplaced text keeps its byte offsets":
    checkOffsets("a \xC3\xA9", "a \xC3\xA9",
      [(0, 0), (1, 1), (2, 2), (4, 4)], replaced = false)

  test "empty unreplaced text starts at zero":
    check DisplayChunk().originalByteOffset(0) == 0
    check mapRuneByteOffset("", "", 0) == 0

  test "selection edges enclose complete replacement glyphs":
    let original = "   "
    let rendered = "\xC2\xB7\xC2\xB7\xC2\xB7"
    let firstByte = mapRuneByteOffset(original, rendered, 1)
    let lastByte = mapRuneByteOffset(original, rendered, 2)
    check rendered[firstByte..<lastByte] == "\xC2\xB7"

  test "block cursor redraws the replacement rune":
    let original = "   "
    let rendered = "\xC2\xB7\xC2\xB7\xC2\xB7"
    let byteOffset = mapRuneByteOffset(original, rendered, 2)
    check $rendered.runeAt(byteOffset) == "\xC2\xB7"

  test "whitespace buffer survives iterator destruction and is reused":
    var buffer = initBuffer(content = "   ")
    var displayMap = DisplayMap.new()
    displayMap.setBuffer(buffer.snapshot.clone())
    var chunk: DisplayChunk
    displayMap.setWhitespaceRendering("\xC2\xB7", color(1, 1, 1))
    block:
      var chunks = displayMap.iter(nil)
      chunk = chunks.next().get
      check bool(chunk.replacementText != nil)
    check bool(chunk.toOpenArray == "\xC2\xB7\xC2\xB7\xC2\xB7".toOpenArray(0, 5))
    block:
      displayMap.setWhitespaceRendering("\xC2\xB7", color(1, 1, 1))
      var chunks = displayMap.iter(nil)
      let nextChunk = chunks.next().get
      check bool(nextChunk.replacementText == chunk.replacementText)
      displayMap.setWhitespaceRendering("", color(1, 1, 1))
    check bool(chunk.toOpenArray == "\xC2\xB7\xC2\xB7\xC2\xB7".toOpenArray(0, 5))

  test "iterators cache map whitespace length and color":
    var buffer = initBuffer(content = "   ")
    var displayMap = DisplayMap.new()
    displayMap.setBuffer(buffer.snapshot.clone())
    let firstColor = color(1, 0, 0)
    let secondColor = color(0, 1, 0)
    displayMap.setWhitespaceRendering("\xC2\xB7", firstColor)
    var first = displayMap.iter(nil)
    displayMap.setWhitespaceRendering("\xC2\xB7", secondColor)
    var second = displayMap.iter(nil)
    displayMap.setWhitespaceRendering("", secondColor)
    var disabled = displayMap.iter(nil)
    let firstChunk = first.next().get
    let secondChunk = second.next().get
    check firstChunk.replacementTextLen == 6
    check secondChunk.replacementTextLen == 6
    check firstChunk.styledChunk.color == firstColor
    check secondChunk.styledChunk.color == secondColor
    check bool(disabled.next().get.replacementText == nil)
