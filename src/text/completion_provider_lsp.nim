import misc/[custom_unicode, util, custom_async, event, timer, custom_logger, fuzzy_matching, response]
import language/[lsp_types, language_server_base]
import completion, text_document
import scripting_api

{.push gcsafe.}
{.push raises: [].}

logCategory "Comp-Lsp"

type
  CompletionProviderLsp* = ref object of CompletionProvider
    document: TextDocument
    lastResponseLocation: Cursor
    languageServer: LanguageServer
    unfilteredCompletions: seq[CompletionItem]
    unfilteredVersion: int
    isFiltering: bool = false

proc updateFilterText(self: CompletionProviderLsp) =
  let selection = self.document.getCompletionSelectionAt(self.location)
  self.currentFilterText = self.document.contentString(selection)

proc refilterCompletions(self: CompletionProviderLsp) {.async.} =
  if self.isFiltering:
    return
  self.isFiltering = true
  defer:
    self.isFiltering = false
  while true:
    # debugf"[LSP.refilterCompletions] {self.location}: '{self.currentFilterText}'"
    let unfilteredVersion = self.unfilteredVersion
    let timer = startTimer()
    var t = startTimer()

    self.filteredCompletions.setLen 0
    for item in self.unfilteredCompletions:
      if t.elapsed.ms > 3:
        try:
          await sleepAsync(3.milliseconds)
          if unfilteredVersion != self.unfilteredVersion:
            break
          t = startTimer()
        except:
          discard

      let text = item.filterText.get(item.label)
      let score = matchFuzzy(self.currentFilterText, text, defaultCompletionMatchingConfig).score.float

      if score < 0:
        continue

      self.filteredCompletions.add Completion(
        item: item,
        filterText: self.currentFilterText,
        score: score,
        source: "LSP",
      )

    if unfilteredVersion != self.unfilteredVersion:
      continue

    if timer.elapsed.ms > 2:
      log lvlInfo, &"[Comp-Lsp] Filtering completions took {timer.elapsed.ms}ms ({self.filteredCompletions.len}/{self.unfilteredCompletions.len})"
    self.onCompletionsUpdated.invoke (self)
    if unfilteredVersion == self.unfilteredVersion:
      break

proc getLspCompletionsAsync(self: CompletionProviderLsp) {.async.} =
  let location = self.location

  # Right now we need to sleep a bit here because this function is triggered by textInserted and
  # the update to the LSP is also sent in textInserted, but it's bound after this and so it would be called
  # to late. The sleep makes sure we run the getCompletions call below after the server got the file change.
  await sleepAsync(2.milliseconds)

  # debugf"[getLspCompletionsAsync] start"
  let completions = await self.languageServer.getCompletions(self.document.filename, location)
  if completions.isSuccess:
    # log lvlInfo, fmt"[getLspCompletionsAsync] at {location}: got {completions.result.items.len} completions"
    self.unfilteredCompletions = completions.result.items
    self.unfilteredVersion.inc()
    asyncSpawn self.refilterCompletions()
  elif completions.isCanceled:
    discard
  else:
    log lvlWarn, fmt"Failed to get completions: {completions.error}"
    self.unfilteredCompletions = @[]
    self.unfilteredVersion.inc()
    asyncSpawn self.refilterCompletions()

method forceUpdateCompletions*(provider: CompletionProviderLsp) =
  provider.updateFilterText()
  asyncSpawn provider.refilterCompletions()
  asyncSpawn provider.getLspCompletionsAsync()

proc newCompletionProviderLsp*(document: TextDocument, languageServer: LanguageServer): CompletionProviderLsp =
  let self = CompletionProviderLsp(document: document, languageServer: languageServer)
  self
