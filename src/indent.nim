import std/strutils
import text_language_config, util

type
  IndentStyleKind* {.pure.} = enum Tabs, Spaces
  IndentStyle* = object
    case kind*: IndentStyleKind
    of Spaces:
      spaces*: int
    else: discard

proc indentWidth*(style: IndentStyle, tabWidth: int): int =
  case style.kind
  of Tabs: return tabWidth
  of Spaces: return style.spaces

proc indentColumns*(style: IndentStyle): int =
  case style.kind
  of Tabs: return 1
  of Spaces: return style.spaces

proc getString*(style: IndentStyle): string =
  case style.kind
  of Tabs: return "\t"
  of Spaces: return " ".repeat(style.spaces)

proc tabWidthAt*(len: int, tabWidth: int): int = tabWidth - (len mod tabWidth)

proc indentLevelForLine*(line: string, tabWidth: int, indentWidth: int): int =
  var len = 0
  for c in line:
    case c
    of '\t':
      len += tabWidthAt(len, tabWidth)
    of ' ':
      len += 1
    else:
      break
  return len div indentWidth

proc indentForNewLine*(
  languageConfig: Option[TextLanguageConfig],
  line: string,
  indentStyle: IndentStyle,
  tabWidth: int,
  column: int,
): string =
  let indentWidth = indentStyle.indentWidth(tabWidth)
  var indentLevel = indentLevelForLine(line, tabWidth, indentWidth)

  if line.len > 0 and languageConfig.getSome(languageConfig):
    for suffix in languageConfig.indentAfter:
      if line[0..<column].endsWith(suffix):
        inc indentLevel
        break

  return indentStyle.getString.repeat(indentLevel)