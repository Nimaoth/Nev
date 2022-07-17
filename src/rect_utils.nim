import std/[macros, strformat, strutils]
import bumpy

type
  MeasurementKind* = enum
    Relative,
    Absolute
  Measurement* = object
    case kind: MeasurementKind
    of Relative: rel: float32
    of Absolute: abs: float32

proc relative*(value: float32): Measurement =
  return Measurement(kind: Relative, rel: value)

proc absolute*(value: float32): Measurement =
  return Measurement(kind: Absolute, abs: value)

proc value*(m: Measurement): float32 =
  case m.kind:
  of Relative:
    return m.rel
  of Absolute:
    return m.abs

macro case_measurement*(m: Measurement, n: varargs[untyped]): untyped =
  var matchcase = newTree nnkCaseStmt
  matchcase.add quote do: `m`.kind

  for elem in n:
    case elem.kind:
      of nnkOfBranch:
        let bindedVar = ident $elem[0][1]
        let body = elem[1]
        let ofBranch = newTree nnkOfBranch
        ofBranch.add elem[0][0]
        ofBranch.add quote do:
          let `bindedVar` = `m`.value
          `body`
        matchcase.add ofBranch

      of nnkElifBranch, nnkElse:
        matchcase.add elem
      else:
        discard

  # echo matchcase.treeRepr
  # echo matchcase.repr
  result = matchcase

proc apply*(m: Measurement, a, b: float32): float32 =
  case_measurement m:
  of Relative(v):
    return a + v * (b - a)
  of Absolute(v):
    return a + v

proc splitH*(r: Rect, y: Measurement): tuple[a, b: Rect] =
  result.a = r
  result.b = r
  result.a.h = y.apply(0, r.h)
  result.b.y = result.a.y + result.a.h
  result.b.h = result.b.h - result.a.h

proc splitHInv*(r: Rect, y: Measurement): tuple[a, b: Rect] =
  let temp = r.splitH(y)
  result = (temp[1], temp[0])

proc splitV*(r: Rect, x: Measurement): tuple[a, b: Rect] =
  result.a = r
  result.b = r
  result.a.w = x.apply(0, r.w)
  result.b.x = result.a.x + result.a.w
  result.b.w = result.b.w - result.a.w

proc splitVInv*(r: Rect, x: Measurement): tuple[a, b: Rect] =
  let temp = r.splitV(x)
  result = (temp[1], temp[0])

proc shrink*(r: Rect, amount: Measurement): Rect =
  let x = amount.apply(0, r.w)
  let y = amount.apply(0, r.h)
  return rect(r.x + x, r.y + y, r.w - x - x, r.h - y - y)