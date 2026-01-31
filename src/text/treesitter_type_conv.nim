import nimsumtree/rope
import treesitter_types
export treesitter_types
from scripting_api import Cursor, Selection

proc toPoint*(p: TSPoint): Point = point(p.row, p.column)
proc toRange*(r: TSRange): Range[Point] = r.first.toPoint...r.last.toPoint

proc toTsPoint*(p: Point): TSPoint = tsPoint(p.row.int, p.column.int)
proc toTsRange*(r: Range[Point]): TSRange = tsRange(r.a.toTsPoint, r.b.toTsPoint)

proc tsPoint*(cursor: Point): TSPoint = TSPoint(row: cursor.row.int, column: cursor.column.int)
proc tsRange*(selection: Range[Point]): TSRange = TSRange(first: tsPoint(selection.a), last: tsPoint(selection.b))
proc toCursor*(point: TSPoint): Cursor = (point.row, point.column)
proc toSelection*(rang: TSRange): scripting_api.Selection = (rang.first.toCursor, rang.last.toCursor)
