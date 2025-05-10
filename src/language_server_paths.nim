import std/[options, tables, strutils, os, json]
import nimsumtree/rope
import misc/[custom_logger, custom_async, util, response, rope_utils, event, regex, rope_regex, myjsonutils]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base, lsp_types]
import dispatch_tables, document_editor, service, layout, events, vfs_service, vfs, config_provider
import text/text_document

logCategory "language-server-paths"

# const pathRegex = """(?:\w+:\/\/)|(?:(?:\w+:\/\/)?(?:[a-zA-Z]:(/|\\{1,})|(/|\\{1,})|\.{1,2}(/|\\{1,})|\.{0,2}(?=\w))(?:[^\\/\s\"'>\[\]:]+(/|\\{1,}))+([^\\/\s\"'>\[\]:]+(?:\.\w+)?)?)"""
# const pathRegex = """(?:\w+:\/\/)|(?:(?:\w+:\/\/)?(?:[a-zA-Z]:(/|\\{1,2})|(/|\\{1,2})|)(?:[^\\/\s\"'>\[\]:]+(/|\\{1,2}))+([^\\/\s\"'>\[\]:]+(?:\.\w+)?)?)"""
# const pathRegex = """(?:(?:\w+:\/\/)(?:[a-zA-Z]:(/|\\{1,2})|(/|\\{1,2})|)(?:[^\\/\s\"'>\[\]:]+(/|\\{1,2}))*([^\\/\s\"'>\[\]:]+(?:\.\w+)?)?)|(?:(?:[a-zA-Z]:(/|\\{1,2})|(/|\\{1,2})|)(?:[^\\/\s\"'>\[\]:]+(/|\\{1,2}))+([^\\/\s\"'>\[\]:]+(?:\.\w+)?)?)"""
const pathRegex = """(?=.*[/\\])(?:(?:\w+:\/\/)?(?:[a-zA-Z]:(/|\\{1,2})|(/|\\{1,2})|)(?:[^\\/\s\"'>\[\]:]+(/|\\{1,2}))*([^\\/\s\"'>\[\]:]+(?:\.\w+)?)?)"""
discard """C:/Users/nima"""
discard """C:/Use"""
discard """./text/completion.nim"""
discard """../src/app_interface.nim"""
discard """C:\Nev\nev.nimble"""
discard """app://src/language_server_command_line.nim"""
discard """nimble://"""

type
  LanguageServerPaths* = ref object of LanguageServer
    services: Services
    config: ConfigStore
    documents: DocumentEditorService
    vfs: VFS
    files: Table[string, string]
    commandHistory*: seq[string]
    pathRegex: Regex

  LanguageServerPathsService* = ref object of Service
    languageServer: LanguageServerPaths

proc newLanguageServerPaths(services: Services): LanguageServerPaths =
  var server = new LanguageServerPaths
  server.services = services
  server.documents = services.getService(DocumentEditorService).get
  server.vfs = services.getService(VFSService).get.vfs
  server.config = services.getService(ConfigService).get.runtime
  try:
    server.pathRegex = re(pathRegex)
  except:
    log lvlError, &"Failed to create path regex: {getCurrentExceptionMsg()}"
  return server

func serviceName*(_: typedesc[LanguageServerPathsService]): string = "LanguageServerPathsService"

addBuiltinService(LanguageServerPathsService, VFSService, DocumentEditorService)

method init*(self: LanguageServerPathsService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"LanguageServerPathsService.init"
  self.languageServer = newLanguageServerPaths(self.services)
  discard self.languageServer.documents.onEditorRegistered.subscribe proc(editor: DocumentEditor) =
    let doc = editor.getDocument()
    if doc of TextDocument:
      let textDoc = doc.TextDocument
      let languages = self.languageServer.config.get("lsp.paths.languages", newSeq[string]())
      if textDoc.languageId in languages and not textDoc.hasLanguageServer(self.languageServer):
        textDoc.addLanguageServer(self.languageServer)
  return ok()

method getDefinition*(self: LanguageServerPaths, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  debugf"getDefinition '{filename}', {location}"
  var definitions = newSeq[Definition]()
  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    let textDoc = doc.TextDocument
    let rope = textDoc.rope
    if location.line >= rope.lines:
      return definitions

    let lineLen = rope.lineLen(location.line)
    if location.column > lineLen or lineLen > 512:
      return definitions

    let pathRegex = textDoc.config.get("lsp.paths.regex", pathRegex)
    let text = rope.slice(point(location.line, 0)...point(location.line, lineLen)).toRope
    let bounds = await findAllAsync(text.slice(int), pathRegex)
    for b in bounds:
      if b.a == b.b or location.column < b.a.column.int or location.column > b.b.column.int:
        continue

      var path = $text[b]
      if path.find("/") == -1 and path.find("\\") == -1:
        continue

      if path.startsWith("../") or path.startsWith("..\\"):
        let fileDir = filename.splitPath.head
        path = fileDir // path

      elif path.startsWith("./") or path.startsWith(".\\"):
        let fileDir = filename.splitPath.head
        path = fileDir // path

      let fileKind = await self.vfs.getFileKind(path)
      if fileKind == FileKind.File.some:
        definitions.add Definition(
          filename: path,
          location: (0, 0),
        )

  return definitions

method getCompletionTriggerChars*(self: LanguageServer): set[char] {.gcsafe, raises: [].} = {'a'..'z', 'A'..'Z', '0'..'9', '/', '\\', ':', '-', '_', '.'}

method getCompletions*(self: LanguageServerPaths, filename: string, location: Cursor): Future[Response[CompletionList]] {.async.} =
  debugf"LanguageServerPaths.getCompletions '{filename}', {location}"
  let vfs = self.services.getService(VfsService).get.vfs

  var completions = newSeq[CompletionItem]()

  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    let textDoc = doc.TextDocument
    let rope = textDoc.rope
    if location.line >= rope.lines or location.column > rope.lineLen(location.line):
      return CompletionList(items: completions).success

    let range = point(location.line, 0)...location.toPoint
    if range.b.column - range.a.column > 512:
      return CompletionList(items: completions).success

    let pathRegex = textDoc.config.get("lsp.paths.regex", pathRegex)
    let text = rope.slice(range).toRope
    let bounds = await findAllAsync(text.slice(int), pathRegex)
    for b in bounds:
      if b.a == b.b or location.column < b.a.column.int or location.column > b.b.column.int:
        continue

      let path = $text[b]
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
          textEdit: lsp_types.TextEdit(
            range: replaceRange.toSelection.toLspRange,
            newText: name & divider,
          ).toJson.jsonTo(CompletionItemTextEditVariant).some
        )

  return CompletionList(items: completions).success
