import std/[tables, options]
import misc/[custom_async, array_view, arena]
import treesitter/api as ts

type TSQuery* = ref object
  impl*: ptr ts.TSQuery

type TSLanguage* = ref object
  languageId*: string
  impl*: ptr ts.TSLanguage
  queries*: Table[string, Option[TSQuery]]
  queryFutures*: Table[string, Future[Option[TSQuery]]]

type TSParser* = object
  impl*: ptr ts.TSParser

type TsTree* = object
  impl*: ptr ts.TSTree

type TSNode* = object
  impl*: ts.TSNode

type TSQueryCapture* = object
  name*: cstring
  node*: TSNode

type TSQueryMatch* = object
  pattern*: int
  captures*: ArrayView[TSQueryCapture]

type TSPredicateResultOperand* = object
  name*: cstring
  `type`*: cstring

type TSPredicateResult* = object
  operator*: cstring
  operands*: ArrayView[TSPredicateResultOperand]

type TSPoint* = object
  row*: int
  column*: int

type TSRange* = object of RootObj
  first*: TSPoint
  last*: TSPoint

type TSInputEdit* = object
  startIndex*: int
  oldEndIndex*: int
  newEndIndex*: int
  startPosition*: TSPoint
  oldEndPosition*: TSPoint
  newEndPosition*: TSPoint

type TSTreeCursor* = object
  valid: bool
  impl*: ts.TSTreeCursor

func `=copy`*(a: var TSTreeCursor, b: TSTreeCursor) {.error.}
func `=dup`*(a: TSTreeCursor): TSTreeCursor {.error.}

func `=destroy`*(t: TSTreeCursor) {.raises: [].} =
  if t.valid:
    ts.tsTreeCursorDelete(t.impl.addr)

proc initTreeCursor*(node: TSNode): TSTreeCursor =
  var cursor = ts.tsTreeCursorNew(node.impl)
  result = TSTreeCursor(impl: cursor, valid: true)

func `=destroy`(t: TsTree) {.raises: [].} = discard

func setLanguage*(self: TSParser, language: TSLanguage): bool =
  return ts.tsParserSetLanguage(self.impl, language.impl)

func isNil*(self: TSParser): bool = self.impl.isNil
func isNil*(self: TSTree): bool = self.impl.isNil

proc clone*(self: TSTree): TSTree =
  assert not self.isNil
  return TSTree(impl: ts.tsTreeCopy(self.impl))

proc delete*(self: var TSTree) =
  if self.impl != nil:
    ts.tsTreeDelete(self.impl)
  self.impl = nil

proc delete*(self: sink TSTree) =
  if self.impl != nil:
    ts.tsTreeDelete(self.impl)

proc deinit*(self: TSParser) =
  ts.tsParserDelete(self.impl)

proc deinit*(self: TSQuery) =
  ts.tsQueryDelete(self.impl)

when defined(mallocImport):
  proc c_free(p: pointer): void {.importc: "host_free", header: "<stdlib.h>", used.}
else:
  proc c_free(p: pointer): void {.importc: "free", header: "<stdlib.h>", used.}

func toTsPoint*(point: TSPoint): ts.TSPoint = ts.TSPoint(row: point.row.uint32, column: point.column.uint32)
proc len*(node: TSNode): int = node.impl.tsNodeChildCount().int
proc high*(node: TSNode): int = node.len - 1
proc low*(node: TSNode): int = 0
proc startByte*(node: TSNode): int = node.impl.tsNodeStartByte.int
proc endByte*(node: TSNode): int = node.impl.tsNodeEndByte.int
proc startPoint*(node: TSNode): TSPoint =
  let point = node.impl.tsNodeStartPoint
  return TSPoint(row: point.row.int, column: point.column.int)
proc endPoint*(node: TSNode): TSPoint =
  let point = node.impl.tsNodeEndPoint
  return TSPoint(row: point.row.int, column: point.column.int)
proc getRange*(node: TSNode): TSRange = TSRange(first: node.startPoint, last: node.endPoint)
proc tsPoint*(line: int, column: int): TSPoint = TSPoint(row: line, column: column)
proc tsRange*(first: TSPoint, last: TSPoint): TSRange = TSRange(first: first, last: last)

proc root*(tree: TSTree): TSNode = TSNode(impl: tree.impl.tsTreeRootNode)
proc edit*(self: TSTree, edit: TSInputEdit): TSTree =
  var tsEdit = ts.TSInputEdit(
    startByte: edit.startIndex.uint32,
    oldEndByte: edit.oldEndIndex.uint32,
    newEndByte: edit.newEndIndex.uint32,
    startPoint: edit.startPosition.toTsPoint,
    oldEndPoint: edit.oldEndPosition.toTsPoint,
    newEndPoint: edit.newEndPosition.toTsPoint,
  )
  self.impl.tsTreeEdit(addr tsEdit)
  return self

proc execute*(cursor: ptr ts.TSQueryCursor, query: TSQuery, node: TSNode) = cursor.tsQueryCursorExec(query.impl, node.impl)
proc prev*(node: TSNode): Option[TSNode] =
  let other = node.impl.tsNodePrevSibling
  if not other.tsNodeIsNull:
    result = TSNode(impl: other).some
proc next*(node: TSNode): Option[TSNode] =
  let other = node.impl.tsNodeNextSibling
  if not other.tsNodeIsNull:
    result = TSNode(impl: other).some
proc prevNamed*(node: TSNode): Option[TSNode] =
  let other = node.impl.tsNodePrevNamedSibling
  if not other.tsNodeIsNull:
    result = TSNode(impl: other).some
proc nextNamed*(node: TSNode): Option[TSNode] =
  let other = node.impl.tsNodeNextNamedSibling
  if not other.tsNodeIsNull:
    result = TSNode(impl: other).some

proc `[]`*(node: TSNode, index: int): TSNode = TSNode(impl: node.impl.tsNodeChild(index.uint32))
proc descendantForRange*(node: TSNode, rang: TSRange): TSNode = TSNode(impl: ts.tsNodeDescendantForPointRange(node.impl, rang.first.toTsPoint, rang.last.toTsPoint))
proc parent*(node: TSNode): TSNode = TSNode(impl: node.impl.tsNodeParent())
proc `==`*(a: TSNode, b: TSNode): bool = a.impl.tsNodeEq(b.impl)
proc nodeType*(node: TSNode): string = $tsNodeType(node.impl)
proc symbol*(node: TSNode): ts.TSSymbol = tsNodeSymbol(node.impl)
proc isNull*(node: TSNode): bool = tsNodeIsNull(node.impl)
proc isNamed*(node: TSNode): bool = tsNodeIsNamed(node.impl)
# proc path*(node: TSNode): seq[int] =
#   var n = node

proc currentNode*(cursor: var ts.TSTreeCursor): TSNode = TSNode(impl: tsTreeCursorCurrentNode(addr cursor))
proc reset*(cursor: var ts.TSTreeCursor, node: TSNode) = tsTreeCursorReset(addr cursor, node.impl)
proc gotoParent*(cursor: var ts.TSTreeCursor): bool = tsTreeCursorGotoParent(addr cursor)
proc gotoPreviousSibling*(cursor: var ts.TSTreeCursor): bool = tsTreeCursorGotoPreviousSibling(addr cursor)
proc gotoNextSibling*(cursor: var ts.TSTreeCursor): bool = tsTreeCursorGotoNextSibling(addr cursor)
proc gotoFirstChild*(cursor: var ts.TSTreeCursor): bool = tsTreeCursorGotoFirstChild(addr cursor)
proc gotoLastChild*(cursor: var ts.TSTreeCursor): bool = tsTreeCursorGotoLastChild(addr cursor)
proc gotoDescendant*(cursor: var ts.TSTreeCursor, index: Natural): bool = tsTreeCursorGotoDescendant(addr cursor, index.uint32)
proc currentDescendantIndex*(cursor: var ts.TSTreeCursor): int = tsTreeCursorCurrentDescendantIndex(addr cursor).int
proc currentDepth*(cursor: var ts.TSTreeCursor): int = tsTreeCursorCurrentDepth(addr cursor).int
proc currentFieldName*(cursor: var ts.TSTreeCursor): cstring = tsTreeCursorCurrentFieldName(addr cursor)
proc currentFieldId*(cursor: var ts.TSTreeCursor): ts.TSFieldId = tsTreeCursorCurrentFieldId(addr cursor)

proc currentNode*(cursor: var TSTreeCursor): TSNode = currentNode(cursor.impl)
proc reset*(cursor: var TSTreeCursor, node: TSNode) = reset(cursor.impl, node)
proc gotoParent*(cursor: var TSTreeCursor): bool = gotoParent(cursor.impl)
proc gotoPreviousSibling*(cursor: var TSTreeCursor): bool = gotoPreviousSibling(cursor.impl)
proc gotoNextSibling*(cursor: var TSTreeCursor): bool = gotoNextSibling(cursor.impl)
proc gotoFirstChild*(cursor: var TSTreeCursor): bool = gotoFirstChild(cursor.impl)
proc gotoLastChild*(cursor: var TSTreeCursor): bool = gotoLastChild(cursor.impl)
proc gotoDescendant*(cursor: var TSTreeCursor, index: Natural): bool = gotoDescendant(cursor.impl, index.uint32)
proc currentDescendantIndex*(cursor: var TSTreeCursor): int = currentDescendantIndex(cursor.impl).int
proc currentDepth*(cursor: var TSTreeCursor): int = currentDepth(cursor.impl).int
proc currentFieldName*(cursor: var TSTreeCursor): cstring = currentFieldName(cursor.impl)
proc currentFieldId*(cursor: var TSTreeCursor): ts.TSFieldId = currentFieldId(cursor.impl)

proc setPointRange*(cursor: ptr ts.TSQueryCursor, rang: TSRange) =
  discard cursor.tsQueryCursorSetPointRange(rang.first.toTsPoint, rang.last.toTsPoint)

proc getCaptureName*(query: TSQuery, index: uint32): string =
  var length: uint32
  var str = ts.tsQueryCaptureNameForId(query.impl, index, addr length)
  defer: assert result.len == length.int
  return $str

proc getCaptureNameC*(query: TSQuery, index: uint32): cstring =
  var length: uint32
  var str = ts.tsQueryCaptureNameForId(query.impl, index, addr length)
  defer: assert result.len == length.int
  return str

proc getStringValue*(query: TSQuery, index: uint32): string =
  var length: uint32
  var str = ts.tsQueryStringValueForId(query.impl, index, addr length)
  defer: assert result.len == length.int
  return $str

proc getStringValueC*(query: TSQuery, index: uint32): cstring =
  var length: uint32
  var str = ts.tsQueryStringValueForId(query.impl, index, addr length)
  defer: assert result.len == length.int
  return str

proc nextMatch*(cursor: ptr ts.TSQueryCursor, query: TSQuery): Option[ts.TSQueryMatch] =
  result = ts.TSQueryMatch.none
  var match: ts.TSQueryMatch
  if cursor.tsQueryCursorNextMatch(addr match):
    when defined(vcc):
      {.emit: ["Result->has = NIM_TRUE; Result->val = ", match, ";"].}
    else:
      result = match.some

proc nextCapture*(cursor: ptr ts.TSQueryCursor): Option[tuple[match: ts.TSQueryMatch, captureIndex: int]] =
  var match: ts.TSQueryMatch
  var index: uint32
  if cursor.tsQueryCursorNextCapture(addr match, addr index):
    result = (match, index.int).some

proc `$`*(node: ts.TSNode): string =
  # debugf"$node: {node.context}, {(cast[uint64](node.id)):x}, {(cast[uint64](node.tree)):x}"
  let c_str = node.tsNodeString()
  defer: c_str.c_free
  result = $c_str

var scratchQueryCursor {.threadvar.}: ptr ts.TSQueryCursor
iterator matches*(self: TSQuery, node: TSNode, rang: TSRange, arena: var Arena): TSQueryMatch =
  if scratchQueryCursor == nil:
    scratchQueryCursor = ts.tsQueryCursorNew()
  let cursor = scratchQueryCursor
  # let cursor = ts.tsQueryCursorNew()
  # defer:
  #   ts.tsQueryCursorDelete(cursor)

  cursor.setPointRange rang
  cursor.execute(self, node)

  var match = cursor.nextMatch(self)
  while match.isSome:
    var m = TSQueryMatch(
      pattern: match.get.patternIndex.int,
      captures: arena.allocEmptyArray(match.get.capture_count.int, TSQueryCapture),
    )
    let capturesRaw = cast[ptr array[100000, ts.TSQueryCapture]](match.get.captures)
    for k in 0..<match.get.capture_count.int:
      if m.captures.len == m.captures.cap:
        continue
      m.captures.add(TSQueryCapture(name: self.getCaptureNameC(capturesRaw[k].index), node: TSNode(impl: capturesRaw[k].node)))

    yield m
    match = cursor.nextMatch(self)

proc predicatesForPattern*(self: TSQuery, patternIndex: int, arena: var Arena): ArrayView[TSPredicateResult] =
  var predicatesLength: uint32 = 0
  let predicatesPtr = ts.tsQueryPredicatesForPattern(self.impl, patternIndex.uint32, addr predicatesLength)
  let predicatesRaw = cast[ptr array[100000, ts.TSQueryPredicateStep]](predicatesPtr)

  var argIndex = 0
  var predicateName: cstring = "".cstring
  var predicateArgs: ArrayView[cstring] = arena.allocEmptyArray(20, cstring)

  result = arena.allocEmptyArray(predicatesLength.int, TSPredicateResult)

  for k in 0..<predicatesLength:
    case predicatesRaw[k].`type`:
    of ts.TSQueryPredicateStepTypeString:
      let value = self.getStringValueC(predicatesRaw[k].valueId)
      if argIndex == 0:
        predicateName = value
      else:
        predicateArgs.add value
      argIndex += 1

    of ts.TSQueryPredicateStepTypeCapture:
      predicateArgs.add self.getCaptureNameC(predicatesRaw[k].valueId)
      argIndex += 1

    of ts.TSQueryPredicateStepTypeDone:
      if predicateArgs.len mod 2 == 0:
        var predicateOperands = arena.allocEmptyArray(predicateArgs.len div 2, TSPredicateResultOperand)
        for i in 0..<(predicateArgs.len div 2):
          predicateOperands.add TSPredicateResultOperand(name: predicateArgs[i * 2], `type`: predicateArgs[i * 2 + 1])
        result.add (TSPredicateResult(operator: predicateName, operands: predicateOperands))
      predicateName = ""
      predicateArgs.setLen 0
      argIndex = 0
