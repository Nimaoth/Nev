import std/[strformat, terminal, typetraits, enumutils, strutils, unicode, algorithm, sequtils, os, sugar]
import misc/[regex, timer, fuzzy_matching, util, custom_async, event, id, custom_logger]
import platform/[filesystem]

logCategory "finder"

type

  FinderItem* = object
    displayName*: string
    filterText*: string
    path*: string
    score*: float

  ItemList* = ref object of RootObj
    discard

  ItemListT*[T: FinderItem] = ref object of ItemList
    items: seq[T]

  DataSource* = ref object of RootObj
    onItemsChanged*: Event[seq[FinderItem]]

  Finder* = ref object
    source*: DataSource
    query*: string
    items*: seq[FinderItem]
    filteredItems*: seq[FinderItem]
    # items*: ItemList
    # filteredItems*: ItemList

    filterAndSort: bool

    queryVersion: int
    itemsVersion: int

    lastTriggeredFilterVersions: tuple[query, items: int]

    onItemsChangedHandle: Id
    onItemsChanged*: Event[void]


method get*(list: ItemList, i: int): lent FinderItem {.base.} = discard
method get*[T](list: ItemListT[T], i: int): lent FinderItem = list.items[i]
method `[]`*[T](list: ItemListT[T], i: int): lent T = list.items[i]

proc handleItemsChanged(self: Finder, items: seq[FinderItem])

method setQuery*(self: DataSource, query: string) {.base.} = discard

proc newFinder*(source: DataSource, filterAndSort: bool = true): Finder =
  new result
  var self = result
  result.source = source
  result.filterAndSort = filterAndSort
  result.onItemsChangedHandle = source.onItemsChanged.subscribe proc(items: seq[FinderItem]) = self.handleItemsChanged(items)

proc cmp*(a, b: FinderItem): int = cmp(a.score, b.score)
proc `<`*(a, b: FinderItem): bool = a.score < b.score

type FilterAndSortResult = object
  items: seq[FinderItem]
  scoreTime: float
  sortTime: float
  totalTime: float

proc filterAndSortItemsThread(args: (string, seq[FinderItem])): FilterAndSortResult {.gcsafe.} =
  try:
    let query = args[0]

    let scoreTimer = startTimer()
    for item in args[1]:
      let score = matchFuzzySublime(query, item.filterText, defaultCompletionMatchingConfig).score.float
      if score < 0:
        continue

      var newItem = item
      newItem.score = score
      result.items.add newItem

    result.scoreTime = scoreTimer.elapsed.ms

    let sortTimer = startTimer()
    result.items.sort(Ascending)
    result.sortTime = sortTimer.elapsed.ms

    result.totalTime = result.scoreTime + result.sortTime

  except:
    discard

proc filterAndSortItems(self: Finder): Future[void] {.async.} =
  if self.query.len == 0:
    self.filteredItems = self.items
    self.filteredItems.reverse()
    self.onItemsChanged.invoke()
    return

  let versions = (query: self.queryVersion, items: self.itemsVersion)

  if versions == self.lastTriggeredFilterVersions:
    # already triggered a filter and search for current query and items
    debugf"[filterAndSortItems] already started for {versions}"
    return

  debugf"[filterAndSortItems] start {versions}"
  self.lastTriggeredFilterVersions = versions

  # todo: filter and sort on main thread if amount < threshold
  let filterResult = spawnAsync(filterAndSortItemsThread, (self.query, self.items)).await
  debugf"[filterAndSortItems] -> {versions}, {filterResult.scoreTime}ms, {filterResult.sortTime}ms, {filterResult.totalTime}ms"

  if self.itemsVersion != versions.items:
    # Items were updated after spawning this filter and sort, so discard the result
    debugf"[filterAndSortItems] stale {versions} (current: {self.queryVersion}, {self.itemsVersion})"
    return

  self.filteredItems = filterResult.items
  self.onItemsChanged.invoke()

proc handleItemsChanged(self: Finder, items: seq[FinderItem]) =
  debugf"[handleItemsChanged] {items.len}"
  self.items = items
  inc self.itemsVersion

  if self.filterAndSort:
    if self.filteredItems.len == 0:
      self.filteredItems = self.items
      self.onItemsChanged.invoke()
    asyncCheck self.filterAndSortItems()
  else:
    self.filteredItems = self.items
    self.filteredItems.reverse()
    self.onItemsChanged.invoke()

proc setQuery*(self: Finder, query: string) =
  debugf"[setQuery] '{query}'"
  self.query = query
  self.queryVersion.inc
  self.source.setQuery(query)

  # todo: add optional delay so we don't spawn tasks on every keystroke, but only after stopping for a bit.
  if self.filterAndSort and self.items.len > 0:
    debugf"[setQuery] filterAndSortItems"
    asyncCheck self.filterAndSortItems()
