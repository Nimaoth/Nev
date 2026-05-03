#use text_editor_component
import std/[options]
import nimsumtree/[buffer, clock, rope]
import misc/[custom_async, delayed_task, event]
import config_provider
import component

export component

const currentSourcePath2 = currentSourcePath()
include module_base

declareSettings MatchingWordHighlightSettings, "":
  ## Enable highlighting of text matching the current selection or word containing the cursor (if the selection is empty).
  declare enable, bool, true

  ## How long after moving the cursor matching text is highlighted.
  declare delay, int, 250

  ## Don't highlight matching text if the selection spans more bytes than this.
  declare maxSelectionLength, int, 1024

  ## Don't highlight matching text if the selection spans more lines than this.
  declare maxSelectionLines, int, 5

  ## Don't highlight matching text in files above this size (in bytes).
  declare maxFileSize, int, 1024*1024*100

type
  SearchComponent* = ref object of Component
    config*: ConfigStore
    matchingWordHiglightSettings*: MatchingWordHighlightSettings
    searchQuery*: string
    searchResults*: seq[Range[Point]]
    isUpdatingSearchResults: bool
    lastSearchResultUpdate: tuple[buffer: BufferId, version: Global, searchQuery: string]
    useMoveSearch*: bool
    isUpdatingMatchingWordHighlights: bool
    updateMatchingWordsTask: DelayedTask
    onSearchResultsUpdated*: Event[SearchComponent]

# DLL API
{.push rtl, gcsafe, raises: [].}
proc getSearchComponent*(self: ComponentOwner): Option[SearchComponent]
proc newSearchComponent*(config: ConfigStore): SearchComponent
proc updateMatchingWordHighlight*(self: SearchComponent)
proc updateSearchResults*(self: SearchComponent)
proc getSearchQuery*(self: SearchComponent): string
proc setSearchQuery*(self: SearchComponent, query: string, escapeRegex: bool = false, prefix: string = "", suffix: string = "", useMoveSearch: bool = false): bool
proc openSearchBar*(self: SearchComponent, query: string = "", scrollToPreview: bool = true, select: bool = true, useMoveSearch: bool = false)
proc getPrevFindResult*(self: SearchComponent, cursor: Point, offset: int = 0, includeAfter: bool = true, wrap: bool = true): Range[Point]
proc getNextFindResult*(self: SearchComponent, cursor: Point, offset: int = 0, includeAfter: bool = true, wrap: bool = true): Range[Point]
{.pop.}

# Nice wrappers

# Implementation
when implModule:
  import std/[sequtils]
  import misc/[util, custom_logger, id, rope_regex, regex, rope_utils]
  import document_editor, text_component, move_component, decoration_component, text_editor_component, command_service, config_component, service

  logCategory "search-component"

  var SearchComponentId: ComponentTypeId = componentGenerateTypeId()

  type SearchComponentImpl* = ref object of SearchComponent

  let searchResultsId = newId()
  let wordHighlightId = newId()

  proc getSearchComponent*(self: ComponentOwner): Option[SearchComponent] {.gcsafe, raises: [].} =
    return self.getComponent(SearchComponentId).mapIt(it.SearchComponent)

  proc newSearchComponent*(config: ConfigStore): SearchComponent =
    return SearchComponentImpl(
      typeId: SearchComponentId,
      config: config,
      matchingWordHiglightSettings: MatchingWordHighlightSettings.new(config),
    )

  proc markDirty(self: SearchComponent) =
    self.owner.DocumentEditor.markDirty()

  proc updateSearchResultsAsync(self: SearchComponent) {.async.} =
    if self.isUpdatingSearchResults:
      return
    self.isUpdatingSearchResults = true
    defer:
      self.isUpdatingSearchResults = false

    let editor = self.owner.DocumentEditor
    let edit = editor.getTextEditorComponent().get
    let decorations = editor.getDecorationComponent().get
    let moves = editor.getMoveComponent().get
    let text = editor.currentDocument.getTextComponent().get

    while true:
      let buffer = text.buffer.snapshot.clone()
      let searchQuery = self.searchQuery
      let useMoveSearch = self.useMoveSearch
      if searchQuery.len == 0:
        decorations.clearCustomHighlights(searchResultsId)
        self.searchResults.setLen(0)
        self.markDirty()
        return

      if self.lastSearchResultUpdate == (buffer.remoteId, buffer.version, searchQuery) and not self.useMoveSearch:
        return

      var searchResults: seq[Range[Point]]
      if useMoveSearch:
        let results = moves.applyMove(edit.selections, searchQuery)
        searchResults = results.mapIt(it)
      else:
        searchResults = await findAllAsync(buffer.visibleText.slice(int), searchQuery)

      if editor.currentDocument.isNil:
        return

      self.searchResults = searchResults
      self.lastSearchResultUpdate = (buffer.remoteId, buffer.version, searchQuery)
      decorations.clearCustomHighlights(searchResultsId)
      for s in searchResults:
        decorations.addCustomHighlight(searchResultsId, s, "editor.findMatchBackground")

      self.onSearchResultsUpdated.invoke(self)

      if text.buffer.remoteId != buffer.remoteId or text.buffer.version != buffer.version:
        continue

      if self.searchQuery != searchQuery:
        continue

      self.markDirty()
      break

  proc updateSearchResults*(self: SearchComponent) =
    asyncSpawn self.updateSearchResultsAsync()

  proc getSearchQuery*(self: SearchComponent): string =
    return self.searchQuery

  proc setSearchQuery*(self: SearchComponent, query: string, escapeRegex: bool = false, prefix: string = "", suffix: string = "", useMoveSearch: bool = false): bool =
    debugf"setSearchQuery '{query}'"

    let query = if escapeRegex:
      query.escapeRegex
    else:
      query

    let finalQuery = prefix & query & suffix
    if self.searchQuery == finalQuery and self.useMoveSearch == useMoveSearch:
      return false

    self.searchQuery = finalQuery
    self.useMoveSearch = useMoveSearch
    self.updateSearchResults()
    return true

  proc useInclusiveSelections*(self: SearchComponent): bool =
    self.config.get("text.inclusive-selection", false)

  proc updateMatchingWordHighlightAsync(self: SearchComponent) {.async.} =
    if self.isUpdatingMatchingWordHighlights:
      return
    self.isUpdatingMatchingWordHighlights = true
    defer:
      self.isUpdatingMatchingWordHighlights = false

    let editor = self.owner.DocumentEditor
    let edit = editor.getTextEditorComponent().get
    let decorations = editor.getDecorationComponent().get
    let moves = editor.getMoveComponent().get
    let text = editor.currentDocument.getTextComponent().get

    while true:
      let content = text.content
      if content.len > self.matchingWordHiglightSettings.maxFileSize.get():
        return

      var oldSelection = edit.selection.normalized
      if oldSelection.b.row.int - oldSelection.a.row.int > self.matchingWordHiglightSettings.maxSelectionLines.get():
        return

      oldSelection = content.clampOnLine(oldSelection)

      let (selection, inclusive, addWordBoundary) = if oldSelection.isEmpty:
        var s = moves.applyMove(oldSelection.b...oldSelection.b, "(vim.word)", includeEol=false).normalized
        const AlphaNumeric = {'A'..'Z', 'a'..'z', '0'..'9', '_'}
        if content.charAt(s.a) notin AlphaNumeric:
          let prev = point(oldSelection.b.row, oldSelection.b.column - 1)
          if s.a.column > 0 and content.charAt(prev) in AlphaNumeric:
            s = moves.applyMove(prev...prev, "(vim.word)", includeEol=false).normalized
          else:
            decorations.clearCustomHighlights(wordHighlightId)
            return
        if content.charAt(s.a) notin AlphaNumeric:
          decorations.clearCustomHighlights(wordHighlightId)
          return
        (s, false, true)
      else:
        (oldSelection.normalized, self.useInclusiveSelections, false)

      let startByte = content.pointToOffset(selection.a)
      let endByte = content.pointToOffset(selection.b)
      assert endByte >= startByte

      if endByte - startByte > self.matchingWordHiglightSettings.maxSelectionLength.get():
        return

      let contentString = text.content(selection, inclusive)
      if contentString.isEmptyOrWhitespace:
        decorations.clearCustomHighlights(wordHighlightId)
        return

      var regex = contentString.escapeRegex
      if addWordBoundary:
        regex = "\\b" & regex & "\\b"

      try:
        let version = text.buffer.version
        let ranges = await findAllAsync(content.slice(int), regex)
        if editor.currentDocument.isNil:
          return
        if text.buffer.version != version or edit.selection != oldSelection:
          continue

        decorations.clearCustomHighlights(wordHighlightId)
        for r in ranges:
          decorations.addCustomHighlight(wordHighlightId, r, "matching-text-highlight")

        break
      except Exception as e:
        log lvlError, &"Failed to find matching words: {e.msg}"

  proc updateMatchingWordHighlight*(self: SearchComponent) =
    let editor = self.owner.DocumentEditor
    let decorations = editor.getDecorationComponent().get
    if not self.matchingWordHiglightSettings.enable.get():
      decorations.clearCustomHighlights(wordHighlightId)
      return

    if self.isUpdatingMatchingWordHighlights:
      return

    if self.updateMatchingWordsTask.isNil:
      self.updateMatchingWordsTask = startDelayed(2, repeat=false):
        if editor.currentDocument.isNil:
          return
        asyncSpawn self.updateMatchingWordHighlightAsync()

    self.updateMatchingWordsTask.interval = self.matchingWordHiglightSettings.delay.get()
    self.updateMatchingWordsTask.schedule()

  proc getPrevFindResult*(self: SearchComponent, cursor: Point, offset: int = 0, includeAfter: bool = true, wrap: bool = true): Range[Point] =
    self.updateSearchResults()

    if self.searchResults.len == 0:
      return cursor.toRange

    let (found, index) = self.searchResults.binarySearchRange(cursor, Bias.Left, proc(r: Range[Point], p: Point): int = cmp(r.a, p))
    if found:
      if index > 0:
        result = self.searchResults[index - 1]
      elif wrap:
        result = self.searchResults.last
      else:
        return cursor.toRange
    elif index == 0 and cursor < self.searchResults[0].a:
      if wrap:
        result = self.searchResults.last
      else:
        return cursor.toRange
    elif index >= 0:
      result = self.searchResults[index]
    else:
      return cursor.toRange

    if not includeAfter:
      let moves = self.owner.getMoveComponent().get
      result.b = moves.applyMove(result.b...result.b, "(column -1)", wrap=false).b

  proc getNextFindResult*(self: SearchComponent, cursor: Point, offset: int = 0, includeAfter: bool = true, wrap: bool = true): Range[Point] =
    self.updateSearchResults()

    if self.searchResults.len == 0:
      return cursor.toRange

    let (found, index) = self.searchResults.binarySearchRange(cursor, Bias.Right, proc(r: Range[Point], p: Point): int = cmp(r.a, p))
    if found:
      if index < self.searchResults.high:
        result = self.searchResults[index + 1]
      elif wrap:
        result = self.searchResults[0]
      else:
        return cursor.toRange
    elif index == self.searchResults.len:
      if wrap:
        result = self.searchResults[0]
      else:
        return cursor.toRange
    elif index >= 0 and index <= self.searchResults.high:
      result = self.searchResults[index]
    else:
      return cursor.toRange

    if not includeAfter:
      let moves = self.owner.getMoveComponent().get
      result.b = moves.applyMove(result.b...result.b, "(column -1)", wrap=false).b

  proc openSearchBar*(self: SearchComponent, query: string = "", scrollToPreview: bool = true, select: bool = true, useMoveSearch: bool = false) =
    let editor = self.owner.DocumentEditor

    let editors = getServiceChecked(DocumentEditorService)
    let commandLineEditor = editors.commandLineEditor
    if commandLineEditor == editor:
      return
    let commands = getServiceChecked(CommandService)

    let edit = editor.getTextEditorComponent().get

    let prevSearchQuery = self.searchQuery
    let prevUseMoveSearch = self.useMoveSearch
    let document = commandLineEditor.currentDocument
    let commandEdit = commandLineEditor.getTextEditorComponent().get
    let commandText = document.getTextComponent().get

    var onEditHandle = Id.new
    var onActiveHandle = Id.new
    var onSearchHandle = Id.new

    commands.openCommandLine "", "/", proc(command: Option[string]): Option[string] =
      commandText.onEdit.unsubscribe(onEditHandle[])
      if command.getSome(command):
        discard self.setSearchQuery(command, useMoveSearch = useMoveSearch)
        if select:
          edit.selection = self.getNextFindResult(edit.selection.b).a.toRange
        edit.scrollToCursor(edit.selection.b)
      else:
        discard self.setSearchQuery(prevSearchQuery, useMoveSearch = prevUseMoveSearch)
        if scrollToPreview:
          edit.scrollToCursor(edit.selection.b)

    commandLineEditor.getConfigComponent().get.set("text.disable-completions", true)
    commandEdit.selection = commandLineEditor.getMoveComponent().get.applyMove(point(0, 0).toRange, "(file) (end)")
    commandEdit.updateTargetColumn(commandEdit.selection.b)

    onEditHandle[] = commandText.onEdit.subscribe proc(arg: tuple[oldText: Rope, patch: Patch[Point]]) =
      discard self.setSearchQuery(($commandText.content).replace(r".set-search-query \"), useMoveSearch = useMoveSearch)

    onActiveHandle[] = commandLineEditor.onActiveChanged.subscribe proc(editor: DocumentEditor) =
      if not editor.active:
        commandText.onEdit.unsubscribe(onEditHandle[])
        commandLineEditor.onActiveChanged.unsubscribe(onActiveHandle[])
        self.onSearchResultsUpdated.unsubscribe(onSearchHandle[])

    onSearchHandle[] = self.onSearchResultsUpdated.subscribe proc(_: SearchComponent) =
      if self.searchResults.len == 0:
        edit.scrollToCursor(edit.selection.b)
      else:
        let s = self.getNextFindResult(edit.selection.b)
        if scrollToPreview:
          edit.scrollToCursor(s.b)

  proc init_module_search_component*() {.cdecl, exportc, dynlib.} =
    discard
