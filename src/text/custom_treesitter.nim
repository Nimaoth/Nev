import std/[options, json, tables, locks]
import misc/[custom_logger, custom_async, util, custom_unicode, jsonex, arena, array_view]
import vfs
import treesitter_type_conv
export treesitter_type_conv

from scripting_api import Cursor, Selection, byteIndexToCursor

{.push stacktrace:off.}
{.push linetrace:off.}

logCategory "treesitter"

from treesitter/api as ts import nil
import treesitter_types
export treesitter_types

include ../dynlib_export

type TSLanguageCtor = proc(): ptr ts.TSLanguage {.stdcall.}

type GetTextCallback* = proc(index: int, position: Cursor): (ptr char, int)

proc treesitterParseString(self: TSParser, text: string, oldTree: Option[TSTree] = TSTree.none): TSTree {.apprtl, gcsafe, raises: [].}
proc treesitterParseCallback(self: TSParser, oldTree: TSTree, text: GetTextCallback): TSTree {.apprtl, gcsafe, raises: [].}

proc parseString*(self: TSParser, text: string, oldTree: Option[TSTree] = TSTree.none): TSTree {.inline.} = treesitterParseString(self, text, oldTree)
proc parseCallback*(self: TSParser, oldTree: TSTree, text: GetTextCallback): TSTree {.inline.} = treesitterParseCallback(self, oldTree, text)

func toTsPoint*(cursor: Cursor, line: openArray[char]): ts.TSPoint = ts.TSPoint(row: cursor.line.uint32, column: line.runeIndex(cursor.column).uint32)
template withQueryCursor*(cursor: untyped, body: untyped): untyped =
  bind ts.tsQueryCursorNew
  bind ts.tsQueryCursorDelete
  block:
    let cursor = ts.tsQueryCursorNew()
    defer: ts.tsQueryCursorDelete(cursor)
    body

template withTreeCursor*(node: untyped, cursor: untyped, body: untyped): untyped =
  block:
    var cursor = initTreeCursor(node)
    body

# Available on all targets

import std/macros

proc getParsers*(): ptr seq[TSParser] {.apprtl, gcsafe, raises: [].}
proc getParsersLock*(): ptr Lock {.apprtl, gcsafe, raises: [].}
proc createTsParser*(): TSParser {.apprtl, gcsafe, raises: [].}
proc freeDynamicLibraries*() {.apprtl, gcsafe, raises: [].}
proc unloadTreesitterLanguage*(languageId: string) {.apprtl, gcsafe, raises: [].}
proc getTreesitterLanguage*(vfs: VFS, languageId: string, pathOverride: Option[string] = string.none): Future[Option[TSLanguage]] {.apprtl, gcsafe, raises: [].}
proc getLoadedLanguage*(languageId: string): TSLanguage {.apprtl, gcsafe, raises: [].}
proc getLoadedLanguageSnapshot*(languageId: string): Option[TSLanguageSnapshot] {.apprtl, gcsafe, raises: [].}
proc treesitterQuery(self: TSLanguage, id: string, source: string, cacheOnFail = true, logSourceOnError = true): Future[Option[TSQuery]] {.apprtl, async.}
proc query*(self: TSLanguage, id: string, source: string, cacheOnFail = true, logSourceOnError = true): Future[Option[TSQuery]] {.async.} = await treesitterQuery(self, id, source, cacheOnFail, logSourceOnError)
var tsAllocated* {.apprtl.}: uint64 = 0
var tsFreed* {.apprtl.}: uint64 = 0

when implModule:
  import std/[os, strutils, dynlib]
  import compilation_config
  import wasm_engine
  import wasmtime

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
  when useBuiltinTreesitterLanguage("markdown"):
    import treesitter_markdown/treesitter_markdown/markdown

  var gTreesitterDllCache = initTable[string, LibHandle]()
  var gEngine = getGlobalWasmEngine()
  var gWasmStore: ptr ts.TSWasmStore = nil
  var gLoadedLanguages: Table[string, TSLanguage]
  var gLoadedLanguagesSnapshots: Table[string, TSLanguageSnapshot]
  var gLoadedLanguagesLock: Lock
  var gLoadingLanguages: Table[string, Future[Option[TSLanguage]]]
  var gParsers: seq[TSParser]
  var gParsersLock: Lock

  gLoadedLanguagesLock.initLock()
  gParsersLock.initLock()

  proc getParsers*(): ptr seq[TSParser] = ({.gcsafe.}: gParsers.addr)
  proc getParsersLock*(): ptr Lock = ({.gcsafe.}: gParsersLock.addr)

  proc getLanguageWasmStore(): ptr ts.TSWasmStore =
    {.gcsafe.}:
      if gWasmStore == nil:
        if gEngine == nil:
          return nil
        var err: ts.TSWasmError
        gWasmStore = ts.tsWasmStoreNew(cast[ptr ts.TSWasmEngine](gEngine), err.addr)
        if err.kind != ts.TSWasmErrorKindNone:
          log lvlError, &"Failed to create wasm store: {err}"
          gWasmStore = nil
          return nil
      return gWasmStore

  proc freeDynamicLibraries*() =
    {.gcsafe.}:
      withLock gParsersLock:
        for p in gParsers:
          p.deinit()
        gParsers.setLen 0

      for (path, lib) in gTreesitterDllCache.pairs:
        lib.unloadLib()
      gTreesitterDllCache.clear()

  proc loadLanguageDynamically(vfs: VFS, languageId: string, pathOverride: Option[string]): Future[Option[TSLanguage]] {.async.} =
    try:
      const fileExtension = when defined(windows):
        "dll"
      else:
        "so"

      var candidates: seq[tuple[path: string, ctor: string]] = @[]

      proc addCandidate(path: string) {.gcsafe, async: (raises: []).} =
        for base in ["app://", homeConfigDir]:
          let path = base & path
          if vfs.getFileKind(path).await.mapIt(it == FileKind.File).get(false):
            let ctor = if path.endsWith(".wasm"):
              languageId
            else:
              &"tree_sitter_{languageId}"
            candidates.add (path, ctor)

      if pathOverride.getSome(path):
        await addCandidate path
      else:
        # todo: rename directory from languages to treesitter
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

          # proc loadLanguageThread(args: (ptr WasmStoreT, cstring, cstring, uint32, ptr ts.TSWasmError)): ptr ts.TSLanguage {.thread.} =
          #   ts.tsWasmStoreLoadLanguage(args[0], args[1], args[2], args[3], args[4])

          var err: ts.TSWasmError
          let language = block:
            # todo: load in separate thread
            # let res = await spawnAsync(loadLanguageThread, (wasmStore, ctorSymbolName.cstring, wasmBytes.cstring, wasmBytes.len.uint32, err.addr))
            # res
            ts.tsWasmStoreLoadLanguage(wasmStore, ctorSymbolName.cstring, wasmBytes.cstring, wasmBytes.len.uint32, err.addr)

          if err.kind != ts.TSWasmErrorKindNone:
            log lvlError, &"Failed to create wasm language: {err}"
            continue

          if language == nil:
            log lvlError, &"Failed to create wasm language"
            continue

          return TSLanguage(languageId: languageId, impl: language).some

        else:
          let cache = ({.gcsafe.}: gTreesitterDllCache.addr)
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

  proc loadLanguage(vfs: VFS, languageId: string, pathOverride: Option[string]): Future[Option[TSLanguage]] {.async.} =
    let language = await loadLanguageDynamically(vfs, languageId, pathOverride)
    if language.isSome:
      return language

    template tryGetLanguage(constructor: untyped): untyped =
      block:
        var l: Option[TSLanguage] = TSLanguage.none
        when declared(constructor):
          log lvlInfo, fmt"Loading builtin language '{languageId}'"
          let languageRaw = constructor()
          if languageRaw == nil:
            log lvlError, &"Failed to create builtin language parser for '{languageId}'"
          else:
            l = TSLanguage(languageId: languageId, impl: languageRaw).some
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
    of "markdown": tryGetLanguage(treeSitterMarkdown)
    else:
      TSLanguage.none

  proc unloadTreesitterLanguage*(languageId: string) {.gcsafe, raises: [].} =
    {.gcsafe.}:
      withLock gLoadedLanguagesLock:
        gLoadedLanguagesSnapshots.del(languageId)
      gLoadedLanguages.del(languageId)
      gLoadingLanguages.del(languageId)

  proc getLoadedLanguage*(languageId: string): TSLanguage {.gcsafe, raises: [].} =
    {.gcsafe.}:
      gLoadedLanguages.getOrDefault(languageId)

  proc getLoadedLanguageSnapshot*(languageId: string): Option[TSLanguageSnapshot] {.apprtl, gcsafe, raises: [].} =
    {.gcsafe.}:
      withLock gLoadedLanguagesLock:
        if languageId in gLoadedLanguagesSnapshots:
          return gLoadedLanguagesSnapshots[languageId].some
        return TSLanguageSnapshot.none

  proc getTreesitterLanguage*(vfs: VFS, languageId: string, pathOverride: Option[string] = string.none): Future[Option[TSLanguage]] {.async.} =
    # log lvlInfo, &"getTreesitterLanguage {languageId}: {pathOverride}"
    let loadingLanguages = ({.gcsafe.}: gLoadingLanguages.addr)
    if loadingLanguages[].contains(languageId):
      let res = await loadingLanguages[][languageId]
      return res

    {.gcsafe.}:
      if gLoadedLanguages.contains(languageId):
        return gLoadedLanguages[languageId].some

    loadingLanguages[][languageId] = loadLanguage(vfs, languageId, pathOverride)
    let language = await loadingLanguages[][languageId]
    if language.getSome(language):
      {.gcsafe.}:
        withLock gLoadedLanguagesLock:
          gLoadedLanguagesSnapshots[languageId] = TSLanguageSnapshot(languageId: language.languageId, impl: language.impl, queries: language.queries)
        gLoadedLanguages[languageId] = language
      loadingLanguages[].del(languageId)

    return language

  proc createTsParser*(): TSParser =
    let wasmStore: ptr ts.TSWasmStore = if gEngine != nil:
      var err: ts.TSWasmError
      let wasmStore = ts.tsWasmStoreNew(cast[ptr ts.TSWasmEngine](gEngine), err.addr)
      if err.kind != ts.TSWasmErrorKindNone:
        log lvlError, &"Failed to create wasm store: {err}"
      wasmStore
    else:
      nil

    let parser = ts.tsParserNew()
    if parser.isNil:
      log lvlError, &"Failed to create treesitter parser"
      return

    if wasmStore != nil:
      log lvlInfo, &"Use wasm store"
      ts.tsParserSetWasmStore(parser, wasmStore)

    return TSParser(impl: parser)

  proc treesitterQuery(self: TSLanguage, id: string, source: string, cacheOnFail = true, logSourceOnError = true): Future[Option[TSQuery]] {.async.} =

    if self.queries.contains(id):
      return self.queries[id]

    logScope lvlInfo, &"Create '{id}' query for {self.languageId}"

    var errorOffset: uint32 = 0
    var queryError: ts.TSQueryError = ts.TSQueryErrorNone
    # todo: can we call tsQueryNew in a separate thread?
    let query = TSQuery(impl: ts.tsQueryNew(self.impl, source.cstring, source.len.uint32, addr errorOffset, addr queryError))

    if queryError != ts.TSQueryErrorNone:
      if logSourceOnError:
        log lvlError, &"Failed to load '{id}' query for '{self.languageId}': {errorOffset} {source.byteIndexToCursor(errorOffset.int)}: {queryError}\n{source}"
      else:
        log lvlError, &"Failed to load '{id}' query for '{self.languageId}': {errorOffset} {source.byteIndexToCursor(errorOffset.int)}: {queryError}"

      if cacheOnFail:
        self.queries[id] = TSQuery.none
      return TSQuery.none

    query.some

  proc queryFileImpl(self: TSLanguage, vfs: VFS, id: string, path: string, cacheOnFail = true): Future[Option[TSQuery]] {.async.} =
    try:
      let queryString = await vfs.read(path)
      return await self.query(id, queryString, cacheOnFail, logSourceOnError = false)
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
    {.gcsafe.}:
      withLock gLoadedLanguagesLock:
        gLoadedLanguagesSnapshots[self.languageId].queries[id] = query
    log lvlInfo, fmt"Loaded {id} query '{path}' for {self.languageId}"
    return query

  proc treesitterParseString(self: TSParser, text: string, oldTree: Option[TSTree] = TSTree.none): TSTree =
    let oldTreePtr: ptr ts.TSTree = if oldTree.getSome(tree):
      tree.impl
    else:
      nil
    let tree = ts.tsParserParseString(self.impl, oldTreePtr, text.cstring, text.len.uint32)
    return TSTree(impl: tree)

  proc getTextRangeTreesitter(payload: pointer; byteIndex: uint32; position: ts.TSPoint; bytesRead: ptr uint32): cstring {.stdcall.} =

    let callback = cast[ptr GetTextCallback](payload)[]
    let (p, len) = callback(byteIndex.int, (position.row.int, position.column.int))
    bytesRead[] = len.uint32
    return cast[cstring](p)

  proc treesitterParseCallback(self: TSParser, oldTree: TSTree, text: GetTextCallback): TSTree =
    let input = ts.TSInput(
      payload: text.addr,
      # read: cast[typeof(ts.TSInput().read)](getTextRangeTreesitter),
      encoding: ts.TSInputEncoding.TSInputEncodingUTF8
    )

    # Ugly hack, but on windows it complains about incompatible function pointer type because nim maps cstring to "char*"
    # instead of "const char*"
    {.emit: [input, ".read = (void*)(", getTextRangeTreesitter, ");"].}

    let oldTreeImpl = if oldTree.isNotNil:
      oldTree.impl
    else:
      nil

    let tree = ts.tsParserParse(self.impl, oldTreeImpl, input)
    return TSTree(impl: tree)

proc getTsParser*(): TSParser =
  var parsers = ({.gcsafe.}: getParsers())
  var p = TSParser()
  withLock getParsersLock()[]:
    if parsers[].len > 0:
      p = parsers[].pop()

  if p.isNil:
    p = createTsParser()
  return p

proc getTsParsers*(num: int): seq[TSParser] =
  result = newSeqOfCap[TSParser](num)
  var p = ({.gcsafe.}: getParsers())
  withLock getParsersLock()[]:
    while p[].len > 0 and result.len < num:
      result.add p[].pop()

  while result.len < num:
    result.add createTsParser()

proc returnParser*(parser: TSParser) =
  var p = ({.gcsafe.}: getParsers())
  withLock getParsersLock()[]:
    p[].add parser

proc returnParsers*(parsers: sink seq[TSParser]) =
  var p = ({.gcsafe.}: getParsers())
  withLock getParsersLock()[]:
    p[].add parsers

template withParser*(p: untyped, body: untyped): untyped =
  var parsers = ({.gcsafe.}: getParsers())
  let lock = ({.gcsafe.}: getParsersLock())
  var p = TSParser()

  withLock lock[]:
    if parsers[].len > 0:
      p = parsers[].pop()

  if p.isNil:
    p = createTsParser()
  if not p.isNil:
    defer:
      withLock lock[]:
        parsers[].add p

    block:
      body

proc tsPoint*(line: int, column: RuneIndex, text: openArray[char]): TSPoint = TSPoint(row: line, column: text.runeOffset(column))
proc tsPoint*(cursor: Cursor): TSPoint = TSPoint(row: cursor.line, column: cursor.column)
proc tsRange*(selection: scripting_api.Selection): TSRange = TSRange(first: tsPoint(selection.first), last: tsPoint(selection.last))

proc tsMalloc(a1: csize_t): pointer {.stdcall.} =
  return allocShared0(a1)

proc tsCalloc(a1: csize_t; a2: csize_t): pointer {.stdcall.} =
  let size = a1.uint64 * a2.uint64
  return allocShared0(size)

proc tsRealloc(a1: pointer; a2: csize_t): pointer {.stdcall.} =
  return reallocShared(a1, a2)

proc tsFree(a1: pointer) {.stdcall.} =
  deallocShared(a1)

ts.tsSetAllocator(tsMalloc, tsCalloc, tsRealloc, tsFree)

proc enableTreesitterMemoryTracking*() {.apprtl, gcsafe, raises: [].}

when implModule:
  proc tsDebugMalloc(a1: csize_t): pointer {.stdcall.} =
    tsAllocated += a1.uint64
    let p = allocShared0(a1 + 8)
    if p == nil:
      return nil

    cast[ptr uint64](p)[] = a1.uint64
    return cast[pointer](cast[uint64](p) + 8)

  proc tsDebugCalloc(a1: csize_t; a2: csize_t): pointer {.stdcall.} =
    let size = a1.uint64 * a2.uint64
    tsAllocated += size
    let p = allocShared0(size + 8)
    if p == nil:
      return nil

    cast[ptr uint64](p)[] = size
    return cast[pointer](cast[uint64](p) + 8)

  proc tsDebugRealloc(a1: pointer; a2: csize_t): pointer {.stdcall.} =
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

  proc tsDebugFree(a1: pointer) {.stdcall.} =
    if a1 == nil:
      return

    let original = cast[ptr uint64](cast[uint64](a1) - 8)
    let size = original[]
    tsFreed += size.uint64
    deallocShared(original)

  proc enableTreesitterMemoryTracking*() =
    ts.tsSetAllocator(tsDebugMalloc, tsDebugCalloc, tsDebugRealloc, tsDebugFree)

iterator query*(query: TSQuery, tree: TSTree, selection: Selection): seq[tuple[node: TSNode, capture: string]] =
  let range = tsRange(tsPoint(selection.first.line, selection.first.column), tsPoint(selection.last.line, selection.last.column))
  var arena = initArena()

  for match in query.matches(tree.root, range, arena):
    let predicates = query.predicatesForPattern(match.pattern, arena)
    var captures = newSeqOfCap[tuple[node: TSNode, capture: string]](match.captures.len)
    for capture in match.captures:
      let node = capture.node
      var matches = true

      for predicate in predicates:
        if not matches:
          break

        for operand in predicate.operands:
          if operand.name != capture.name:
            matches = false
            break

      #     case predicate.operator
      #     of "match?":
      #       if not regexes[].contains(operand.`type`):
      #         try:
      #           regexes[][operand.`type`] = re(operand.`type`)
      #         except RegexError:
      #           matches = false
      #           break
      #       let regex {.cursor.} = regexes[][operand.`type`]

      #       let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
      #       if nodeText.matchLen(regex, 0) != nodeText.len:
      #         matches = false
      #         break

      #     of "not-match?":
      #       if not regexes[].contains(operand.`type`):
      #         try:
      #           regexes[][operand.`type`] = re(operand.`type`)
      #         except RegexError:
      #           matches = false
      #           break
      #       let regex {.cursor.} = regexes[][operand.`type`]

      #       let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
      #       if nodeText.matchLen(regex, 0) == nodeText.len:
      #         matches = false
      #         break

      #     of "eq?":
      #       # @todo: second arg can be capture aswell
      #       let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
      #       if nodeText != operand.`type`:
      #         matches = false
      #         break

      #     of "not-eq?":
      #       # @todo: second arg can be capture aswell
      #       let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
      #       if nodeText == operand.`type`:
      #         matches = false
      #         break

      #     # of "any-of?":
      #     #   # todo
      #     #   log(lvlError, fmt"Unknown predicate '{predicate.name}'")

      #     else:
      #       discard

      if not matches:
        continue

      captures.add (node, $capture.name)
    yield captures
