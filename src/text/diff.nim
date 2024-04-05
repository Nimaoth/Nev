
type
  LineMapping* = object
    source*: tuple[first: int, last: int]
    target*: tuple[first: int, last: int]
    lines*: seq[string]