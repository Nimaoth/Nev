import std/[strutils]
import misc/[custom_unicode, util]
import language/lsp_types

type
  CompletionProvider* = ref object of RootObj
    discard

  CompletionEngine* = ref object
    providers: seq[CompletionProvider]
    combinedCompletions: seq[CompletionItem]

proc getCompletions*(self: CompletionEngine): seq[CompletionItem] =
  discard
