when defined(js):
  import std/jsre
  export jsre

  type Regex* = object
    impl: RegExp

  proc findBoundsJs*(self: RegExp; pattern: cstring): seq[int] {.importjs: "((#.exec(#)) || {indices: [[-1, 0]]}).indices[0]".}

  proc findBounds*(text: string, regex: Regex, start: int): tuple[first: int, last: int] =
    regex.impl.lastIndex = 0
    let bounds = regex.impl.findBoundsJs(text[start..^1].cstring)
    return (bounds[0], bounds[1] - 1)

  proc matchLenJs*(self: RegExp; pattern: cstring): int {.importjs: "((#.exec(#)) || {index:-1}).index".}

  proc matchLen*(text: string, regex: Regex, start: int): int =
    regex.impl.lastIndex = 0
    regex.impl.matchLenJs(text[start..^1].cstring)

  proc re*(text: string): Regex =
    return Regex(impl: newRegExp(text.cstring, "dg"))

else:
  import std/re
  export re