import std/[options, json]
import misc/[myjsonutils]

type
  TextLanguageConfig* = ref object
    tabWidth*: int = 4
    indentAfter*: seq[string]
    lineComment*: Option[string]
    blockComment*: Option[(string, string)]
    ignoreContextLinePrefix*: Option[string]

proc fromJsonHook*(self: var TextLanguageConfig, node: JsonNode, opt = Joptions()) =
  if self.isNil:
    new self
  try:
    if node.hasKey("tabWidth"):
      self.tabWidth = node["tabWidth"].num.int
    else:
      self.tabWidth = 4

    if node.hasKey("indentAfter"):
      let arr = node["indentAfter"]
      self.indentAfter = newSeqOfCap[string](arr.len)
      for i in arr:
        self.indentAfter.add i.str
    else:
      self.indentAfter = @[":", "=", "(", "{", "["]

    if node.hasKey("lineComment"):
      self.lineComment = node["lineComment"].str.some
    else:
      self.lineComment = string.none

    if node.hasKey("blockComment"):
      self.blockComment = (node["blockComment"][0].str, node["blockComment"][1].str).some
    else:
      self.blockComment = (string, string).none

    if node.hasKey("ignoreContextLinePrefix"):
      self.ignoreContextLinePrefix = node["ignoreContextLinePrefix"].str.some
    else:
      self.ignoreContextLinePrefix = string.none
  except CatchableError:
    discard