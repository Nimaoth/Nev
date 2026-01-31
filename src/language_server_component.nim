import std/[options, json]
import misc/[event, custom_async, response]
import component
import text/language/[language_server_base, lsp_types]
export component
from scripting_api import Cursor, Selection

include dynlib_export

type LanguageServerComponent* = ref object of Component
  onLanguageServerAttached*: Event[tuple[component: LanguageServerComponent, languageServer: LanguageServer]]
  onLanguageServerDetached*: Event[tuple[component: LanguageServerComponent, languageServer: LanguageServer]]

# DLL API
var LanguageServerComponentId* {.apprtl.}: ComponentTypeId

proc languageServerComponentAddLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool {.apprtl, gcsafe, raises: [].}
proc languageServerComponentRemoveLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool {.apprtl, gcsafe, raises: [].}
proc languageServerComponentHasLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool {.apprtl, gcsafe, raises: [].}
proc getLanguageServerComponent*(self: ComponentOwner): Option[LanguageServerComponent] {.apprtl, gcsafe, raises: [].}

proc languageServerComponentGetDefinition(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentGetDeclaration(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentGetImplementation(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentGetTypeDefinition(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentGetReferences(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentSwitchSourceHeader(self: LanguageServerComponent, filename: string): Future[Option[string]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentGetCompletions(self: LanguageServerComponent, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentGetSymbols(self: LanguageServerComponent, filename: string): Future[seq[Symbol]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentGetWorkspaceSymbols(self: LanguageServerComponent, filename: string, query: string): Future[seq[Symbol]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentGetHover(self: LanguageServerComponent, filename: string, location: Cursor): Future[Option[string]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentGetSignatureHelp(self: LanguageServerComponent, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentGetInlayHints(self: LanguageServerComponent, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentGetDiagnostics(self: LanguageServerComponent, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentGetCompletionTriggerChars(self: LanguageServerComponent): set[char] {.apprtl, gcsafe, raises: [].}
proc languageServerComponentGetCodeActions(self: LanguageServerComponent, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]): Future[Response[lsp_types.CodeActionResponse]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentRename(self: LanguageServerComponent, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] {.apprtl, async: (raises: []), gcsafe.}
proc languageServerComponentExecuteCommand(self: LanguageServerComponent, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.apprtl, async: (raises: []), gcsafe.}

# Nice wrappers
proc addLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool = languageServerComponentAddLanguageServer(self, languageServer)
proc removeLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool = languageServerComponentRemoveLanguageServer(self, languageServer)

proc hasLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool = languageServerComponentHasLanguageServer(self, languageServer)


proc getDefinition*(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.async: (raises: []).} =
  await languageServerComponentGetDefinition(self, filename, location)
proc getDeclaration*(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.async: (raises: []).} =
  await languageServerComponentGetDeclaration(self, filename, location)
proc getImplementation*(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.async: (raises: []).} =
  await languageServerComponentGetImplementation(self, filename, location)
proc getTypeDefinition*(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.async: (raises: []).} =
  await languageServerComponentGetTypeDefinition(self, filename, location)
proc getReferences*(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.async: (raises: []).} =
  await languageServerComponentGetReferences(self, filename, location)
proc switchSourceHeader*(self: LanguageServerComponent, filename: string): Future[Option[string]] {.async: (raises: []).} =
  await languageServerComponentSwitchSourceHeader(self, filename)
proc getCompletions*(self: LanguageServerComponent, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.async: (raises: []).} =
  await languageServerComponentGetCompletions(self, filename, location)
proc getSymbols*(self: LanguageServerComponent, filename: string): Future[seq[Symbol]] {.async: (raises: []).} =
  await languageServerComponentGetSymbols(self, filename)
proc getWorkspaceSymbols*(self: LanguageServerComponent, filename: string, query: string): Future[seq[Symbol]] {.async: (raises: []).} =
  await languageServerComponentGetWorkspaceSymbols(self, filename, query)
proc getHover*(self: LanguageServerComponent, filename: string, location: Cursor): Future[Option[string]] {.async: (raises: []).} =
  await languageServerComponentGetHover(self, filename, location)
proc getSignatureHelp*(self: LanguageServerComponent, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] {.async: (raises: []).} =
  await languageServerComponentGetSignatureHelp(self, filename, location)
proc getInlayHints*(self: LanguageServerComponent, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.async: (raises: []).} =
  await languageServerComponentGetInlayHints(self, filename, selection)
proc getDiagnostics*(self: LanguageServerComponent, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.async: (raises: []).} =
  await languageServerComponentGetDiagnostics(self, filename)
proc getCompletionTriggerChars*(self: LanguageServerComponent): set[char] =
  languageServerComponentGetCompletionTriggerChars(self)
proc getCodeActions*(self: LanguageServerComponent, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]): Future[Response[lsp_types.CodeActionResponse]] {.async: (raises: []).} =
  await languageServerComponentGetCodeActions(self, filename, selection, diagnostics)
proc rename*(self: LanguageServerComponent, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] {.async: (raises: []).} =
  await languageServerComponentRename(self, filename, position, newName)
proc executeCommand*(self: LanguageServerComponent, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.async: (raises: []).} =
  await languageServerComponentExecuteCommand(self, command, arguments)

# Implementation
when implModule:
  import std/strformat
  import misc/[util, custom_logger]
  import language_server_list

  logCategory "language-server-comp"

  LanguageServerComponentId = componentGenerateTypeId()

  type LanguageServerComponentImpl* = ref object of LanguageServerComponent
    languageServerList*: LanguageServerList

  proc languageServerComponentAddLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool =
    let self = self.LanguageServerComponentImpl
    if not self.languageServerList.addLanguageServer(languageServer):
      return false
    self.onLanguageServerAttached.invoke (self.LanguageServerComponent, languageServer)
    return true

  proc languageServerComponentRemoveLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool =
    let self = self.LanguageServerComponentImpl
    if not self.languageServerList.removeLanguageServer(languageServer):
      return false
    self.onLanguageServerDetached.invoke (self.LanguageServerComponent, languageServer)
    return true

  proc languageServerComponentHasLanguageServer*(self: LanguageServerComponent, languageServer: LanguageServer): bool =
    let self = self.LanguageServerComponentImpl
    return self.languageServerList.languageServers.find(languageServer) != -1

  proc getLanguageServerComponent*(self: ComponentOwner): Option[LanguageServerComponent] {.gcsafe, raises: [].} =
    return self.getComponent(LanguageServerComponentId).mapIt(it.LanguageServerComponent)

  proc newLanguageServerComponent*(languageServer: LanguageServerList): LanguageServerComponent =
    return LanguageServerComponentImpl(typeId: LanguageServerComponentId, languageServerList: languageServer)

  proc languageServerComponentGetDefinition(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getDefinition(filename, location)
    except CatchableError as e:
      log lvlError, &"getDefinition: {e.msg}"
  proc languageServerComponentGetDeclaration(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getDeclaration(filename, location)
    except CatchableError as e:
      log lvlError, &"getDeclaration: {e.msg}"
  proc languageServerComponentGetImplementation(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getImplementation(filename, location)
    except CatchableError as e:
      log lvlError, &"getImplementation: {e.msg}"
  proc languageServerComponentGetTypeDefinition(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getTypeDefinition(filename, location)
    except CatchableError as e:
      log lvlError, &"getTypeDefinition: {e.msg}"
  proc languageServerComponentGetReferences(self: LanguageServerComponent, filename: string, location: Cursor): Future[seq[Definition]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getReferences(filename, location)
    except CatchableError as e:
      log lvlError, &"getReferences: {e.msg}"
  proc languageServerComponentSwitchSourceHeader(self: LanguageServerComponent, filename: string): Future[Option[string]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.switchSourceHeader(filename)
    except CatchableError as e:
      log lvlError, &"switchSourceHeader: {e.msg}"
  proc languageServerComponentGetCompletions(self: LanguageServerComponent, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getCompletions(filename, location)
    except CatchableError as e:
      log lvlError, &"getCompletions: {e.msg}"
  proc languageServerComponentGetSymbols(self: LanguageServerComponent, filename: string): Future[seq[Symbol]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getSymbols(filename)
    except CatchableError as e:
      log lvlError, &"getSymbols: {e.msg}"
  proc languageServerComponentGetWorkspaceSymbols(self: LanguageServerComponent, filename: string, query: string): Future[seq[Symbol]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getWorkspaceSymbols(filename, query)
    except CatchableError as e:
      log lvlError, &"getWorkspaceSymbols: {e.msg}"
  proc languageServerComponentGetHover(self: LanguageServerComponent, filename: string, location: Cursor): Future[Option[string]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getHover(filename, location)
    except CatchableError as e:
      log lvlError, &"getHover: {e.msg}"
  proc languageServerComponentGetSignatureHelp(self: LanguageServerComponent, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getSignatureHelp(filename, location)
    except CatchableError as e:
      log lvlError, &"getSignatureHelp: {e.msg}"
  proc languageServerComponentGetInlayHints(self: LanguageServerComponent, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getInlayHints(filename, selection)
    except CatchableError as e:
      log lvlError, &"getInlayHints: {e.msg}"
  proc languageServerComponentGetDiagnostics(self: LanguageServerComponent, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getDiagnostics(filename)
    except CatchableError as e:
      log lvlError, &"getDiagnostics: {e.msg}"
  proc languageServerComponentGetCompletionTriggerChars(self: LanguageServerComponent): set[char] =
    try:
      self.LanguageServerComponentImpl.languageServerList.getCompletionTriggerChars()
    except CatchableError as e:
      log lvlError, &"getCompletionTriggerChars: {e.msg}"
      return {}
  proc languageServerComponentGetCodeActions(self: LanguageServerComponent, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]): Future[Response[lsp_types.CodeActionResponse]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.getCodeActions(filename, selection, diagnostics)
    except CatchableError as e:
      log lvlError, &"getCodeActions: {e.msg}"
  proc languageServerComponentRename(self: LanguageServerComponent, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.rename(filename, position, newName)
    except CatchableError as e:
      log lvlError, &"rename: {e.msg}"
  proc languageServerComponentExecuteCommand(self: LanguageServerComponent, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.async: (raises: []).} =
    try:
      return await self.LanguageServerComponentImpl.languageServerList.executeCommand(command, arguments)
    except CatchableError as e:
      log lvlError, &"executeCommand: {e.msg}"
