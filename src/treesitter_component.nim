import std/[options, tables]
import misc/[custom_async]
import nimsumtree/[rope]
import component
import text/treesitter_types

export component
export treesitter_types

include dynlib_export

type
  TreesitterComponent* = ref object of Component
    tsLanguage*: TSLanguage
    currentTree*: TSTree
    highlightQuery*: TSQuery
    textObjectsQuery*: TSQuery
    errorQuery*: TSQuery
    tsQueries*: Table[string, Option[TSQuery]]
  # Query* = ref object of RootObj
  # QueryIter* = ref object of RootObj

# DLL API
var TreesitterComponentId* {.apprtl.}: ComponentTypeId

proc getTreesitterComponent*(self: ComponentOwner): Option[TreesitterComponent] {.apprtl, gcsafe, raises: [].}
proc treesitterComponentQuery*(self: TreesitterComponent, name: string): Future[Option[TSQuery]] {.apprtl, gcsafe, raises: [].}
# proc treesitterQueryIter*(query: Query, r: Range[Point]): QueryIter {.apprtl, gcsafe, raises: [].}
# proc treesitterQueryIterNext*(queryIter: QueryIter): Option[TSQueryMatch] {.apprtl, gcsafe, raises: [].}

# Nice wrappers
proc query*(self: TreesitterComponent, name: string): Future[Option[TSQuery]] = self.treesitterComponentQuery(name)

# Implementation
when implModule:
  import std/[strformat, sequtils]
  import misc/[util, myjsonutils, custom_logger, rope_utils, arena]
  import text/custom_treesitter
  import vfs

  logCategory "treesitter-component"

  TreesitterComponentId = componentGenerateTypeId()

  type
    TreesitterComponentImpl* = ref object of TreesitterComponent
      vfs: VFS
      currentContentFailedToParse*: bool

    # QueryImpl* = ref object of Query
    #   tsQuery: TSQuery
    #   tree: TSTree

    # QueryIterImpl* = ref object of QueryIter
    #   iter: iterator(queryIter: QueryIterImpl): TSQueryMatch {.gcsafe, raises: [].}
    #   query: QueryImpl
    #   r: Range[Point]
    #   arena: Arena

  proc clear*(self: TreeSitterComponent) =
    let self = self.TreesitterComponentImpl
    self.tsQueries.clear()
    self.highlightQuery = nil
    self.textObjectsQuery = nil
    self.errorQuery = nil
    self.currentContentFailedToParse = false
    self.tsLanguage = nil
    if not self.currentTree.isNil:
      self.currentTree.delete()

  proc getTreesitterComponent*(self: ComponentOwner): Option[TreesitterComponent] {.gcsafe, raises: [].} =
    return self.getComponent(TreesitterComponentId).mapIt(it.TreesitterComponent)

  proc newTreesitterComponent*(vfs: VFS): TreesitterComponentImpl =
    return TreesitterComponentImpl(
      typeId: TreesitterComponentId,
      currentTree: TSTree(),
      vfs: vfs,
    )

  proc treesitterComponentQuery*(self: TreesitterComponent, name: string): Future[Option[TSQuery]] {.async.} =
    let self = self.TreesitterComponentImpl
    self.tsQueries.withValue(name, q):
      if q[].isSome:
        return q[].get.some
      return TSQuery.none

    if self.tsLanguage.isNil:
      return TSQuery.none

    let prevLanguageId = self.tsLanguage.languageId
    # let treesitterLanguageName = self.settings.treesitter.language.get().get(self.tsLanguage.languageId)
    let treesitterLanguageName = self.tsLanguage.languageId
    let path = &"app://languages/{treesitterLanguageName}/queries/{name}.scm"
    let query = self.tsLanguage.queryFile(self.vfs, name, path).await
    if prevLanguageId != self.tsLanguage.languageId:
      return TSQuery.none

    self.tsQueries[name] = query
    if query.isSome:
      return query.get.some
    return TSQuery.none

  # iterator queryMatches(queryIter: QueryIterImpl): TSQueryMatch {.closure, gcsafe, raises: [].} =
  #   for m in queryIter.query.tsQuery.matches(queryIter.query.tree.root, queryIter.r.toSelection.tsRange, queryIter.arena):
  #     yield m

  # proc treesitterQueryIter*(query: Query, r: Range[Point]): QueryIter =
  #   let query = query.QueryImpl
  #   return QueryIterImpl(iter: queryMatches, query: query, r: r, arena: initArena())

  # proc treesitterQueryIterNext*(queryIter: QueryIter): Option[TSQueryMatch] =
  #   let queryIter = queryIter.QueryIterImpl
  #   let res = queryIter.iter(queryIter)
  #   if finished(queryIter.iter):
  #     return TSQueryMatch.none
  #   return res.some
