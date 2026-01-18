
import std/[options, json]
import misc/[custom_logger, util, response, custom_async]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base, lsp_types]
import document

include dynlib_export

type
  LanguageServerDynamic* = ref object of LanguageServer
    connectImpl*: proc(self: LanguageServerDynamic, document: Document) {.gcsafe, raises: [].}
    disconnectImpl*: proc(self: LanguageServerDynamic, document: Document) {.gcsafe, raises: [].}
    getDefinitionImpl*: proc(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.gcsafe, raises: [].}
    getDeclarationImpl*: proc(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.gcsafe, raises: [].}
    getImplementationImpl*: proc(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.gcsafe, raises: [].}
    getTypeDefinitionImpl*: proc(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.gcsafe, raises: [].}
    getReferencesImpl*: proc(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.gcsafe, raises: [].}
    switchSourceHeaderImpl*: proc(self: LanguageServerDynamic, filename: string): Future[Option[string]] {.gcsafe, raises: [].}
    getCompletionsImpl*: proc(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.gcsafe, raises: [].}
    getSymbolsImpl*: proc(self: LanguageServerDynamic, filename: string): Future[seq[Symbol]] {.gcsafe, raises: [].}
    getWorkspaceSymbolsImpl*: proc(self: LanguageServerDynamic, filename: string, query: string): Future[seq[Symbol]] {.gcsafe, raises: [].}
    getHoverImpl*: proc(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Option[string]] {.gcsafe, raises: [].}
    getSignatureHelpImpl*: proc(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] {.gcsafe, raises: [].}
    getInlayHintsImpl*: proc(self: LanguageServerDynamic, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.gcsafe, raises: [].}
    getDiagnosticsImpl*: proc(self: LanguageServerDynamic, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.gcsafe, raises: [].}
    getCompletionTriggerCharsImpl*: proc(self: LanguageServerDynamic): set[char] {.gcsafe, raises: [].}
    getCodeActionsImpl*: proc(self: LanguageServerDynamic, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]): Future[Response[lsp_types.CodeActionResponse]] {.gcsafe, raises: [].}
    renameImpl*: proc(self: LanguageServerDynamic, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] {.gcsafe, raises: [].}
    executeCommandImpl*: proc(self: LanguageServerDynamic, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.gcsafe, raises: [].}

proc newLanguageServerDynamic*(): LanguageServerDynamic =
  var server = new LanguageServerDynamic
  return server

when implModule:
  method connect*(self: LanguageServerDynamic, document: Document) {.gcsafe, raises: [].} =
    if self.connectImpl != nil:
      self.connectImpl(self, document)

  method disconnect*(self: LanguageServerDynamic, document: Document) {.gcsafe, raises: [].} =
    if self.disconnectImpl != nil:
      self.disconnectImpl(self, document)

  method getDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] =
    if self.getDefinitionImpl != nil:
      return self.getDefinitionImpl(self, filename, location)
    else:
      return seq[Definition].default.toFuture

  method getDeclaration*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] =
    if self.getDeclarationImpl != nil:
      return self.getDeclarationImpl(self, filename, location)
    else:
      return seq[Definition].default.toFuture

  method getImplementation*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] =
    if self.getImplementationImpl != nil:
      return self.getImplementationImpl(self, filename, location)
    else:
      return seq[Definition].default.toFuture

  method getTypeDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] =
    if self.getTypeDefinitionImpl != nil:
      return self.getTypeDefinitionImpl(self, filename, location)
    else:
      return seq[Definition].default.toFuture

  method getReferences*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] =
    if self.getReferencesImpl != nil:
      return self.getReferencesImpl(self, filename, location)
    else:
      return seq[Definition].default.toFuture

  method switchSourceHeader*(self: LanguageServerDynamic, filename: string): Future[Option[string]] =
    if self.switchSourceHeaderImpl != nil:
      return self.switchSourceHeaderImpl(self, filename)
    else:
      return Option[string].default.toFuture

  method getCompletions*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] =
    if self.getCompletionsImpl != nil:
      return self.getCompletionsImpl(self, filename, location)
    else:
      return Response[lsp_types.CompletionList].default.toFuture

  method getSymbols*(self: LanguageServerDynamic, filename: string): Future[seq[Symbol]] =
    if self.getSymbolsImpl != nil:
      return self.getSymbolsImpl(self, filename)
    else:
      return seq[Symbol].default.toFuture

  method getWorkspaceSymbols*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[Symbol]] =
    if self.getWorkspaceSymbolsImpl != nil:
      return self.getWorkspaceSymbolsImpl(self, filename, query)
    else:
      return seq[Symbol].default.toFuture

  method getHover*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Option[string]] =
    if self.getHoverImpl != nil:
      return self.getHoverImpl(self, filename, location)
    else:
      return Option[string].default.toFuture

  method getSignatureHelp*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] =
    if self.getSignatureHelpImpl != nil:
      return self.getSignatureHelpImpl(self, filename, location)
    else:
      return Response[seq[lsp_types.SignatureHelpResponse]].default.toFuture

  method getInlayHints*(self: LanguageServerDynamic, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] =
    if self.getInlayHintsImpl != nil:
      return self.getInlayHintsImpl(self, filename, selection)
    else:
      return Response[seq[language_server_base.InlayHint]].default.toFuture

  method getDiagnostics*(self: LanguageServerDynamic, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] =
    if self.getDiagnosticsImpl != nil:
      return self.getDiagnosticsImpl(self, filename)
    else:
      return Response[seq[lsp_types.Diagnostic]].default.toFuture

  method getCompletionTriggerChars*(self: LanguageServerDynamic): set[char] =
    if self.getCompletionTriggerCharsImpl != nil:
      return self.getCompletionTriggerCharsImpl(self)
    else:
      return set[char].default

  method getCodeActions*(self: LanguageServerDynamic, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]): Future[Response[lsp_types.CodeActionResponse]] =
    if self.getCodeActionsImpl != nil:
      return self.getCodeActionsImpl(self, filename, selection, diagnostics)
    else:
      return Response[lsp_types.CodeActionResponse].default.toFuture

  method rename*(self: LanguageServerDynamic, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] =
    if self.renameImpl != nil:
      return self.renameImpl(self, filename, position, newName)
    else:
      return Response[seq[lsp_types.WorkspaceEdit]].default.toFuture

  method executeCommand*(self: LanguageServerDynamic, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] =
    if self.executeCommandImpl != nil:
      return self.executeCommandImpl(self, command, arguments)
    else:
      return Response[JsonNode].default.toFuture
