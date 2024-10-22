import std/[options, json, tables]
import misc/[custom_logger, custom_async, util, custom_unicode]
import vfs

from scripting_api import Cursor, Selection, byteIndexToCursor

{.push stacktrace:off.}
{.push linetrace:off.}

logCategory "treesitter"

import std/dynlib
import treesitter/api as ts

import compilation_config

import nimwasmtime

when useBuiltinTreesitterLanguage("nim"):
  import treesitter_nim/treesitter_nim/nim
when useBuiltinTreesitterLanguage("cpp"):
  import treesitter_cpp/treesitter_cpp/cpp
when useBuiltinTreesitterLanguage("zig"):
  import treesitter_zig/treesitter_zig/zig
when useBuiltinTreesitterLanguage("agda"):
  import treesitter_agda/treesitter_agda/agda
when useBuiltinTreesitterLanguage("bash"):
  import treesitter_bash/treesitter_bash/bash
when useBuiltinTreesitterLanguage("c"):
  import treesitter_c/treesitter_c/c
when useBuiltinTreesitterLanguage("csharp"):
  import treesitter_c_sharp/treesitter_c_sharp/c_sharp
when useBuiltinTreesitterLanguage("css"):
  import treesitter_css/treesitter_css/css
when useBuiltinTreesitterLanguage("go"):
  import treesitter_go/treesitter_go/go
when useBuiltinTreesitterLanguage("haskell"):
  import treesitter_haskell/treesitter_haskell/haskell
when useBuiltinTreesitterLanguage("html"):
  import treesitter_html/treesitter_html/html
when useBuiltinTreesitterLanguage("java"):
  import treesitter_java/treesitter_java/java
when useBuiltinTreesitterLanguage("javascript"):
  import treesitter_javascript/treesitter_javascript/javascript
when useBuiltinTreesitterLanguage("ocaml"):
  import treesitter_ocaml/treesitter_ocaml/ocaml
when useBuiltinTreesitterLanguage("php"):
  import treesitter_php/treesitter_php/php
when useBuiltinTreesitterLanguage("python"):
  import treesitter_python/treesitter_python/python
when useBuiltinTreesitterLanguage("ruby"):
  import treesitter_ruby/treesitter_ruby/ruby
when useBuiltinTreesitterLanguage("rust"):
  import treesitter_rust/treesitter_rust/rust
when useBuiltinTreesitterLanguage("scala"):
  import treesitter_scala/treesitter_scala/scala
when useBuiltinTreesitterLanguage("typescript"):
  import treesitter_typescript/treesitter_typescript/typescript
when useBuiltinTreesitterLanguage("json"):
  import treesitter_json/treesitter_json/json

type TSQuery* = ref object
  impl: ptr ts.TSQuery

type TSLanguage* = ref object
  languageId: string
  impl: ptr ts.TSLanguage
  queries: Table[string, Option[TSQuery]]
  queryFutures: Table[string, Future[Option[TSQuery]]]

type TSParser* = object
  impl: ptr ts.TSParser

type TsTree* = object
  impl: ptr ts.TSTree

type TSNode* = object
  impl: ts.TSNode

type TSQueryCapture* = object
  name*: string
  node*: TSNode

type TSQueryMatch* = ref object
  pattern*: int
  captures*: seq[TSQueryCapture]

type TSPredicateResultOperand* = object
  name*: string
  `type`*: string

type TSPredicateResult* = object
  operator*: string
  operands*: seq[TSPredicateResultOperand]

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

type TSLanguageCtor = proc(): ptr ts.TSLanguage {.stdcall.}

func `=destroy`(t: TsTree) {.raises: [].} = discard

func setLanguage*(self: TSParser, language: TSLanguage) =
  assert ts.tsParserSetLanguage(self.impl, language.impl)

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

proc query*(self: TSLanguage, id: string, source: string, cacheOnFail = true):
    Future[Option[TSQuery]] {.async.} =

  if self.queries.contains(id):
    return self.queries[id]

  logScope lvlInfo, &"Create '{id}' query for {self.languageId}"

  var errorOffset: uint32 = 0
  var queryError: ts.TSQueryError = ts.TSQueryErrorNone
  # todo: can we call tsQueryNew in a separate thread?
  let query = TSQuery(impl: self.impl.tsQueryNew(source.cstring, source.len.uint32, addr errorOffset, addr queryError))

  if queryError != ts.TSQueryErrorNone:
    log lvlError, &"Failed to load highlights query: {errorOffset} {source.byteIndexToCursor(errorOffset.int)}: {queryError}\n{source}"
    if cacheOnFail:
      self.queries[id] = TSQuery.none
    return TSQuery.none

  query.some

proc queryFileImpl(self: TSLanguage, vfs: VFS, id: string, path: string, cacheOnFail = true): Future[Option[TSQuery]] {.async.} =
  try:
    let queryString = await vfs.read(path)
    return await self.query(id, queryString, cacheOnFail)
  except FileNotFoundError:
    return TSQuery.none
  except IOError as e:
    log lvlError, &"Failed to load query file: {e.msg}"
    return TSQuery.none

proc queryFile*(self: TSLanguage, vfs: VFS, id: string, path: string, cacheOnFail = true): Future[Option[TSQuery]] {.async.} =
  if self.queries.contains(id):
    return self.queries[id]
  if self.queryFutures.contains(id):
    return await self.queryFutures[id]

  let queryFuture = self.queryFileImpl(vfs, id, path, cacheOnFail)
  self.queryFutures[id] = queryFuture

  let query = await queryFuture
  self.queryFutures.del(id)
  self.queries[id] = query
  return query

proc parseString*(self: TSParser, text: string, oldTree: Option[TSTree] = TSTree.none): TSTree =
  let oldTreePtr: ptr ts.TSTree = if oldTree.getSome(tree):
    tree.impl
  else:
    nil
  let tree = self.impl.tsParserParseString(oldTreePtr, text.cstring, text.len.uint32)
  return TSTree(impl: tree)

type GetTextCallback* = proc(index: int, position: Cursor): (ptr char, int)
proc getTextRangeTreesitter(payload: pointer; byteIndex: uint32; position: ts.TSPoint; bytesRead: ptr uint32): cstring {.stdcall.} =

  let callback = cast[ptr GetTextCallback](payload)[]
  let (p, len) = callback(byteIndex.int, (position.row.int, position.column.int))
  bytesRead[] = len.uint32
  return cast[cstring](p)

proc parseCallback*(self: TSParser, oldTree: TSTree, text: GetTextCallback): TSTree =
  let input = TSInput(
    payload: text.addr,
    read: cast[typeof(TSInput().read)](getTextRangeTreesitter),
    encoding: TSInputEncoding.TSInputEncodingUTF8
  )

  let oldTreeImpl = if oldTree.isNotNil:
    oldTree.impl
  else:
    nil

  let tree = self.impl.tsParserParse(oldTreeImpl, input)
  return TSTree(impl: tree)

when not declared(c_malloc):
  proc c_malloc(size: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>", used.}
  proc c_free(p: pointer): void {.importc: "free", header: "<stdlib.h>", used.}

func toTsPoint*(cursor: Cursor, line: openArray[char]): ts.TSPoint = ts.TSPoint(row: cursor.line.uint32, column: line.runeIndex(cursor.column).uint32)
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

proc setPointRange*(cursor: ptr ts.TSQueryCursor, rang: TSRange) =
  cursor.tsQueryCursorSetPointRange(rang.first.toTsPoint, rang.last.toTsPoint)

proc getCaptureName*(query: TSQuery, index: uint32): string =
  var length: uint32
  var str = ts.tsQueryCaptureNameForId(query.impl, index, addr length)
  defer: assert result.len == length.int
  return $str

proc getStringValue*(query: TSQuery, index: uint32): string =
  var length: uint32
  var str = ts.tsQueryStringValueForId(query.impl, index, addr length)
  defer: assert result.len == length.int
  return $str

proc nextMatch(cursor: ptr ts.TSQueryCursor, query: TSQuery): Option[ts.TSQueryMatch] =
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

template withQueryCursor*(cursor: untyped, body: untyped): untyped =
  bind tsQueryCursorNew
  bind tsQueryCursorDelete
  block:
    let cursor = ts.tsQueryCursorNew()
    defer: ts.tsQueryCursorDelete(cursor)
    body

template withTreeCursor*(node: untyped, cursor: untyped, body: untyped): untyped =
  bind tsTreeCursorNew
  bind tsTreeCursorDelete
  block:
    var cursor = ts.tsTreeCursorNew(node.impl)
    defer: ts.tsTreeCursorDelete(cursor.addr)
    body

var scratchQueryCursor: ptr ts.TSQueryCursor = nil

proc matches*(self: TSQuery, node: TSNode, rang: TSRange): seq[TSQueryMatch] =
  result = @[]

  if scratchQueryCursor.isNil:
    scratchQueryCursor = ts.tsQueryCursorNew()
  let cursor = scratchQueryCursor

  cursor.setPointRange rang
  cursor.execute(self, node)

  var match = cursor.nextMatch(self)
  while match.isSome:
    var m = TSQueryMatch(pattern: match.get.patternIndex.int)
    let capturesRaw = cast[ptr array[100000, ts.TSQueryCapture]](match.get.captures)
    for k in 0..<match.get.capture_count.int:
      m.captures.add(TSQueryCapture(name: self.getCaptureName(capturesRaw[k].index), node: TSNode(impl: capturesRaw[k].node)))

    result.add m
    match = cursor.nextMatch(self)

  for m in result:
    for c in m.captures:
      assert not c.node.impl.id.isNil
      assert not c.node.impl.tree.isNil

proc predicatesForPattern*(self: TSQuery, patternIndex: int): seq[TSPredicateResult] =
  var predicatesLength: uint32 = 0
  let predicatesPtr = ts.tsQueryPredicatesForPattern(self.impl, patternIndex.uint32, addr predicatesLength)
  let predicatesRaw = cast[ptr array[100000, ts.TSQueryPredicateStep]](predicatesPtr)

  result = @[]

  var argIndex = 0
  var predicateName: string = ""
  var predicateArgs: seq[string] = @[]

  for k in 0..<predicatesLength:
    case predicatesRaw[k].`type`:
    of ts.TSQueryPredicateStepTypeString:
      let value = self.getStringValue(predicatesRaw[k].valueId)
      if argIndex == 0:
        predicateName = value
      else:
        predicateArgs.add value
      argIndex += 1

    of ts.TSQueryPredicateStepTypeCapture:
      predicateArgs.add self.getCaptureName(predicatesRaw[k].valueId)
      argIndex += 1

    of ts.TSQueryPredicateStepTypeDone:
      if predicateArgs.len mod 2 == 0:
        var predicateOperands: seq[TSPredicateResultOperand] = @[]
        for i in 0..<(predicateArgs.len div 2):
          predicateOperands.add TSPredicateResultOperand(name: predicateArgs[i * 2], `type`: predicateArgs[i * 2 + 1])
        result.add (TSPredicateResult(operator: predicateName, operands: predicateOperands))
      predicateName = ""
      predicateArgs.setLen 0
      argIndex = 0

# Available on all targets

import std/[os, strutils]
var treesitterDllCache = initTable[string, LibHandle]()

var wasmEngine = WasmEngine.new(WasmConfig.new())
var wasmStore: ptr TSWasmStore = nil

import std/macros

proc getLanguageWasmStore(): ptr TSWasmStore =
  if wasmStore == nil:
    var err: TSWasmError
    wasmStore = tsWasmStoreNew(cast[ptr TSWasmEngine](wasmEngine.it), err.addr)
    if err.kind != TSWasmErrorKindNone:
      log lvlError, &"Failed to create wasm store: {err}"
      return nil

  return wasmStore

proc loadLanguageDynamically*(vfs: VFS, languageId: string, config: JsonNode): Future[Option[TSLanguage]] {.async.} =
  try:
    const fileExtension = when defined(windows):
      "dll"
    else:
      "so"

    var candidates: seq[tuple[path: string, ctor: string]] = @[]

    proc addCandidate(path: string) {.gcsafe, async: (raises: []).} =
      let path = "app://" & path
      if vfs.getFileKind(path).await.mapIt(it == FileKind.File).get(false):
        let ctor = if path.endsWith(".wasm"):
          languageId
        else:
          &"tree_sitter_{languageId}"
        candidates.add (path, ctor)

    if config.hasKey("path"):
      await addCandidate config["path"].getStr
    else:
      await addCandidate &"languages/tree-sitter-{languageId}.wasm"
      await addCandidate &"languages/{languageId}.wasm"
      await addCandidate &"languages/tree-sitter-{languageId}.{fileExtension}"
      await addCandidate &"languages/{languageId}.{fileExtension}"

    for (path, ctorSymbolName) in candidates:
      log lvlInfo, &"Trying to load treesitter from '{path}' using function '{ctorSymbolName}'"

      if path.endsWith(".wasm"):
        let wasmStore = getLanguageWasmStore()
        if wasmStore == nil:
          continue

        let wasmBytes = try:
          let wasmBytes = await vfs.read(path, {Binary})
          if wasmBytes.len == 0:
            log lvlError, &"Failed to load wasm file {path}"
            continue
          wasmBytes
        except IOError as e:
          log lvlError, &"Failed to load wasm file {path}: {e.msg}"
          continue

        logScope lvlInfo, &"Create wasm language from module for {languageId}"

        # proc loadLanguageThread(args: (ptr TSWasmStore, cstring, cstring, uint32, ptr TSWasmError)): ptr ts.TSLanguage {.thread.} =
        #   tsWasmStoreLoadLanguage(args[0], args[1], args[2], args[3], args[4])

        var err: TSWasmError
        let language = block:
          logScope lvlDebug, &"tsWasmStoreLoadLanguage {languageId}"
          # todo: load in separate thread
          # let res = await spawnAsync(loadLanguageThread, (wasmStore, ctorSymbolName.cstring, wasmBytes.cstring, wasmBytes.len.uint32, err.addr))
          # res
          tsWasmStoreLoadLanguage(wasmStore, ctorSymbolName.cstring, wasmBytes.cstring, wasmBytes.len.uint32, err.addr)

        if err.kind != TSWasmErrorKindNone:
          log lvlError, &"Failed to create wasm language: {err}"
          continue

        if language == nil:
          log lvlError, &"Failed to create wasm language"
          continue

        return TSLanguage(languageId: languageId, impl: language).some

      else:
        let cache = ({.gcsafe.}: treesitterDllCache.addr)

        let lib = if cache[].contains(path):
          cache[][path]
        else:
          let lib = loadLib(path)
          if lib.isNil:
            log(lvlError, fmt"Failed to load treesitter dll for '{languageId}': '{path}'")
            continue
          cache[][path] = lib
          lib

        let ctor = cast[TSLanguageCtor](lib.symAddr(ctorSymbolName.cstring))
        if ctor.isNil:
          log(lvlError, fmt"Failed to load treesitter dll for '{languageId}': '{path}'")
          continue

        {.gcsafe.}:
          let tsLanguage = ctor()
          if tsLanguage.isNil:
            log(lvlError, fmt"Failed to create language from dll '{languageId}': '{path}'")
            continue

          return TSLanguage(languageId: languageId, impl: tsLanguage).some

    return TSLanguage.none
  except:
    log(lvlError, fmt"Failed to load language from dll: '{languageId}': {getCurrentExceptionMsg()}")
    return TSLanguage.none

var loadedLanguages: Table[string, TSLanguage]
var loadingLanguages: Table[string, Future[Option[TSLanguage]]]

proc loadLanguage(vfs: VFS, languageId: string, config: JsonNode): Future[Option[TSLanguage]] {.async.} =
  let language = await loadLanguageDynamically(vfs, languageId, config)
  if language.isSome:
    return language

  log(lvlInfo, fmt"No dll language for {languageId}, try builtin")

  template tryGetLanguage(constructor: untyped): untyped =
    block:
      var l: Option[TSLanguage] = TSLanguage.none
      when declared(constructor):
        log lvlInfo, fmt"Loading builtin language"
        l = TSLanguage(languageId: languageId, impl: constructor()).some
      l

  return case languageId
  of "agda": tryGetLanguage(treeSitterAgda)
  of "c": tryGetLanguage(treeSitterC)
  of "bash": tryGetLanguage(treeSitterBash)
  of "csharp": tryGetLanguage(treeSitterCSharp)
  of "cpp": tryGetLanguage(treeSitterCpp)
  of "css": tryGetLanguage(treeSitterCss)
  of "go": tryGetLanguage(treeSitterGo)
  of "haskell": tryGetLanguage(treeSitterHaskell)
  of "html": tryGetLanguage(treeSitterHtml)
  of "java": tryGetLanguage(treeSitterJava)
  of "javascript": tryGetLanguage(treeSitterJavascript)
  of "ocaml": tryGetLanguage(treeSitterOcaml)
  of "php": tryGetLanguage(treeSitterPhp)
  of "python": tryGetLanguage(treeSitterPython)
  of "ruby": tryGetLanguage(treeSitterRuby)
  of "rust": tryGetLanguage(treeSitterRust)
  of "scala": tryGetLanguage(treeSitterScala)
  of "typescript": tryGetLanguage(treeSitterTypecript)
  of "nim": tryGetLanguage(treeSitterNim)
  of "zig": tryGetLanguage(treeSitterZig)
  of "json": tryGetLanguage(treeSitterJson)
  else:
    log(lvlWarn, fmt"Failed to init treesitter for language '{languageId}'")
    TSLanguage.none

proc unloadTreesitterLanguage*(languageId: string) {.gcsafe, raises: [].} =
  {.gcsafe.}:
    loadedLanguages.del(languageId)
    loadingLanguages.del(languageId)

proc getTreesitterLanguage*(vfs: VFS, languageId: string, config: JsonNode): Future[Option[TSLanguage]] {.async.} =
  log lvlInfo, &"getTreesitterLanguage {languageId}: {config}"
  let loadingLanguages = ({.gcsafe.}: loadingLanguages.addr)
  let loadedLanguages = ({.gcsafe.}: loadedLanguages.addr)
  if loadingLanguages[].contains(languageId):
    let res = await loadingLanguages[][languageId]
    return res

  elif loadedLanguages[].contains(languageId):
    return loadedLanguages[][languageId].some

  else:
    loadingLanguages[][languageId] = loadLanguage(vfs, languageId, config)
    let language = await loadingLanguages[][languageId]
    if language.getSome(language):
      loadedLanguages[][languageId] = language
      loadingLanguages[].del(languageId)

    return language

proc createTsParser*(): TSParser =
  let wasmStore: ptr TSWasmStore = if wasmEngine.it != nil:
    var err: TSWasmError
    let wasmStore = tsWasmStoreNew(cast[ptr TSWasmEngine](wasmEngine.it), err.addr)
    if err.kind != TSWasmErrorKindNone:
      log lvlError, &"Failed to create wasm store: {err}"
    wasmStore

  else:
    nil

  let parser = ts.tsParserNew()

  if wasmStore != nil:
    log lvlInfo, &"Use wasm store"
    parser.tsParserSetWasmStore(wasmStore)

  return TSParser(impl: parser)

proc createTsParser*(language: TSLanguage): Option[TSParser] =
  let wasmStore: ptr TSWasmStore = if language.impl.tsLanguageIsWasm():
    assert wasmEngine.it != nil
    var err: TSWasmError
    let wasmStore = tsWasmStoreNew(cast[ptr TSWasmEngine](wasmEngine.it), err.addr)
    if err.kind != TSWasmErrorKindNone:
      log lvlError, &"Failed to create wasm store: {err}"
      return TSParser.none

    wasmStore

  else:
    nil

  let parser = ts.tsParserNew()
  if wasmStore != nil:
    log lvlInfo, &"Use wasm store"
    parser.tsParserSetWasmStore(wasmStore)
  assert ts.tsParserSetLanguage(parser, language.impl)
  return TSParser(impl: parser).some

var parsers: seq[TSParser]

template withParser*(p: untyped, body: untyped): untyped =
  var parsers = ({.gcsafe.}: parsers.addr)
  if parsers[].len == 0:
    parsers[].add createTsParser()

  let p = parsers[].pop()
  defer:
    parsers[].add p

  block:
    body

proc deinit*(self: TSParser) =
  self.impl.tsParserDelete()

proc deinit*(self: TSQuery) =
  self.impl.tsQueryDelete()

proc tsPoint*(line: int, column: RuneIndex, text: openArray[char]): TSPoint = TSPoint(row: line, column: text.runeOffset(column))
proc tsPoint*(line: int, column: int): TSPoint = TSPoint(row: line, column: column)
proc tsPoint*(cursor: Cursor): TSPoint = TSPoint(row: cursor.line, column: cursor.column)
proc tsRange*(first: TSPoint, last: TSPoint): TSRange = TSRange(first: first, last: last)
proc tsRange*(selection: scripting_api.Selection): TSRange = TSRange(first: tsPoint(selection.first), last: tsPoint(selection.last))
proc toCursor*(point: TSPoint): Cursor = (point.row, point.column)
proc toSelection*(rang: TSRange): scripting_api.Selection = (rang.first.toCursor, rang.last.toCursor)

proc freeDynamicLibraries*() =
  for p in parsers:
    p.deinit()
  parsers.setLen 0

  for (path, lib) in treesitterDllCache.pairs:
    lib.unloadLib()
  treesitterDllCache.clear()

var tsAllocated*: uint64 = 0
var tsFreed*: uint64 = 0

proc tsMalloc(a1: csize_t): pointer {.stdcall.} =
  tsAllocated += a1.uint64
  let p = allocShared0(a1 + 8)
  if p == nil:
    return nil

  cast[ptr uint64](p)[] = a1.uint64
  return cast[pointer](cast[uint64](p) + 8)

proc tsCalloc(a1: csize_t; a2: csize_t): pointer {.stdcall.} =
  let size = a1.uint64 * a2.uint64
  tsAllocated += size
  let p = allocShared0(size + 8)
  if p == nil:
    return nil

  cast[ptr uint64](p)[] = size
  return cast[pointer](cast[uint64](p) + 8)

proc tsRealloc(a1: pointer; a2: csize_t): pointer {.stdcall.} =
  if a1 == nil:
    return tsMalloc(a2)

  let original = cast[ptr uint64](cast[uint64](a1) - 8)
  let size = original[]
  if size > a2:
    tsFreed += size - a2.uint64
  else:
    tsAllocated += a2.uint64 - size

  let p = reallocShared(original, a2 + 8)
  if p == nil:
    return nil

  cast[ptr uint64](p)[] = a2.uint64
  return cast[pointer](cast[uint64](p) + 8)

proc tsFree(a1: pointer) {.stdcall.} =
  if a1 == nil:
    return

  let original = cast[ptr uint64](cast[uint64](a1) - 8)
  let size = original[]
  tsFreed += size.uint64
  deallocShared(original)

proc enableTreesitterMemoryTracking*() =
  tsSetAllocator(tsMalloc, tsCalloc, tsRealloc, tsFree)
