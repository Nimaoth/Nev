import std/[algorithm, sugar, strutils]
import misc/[regex, timer, fuzzy_matching, util, custom_async, event, id, custom_logger]

logCategory "finder"

type
  FinderItem* = object
    displayName*: string
    details*: seq[string]
    filterText*: string
    data*: string
    score*: float
    originalIndex: Option[int]
    filtered*: bool

type
  ItemList* = object
    len: int = 0
    cap: int = 0
    filtered*: int = 0
    data: ptr UncheckedArray[FinderItem] = nil

type
  DataSource* = ref object of RootObj
    onItemsChanged*: Event[ItemList]

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

method close*(self: DataSource) {.base, gcsafe, raises: [].} = discard
method setQuery*(self: DataSource, query: string) {.base, gcsafe, raises: [].} = discard

var allocated = 0

proc cmp*(a, b: FinderItem): int = cmp(a.score, b.score)
proc `<`*(a, b: FinderItem): bool = a.score < b.score

var itemListPool = newSeq[ItemList]()
proc newItemList*(len: int): ItemList {.gcsafe, raises: [].} =
  {.gcsafe.}:
    if itemListPool.len > 0:
      result = itemListPool.pop
      if result.cap < len:
        result.data = cast[ptr UncheckedArray[FinderItem]](
          realloc0(result.data.pointer, sizeof(FinderItem) * result.cap, sizeof(FinderItem) * len))
        result.cap = len

      result.len = len
      return

  result = ItemList(len: len, cap: len)
  if len > 0:
    result.data = cast[ptr UncheckedArray[FinderItem]](alloc0(sizeof(FinderItem) * len))

  allocated += len

func high*(list: ItemList): int = list.len - 1
func len*(list: ItemList): int = list.len
func filteredLen*(list: ItemList): int = list.len - list.filtered

proc free*(list: ItemList) =
  if not list.data.isNil:
    allocated -= list.len

    for i in 0..<list.len:
      `=destroy`(list.data[i])
    dealloc(list.data)

proc pool*(list: ItemList) {.gcsafe.} =
  {.gcsafe.}:
    if itemListPool.len > 5:
      list.free()

    else:
      var list = list
      if list.cap > 0:
        for i in 0..<list.len:
          list.data[i] = FinderItem()

      list.len = 0
      list.filtered = 0
      {.gcsafe.}:
        itemListPool.add list

proc setLen*(list: var ItemList, newLen: int) =
  assert newLen >= 0
  assert newLen <= list.len
  list.len = newLen

proc clone*(list: ItemList): ItemList =
  result = newItemList(list.len)
  for i in 0..<list.len:
    result.data[i] = list.data[i]

proc `[]=`*(list: var ItemList, i: int, item: sink FinderItem) =
  assert i >= 0
  assert i < list.len
  list.data[i] = item

proc `[]`*(list: ItemList, i: int): lent FinderItem =
  assert i >= 0
  assert i < list.len
  list.data[i]

proc `[]`*(list: var ItemList, i: int): var FinderItem =
  assert i >= 0
  assert i < list.len
  list.data[i]

template items*(list: ItemList): openArray[FinderItem] =
  # assert not list.data.isNil
  toOpenArray(list.data, 0, list.len - 1)

proc reverse*(list: ItemList) =
  var x = 0
  var y = list.len - 1
  while x < y:
    swap(list.data[x], list.data[y])
    dec(y)
    inc(x)

func sort*(list: ItemList, cmp: proc (x, y: FinderItem): int {.closure.},
           order = SortOrder.Descending) {.effectsOf: cmp.} =
  var list = list
  toOpenArray(list.data, 0, list.len - 1).sort(cmp, order)

proc sort*(list: ItemList, order = SortOrder.Descending) =
  var list = list
  toOpenArray(list.data, 0, list.len - 1).sort(order)

proc newItemList*(items: seq[FinderItem]): ItemList =
  result = newItemList(items.len)
  for i, item in items:
    result[i] = item

proc deinit*(finder: Finder) {.gcsafe, raises: [].} =
  if finder.source.isNotNil:
    finder.source.close()
  finder.source = nil
  if finder.filteredItems.getSome(list):
    list.pool()
  finder.filteredItems = ItemList.none

proc `=destroy`*(finder: typeof(Finder()[])) =
  if finder.source.isNotNil:
    finder.source.close()
  `=destroy`(finder.queries)
  if finder.filteredItems.getSome(list):
    list.pool()

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

proc filterAndSortItemsThread(args: tuple[queries: seq[string], list: ItemList, sort: bool, minScore: float, skipFirstQuery: bool]): FilterAndSortResult {.gcsafe.} =
  try:
    var list = args.list
    let scoreTimer = startTimer()
    if list.len > 0:
      result.filtered = 0

      for i, item in list.items.mpairs:
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
        for i, item in list.items.mpairs:
          if item.filtered:
            continue
          let filterText = if queryIndex == firstQueryIndex:
            if item.filterText.len > 0:
              item.filterText
            else:
              item.displayName
          else:
            let detailIndex = (queryIndex - 1) - firstQueryIndex
            if detailIndex in 0..item.details.high:
              item.details[detailIndex]
            else:
              ""

          item.score = matchFuzzySublime(args.queries[queryIndex], filterText, defaultCompletionMatchingConfig).score.float
          maxScore = max(maxScore, item.score)
          minScore = min(minScore, item.score)

        for item in list.items.mitems:
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

  except:
    discard

proc filterAndSortItems(self: Finder, list: ItemList): Future[void] {.async.} =
  assert self.queries.len > 0

  let versions = (query: self.queryVersion, items: self.itemsVersion)

  if versions == self.lastTriggeredFilterVersions:
    # already triggered a filter and search for current query and items
    return

  self.lastTriggeredFilterVersions = versions

  # todo: filter and sort on main thread if amount < threshold
  var filterResult = spawnAsync(filterAndSortItemsThread, (self.queries, list, self.sort, self.minScore, self.skipFirstQuery)).await

  # debugf"[filterAndSortItems] -> {versions}, {filterResult.scoreTime}ms, {filterResult.sortTime}ms, {filterResult.totalTime}ms"

  if self.itemsVersion != versions.items:
    # Items were updated after spawning this filter and sort, so discard the result
    list.pool()
    return

  if self.filteredItems.getSome(list):
    list.pool()

  var list = list
  list.filtered = filterResult.filtered
  self.filteredItems = list.some
  self.onItemsChanged.invoke()

proc handleItemsChanged(self: Finder, list: ItemList) =
  if self.source.isNil:
    list.pool()
    return

  inc self.itemsVersion

  if self.filterAndSort and self.queries.len > 0:
    asyncSpawn self.filterAndSortItems(list)
  else:
    if self.filteredItems.getSome(list):
      list.pool()
    self.filteredItems = list.some
    self.onItemsChanged.invoke()

proc setQuery*(self: Finder, query: string) =
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
      self.filteredItems.get.filtered = 0
      self.onItemsChanged.invoke()

    else:
      asyncSpawn self.filterAndSortItems(list.clone())

type
  StaticDataSource* = ref object of DataSource
    wasQueried: bool = false
    items: seq[FinderItem]

proc newStaticDataSource*(items: sink seq[FinderItem]): StaticDataSource =
  new result
  result.items = items

method setQuery*(self: StaticDataSource, query: string) =
  if self.wasQueried:
    return
  self.wasQueried = true

  var list = newItemList(self.items.len)
  for i, item in self.items:
    list[i] = item

  self.onItemsChanged.invoke list

type
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

proc getDataAsync(self: AsyncFutureDataSource): Future[void] {.async.} =
  let list = self.future.await
  self.onItemsChanged.invoke list

proc getDataAsync(self: AsyncCallbackDataSource): Future[void] {.async.} =
  let list = self.callback().await
  self.onItemsChanged.invoke list

proc newAsyncFutureDataSource*(future: Future[ItemList]): AsyncFutureDataSource =
  new result
  result.future = future

proc newAsyncCallbackDataSource*(callback: proc(): Future[ItemList] {.gcsafe, async: (raises: []).}): AsyncCallbackDataSource =
  new result
  result.callback = callback

proc newSyncDataSource*(callback: proc(): seq[FinderItem] {.gcsafe, raises: [].}): SyncDataSource =
  new result
  result.callbackSeq = callback

proc newSyncDataSource*(callback: proc(): ItemList {.gcsafe, raises: [].}): SyncDataSource =
  new result
  result.callbackList = callback

method setQuery*(self: AsyncFutureDataSource, query: string) {.gcsafe, raises: [].} =
  if not self.wasQueried:
    self.wasQueried = true
    asyncSpawn self.getDataAsync()

method setQuery*(self: AsyncCallbackDataSource, query: string) {.gcsafe, raises: [].} =
  if not self.wasQueried:
    self.wasQueried = true
    asyncSpawn self.getDataAsync()

method setQuery*(self: SyncDataSource, query: string) {.gcsafe, raises: [].} =
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

proc retrigger*(self: AsyncCallbackDataSource) {.gcsafe, raises: [].} =
  self.wasQueried = false
  self.setQuery("")

proc retrigger*(self: SyncDataSource) {.gcsafe, raises: [].} =
  self.wasQueried = false
  self.setQuery("")
