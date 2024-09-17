import std/[strutils, sugar, sets, algorithm]
import misc/[custom_unicode, util, id, event, timer, custom_logger, fuzzy_matching, delayed_task, custom_async]
import language/[lsp_types]
import completion, text_document
import scripting_api

import nimsumtree/buffer
import nimsumtree/sumtree except Cursor
import nimsumtree/rope except Cursor

logCategory "Comp-Doc"

type
  CompletionProviderDocument* = ref object of CompletionProvider
    document: TextDocument
    onEditHandle: Id
    wordCache: HashSet[string]
    updateTask: DelayedTask
    revision: int
    buffer: string

proc cacheLine(self: CompletionProviderDocument, line: int) =
  var c = self.document.buffer.visibleText.cursorT(Point.init(line, 0))

  # Compiler complains about intantiation of SumTree[Cursor], even though we don't explicitly instantiate it,
  # but binarySearch uses cmp[Cursor] which somehow instantiates SumTree[Cursor]
  func cmpFn(a, b: Cursor): int = cmp(a, b)

  self.buffer.setLen(0)

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
      self.buffer.add r
    else:
      if self.buffer.len > 0 and self.cursors.binarySearch(cursor, cmpFn) == -1:
        self.wordCache.incl self.buffer
      self.buffer.setLen(0)
      wordStart = i + 1.RuneCount
      continue

  if self.buffer.len > 0 and self.cursors.binarySearch(cursor, cmpFn) == -1:
    self.wordCache.incl self.buffer
    self.buffer.setLen(0)

proc updateFilterText(self: CompletionProviderDocument) =
  let selection = self.document.getCompletionSelectionAt(self.location)
  self.currentFilterText = self.document.contentString(selection)

proc updateWordCache(self: CompletionProviderDocument) =
  let timer = startTimer()

  # debugf"[updateWordCache] update cache around line {self.location.line}"
  const maxCacheTimeMs = 4
  for i in countdown(self.location.line, 0):
    self.cacheLine(i)
    if timer.elapsed.ms > maxCacheTimeMs:
      break

  for i in countup(self.location.line + 1, self.document.numLines):
    self.cacheLine(i)
    if timer.elapsed.ms > maxCacheTimeMs:
      break

  # debugf"[updateWordCache] Took {timer.elapsed.ms}ms. Word cache: {self.wordCache.len}"

proc refilterCompletions(self: CompletionProviderDocument) {.async.} =
  # debugf"[Doc.refilterCompletions] {self.location}: '{self.currentFilterText}'"
  let timer = startTimer()
  let revision = self.revision

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
      await sleepAsync(15)
      if self.revision != revision:
        return

      loopTimer = startTimer()

  # if timer.elapsed.ms > 2:
  #   log lvlInfo, &"[Comp-Doc] Filtering completions took {timer.elapsed.ms}ms ({self.filteredCompletions.len}/{self.wordCache.len})"
  self.onCompletionsUpdated.invoke (self)

proc handleTextEdits(self: CompletionProviderDocument, document: TextDocument, edits: seq[tuple[old, new: Selection]]) =
  self.updateFilterText()
  self.updateTask.reschedule()

method forceUpdateCompletions*(provider: CompletionProviderDocument) =
  provider.updateFilterText()
  provider.updateTask.reschedule()

proc newCompletionProviderDocument*(document: TextDocument): CompletionProviderDocument =
  let self = CompletionProviderDocument(document: document)
  self.onEditHandle = self.document.onEdit.subscribe (arg: tuple[document: TextDocument, edits: seq[tuple[old, new: Selection]]]) => self.handleTextEdits(arg.document, arg.edits)

  self.updateTask = startDelayed(50, repeat=false):
    inc self.revision
    self.updateWordCache()
    asyncCheck self.refilterCompletions()

  self.updateTask.pause()

  self
