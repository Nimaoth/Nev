import std/[sequtils, strutils]
import custom_unicode

type IdentifierCase* = enum Camel, Pascal, Kebab, Snake, ScreamingSnake

proc splitCase*(s: string): tuple[cas: IdentifierCase, parts: seq[string]] =
  if s == "":
    return (IdentifierCase.Camel, @[])

  if s.find('_') != -1:
    result.cas = IdentifierCase.Snake
    result.parts = s.split('_').mapIt(custom_unicode.toLower(it))
    for r in s.runes:
      if r != '_'.Rune and not r.isLower:
        result.cas = IdentifierCase.ScreamingSnake
        break

  elif s.find('-') != -1:
    result.cas = IdentifierCase.Kebab
    result.parts = s.split('-').mapIt(custom_unicode.toLower(it))
  else:
    if s[0].isUpperAscii:
      result.cas = IdentifierCase.Pascal
    else:
      result.cas = IdentifierCase.Camel

    result.parts.add ""
    for r in s.runes:
      if not r.isLower and result.parts[^1].len > 0:
        result.parts.add ""
      result.parts[^1].add(custom_unicode.toLower(r))

proc joinCase*(parts: seq[string], cas: IdentifierCase): string =
  if parts.len == 0:
    return ""
  case cas
  of IdentifierCase.Camel:
    parts[0] & parts[1..^1].mapIt(it.capitalize).join("")
  of IdentifierCase.Pascal:
    parts.mapIt(it.capitalize).join("")
  of IdentifierCase.Kebab:
    parts.join("-")
  of IdentifierCase.Snake:
    parts.join("_")
  of IdentifierCase.ScreamingSnake:
    parts.mapIt(custom_unicode.toUpper(it)).join("_")

proc cycleCase*(s: string): string =
  if s.len == 0:
    return s
  let (cas, parts) = s.splitCase()
  let nextCase = if cas == IdentifierCase.high:
    IdentifierCase.low
  else:
    cas.succ
  return parts.joinCase(nextCase)
