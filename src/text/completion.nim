import std/[strutils, sugar, sets, algorithm, json, tables]
import misc/[custom_unicode, util, id, custom_async, event, timer, custom_logger, fuzzy_matching]
import language/[lsp_types, language_server_base]
import config_provider
import scripting_api

logCategory "completion"

type
  Completion* = object
    item*: CompletionItem
    filterText*: string
    providerIndex: int
    score*: float

  CompletionProvider* = ref object of RootObj
    onCompletionsUpdated: Event[CompletionProvider]
    location: Cursor
    filteredCompletions: seq[Completion]
    currentFilterText: string

  CompletionEngine* = ref object
    providers: seq[tuple[provider: CompletionProvider, onCompletionsUpdatedHandle: Id]]
    combinedCompletions: seq[Completion]
    combinedProviderIndices: seq[int]
    onCompletionsUpdated*: Event[void]
    combinedDirty: bool

method forceUpdateCompletions*(provider: CompletionProvider) {.base.} = discard

proc updateCompletionsAt*(self: CompletionEngine, location: Cursor) =
  for provider in self.providers:
    provider.provider.location = location
    provider.provider.forceUpdateCompletions()

proc cmp(a, b: Completion): int =
  let preselectA = a.item.preselect.get(false)
  let preselectB = a.item.preselect.get(false)
  if preselectA and not preselectB:
    return -1
  if not preselectA and preselectB:
    return 1

  cmp(a.score, b.score)

proc updateCombinedCompletions(self: CompletionEngine) =
  let timer = startTimer()
  self.combinedCompletions.setLen 0
  self.combinedProviderIndices.setLen 0

  for i, provider in self.providers:
    for c in provider.provider.filteredCompletions:
      self.combinedCompletions.add c
      self.combinedProviderIndices.add i

  self.combinedCompletions.sort(cmp, Descending)
  self.combinedDirty = false

  log lvlInfo, &"[Comp] Combine completions took {timer.elapsed.ms}. {self.combinedCompletions.len} completions."

proc handleProviderCompletionsUpdated(self: CompletionEngine, provider: CompletionProvider) =
  self.combinedDirty = true
  self.onCompletionsUpdated.invoke()

proc setCurrentLocation*(self: CompletionEngine, location: Cursor) =
  for provider in self.providers:
    provider.provider.location = location

proc getCompletions*(self: CompletionEngine): lent seq[Completion] =
  if self.combinedDirty:
    self.updateCombinedCompletions()
  self.combinedCompletions

proc addProvider*(self: CompletionEngine, provider: CompletionProvider) =
  let handle = provider.onCompletionsUpdated.subscribe (provider: CompletionProvider) => self.handleProviderCompletionsUpdated(provider)
  self.providers.add (provider, handle)

proc removeProvider*(self: CompletionEngine, provider: CompletionProvider) =
  for i in 0..self.providers.high:
    if self.providers[i].provider == provider:
      provider.onCompletionsUpdated.unsubscribe self.providers[i].onCompletionsUpdatedHandle
      self.providers.removeShift(i)

      # Remove completions of the removed provider and update provider indices
      for k in countdown(self.combinedCompletions.high, 0):
        if self.combinedProviderIndices[k] > i:
          dec self.combinedProviderIndices[k]
        elif self.combinedProviderIndices[k] == i:
          self.combinedCompletions.removeShift(k)
          self.combinedProviderIndices.removeShift(k)

      return

import text_document

type
  CompletionProviderDocument* = ref object of CompletionProvider
    document: TextDocument
    textInsertedHandle: Id
    textDeletedHandle: Id
    wordCache: HashSet[string]

proc updateIndexFromContentAsync(self: CompletionProviderDocument) {.async.} =
  while self.document.isNotNil:
    await sleepAsync(100)

proc cacheLine(self: CompletionProviderDocument, line: int) =
  let line = self.document.getLine(line)

  var i = 0.RuneIndex
  var wordStart = 0.RuneIndex
  var runeLen = 0.RuneCount
  for r in line.runes:
    inc runeLen
    let isWord = r.char in IdentChars or r.isAlpha
    if not isWord:
      let len = i - wordStart
      if len > 1.RuneCount:
        self.wordCache.incl line[wordStart..<i]
      wordStart = i + 1.RuneCount

    inc i

  if wordStart < runeLen:
    self.wordCache.incl line[wordStart..<runeLen.RuneIndex]

proc updateFilterText(self: CompletionProviderDocument) =
  let selection = self.document.getCompletionSelectionAt(self.location)
  self.currentFilterText = self.document.contentString(selection)

proc updateWordCache(self: CompletionProviderDocument) =
  let timer = startTimer()

  # debugf"[updateWordCache] update cache around line {self.location.line}"
  const maxCacheTimeMs = 4
  for i in countdown(self.location.line - 1, 0):
    self.cacheLine(i)
    if timer.elapsed.ms > maxCacheTimeMs:
      debugf"[updateWordCache] cancel up at line {i}"
      break

  for i in countup(self.location.line + 1, self.document.lines.len):
    self.cacheLine(i)
    if timer.elapsed.ms > maxCacheTimeMs:
      debugf"[updateWordCache] cancel down at line {i}"
      break

  # debugf"[updateWordCache] Took {timer.elapsed.ms}ms. Word cache: {self.wordCache.len}"

proc refilterCompletions(self: CompletionProviderDocument) =
  # debugf"[Doc.refilterCompletions] {self.location}: '{self.currentFilterText}'"
  let timer = startTimer()

  self.filteredCompletions.setLen 0
  for word in self.wordCache:
    let score = matchFuzzySublime(self.currentFilterText, word, defaultCompletionMatchingConfig).score.float
    if score < 0:
      continue

    self.filteredCompletions.add Completion(
      item: CompletionItem(
        label: word,
        kind: CompletionKind.Text,
        score: score.some,
      ),
      filterText: self.currentFilterText,
      score: score,
    )

  log lvlInfo, &"[Comp-Doc] Filtering completions took {timer.elapsed.ms}ms ({self.filteredCompletions.len}/{self.wordCache.len})"
  self.onCompletionsUpdated.invoke (self)

proc handleTextInserted(self: CompletionProviderDocument, document: TextDocument, location: Selection, text: string) =
  self.location = location.getChangedSelection(text).last
  self.updateFilterText()
  self.updateWordCache()
  self.refilterCompletions()

proc handleTextDeleted(self: CompletionProviderDocument, document: TextDocument, selection: Selection) =
  self.location = selection.first
  self.updateFilterText()
  self.updateWordCache()
  self.refilterCompletions()

method forceUpdateCompletions*(provider: CompletionProviderDocument) =
  provider.updateFilterText()
  provider.updateWordCache()
  provider.refilterCompletions()

proc newCompletionProviderDocument*(document: TextDocument): CompletionProviderDocument =
  let self = CompletionProviderDocument(document: document)
  self.textInsertedHandle = self.document.textInserted.subscribe (arg: tuple[document: TextDocument, location: Selection, text: string]) => self.handleTextInserted(arg.document, arg.location, arg.text)
  self.textDeletedHandle = self.document.textDeleted.subscribe (arg: tuple[document: TextDocument, location: Selection]) => self.handleTextDeleted(arg.document, arg.location)
  self

type
  CompletionProviderLsp* = ref object of CompletionProvider
    document: TextDocument
    lastResponseLocation: Cursor
    languageServer: LanguageServer
    textInsertedHandle: Id
    textDeletedHandle: Id
    unfilteredCompletions: seq[CompletionItem]

proc updateFilterText(self: CompletionProviderLsp) =
  let selection = self.document.getCompletionSelectionAt(self.location)
  self.currentFilterText = self.document.contentString(selection)

proc refilterCompletions(self: CompletionProviderLsp) =
  # debugf"[LSP.refilterCompletions] {self.location}: '{self.currentFilterText}'"
  let timer = startTimer()

  self.filteredCompletions.setLen 0
  for item in self.unfilteredCompletions:
    let text = item.filterText.get(item.label)
    let score = matchFuzzySublime(self.currentFilterText, text, defaultCompletionMatchingConfig).score.float

    if score < 0:
      continue

    self.filteredCompletions.add Completion(
      item: item,
      filterText: self.currentFilterText,
      score: score,
    )

  log lvlInfo, &"[Comp-Lsp] Filtering completions took {timer.elapsed.ms}ms ({self.filteredCompletions.len}/{self.unfilteredCompletions.len})"
  self.onCompletionsUpdated.invoke (self)

proc getLspCompletionsAsync(self: CompletionProviderLsp) {.async.} =
  let location = self.location

  # Right now we need to sleep a bit here because this function is triggered by textInserted and
  # the update to the LSP is also sent in textInserted, but it's bound after this and so it would be called
  # to late. The sleep makes sure we run the getCompletions call below after the server got the file change.
  await sleepAsync(1)

  # debugf"[getLspCompletionsAsync] start"
  let completions = await self.languageServer.getCompletions(self.document.languageId, self.document.fullPath, location)
  if completions.isSuccess and completions.result.items.len > 0:
    # debugf"[getLspCompletionsAsync] at {location} got {completions.result.items.len} completions"
    self.unfilteredCompletions = completions.result.items
    self.refilterCompletions()
  else:
    log lvlError, fmt"Failed to get completions"

proc handleTextInserted(self: CompletionProviderLsp, document: TextDocument, location: Selection, text: string) =
  self.location = location.getChangedSelection(text).last
  # debugf"[Lsp.handleTextInserted] {self.location}"
  self.updateFilterText()
  self.refilterCompletions()
  asyncCheck self.getLspCompletionsAsync()

proc handleTextDeleted(self: CompletionProviderLsp, document: TextDocument, selection: Selection) =
  self.location = selection.first
  self.updateFilterText()
  self.refilterCompletions()
  asyncCheck self.getLspCompletionsAsync()

method forceUpdateCompletions*(provider: CompletionProviderLsp) =
  provider.updateFilterText()
  provider.refilterCompletions()
  asyncCheck provider.getLspCompletionsAsync()

proc newCompletionProviderLsp*(document: TextDocument, languageServer: LanguageServer): CompletionProviderLsp =
  let self = CompletionProviderLsp(document: document, languageServer: languageServer)
  self.textInsertedHandle = self.document.textInserted.subscribe (arg: tuple[document: TextDocument, location: Selection, text: string]) => self.handleTextInserted(arg.document, arg.location, arg.text)
  self.textDeletedHandle = self.document.textDeleted.subscribe (arg: tuple[document: TextDocument, location: Selection]) => self.handleTextDeleted(arg.document, arg.location)
  self

type
  CompletionProviderSnippet* = ref object of CompletionProvider
    document: TextDocument
    textInsertedHandle: Id
    textDeletedHandle: Id
    unfilteredCompletions: seq[CompletionItem]
    configProvider: ConfigProvider

proc addSnippetCompletions(self: CompletionProviderSnippet) =
  try:
    let snippets = self.configProvider.getValue("editor.text.snippets." & self.document.languageId, newJObject())
    for (name, definition) in snippets.fields.pairs:
      # todo: handle language scope
      # let scopes = definition["scope"].getStr.split(",")
      let prefix = definition["prefix"].getStr
      let body = definition["body"].elems
      var text = ""
      for i, line in body:
        if text.len > 0:
          text.add "\n"
        text.add line.getStr

      let edit = lsp_types.TextEdit(`range`: Range(start: Position(line: -1, character: -1), `end`: Position(line: -1, character: -1)), newText: text)
      self.unfilteredCompletions.add(CompletionItem(label: prefix, detail: name.some, insertTextFormat: InsertTextFormat.Snippet.some, textEdit: lsp_types.init(lsp_types.CompletionItemTextEditVariant, edit).some))

  except:
    log lvlError, fmt"Failed to get snippets for language {self.document.languageId}"

proc refilterCompletions(self: CompletionProviderSnippet) =
  # debugf"[Snip.refilterCompletions] {self.location}: '{self.currentFilterText}'"
  let timer = startTimer()

  self.filteredCompletions.setLen 0
  for item in self.unfilteredCompletions:
    let text = item.filterText.get(item.label)
    let score = matchFuzzySublime(self.currentFilterText, text, defaultCompletionMatchingConfig).score.float

    if score < 0:
      continue

    self.filteredCompletions.add Completion(
      item: item,
      filterText: self.currentFilterText,
      score: score,
    )

  log lvlInfo, &"[Comp-Snippet] Filtering completions took {timer.elapsed.ms}ms ({self.filteredCompletions.len}/{self.unfilteredCompletions.len})"
  self.onCompletionsUpdated.invoke (self)

proc updateFilterText(self: CompletionProviderSnippet) =
  let selection = self.document.getCompletionSelectionAt(self.location)
  self.currentFilterText = self.document.contentString(selection)

proc handleTextInserted(self: CompletionProviderSnippet, document: TextDocument, location: Selection, text: string) =
  self.location = location.getChangedSelection(text).last
  self.updateFilterText()
  self.refilterCompletions()

proc handleTextDeleted(self: CompletionProviderSnippet, document: TextDocument, selection: Selection) =
  self.location = selection.first
  self.updateFilterText()
  self.refilterCompletions()

method forceUpdateCompletions*(provider: CompletionProviderSnippet) =
  provider.updateFilterText()
  provider.refilterCompletions()

proc newCompletionProviderSnippet*(configProvider: ConfigProvider, document: TextDocument): CompletionProviderSnippet =
  let self = CompletionProviderSnippet(configProvider: configProvider, document: document)
  self.addSnippetCompletions()
  self.textInsertedHandle = self.document.textInserted.subscribe (arg: tuple[document: TextDocument, location: Selection, text: string]) => self.handleTextInserted(arg.document, arg.location, arg.text)
  self.textDeletedHandle = self.document.textDeleted.subscribe (arg: tuple[document: TextDocument, location: Selection]) => self.handleTextDeleted(arg.document, arg.location)
  self
