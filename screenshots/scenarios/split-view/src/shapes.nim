import std/[strutils, sequtils]

type
  Shape = object
    name: string
    sides: int

proc describe(shape: Shape): string =
  ## Returns a short description of the shape.
  if shape.sides == 0:
    return shape.name & " (round)"
  shape.name & " with " & $shape.sides & " sides"

when isMainModule:
  let shapes = @[
    Shape(name: "circle", sides: 0),
    Shape(name: "triangle", sides: 3),
    Shape(name: "square", sides: 4),
  ]
  for shape in shapes:
    echo shape.describe()
  echo shapes.mapIt(it.sides).foldl(a + b)
