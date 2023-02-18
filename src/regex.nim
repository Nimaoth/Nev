when defined(js):
  import std/jsre
  export jsre

  type Regex* = object
    discard

  proc findBounds*(text: string, regex: Regex, start: int): tuple[first: int, last: int] =
    discard

  proc matchLen*(text: string, regex: Regex, start: int): int =
    discard

  proc re*(text: string): Regex =
    discard

else:
  import std/re
  export re