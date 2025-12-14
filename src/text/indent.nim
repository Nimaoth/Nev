import std/strutils
import misc/util

type
  IndentStyleKind* {.pure.} = enum Tabs = "tabs", Spaces = "spaces"

proc getIndentString*(style: IndentStyleKind, width: int): string =
  case style
  of Tabs: return "\t"
  of Spaces: return " ".repeat(width)

proc tabWidthAt*(len: int, tabWidth: int): int = tabWidth - (len mod tabWidth)

proc indentLevelForLine*(line: string, width: int): int =
  var len = 0
  for c in line:
    case c
    of '\t':
      len += tabWidthAt(len, width)
    of ' ':
      len += 1
    else:
      break
  return len div width

proc indentForNewLine*(
  indentAfter: Option[seq[string]],
  line: string,
  style: IndentStyleKind,
  width: int,
  column: int,
  indentOffset: int = 0,
): string =
  var indentLevel = max(indentLevelForLine(line, width) + indentOffset, 0)

  if line.len > 0 and indentAfter.getSome(indentAfter):
    for suffix in indentAfter:
      if line[0..<column].endsWith(suffix):
        inc indentLevel
        break

  return getIndentString(style, width).repeat(indentLevel)
