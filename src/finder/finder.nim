import std/[strformat, terminal, typetraits, enumutils, strutils, unicode, algorithm, sequtils, os, sugar]
import misc/[regex, timer, fuzzy_matching, util, custom_async, event, id, custom_logger]
import platform/[filesystem]

logCategory "finder"

type

  FinderItem* = object
    displayName*: string
    detail*: string
    filterText*: string
    data*: string
    score*: float
    originalScore: float

  ItemList* = object
    counter: int = 0
    len: int = 0
    cap: int = 0
    data: ptr UncheckedArray[FinderItem] = nil

  DataSource* = ref object of RootObj
    onItemsChanged*: Event[ItemList]

  Finder* = ref object
    source*: DataSource
    query*: string
    filteredItems*: Option[ItemList]

    filterAndSort: bool
    filterThreshold*: float = 0

    queryVersion: int
    itemsVersion: int

    lastTriggeredFilterVersions: tuple[query, items: int]

    onItemsChangedHandle: Id
    onItemsChanged*: Event[void]

method close*(self: DataSource) {.base.} = discard
method setQuery*(self: DataSource, query: string) {.base.} = discard

var copyCounter = 0
var allocated = 0

proc cmp*(a, b: FinderItem): int = cmp(a.score, b.score)
proc `<`*(a, b: FinderItem): bool = a.score < b.score # echo "xvlc"

var itemListPool = newSeq[ItemList]()
proc newItemList*(len: int): ItemList =
  if itemListPool.len > 0:
  #   defer:
  #     debugf"reuseing item list #{result.counter}, len = {result.len}/{result.cap}, allocated = {allocated}"

    result = itemListPool.pop
    if result.cap < len:
      result.data = cast[ptr UncheckedArray[FinderItem]](
        realloc0(result.data.pointer, sizeof(FinderItem) * result.cap, sizeof(FinderItem) * len))
      result.cap = len
    result.len = len
    return

  inc copyCounter
  result = ItemList(counter: copyCounter, len: len, cap: len)
  if len > 0:
    result.data = cast[ptr UncheckedArray[FinderItem]](alloc0(sizeof(FinderItem) * len))
  allocated += len
  # debugf"---[newItemList] #{result.counter}, len = {len}, allocated = {allocated}"

func high*(list: ItemList): int = list.len - 1
func len*(list: ItemList): int = list.len

proc free*(list: ItemList) =
  if not list.data.isNil:
    allocated -= list.len
    # debugf"---[free] #{list.counter}, len = {list.len}/{list.cap}, allocated = {allocated}"

    for i in 0..<list.len:
      `=destroy`(list.data[i])
    dealloc(list.data)

proc pool*(list: ItemList) =
  if itemListPool.len > 5:
    list.free()
  elif list.cap > 0:
    # debugf"[pool] #{list.counter}, len = {list.len}/{list.cap}"
    var list = list
    for i in 0..<list.len:
      list.data[i] = FinderItem()
    list.len = 0
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
  assert not list.data.isNil
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

proc deinit*(finder: Finder) =
  if finder.source.isNotNil:
    finder.source.close()
  finder.source = nil
  if finder.filteredItems.getSome(list):
    list.pool()
  finder.filteredItems = ItemList.none

proc `=destroy`*(finder: typeof(Finder()[])) =
  if finder.source.isNotNil:
    finder.source.close()
  `=destroy`(finder.query)
  if finder.filteredItems.getSome(list):
    list.pool()

proc handleItemsChanged(self: Finder, list: ItemList)

proc newFinder*(source: DataSource, filterAndSort: bool = true): Finder =
  new result
  var self = result
  result.source = source
  result.filterAndSort = filterAndSort
  result.onItemsChangedHandle = source.onItemsChanged.subscribe proc(items: ItemList) =
    self.handleItemsChanged(items)

type FilterAndSortResult = object
  scoreTime: float
  sortTime: float
  totalTime: float

proc filterAndSortItemsThread(args: (string, ItemList)): FilterAndSortResult {.gcsafe.} =
  try:
    let query = args[0]
    var list = args[1]

    let scoreTimer = startTimer()
    if list.len > 0:
      for item in list.items.mitems:
        let filterText = if item.filterText.len > 0:
          item.filterText
        else:
          item.displayName
        item.score = matchFuzzySublime(query, filterText, defaultCompletionMatchingConfig).score.float

    result.scoreTime = scoreTimer.elapsed.ms

    let sortTimer = startTimer()
    list.sort(Descending)
    result.sortTime = sortTimer.elapsed.ms

    result.totalTime = result.scoreTime + result.sortTime

  except:
    discard

proc filterAndSortItems(self: Finder, list: ItemList): Future[void] {.async.} =
  assert self.query.len > 0

  let versions = (query: self.queryVersion, items: self.itemsVersion)

  if versions == self.lastTriggeredFilterVersions:
    # already triggered a filter and search for current query and items
    return

  self.lastTriggeredFilterVersions = versions

  # todo: filter and sort on main thread if amount < threshold
  var filterResult = spawnAsync(filterAndSortItemsThread, (self.query, list)).await
  debugf"[filterAndSortItems] -> {versions}, {filterResult.scoreTime}ms, {filterResult.sortTime}ms, {filterResult.totalTime}ms"

  if self.itemsVersion != versions.items:
    # Items were updated after spawning this filter and sort, so discard the result
    list.pool()
    return

  if self.filteredItems.getSome(list):
    list.pool()

  self.filteredItems = list.some
  self.onItemsChanged.invoke()

proc handleItemsChanged(self: Finder, list: ItemList) =
  if self.source.isNil:
    list.pool()
    return

  inc self.itemsVersion

  if self.filterAndSort and self.query.len > 0:
    asyncCheck self.filterAndSortItems(list)
  else:
    list.reverse()
    if self.filteredItems.getSome(list):
      list.pool()
    self.filteredItems = list.some
    self.onItemsChanged.invoke()

proc setQuery*(self: Finder, query: string) =
  self.query = query
  self.queryVersion.inc
  self.source.setQuery(query)

  # todo: add optional delay so we don't spawn tasks on every keystroke, but only after stopping for a bit.
  if self.filterAndSort and self.filteredItems.getSome(list):
    var mlist = list
    if self.query.len == 0:
      for i in 0..<mlist.len:
        mlist[i].score = mlist[i].originalScore
      mlist.sort((a, b) => cmp(a.originalScore, b.originalScore), Descending)
      self.onItemsChanged.invoke()

    else:
      asyncCheck self.filterAndSortItems(list.clone())

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
    callback: proc(): Future[ItemList]

  SyncDataSource* = ref object of DataSource
    wasQueried: bool = false
    callbackSeq: proc(): seq[FinderItem]
    callbackList: proc(): ItemList

proc getDataAsync(self: AsyncFutureDataSource): Future[void] {.async.} =
  let list = self.future.await
  self.onItemsChanged.invoke list

proc getDataAsync(self: AsyncCallbackDataSource): Future[void] {.async.} =
  let list = self.callback().await
  self.onItemsChanged.invoke list

proc newAsyncFutureDataSource*(future: Future[ItemList]): AsyncFutureDataSource =
  new result
  result.future = future

proc newAsyncCallbackDataSource*(callback: proc(): Future[ItemList]): AsyncCallbackDataSource =
  new result
  result.callback = callback

proc newSyncDataSource*(callback: proc(): seq[FinderItem]): SyncDataSource =
  new result
  result.callbackSeq = callback

proc newSyncDataSource*(callback: proc(): ItemList): SyncDataSource =
  new result
  result.callbackList = callback

method setQuery*(self: AsyncFutureDataSource, query: string) =
  if not self.wasQueried:
    self.wasQueried = true
    asyncCheck self.getDataAsync()

method setQuery*(self: AsyncCallbackDataSource, query: string) =
  if not self.wasQueried:
    self.wasQueried = true
    asyncCheck self.getDataAsync()

method setQuery*(self: SyncDataSource, query: string) =
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

proc retrigger*(self: AsyncCallbackDataSource) =
  self.wasQueried = false
  self.setQuery("")

proc retrigger*(self: SyncDataSource) =
  self.wasQueried = false
  self.setQuery("")
