import std/[sugar, algorithm]
import misc/[custom_unicode, util, id, event, timer, custom_logger]
import language/[lsp_types]
import scripting_api

logCategory "completion"

type
  MergeStrategyKind* = enum
    TakeAll
    FillN

  MergeStrategy* = object
    case kind*: MergeStrategyKind
    of TakeAll: discard
    of FillN:
      max*: int

  Completion* = object
    item*: CompletionItem
    origin*: Option[tuple[line: int, column: RuneIndex]]
    filterText*: string
    providerIndex: int
    score*: float

  CompletionProvider* = ref object of RootObj
    onCompletionsUpdated*: Event[CompletionProvider]
    location*: Cursor
    filteredCompletions*: seq[Completion]
    currentFilterText*: string
    priority*: Option[int]
    mergeStrategy*: MergeStrategy = MergeStrategy(kind: TakeAll)

  CompletionEngine* = ref object
    providers: seq[tuple[provider: CompletionProvider, onCompletionsUpdatedHandle: Id]]
    providersByPriority: seq[CompletionProvider]
    combinedCompletions: seq[Completion]
    onCompletionsUpdated*: Event[void]
    combinedDirty: bool

method forceUpdateCompletions*(provider: CompletionProvider) {.base.} = discard

proc withMergeStrategy*(provider: CompletionProvider, mergeStrategy: MergeStrategy): CompletionProvider =
  provider.mergeStrategy = mergeStrategy
  provider

proc withPriority*(provider: CompletionProvider, priority: int): CompletionProvider =
  provider.priority = priority.some
  provider

proc updateCompletionsAt*(self: CompletionEngine, location: Cursor) =
  for provider in self.providersByPriority:
    provider.location = location
    provider.forceUpdateCompletions()

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

  for i, provider in self.providersByPriority:
    case provider.mergeStrategy.kind
    of TakeAll:
      for c in provider.filteredCompletions:
        self.combinedCompletions.add c

    of FillN:
      provider.filteredCompletions.sort(cmp, Descending)
      for c in provider.filteredCompletions:
        if self.combinedCompletions.len >= provider.mergeStrategy.max:
          break
        self.combinedCompletions.add c

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

proc updateProvidersByPriority*(self: CompletionEngine) =
  var providersWithPriority = newSeq[tuple[provider: CompletionProvider, priority: int]]()
  var providersWithoutPriority = newSeq[CompletionProvider]()
  for (provider, _) in self.providers:
    if provider.priority.getSome(priority):
      providersWithPriority.add (provider, priority)
    else:
      providersWithoutPriority.add provider

  providersWithPriority.sort((a, b) => cmp(a.priority, b.priority), Descending)

  self.providersByPriority.setLen 0
  for (provider, _) in providersWithPriority:
    self.providersByPriority.add provider

  for provider in providersWithoutPriority:
    self.providersByPriority.add provider

proc addProvider*(self: CompletionEngine, provider: CompletionProvider) =
  let handle = provider.onCompletionsUpdated.subscribe (provider: CompletionProvider) =>
    self.handleProviderCompletionsUpdated(provider)
  self.providers.add (provider, handle)
  self.updateProvidersByPriority()

proc removeProvider*(self: CompletionEngine, provider: CompletionProvider) =
  defer:
    self.updateProvidersByPriority()

  for i in 0..self.providers.high:
    if self.providers[i].provider == provider:
      provider.onCompletionsUpdated.unsubscribe self.providers[i].onCompletionsUpdatedHandle
      self.providers.removeShift(i)
      break
