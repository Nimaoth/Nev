import nimsumtree/rope
import treesitter_types
export treesitter_types

proc toPoint*(p: TSPoint): Point = point(p.row, p.column)
proc toRange*(r: TSRange): Range[Point] = r.first.toPoint...r.last.toPoint

proc toTsPoint*(p: Point): TSPoint = tsPoint(p.row.int, p.column.int)
proc toTsRange*(r: Range[Point]): TSRange = tsRange(r.a.toTsPoint, r.b.toTsPoint)
