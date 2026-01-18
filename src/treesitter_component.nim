import std/[options, tables]
import misc/[custom_async]
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

# DLL API
var TreesitterComponentId* {.apprtl.}: ComponentTypeId

proc getTreesitterComponent*(self: ComponentOwner): Option[TreesitterComponent] {.apprtl, gcsafe, raises: [].}
proc treesitterComponentQuery*(self: TreesitterComponent, name: string): Future[Option[TSQuery]] {.apprtl, gcsafe, raises: [].}

# Nice wrappers
proc query*(self: TreesitterComponent, name: string): Future[Option[TSQuery]] = self.treesitterComponentQuery(name)

# Implementation
when implModule:
  import std/[strformat]
  import misc/[util, custom_logger]
  import text/custom_treesitter
  import vfs

  logCategory "treesitter-component"

  TreesitterComponentId = componentGenerateTypeId()

  type
    TreesitterComponentImpl* = ref object of TreesitterComponent
      vfs: VFS
      currentContentFailedToParse*: bool

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
    # todo
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
