import std/[json, tables, options]
import misc/[traits, custom_async, myjsonutils]

traitRef ISelectorPopup:
  method getSearchString*(self: ISelectorPopup): string
  method updateCompletions*(self: ISelectorPopup)
  method enableAutoSort*(self: ISelectorPopup)
  method closed*(self: ISelectorPopup): bool

type
  SelectorItem* = ref object of RootObj
    score*: float32
    hasCompletionMatchPositions*: bool = false
    completionMatchPositions*: seq[int]

  SelectorPopupBuilder* = object
    scope*: Option[string]
    scaleX*: float = 0.5
    scaleY*: float = 0.5
    getCompletions*: proc(popup: ISelectorPopup, text: string): seq[SelectorItem]
    getCompletionsAsync*: proc(popup: ISelectorPopup, text: string): Future[seq[SelectorItem]]
    getCompletionsAsyncIter*: proc(popup: ISelectorPopup, text: string): Future[void]
    handleItemSelected*: proc(popup: ISelectorPopup, item: SelectorItem)
    handleItemConfirmed*: proc(popup: ISelectorPopup, item: SelectorItem): bool
    handleCanceled*: proc(popup: ISelectorPopup)
    customActions*: Table[string, proc(popup: ISelectorPopup, args: JsonNode): bool]
    sortFunction*: proc(a, b: SelectorItem): int
    enableAutoSort*: bool

method changed*(self: SelectorItem, other: SelectorItem): bool {.base.} = discard
method itemToJson*(self: SelectorItem): JsonNode {.base.} = self.toJson