import std/[options]

type
  TextLanguageConfig* = ref object
    tabWidth*: int
    indentAfter*: seq[string]
    lineComment*: Option[string]
    blockComment*: Option[(string, string)]

