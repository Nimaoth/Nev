when defined(js):
  import std/jsre
  export jsre

  type Regex* = object
    impl: RegExp

  proc findBoundsJs*(self: RegExp; pattern: cstring): seq[int] {.importjs: "((#.exec(#)) || {indices: [[-1, 0]]}).indices[0]".}

  proc findBounds*(text: string, regex: Regex, start: int): tuple[first: int, last: int] =
    regex.impl.lastIndex = 0
    let bounds = regex.impl.findBoundsJs(text[start..^1].cstring)
    result = (bounds[0], bounds[1] - 1)
    if result.first != -1:
      result.first += start
      result.last += start

  proc matchLenJs*(self: RegExp; pattern: cstring): int {.importjs: "((#.exec(#)) || {index:-1}).index".}

  proc matchLen*(text: string, regex: Regex, start: int): int =
    regex.impl.lastIndex = 0
    result = regex.impl.matchLenJs(text[start..^1].cstring)
    if result != -1:
      result += start

  proc match*(text: string, regex: Regex, start: int): bool =
    return text.matchLen(regex, start) != -1

  proc re*(text: string): Regex =
    return Regex(impl: newRegExp(text.cstring, "dg"))

else:
  import std/re
  export re