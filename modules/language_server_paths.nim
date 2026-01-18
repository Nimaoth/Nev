import std/[options, tables, strutils, os, strformat]
import misc/[custom_logger, custom_async, util, response, rope_utils, event, regex, rope_regex, myjsonutils]
import text/language/[language_server_base, lsp_types]
import nimsumtree/[arc, rope]
import service, event_service, language_server_dynamic, document_editor, config_provider, vfs, vfs_service
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor

const currentSourcePath2 = currentSourcePath()
include module_base

when implModule:
  import language_server_component, config_component, text_component
  logCategory "language-server-paths"

  const pathRegex = """(?=.*[/\\])(?:(?:\w+:\/\/)?(?:[a-zA-Z]:(/|\\{1,2})|(/|\\{1,2})|)(?:[^\\/\s\"'>\[\]:(),]+(/|\\{1,2}))*([^\\/\s\"'>\[\]:(),]+(?:\.\w+)?)?)"""
  const lineInfoRegex = """^((:\d+(:\d+)?)|(\((\d+), (\d+)\)))"""
  const numberRegex = """(\d+)"""

  type
    LanguageServerPaths* = ref object of LanguageServerDynamic
      services: Services
      config: ConfigStore
      documents: DocumentEditorService
      eventBus: EventService
      vfs: Arc[VFS2]
      files: Table[string, string]
      commandHistory*: seq[string]
      pathRegex: Regex

  proc pathsGetDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerPaths
    # log lvlDebug, &"getDefinition '{filename}', {location}"
    var definitions = newSeq[Definition]()
    if self.documents.getDocumentByPath(filename).getSome(doc):
      let config = doc.getConfigComponent().getOr:
        return
      let text = doc.getTextComponent().getOr:
        return
      let rope = text.content
      if location.line >= rope.lines:
        return definitions

      let lineLen = rope.lineLen(location.line)
      if location.column > lineLen or lineLen > 512: # todo: make this limit configurable
        return definitions

      let pathRegex = config.get("lsp.paths.regex", pathRegex)
      let line = rope.slice(point(location.line, 0)...point(location.line, lineLen)).toRope # todo: don't use toRope once the bug with slicing a slice is fixed
      let bounds = await findAllAsync(line.slice(int), pathRegex)
      for b in bounds:
        if b.a == b.b or location.column < b.a.column.int or location.column > b.b.column.int:
          continue

        var path = $line[b]
        if path.find("/") == -1 and path.find("\\") == -1:
          continue

        if path.startsWith("../") or path.startsWith("..\\") or path.startsWith("./") or path.startsWith(".\\"):
          var fileDir = filename.splitPath.head
          path = fileDir // path

        var fileCursorLocation: Cursor = (0, 0)

        try:
          let lineInfoRegex = re(lineInfoRegex)
          let numberRegex = re(numberRegex)
          let lineStr = ($line)[b.b.column..^1]
          let lineNumberInfo = lineStr.findBounds(lineInfoRegex, 0)
          if lineNumberInfo.first == 0:
            let lineNumberString = lineStr[lineNumberInfo.first..lineNumberInfo.last]
            let bounds = lineNumberString.findAllBounds(0, numberRegex)
            if bounds.len >= 1:
              fileCursorLocation.line = (lineNumberString[bounds[0].first.column..<bounds[0].last.column]).parseInt - 1
            if bounds.len >= 2:
              fileCursorLocation.column = (lineNumberString[bounds[1].first.column..<bounds[1].last.column]).parseInt - 1
        except:
          discard

        let fileKind = await self.vfs.getFileKind(path)
        if fileKind == FileKind.File.some:
          definitions.add Definition(
            filename: path,
            location: fileCursorLocation,
          )

    return definitions

  proc pathsGetCompletionTriggerChars*(self: LanguageServerDynamic): set[char] {.gcsafe, raises: [].} = {'a'..'z', 'A'..'Z', '0'..'9', '/', '\\', ':', '-', '_', '.'}

  proc pathsGetCompletions*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[CompletionList]] {.async.} =
    let self = self.LanguageServerPaths
    # log lvlDebug, &"LanguageServerDynamic.getCompletions '{filename}', {location}"

    var completions = newSeq[CompletionItem]()

    if self.documents.getDocumentByPath(filename).getSome(doc):
      let config = doc.getConfigComponent().getOr:
        return CompletionList(items: completions).success
      let text = doc.getTextComponent().getOr:
        return CompletionList(items: completions).success

      let rope = text.content
      if location.line >= rope.lines or location.column > rope.lineLen(location.line):
        return CompletionList(items: completions).success

      let range = point(location.line, 0)...location.toPoint
      if range.b.column - range.a.column > 512:
        return CompletionList(items: completions).success

      let pathRegex = config.get("lsp.paths.regex", pathRegex)
      let pathText = rope.slice(range).toRope
      let bounds = await findAllAsync(pathText.slice(int), pathRegex)

      for b in bounds:
        if b.a == b.b or location.column < b.a.column.int or location.column > b.b.column.int:
          continue

        let path = $pathText[b]
        var endIndex = path.len
        let lastForwardSlash = path.rfind("/")
        let lastBackslash = path.rfind("\\")

        if lastForwardSlash != -1 and lastBackslash != -1:
          endIndex = max(lastForwardSlash + 1, lastBackslash + 1)
        elif lastForwardSlash != -1:
          endIndex = lastForwardSlash + 1
        elif lastBackslash != -1:
          endIndex = lastBackslash + 1
        else:
          continue

        let divider = if lastBackslash != -1:
          if lastBackslash > 0 and path[lastBackslash - 1] == '\\':
            "\\\\"
          else:
            "\\"
        else:
          "/"

        var directory = path[0..<endIndex]
        if directory.startsWith("../") or directory.startsWith("..\\"):
          let fileDir = filename.splitPath.head
          directory = fileDir // directory

        elif directory.startsWith("./") or directory.startsWith(".\\"):
          let fileDir = filename.splitPath.head
          directory = fileDir // directory

        let replaceRange = point(location.line, location.column - (path.len - endIndex))...location.toPoint
        let listing = await self.vfs.getDirectoryListing(directory)

        for name in listing.files:
          completions.add CompletionItem(
            label: name,
            kind: CompletionKind.Function,
            textEdit: lsp_types.TextEdit(
              range: replaceRange.toSelection.toLspRange,
              newText: name,
            ).toJson.jsonTo(CompletionItemTextEditVariant).some
          )
        for name in listing.folders:
          completions.add CompletionItem(
            label: name & divider,
            kind: CompletionKind.Class,
            showCompletionsAgain: true.some,
            textEdit: lsp_types.TextEdit(
              range: replaceRange.toSelection.toLspRange,
              newText: name & divider,
            ).toJson.jsonTo(CompletionItemTextEditVariant).some
          )

    return CompletionList(items: completions).success

  proc newLanguageServerPaths(services: Services): LanguageServerPaths =
    result = new LanguageServerPaths
    result.name = "paths"
    result.services = services
    result.documents = services.getService(DocumentEditorService).get
    result.eventBus = services.getService(EventService).get
    result.vfs = services.getService(VFSService).get.vfs2
    result.config = services.getService(ConfigService).get.runtime
    result.capabilities.completionProvider = lsp_types.CompletionOptions().some
    result.refetchWorkspaceSymbolsOnQueryChange = false
    try:
      result.pathRegex = re(pathRegex)
    except:
      log lvlError, &"Failed to create path regex: {getCurrentExceptionMsg()}"

    result.getDefinitionImpl = pathsGetDefinition
    result.getCompletionsImpl = pathsGetCompletions
    result.getCompletionTriggerCharsImpl = pathsGetCompletionTriggerChars

    return result

  proc init_module_language_server_paths*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_language_server_paths: no services found"
      return

    var ls = newLanguageServerPaths(services)

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

          let languages = config.get("lsp.paths.languages", newSeq[string]())
          let language = lsps.languageId

          if language in languages or "*" in languages:
            discard lsps.addLanguageServer(ls)
      except CatchableError as e:
        log lvlError, &"Error: {e.msg}"
    events.get.listen(newId(), "editor/*/registered", handleEditorRegistered)
