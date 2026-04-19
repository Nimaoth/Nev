import std/[terminal, strutils]

proc escapeUnprintableColored*(s: string): string =
  var len = 0

  let escapeColor = ansiForegroundColorCode(fgRed)
  let defaultColor = ansiForegroundColorCode(fgDefault)
  for c in s:
    if (c in PrintableChars and c notin Newlines) or c.int >= 128:
      inc len
    else:
      len += 4 + escapeColor.len + defaultColor.len
  for c in s:
    if (c in PrintableChars and c notin Newlines) or c.int >= 128:
      result.add c
    else:
      # result.add ansiForegroundColorCode(fgRed)
      result.add escapeColor
      result.add "\\x"
      result.add c.int.toHex(2)
      # result.add ansiForegroundColorCode(fgDefault)
      result.add defaultColor

when isMainModule:
  static:
    echo "hello\r\nwor\x16ld"
    echo "hello\r\nwor\x16ld".escapeUnprintableColored()
