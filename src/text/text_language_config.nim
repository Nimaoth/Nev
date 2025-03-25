import std/[options, json]
import misc/[myjsonutils, regex, custom_logger, util, jsonex]

logCategory "language-config"

type
  TextLanguageConfig* = ref object
    tabWidth*: Option[int]
    indentAfter*: seq[string]
    lineComment*: Option[string]
    blockComment*: Option[(string, string)]
    ignoreContextLinePrefix*: Option[string]
    ignoreContextLineRegex*: Option[Regex]
    completionWordChars*: set[char] = {'a'..'z', 'A'..'Z', '0'..'9', '_'}

proc fromJsonExHook*(self: var TextLanguageConfig, node: JsonNodeEx, opt = Joptions()) =
  if self.isNil:
    new self
  try:
    if node.hasKey("tabWidth"):
      self.tabWidth = node["tabWidth"].num.int.some

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

    if node.hasKey("ignoreContextLineRegex"):
      self.ignoreContextLineRegex = re(node["ignoreContextLineRegex"].str).some.catch:
        Regex.none
    else:
      self.ignoreContextLineRegex = Regex.none

    if node.hasKey("completionWordChars"):
      self.completionWordChars = {}
      for s in node["completionWordChars"]:
        if s.kind == JString:
          self.completionWordChars.incl s.str[0]
        if s.kind == JArray:
          self.completionWordChars.incl {s[0].str[0]..s[1].str[0]}

  except CatchableError:
    log lvlError, &"Failed to parse language config: {getCurrentExceptionMsg()}:\n{node}"