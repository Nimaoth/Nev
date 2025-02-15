import std/[strutils, sets, algorithm]
import misc/[custom_unicode, util, event, timer, custom_logger, fuzzy_matching, delayed_task, custom_async]
import language/[lsp_types]
import completion, text_document
import scripting_api

import nimsumtree/[buffer, clock]
import nimsumtree/sumtree except Cursor
import nimsumtree/rope except Cursor

logCategory "Comp-Doc"

type
  CompletionProviderDocument* = ref object of CompletionProvider
    document: TextDocument
    wordCache: HashSet[string]
    updateTask: DelayedTask
    revision: int
    buffer: string
    isUpdatingAsync: bool = false
    isFiltering: bool = false

proc refilterCompletions(self: CompletionProviderDocument) {.async.}

proc updateFilterText(self: CompletionProviderDocument) =
  let selection = self.document.getCompletionSelectionAt(self.location)
  self.currentFilterText = self.document.contentString(selection)

type CompletionProviderDocumentThreadState = object
  rope: Rope
  wordCache: HashSet[string]
  cursors: seq[Cursor]

proc cacheLine(rope: Rope, buffer: var string, wordCache: var HashSet[string], line: int, cursors: openArray[Cursor]) =
  var c = rope.cursorT(Point.init(line, 0))

  # Compiler complains about intantiation of SumTree[Cursor], even though we don't explicitly instantiate it,
  # but binarySearch uses cmp[Cursor] which somehow instantiates SumTree[Cursor]
  # so use this wrapper to avoid instantiating cmp[Cursor] in the other binarySearch overload
  func cmpFn(a, b: Cursor): int = cmp(a, b)

  buffer.setLen(0)

  var i = 0.RuneIndex
  var wordStart = 0.RuneIndex
  var cursor: Cursor = (line, 0)
  while not c.atEnd:
    let r = c.currentRune()
    if r == '\n'.Rune:
      break
    c.seekNextRune()

    defer:
      inc i
      cursor.column += r.size

    let isWord = r.char in IdentChars or r.isAlpha or (i > wordStart and r.isDigit)
    if isWord:
      buffer.add r
    else:
      if buffer.len > 0 and cursors.binarySearch(cursor, cmpFn) == -1:
        wordCache.incl buffer
      buffer.setLen(0)
      wordStart = i + 1.RuneCount
      continue

  if buffer.len > 0 and cursors.binarySearch(cursor, cmpFn) == -1:
    wordCache.incl buffer
    buffer.setLen(0)

proc cacheWordsThread(data: ptr CompletionProviderDocumentThreadState) =
  let rope = data.rope.clone()
  var buffer = ""
  var wordCache = initHashSet[string]()
  for i in 0..rope.lines:
    cacheLine(rope, buffer, wordCache, i, data.cursors)

  data.wordCache = wordCache

proc updateWordCache(self: CompletionProviderDocument) {.async.} =
  if self.isUpdatingAsync:
    return
  self.isUpdatingAsync = true
  defer:
    self.isUpdatingAsync = false

  var data = CompletionProviderDocumentThreadState(rope: self.document.buffer.visibleText.clone(), cursors: self.cursors)
  while true:
    let timer = startTimer()
    let oldId = (self.document.buffer.version, self.document.buffer.remoteId)
    await spawnAsync(cacheWordsThread, data.addr)
    if self.document.isNil:
      return

    self.wordCache = data.wordCache
    let newId = (self.document.buffer.version, self.document.buffer.remoteId)
    if oldId == newId:
      inc self.revision
      asyncSpawn self.refilterCompletions()
      return

    data.rope = self.document.buffer.visibleText.clone()
    data.cursors = self.cursors

proc refilterCompletions(self: CompletionProviderDocument) {.async.} =
  if self.isFiltering:
    return
  self.isFiltering = true
  defer:
    self.isFiltering = false

  var revision = self.revision
  while true:
    revision = self.revision
    self.filteredCompletions.setLen 0

    var loopTimer = startTimer()
    var i = 0
    for word in self.wordCache:
      defer: inc i

      let score = matchFuzzySublime(self.currentFilterText, word, defaultCompletionMatchingConfig).score.float
      if score >= 0:
        self.filteredCompletions.add Completion(
          item: CompletionItem(
            label: word,
            kind: CompletionKind.Text,
            score: score.some,
          ),
          filterText: self.currentFilterText,
          score: score,
          source: "DOC",
        )

      if i < self.wordCache.len - 1 and loopTimer.elapsed.ms > 3:
        self.onCompletionsUpdated.invoke (self)
        await sleepAsync(15.milliseconds)
        if self.revision != revision:
          break

        loopTimer = startTimer()

    self.onCompletionsUpdated.invoke (self)
    if self.revision == revision:
      break

method forceUpdateCompletions*(provider: CompletionProviderDocument) =
  provider.updateFilterText()
  provider.updateTask.reschedule()

proc newCompletionProviderDocument*(document: TextDocument): CompletionProviderDocument =
  let self = CompletionProviderDocument(document: document)

  self.updateTask = startDelayed(50, repeat=false):
    inc self.revision
    asyncSpawn self.updateWordCache()
    asyncSpawn self.refilterCompletions()

  self.updateTask.pause()

  self
