import std/[strutils, sugar, sets]
import misc/[custom_unicode, util, id, event, timer, custom_logger, fuzzy_matching, delayed_task]
import language/[lsp_types]
import completion, text_document
import scripting_api

logCategory "Comp-Doc"

type
  CompletionProviderDocument* = ref object of CompletionProvider
    document: TextDocument
    textInsertedHandle: Id
    textDeletedHandle: Id
    wordCache: HashSet[string]
    updateTask: DelayedTask

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
      if len > 1.RuneCount and not line[wordStart].isDigit:
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

  if timer.elapsed.ms > 2:
    log lvlInfo, &"[Comp-Doc] Filtering completions took {timer.elapsed.ms}ms ({self.filteredCompletions.len}/{self.wordCache.len})"
  self.onCompletionsUpdated.invoke (self)

proc handleTextInserted(self: CompletionProviderDocument, document: TextDocument, location: Selection, text: string) =
  self.location = location.getChangedSelection(text).last
  self.updateFilterText()
  self.updateTask.reschedule()

proc handleTextDeleted(self: CompletionProviderDocument, document: TextDocument, selection: Selection) =
  self.location = selection.first
  self.updateFilterText()
  self.updateTask.reschedule()

method forceUpdateCompletions*(provider: CompletionProviderDocument) =
  provider.updateFilterText()
  provider.updateTask.reschedule()

proc newCompletionProviderDocument*(document: TextDocument): CompletionProviderDocument =
  let self = CompletionProviderDocument(document: document)
  self.textInsertedHandle = self.document.textInserted.subscribe (arg: tuple[document: TextDocument, location: Selection, text: string]) => self.handleTextInserted(arg.document, arg.location, arg.text)
  self.textDeletedHandle = self.document.textDeleted.subscribe (arg: tuple[document: TextDocument, location: Selection]) => self.handleTextDeleted(arg.document, arg.location)

  self.updateTask = startDelayed(50, repeat=false):
    self.updateWordCache()
    self.refilterCompletions()

  self.updateTask.pause()

  self
