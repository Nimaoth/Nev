import std/[sugar, algorithm]
import misc/[custom_unicode, util, id, event, timer, custom_logger]
import language/[lsp_types]
import scripting_api

logCategory "completion"

type
  Completion* = object
    item*: CompletionItem
    filterText*: string
    providerIndex: int
    score*: float

  CompletionProvider* = ref object of RootObj
    onCompletionsUpdated*: Event[CompletionProvider]
    location*: Cursor
    filteredCompletions*: seq[Completion]
    currentFilterText*: string

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
