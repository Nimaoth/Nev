import std/[options, tables]
import nimsumtree/[arc]
import misc/[custom_async]
import component
import text/treesitter_types
import text/syntax_map
import vfs

export component
export treesitter_types
export syntax_map

include dynlib_export

type
  TreesitterComponent* = ref object of Component
    tsLanguage*: TSLanguage
    highlightQuery*: TSQuery
    textObjectsQuery*: TSQuery
    tagsQuery*: TSQuery
    errorQuery*: TSQuery
    tsQueries*: Table[string, Option[TSQuery]]
    syntaxMap*: SyntaxMap

# DLL API

{.push apprtl, gcsafe, raises: [].}
proc newTreesitterComponent*(vfs: Arc[VFS2]): TreesitterComponent
proc getTreesitterComponent*(self: ComponentOwner): Option[TreesitterComponent]
proc treesitterComponentQuery*(self: TreesitterComponent, name: string, language: string = ""): Future[Option[TSQuery]]
proc treesitterComponentClear(self: TreeSitterComponent)
{.pop.}

# Nice wrappers
proc query*(self: TreesitterComponent, name: string, language: string = ""): Future[Option[TSQuery]] = self.treesitterComponentQuery(name, language)
proc clear*(self: TreeSitterComponent) = treesitterComponentClear(self)

# Implementation
when implModule:
  import std/[strformat]
  import misc/[util, custom_logger]
  import text/custom_treesitter

  logCategory "treesitter-component"

  let TreesitterComponentId = componentGenerateTypeId()

  type
    TreesitterComponentImpl* = ref object of TreesitterComponent
      vfs: Arc[VFS2]
      requestedLanguages: seq[string]

  proc treesitterComponentClear(self: TreeSitterComponent) =
    let self = self.TreesitterComponentImpl
    self.tsQueries.clear()
    self.highlightQuery = nil
    self.textObjectsQuery = nil
    self.tagsQuery = nil
    self.errorQuery = nil
    self.tsLanguage = nil
    self.syntaxMap.clear()

  proc getTreesitterComponent*(self: ComponentOwner): Option[TreesitterComponent] {.gcsafe, raises: [].} =
    return self.getComponent(TreesitterComponentId).mapIt(it.TreesitterComponent)

  proc loadInjectionLanguageAsync(self: TreesitterComponentImpl, languageName: string) {.async.} =
    if languageName in self.requestedLanguages:
      return
    self.requestedLanguages.add languageName
    let language = await getTreesitterLanguage(self.vfs, languageName)
    if language.isNone:
      log lvlWarn, &"loadInjectionLanguageAsync: Failed to load language '{languageName}'"
      return
    let lang = language.get
    # Load highlights and injections queries for the newly loaded language so
    # subsequent parses can use them directly from lang.queries.
    let highlightsPath = &"app://languages/{languageName}/queries/highlights.scm"
    discard await lang.queryFile(self.vfs, "highlights", highlightsPath, cacheOnFail = false)
    let injectionsPath = &"app://languages/{languageName}/queries/injections.scm"
    discard await lang.queryFile(self.vfs, "injections", injectionsPath, cacheOnFail = false)
    # Retrigger parsing now that the language (and its queries) are available
    self.syntaxMap.reparse()

  proc newTreesitterComponent*(vfs: Arc[VFS2]): TreesitterComponent =
    let sm = newSyntaxMap()
    let comp = TreesitterComponentImpl(
      typeId: TreesitterComponentId,
      syntaxMap: sm,
      vfs: vfs,
    )
    sm.loadInjectionLanguage = proc(languageName: string) {.gcsafe, raises: [].} =
      asyncSpawn comp.loadInjectionLanguageAsync(languageName)
    return comp

  proc treesitterComponentQuery*(self: TreesitterComponent, name: string, language: string = ""): Future[Option[TSQuery]] {.async.} =
    let self = self.TreesitterComponentImpl
    let language = if language == "":
      if self.tsLanguage.isNil: "" else: self.tsLanguage.languageId
    else:
      language

    let key = &"{language}/{name}"
    let tsLanguage = getLoadedLanguage(language)

    self.tsQueries.withValue(key, q):
      if q[].isSome:
        return q[].get.some
      return TSQuery.none

    if tsLanguage.isNil:
      return TSQuery.none

    # todo
    # let treesitterLanguageName = self.settings.treesitter.language.get().get(tsLanguage.languageId)
    let treesitterLanguageName = tsLanguage.languageId
    let path = &"app://languages/{treesitterLanguageName}/queries/{name}.scm"
    let query = tsLanguage.queryFile(self.vfs, name, path).await

    self.tsQueries[key] = query
    if query.isSome:
      return query.get.some
    return TSQuery.none
