import std/[sugar, json, tables]
import misc/[custom_unicode, util, id, event, timer, custom_logger, fuzzy_matching]
import language/[lsp_types]
import completion, text_document
import config_provider, scripting_api

logCategory "Comp-Snip"

type
  CompletionProviderSnippet* = ref object of CompletionProvider
    document: TextDocument
    unfilteredCompletions: seq[CompletionItem]
    didCacheCompletionItems: bool = false
    configProvider: ConfigProvider
    onConfigChangedHandle: Id

proc invalidateCompletionItemCache(self: CompletionProviderSnippet) =
  self.unfilteredCompletions.setLen 0
  self.didCacheCompletionItems = false

proc cacheCompletionItems(self: CompletionProviderSnippet) =
  self.didCacheCompletionItems = true
  try:
    let snippets = self.configProvider.getValue("snippets." & self.document.languageId, newJObject())
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

  if not self.didCacheCompletionItems:
    self.cacheCompletionItems()

  # todo: make this configurable
  let config = defaultCompletionMatchingConfig

  self.filteredCompletions.setLen 0
  for item in self.unfilteredCompletions:
    let text = item.filterText.get(item.label)
    let score = matchFuzzySublime(self.currentFilterText, text, config).score.float

    if score < 0:
      continue

    self.filteredCompletions.add Completion(
      item: item,
      filterText: self.currentFilterText,
      score: score,
      source: "SNP",
    )

  if timer.elapsed.ms > 2:
    log lvlInfo, &"[Comp-Snippet] Filtering completions took {timer.elapsed.ms}ms ({self.filteredCompletions.len}/{self.unfilteredCompletions.len})"
  self.onCompletionsUpdated.invoke (self)

proc updateFilterText(self: CompletionProviderSnippet) =
  let selection = self.document.getCompletionSelectionAt(self.location)
  self.currentFilterText = self.document.contentString(selection)

method forceUpdateCompletions*(provider: CompletionProviderSnippet) =
  provider.updateFilterText()
  provider.refilterCompletions()

proc newCompletionProviderSnippet*(configProvider: ConfigProvider, document: TextDocument):
    CompletionProviderSnippet =

  let self = CompletionProviderSnippet(configProvider: configProvider, document: document)

  # todo: unsubscribe
  self.onConfigChangedHandle = configProvider.onConfigChanged.subscribe proc() =
    self.invalidateCompletionItemCache()

  self
