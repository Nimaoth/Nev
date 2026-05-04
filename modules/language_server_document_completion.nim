#use event_service
import std/[options, strutils, sets]
import nimsumtree/rope except Cursor
import misc/[custom_logger, custom_unicode, util, event, custom_async, response, fuzzy_matching]
import text/language/[language_server_base, lsp_types]
import service, event_service, language_server_dynamic, document_editor, config_provider

const currentSourcePath2 = currentSourcePath()
include module_base

proc getLanguageServerDocumentCompletion*(): LanguageServerDynamic {.rtl, gcsafe, raises: [].}

when implModule:
  import language_server_component, config_component, language_component, text_component
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor

  logCategory "language-server-document-completion"

  type
    LanguageServerDocumentCompletion* = ref object of LanguageServerDynamic
      services: Services
      config: ConfigStore
      documents: DocumentEditorService
      eventBus: EventService

  type CollectWordsThreadState = object
    rope: Rope
    filterText: string
    items: seq[lsp_types.CompletionItem]

  proc collectWordsAndFilterThread(data: ptr CollectWordsThreadState) {.gcsafe, raises: [].} =
    let rope = data.rope.clone()
    let filterText = data.filterText
    var buffer = ""
    var wordCache = initHashSet[string]()

    for line in 0..rope.lines:
      var c = rope.cursorT(Point.init(line, 0))
      buffer.setLen(0)
      var wordStart = 0.RuneIndex
      var i = 0.RuneIndex
      while not c.atEnd:
        let r = c.currentRune()
        if r == '\n'.Rune:
          break
        c.seekNextRune()
        defer:
          inc i
        let isWord = r.char in IdentChars or r.isAlpha or (i > wordStart and r.isDigit)
        if isWord:
          buffer.add r
        else:
          if buffer.len > 0:
            wordCache.incl buffer
          buffer.setLen(0)
          wordStart = i + 1.RuneCount
      if buffer.len > 0:
        wordCache.incl buffer

    var items: seq[lsp_types.CompletionItem]
    for word in wordCache:
      if word == filterText:
        continue
      let (score, matched) = matchFuzzy(filterText, word)
      if filterText.len == 0 or matched:
        items.add lsp_types.CompletionItem(
          label: word,
          kind: lsp_types.CompletionKind.Text,
          sortText: if filterText.len > 0: some($(-score)) else: string.none,
        )
    data.items = items

  proc getFilterText(rope: Rope, location: Cursor): string =
    ## Returns the word fragment immediately before location (the filter prefix).
    ## location.column is a rune column index.
    var c = rope.cursorT(Point.init(location.line, 0))
    var word = ""
    var runeCol = 0
    while not c.atEnd and runeCol < location.column:
      let r = c.currentRune()
      if r == '\n'.Rune:
        break
      c.seekNextRune()
      inc runeCol
      let isWord = r.char in IdentChars or r.isAlpha or (word.len > 0 and r.isDigit)
      if isWord:
        word.add r
      else:
        word.setLen(0)
    return word

  proc getCompletionsImpl(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.async.} =
    let self = self.LanguageServerDocumentCompletion
    let doc = self.documents.getDocumentByPath(filename).getOr:
      return success(lsp_types.CompletionList())
    let text = doc.getTextComponent().getOr:
      return success(lsp_types.CompletionList())

    let rope = text.content
    var data = CollectWordsThreadState(
      rope: rope.clone(),
      filterText: getFilterText(rope, location),
    )
    try:
      await spawnAsync(collectWordsAndFilterThread, data.addr)
    except CancelledError:
      return success(lsp_types.CompletionList())

    return success(lsp_types.CompletionList(isIncomplete: false, items: data.items))

  # proc ueGetCompletionTriggerChars*(self: LanguageServerDynamic): set[char] =
  #   return {'.', '>', ':'}

  proc newLanguageServerDocumentCompletion(services: Services): LanguageServerDocumentCompletion =
    result = new LanguageServerDocumentCompletion
    result.capabilities.completionProvider = lsp_types.CompletionOptions().some
    result.name = "document-completion"
    result.services = services
    result.documents = services.getService(DocumentEditorService).get
    result.eventBus = services.getService(EventService).get
    result.config = services.getService(ConfigService).get.runtime
    result.getCompletionsImpl = getCompletionsImpl

  var gls: LanguageServerDocumentCompletion = nil

  proc getLanguageServerDocumentCompletion*(): LanguageServerDynamic {.gcsafe, raises: [].} =
    {.gcsafe.}:
      return gls

  proc init_module_language_server_document_completion*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, "Failed to initialize language_server_document_completion: no services found"
      return

    var ls = newLanguageServerDocumentCompletion(services)
    {.gcsafe.}:
      gls = ls

    let events = services.getService(EventService)
    let documents = services.getService(DocumentEditorService).get

    proc handleEditorRegistered(event, payload: string) {.gcsafe, raises: [].} =
      try:
        let id = payload.parseInt.EditorIdNew
        if documents.getEditor(id).getSome(editor):
          let doc = editor.getEditorDocument()
          let config = doc.getConfigComponent().getOr:
            return
          let lsps = doc.getLanguageServerComponent().getOr:
            return
          let language = doc.getLanguageComponent().getOr:
            return

          let languages = config.get("lsp.document-completion.languages", newSeq[string]())
          if language.languageId in languages or "*" in languages:
            discard lsps.addLanguageServer(ls)
      except CatchableError as e:
        log lvlError, &"Error: {e.msg}"

    events.get.listen(newId(), "editor/*/registered", handleEditorRegistered)
