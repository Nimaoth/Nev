import std/[options]
import nimsumtree/arc
import misc/[event, custom_async, fuzzy_matching]
import scripting_api

include misc/dynlib_export

type
  GetPreviewTextImpl* = proc(item: FinderItem): string {.gcsafe, raises: [].}

  FinderItem* = object
    displayName*: string
    details*: seq[string]
    filterText*: string
    data*: string
    score*: float
    originalIndex: Option[int]
    filtered*: bool

  ItemListData* = object
    filtered*: int = 0
    locked*: bool
    items*: seq[FinderItem]

  ItemList* = object
    data: Arc[ItemListData]

  DataSource* = ref object of RootObj
    onItemsChanged*: Event[ItemList]

    closeImpl*: proc(self: DataSource) {.gcsafe, raises: [].}
    setQueryImpl*: proc(self: DataSource, query: string) {.gcsafe, raises: [].}

  Finder* = ref object
    source*: DataSource
    queries*: seq[string]
    filteredItems*: Option[ItemList]

    filterAndSort: bool
    minScore*: float = 0
    sort*: bool
    filterThreshold*: float = 0
    skipFirstQuery*: bool = false

    queryVersion: int
    itemsVersion: int

    lastTriggeredFilterVersions: tuple[query, items: int]

    onItemsChangedHandle: Id
    onItemsChanged*: Event[void]

  AsyncCallbackDataSourceImpl* = proc(): Future[ItemList] {.gcsafe, async: (raises: []).}
  SyncDataSourceImpl1* = proc(): seq[FinderItem] {.gcsafe, raises: [].}
  SyncDataSourceImpl2* = proc(): ItemList {.gcsafe, raises: [].}

  StaticDataSource* = ref object of DataSource
    wasQueried: bool = false
    items: seq[FinderItem]

  AsyncFutureDataSource* = ref object of DataSource
    wasQueried: bool = false
    future: Future[ItemList]

  AsyncCallbackDataSource* = ref object of DataSource
    wasQueried: bool = false
    callback: proc(): Future[ItemList] {.gcsafe, async: (raises: []).}

  SyncDataSource* = ref object of DataSource
    wasQueried: bool = false
    callbackSeq: proc(): seq[FinderItem] {.gcsafe, raises: [].}
    callbackList: proc(): ItemList {.gcsafe, raises: [].}

{.push apprtl, gcsafe, raises: [].}
proc newFinder*(source: DataSource, filterAndSort: bool = true, sort: bool = true, minScore: float = 0, skipFirstQuery: bool = false): Finder
proc finderDeinit(finder: Finder)
proc newStaticDataSource*(items: sink seq[FinderItem]): StaticDataSource
proc newAsyncFutureDataSource*(future: Future[ItemList]): AsyncFutureDataSource
proc newAsyncCallbackDataSource*(callback: AsyncCallbackDataSourceImpl): AsyncCallbackDataSource
proc newSyncDataSource1*(callback: SyncDataSourceImpl1): SyncDataSource
proc newSyncDataSource2*(callback: SyncDataSourceImpl2): SyncDataSource
proc finderSetQuery(self: Finder, query: string)
proc finderParsePathAndLocationFromItemData(item: FinderItem): Option[tuple[path: string, location: Option[Cursor], isFile: Option[bool], editorId: Option[EditorId]]]
{.pop.}

proc deinit*(finder: Finder) = finderDeinit(finder)
proc newSyncDataSource*(callback: SyncDataSourceImpl1): SyncDataSource = newSyncDataSource1(callback)
proc newSyncDataSource*(callback: SyncDataSourceImpl2): SyncDataSource = newSyncDataSource2(callback)
proc setQuery*(self: Finder, query: string) = finderSetQuery(self, query)
proc parsePathAndLocationFromItemData*(item: FinderItem): Option[tuple[path: string, location: Option[Cursor], isFile: Option[bool], editorId: Option[EditorId]]] = finderParsePathAndLocationFromItemData(item)

proc cmp*(a, b: FinderItem): int = cmp(a.score, b.score)
proc `<`*(a, b: FinderItem): bool = a.score < b.score

proc newItemList*(len: int): ItemList {.gcsafe, raises: [].} =
  return ItemList(data: Arc[ItemListData].new(ItemListData(items: newSeq[FinderItem](len))))

proc newItemList*(items: sink seq[FinderItem]): ItemList =
  return ItemList(data: Arc[ItemListData].new(ItemListData(items: items.ensureMove)))

func high*(list: ItemList): int = list.data.get.items.high
func len*(list: ItemList): int = list.data.get.items.len
func filteredLen*(list: ItemList): int = list.len - list.data.get.filtered
proc locked*(list: ItemList): bool = list.data.get.locked
proc filtered*(list: ItemList): int = list.data.get.filtered

proc data*(list: ItemList): lent ItemListData =
  return list.data.get

proc mdata*(list: var ItemList): var ItemListData =
  return list.data.getMut

proc setLen*(list: var ItemList, newLen: int) =
  assert newLen >= 0
  assert newLen <= list.len
  list.data.getMut.items.setLen(newLen)

proc isValidIndex*(list: ItemList, i: int): bool =
  return i >= 0 and i < list.len

proc `[]=`*(list: var ItemList, i: int, item: sink FinderItem) =
  assert i >= 0
  assert i < list.len
  list.data.getMut.items[i] = item.ensureMove

proc `[]`*(list: ItemList, i: int): lent FinderItem =
  assert i >= 0
  assert i < list.len
  list.data.get.items[i]

proc `[]`*(list: var ItemList, i: int): var FinderItem =
  assert i >= 0
  assert i < list.len
  list.data.getMut.items[i]

template items*(list: ItemList): openArray[FinderItem] =
  # assert not list.data.isNil
  list.data.get.items

proc close*(self: DataSource) {.gcsafe, raises: [].} =
  if self.closeImpl != nil:
    self.closeImpl(self)

proc setQuery*(self: DataSource, query: string) {.gcsafe, raises: [].} =
  if self.setQueryImpl != nil:
    self.setQueryImpl(self, query)

proc retrigger*(self: AsyncCallbackDataSource) {.gcsafe, raises: [].} =
  self.wasQueried = false
  self.setQuery("")

proc retrigger*(self: SyncDataSource) {.gcsafe, raises: [].} =
  self.wasQueried = false
  self.setQuery("")

var finderFuzzyMatchConfig* {.apprtlvar.} = FuzzyMatchConfig(ignoredChars: {' '}, useDiff: true)

when implModule:
  import std/[algorithm, sugar, strutils, json, tables]
  import misc/[regex, timer, util, id, custom_logger, myjsonutils]
  import malebolgia

  logCategory "finder"

  func sort(list: var ItemList, cmp: proc (x, y: FinderItem): int {.closure.},
             order = SortOrder.Descending) {.effectsOf: cmp.} =
    list.data.getMutUnsafe.items.sort(cmp, order)

  proc finderDeinit(finder: Finder) =
    if finder.source.isNotNil:
      finder.source.close()
    finder.source = nil
    finder.filteredItems = ItemList.none

  proc `=destroy`*(finder: typeof(Finder()[])) =
    if finder.source.isNotNil:
      finder.source.close()
    `=destroy`(finder.queries)

  proc handleItemsChanged(self: Finder, list: ItemList) {.gcsafe, raises: [].}

  proc newFinder*(source: DataSource, filterAndSort: bool = true, sort: bool = true, minScore: float = 0, skipFirstQuery: bool = false): Finder =
    new result
    var self = result
    result.source = source
    result.filterAndSort = filterAndSort
    result.skipFirstQuery = skipFirstQuery
    result.sort = sort
    result.minScore = minScore
    result.onItemsChangedHandle = source.onItemsChanged.subscribe proc(items: ItemList) =
      self.handleItemsChanged(items)

  type FilterAndSortResult = object
    scoreTime: float
    sortTime: float
    totalTime: float
    filtered: int

  proc parallelForChunk[T, C](items: ptr UncheckedArray[T], first: int, last: int, ctx: C, cb: proc(index: int, item: var T, ctx: C) {.nimcall, gcsafe, raises: [].}) =
    for i in first..<last:
      cb(i, items[i], ctx)

  proc parallelFor*[T, C](items: openArray[T], chunkSize: int, ctx: C, cb: proc(index: int, item: var T, ctx: C) {.nimcall, gcsafe, raises: [].}) =
    var numChunks = items.len div chunkSize
    if numChunks * chunkSize < items.len:
      inc numChunks
    var m = createMaster()
    m.awaitAll:
      var start = 0
      while start < items.len:
        let len = min(chunkSize, items.len - start)
        m.spawn parallelForChunk[T, C](cast[ptr UncheckedArray[T]](items[0].addr), start, start + len, ctx, cb)
        start += chunkSize

  type FilterAndSortArgs = tuple[queries: seq[string], list: ItemList, sort: bool, minScore: float, skipFirstQuery: bool]

  proc applyFuzzyFilter(index: int, item: var FinderItem, ctx: tuple[firstQueryIndex: int, queryIndex: int, args: ptr FilterAndSortArgs]) {.nimcall.} =
    if item.filtered:
      return
    if ctx.queryIndex == ctx.firstQueryIndex:
      if item.filterText.len > 0:
        item.score = matchFuzzy(ctx.args.queries[ctx.queryIndex], item.filterText, finderFuzzyMatchConfig).score.float
      else:
        item.score = matchFuzzy(ctx.args.queries[ctx.queryIndex], item.displayName, finderFuzzyMatchConfig).score.float
    else:
      let detailIndex = (ctx.queryIndex - 1) - ctx.firstQueryIndex
      if detailIndex in 0..item.details.high:
        item.score = matchFuzzy(ctx.args.queries[ctx.queryIndex], item.details[detailIndex], finderFuzzyMatchConfig).score.float
      else:
        item.score = matchFuzzy(ctx.args.queries[ctx.queryIndex], "", finderFuzzyMatchConfig).score.float

  proc filterAndSortItemsThread(args: FilterAndSortArgs): FilterAndSortResult {.gcsafe.} =
    try:
      var list = args.list
      let scoreTimer = startTimer()
      if list.len > 0:
        result.filtered = 0

        for i, item in list.data.getMutUnsafe.items.mpairs:
          item.filtered = false
          if item.originalIndex.isNone:
            item.originalIndex = i.some

        let firstQueryIndex = if args.skipFirstQuery:
          1
        else:
          0
        var queryIndex = firstQueryIndex
        while queryIndex < args.queries.len:
          var minScore = float.high
          var maxScore = float.low

          parallelFor list.data.getMutUnsafe.items, 512, (firstQueryIndex, queryIndex, args.addr), applyFuzzyFilter

          for i, item in list.data.getMutUnsafe.items.mpairs:
            if item.filtered:
              continue
            maxScore = max(maxScore, item.score)
            minScore = min(minScore, item.score)

          for i, item in list.data.getMutUnsafe.items.mpairs:
            if item.filtered:
              continue
            if item.score > 0:
              item.score /= maxScore
            elif item.score < 0:
              item.score /= -minScore
            item.filtered = item.score < args.minScore
            if item.filtered:
              inc result.filtered

          inc queryIndex

      result.scoreTime = scoreTimer.elapsed.ms

      proc customCmp(a, b: FinderItem): int =
        if a.filtered and not b.filtered:
          return -1
        if not a.filtered and b.filtered:
          return 1
        if args.sort:
          return cmp(a.score, b.score)
        elif a.originalIndex.isSome and b.originalIndex.isSome:
          return cmp(b.originalIndex.get, a.originalIndex.get)
        return 0

      let sortTimer = startTimer()
      list.sort(customCmp, Descending)
      result.sortTime = sortTimer.elapsed.ms

      result.totalTime = result.scoreTime + result.sortTime

    except CatchableError:
      discard

  proc filterAndSortItems(self: Finder, items: sink ItemList): Future[void] {.async.} =
    assert self.queries.len > 0

    let versions = (query: self.queryVersion, items: self.itemsVersion)

    while items.data.getMutUnsafe.locked:
      await sleepAsync(5.milliseconds)

    if self.queryVersion != versions.query:
      # Query was updated after spawning this filter and sort, so discard the result
      return

    items.data.getMutUnsafe.locked = true
    defer:
      items.data.getMutUnsafe.locked = false

    if versions == self.lastTriggeredFilterVersions:
      # already triggered a filter and search for current query and items
      return

    self.lastTriggeredFilterVersions = versions

    var filterResult = spawnAsync(filterAndSortItemsThread, (self.queries, items, self.sort, self.minScore, self.skipFirstQuery)).await

    # debugf"[filterAndSortItems] -> {versions}, {filterResult.scoreTime}ms, {filterResult.sortTime}ms, {filterResult.totalTime}ms"

    if self.itemsVersion != versions.items:
      # Items were updated after spawning this filter and sort, so discard the result
      return

    items.data.getMutUnsafe.filtered = filterResult.filtered
    self.filteredItems = items.some
    self.onItemsChanged.invoke()

  proc handleItemsChanged(self: Finder, list: ItemList) =
    if self.source.isNil:
      return

    inc self.itemsVersion

    if self.filterAndSort and self.queries.len > 0:
      asyncSpawn self.filterAndSortItems(list)
    else:
      self.filteredItems = list.some
      self.onItemsChanged.invoke()

  proc finderSetQuery(self: Finder, query: string) =
    self.queries = query.split("\t")
    self.queryVersion.inc
    self.source.setQuery(self.queries[0])

    # todo: add optional delay so we don't spawn tasks on every keystroke, but only after stopping for a bit.
    if self.filterAndSort and self.filteredItems.getSome(list):
      var mlist = list
      if self.queries.len == 0:
        for i in 0..<mlist.len:
          mlist[i].filtered = false
        mlist.sort((a, b) => -cmp(a.originalIndex.get(0), b.originalIndex.get(0)), Descending)
        self.filteredItems.get.data.getMut.filtered = 0
        self.onItemsChanged.invoke()

      else:
        asyncSpawn self.filterAndSortItems(list)

  proc staticDataSourceSetQuery*(self: DataSource, query: string) =
    let self = self.StaticDataSource
    if self.wasQueried:
      return
    self.wasQueried = true

    var list = newItemList(self.items.len)
    for i, item in self.items:
      list[i] = item

    self.onItemsChanged.invoke list

  proc getDataAsync(self: AsyncFutureDataSource): Future[void] {.async.} =
    let list = self.future.await
    self.onItemsChanged.invoke list

  proc getDataAsync(self: AsyncCallbackDataSource): Future[void] {.async.} =
    let list = self.callback().await
    self.onItemsChanged.invoke list

  proc asyncFutureDataSourceSetQuery*(self: DataSource, query: string) {.gcsafe, raises: [].} =
    let self = self.AsyncFutureDataSource
    if not self.wasQueried:
      self.wasQueried = true
      asyncSpawn self.getDataAsync()

  proc asyncCallbackDataSourceSetQuery*(self: DataSource, query: string) {.gcsafe, raises: [].} =
    let self = self.AsyncCallbackDataSource
    if not self.wasQueried:
      self.wasQueried = true
      asyncSpawn self.getDataAsync()

  proc syncDataSourceSetQuery*(self: DataSource, query: string) {.gcsafe, raises: [].} =
    let self = self.SyncDataSource
    if not self.wasQueried:
      self.wasQueried = true

      let list = if self.callbackList.isNotNil:
        self.callbackList()
      else:
        let items = self.callbackSeq()
        var list = newItemList(items.len)
        for i, item in items:
          list[i] = item
        list

      self.onItemsChanged.invoke list

  proc finderParsePathAndLocationFromItemData(item: FinderItem):
      Option[tuple[path: string, location: Option[Cursor], isFile: Option[bool], editorId: Option[EditorId]]] {.gcsafe, raises: [].} =
    try:
      if not item.data.startsWith("{"):
        return (item.data, Cursor.none, bool.none, EditorId.none).some

      let jsonData = item.data.parseJson.catch:
        return

      if jsonData.kind != JObject:
        return

      if not jsonData.hasKey "path":
        return

      let editorId = if jsonData.hasKey "editorId":
        jsonData["editorId"].jsonTo(Option[EditorId])
      else:
        EditorId.none

      let path = jsonData.fields["path"]
      if path.kind != JString:
        return

      let isFile = if jsonData.hasKey("isFile") and jsonData.fields["isFile"].kind == JBool:
        jsonData.fields["isFile"].getBool.some
      else:
        bool.none

      var cursor: Option[Cursor] = if jsonData.hasKey "line":
        (
          jsonData.fields["line"].getInt,
          jsonData.fields.getOrDefault("column", % 0).getInt,
        ).some.catch:
          Cursor.none
      else:
        Cursor.none

      return (path.getStr, cursor, isFile, editorId).some

    except CatchableError:
      return

  proc newStaticDataSource*(items: sink seq[FinderItem]): StaticDataSource =
    let res = StaticDataSource()
    res.items = items
    res.setQueryImpl = staticDataSourceSetQuery
    return res

  proc newAsyncFutureDataSource*(future: Future[ItemList]): AsyncFutureDataSource =
    let res = AsyncFutureDataSource()
    res.future = future
    res.setQueryImpl = asyncFutureDataSourceSetQuery
    return res

  proc newAsyncCallbackDataSource*(callback: AsyncCallbackDataSourceImpl): AsyncCallbackDataSource =
    let res = AsyncCallbackDataSource()
    res.callback = callback
    res.setQueryImpl = asyncCallbackDataSourceSetQuery
    return res

  proc newSyncDataSource1*(callback: SyncDataSourceImpl1): SyncDataSource =
    let res = SyncDataSource()
    res.callbackSeq = callback
    res.setQueryImpl = syncDataSourceSetQuery
    return res

  proc newSyncDataSource2*(callback: SyncDataSourceImpl2): SyncDataSource =
    let res = SyncDataSource()
    res.callbackList = callback
    res.setQueryImpl = syncDataSourceSetQuery
    return res
