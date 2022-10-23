import std/[macros]
import bumpy, boxy

type
  MeasurementKind* = enum
    Relative
    Absolute
    Percent
  Measurement* = object
    case kind: MeasurementKind
    of Relative: rel: float32
    of Absolute: abs: float32
    of Percent: per: float32

proc relative*(value: float32): Measurement =
  return Measurement(kind: Relative, rel: value)

proc absolute*(value: float32): Measurement =
  return Measurement(kind: Absolute, abs: value)

proc percent*(value: float32): Measurement =
  return Measurement(kind: Percent, per: value)

proc value*(m: Measurement): float32 =
  case m.kind:
  of Relative:
    return m.rel
  of Absolute:
    return m.abs
  of Percent:
    return m.per

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
    return a + v
  of Absolute(v):
    return v
  of Percent(v):
    return a + v * (b - a)

proc splitH*(r: Rect, y: Measurement): tuple[a, b: Rect] =
  result.a = r
  result.b = r
  # result.a.h = y.apply(0, r.h)
  result.a.h = y.apply(r.y, r.y + r.h) - r.y
  result.b.y = result.a.y + result.a.h
  result.b.h = result.b.h - result.a.h

proc splitHInv*(r: Rect, y: Measurement): tuple[a, b: Rect] =
  result.a = r
  result.b = r
  result.a.h = r.h - (y.apply(r.y, r.y + r.h) - r.y)
  result.b.y = result.a.y + result.a.h
  result.b.h = result.b.h - result.a.h

proc splitV*(r: Rect, x: Measurement): tuple[a, b: Rect] =
  result.a = r
  result.b = r
  # result.a.w = x.apply(0, r.w)
  result.a.w = x.apply(r.x, r.x + r.w) - r.x
  result.b.x = result.a.x + result.a.w
  result.b.w = result.b.w - result.a.w

proc splitVInv*(r: Rect, x: Measurement): tuple[a, b: Rect] =
  result.a = r
  result.b = r
  result.a.w = r.w - (x.apply(r.x, r.x + r.w) - r.x)
  result.b.x = result.a.x + result.a.w
  result.b.w = result.b.w - result.a.w

proc shrink*(r: Rect, amount: Measurement): Rect =
  let x = amount.apply(0, r.w)
  let y = amount.apply(0, r.h)
  return rect(r.x + x, r.y + y, r.w - x - x, r.h - y - y)

proc shrink*(r: Rect, amountX: Measurement, amountY: Measurement): Rect =
  let x = amountX.apply(0, r.w)
  let y = amountY.apply(0, r.h)
  return rect(r.x + x, r.y + y, r.w - x - x, r.h - y - y)

proc shrink*(r: Rect, amount: Vec2): Rect =
  let x = amount.x
  let y = amount.y
  return rect(r.x + x, r.y + y, r.w - x - x, r.h - y - y)

proc grow*(r: Rect, amount: Measurement): Rect =
  let x = amount.apply(0, r.w)
  let y = amount.apply(0, r.h)
  return rect(r.x - x, r.y - y, r.w + x + x, r.h + y + y)

proc grow*(r: Rect, amountX: Measurement, amountY: Measurement): Rect =
  let x = amountX.apply(0, r.w)
  let y = amountY.apply(0, r.h)
  return rect(r.x - x, r.y - y, r.w + x + x, r.h + y + y)

proc grow*(r: Rect, amount: Vec2): Rect =
  let x = amount.x
  let y = amount.y
  return rect(r.x - x, r.y - y, r.w + x + x, r.h + y + y)

proc `+`*(a: Rect, b: Vec2): Rect =
  result.x = a.x + b.x
  result.y = a.y + b.y
  result.w = a.w
  result.h = a.h

proc `-`*(a: Rect, b: Vec2): Rect =
  result.x = a.x - b.x
  result.y = a.y - b.y
  result.w = a.w
  result.h = a.h

template xw*(r: Rect): float32 = r.x + r.w
template yh*(r: Rect): float32 = r.y + r.h
template xwyh*(r: Rect): Vec2 = vec2(r.xw, r.yh)
template xwy*(r: Rect): Vec2 = vec2(r.xw, r.y)
template xyh*(r: Rect): Vec2 = vec2(r.x, r.yh)
template xyRect*(r: Rect): Rect = rect(r.x, r.y, 0, 0)
template whRect*(r: Rect): Rect = rect(0, 0, r.w, r.h)

proc intersects*(a, b: Rect): bool =
  let intersection = a and b
  return intersection.w > 0 and intersection.h > 0

proc contains*(a: Rect, b: Vec2): bool =
  return b.x >= a.x and b.x <= a.xw and b.y >= a.y and b.y <= a.yh