import std/[json, options]
import misc/[traits, custom_async]
import platform/platform
import workspaces/workspace
import text/language/language_server_base
import events, document_editor, document, popup, config_provider, selector_popup_builder
from scripting_api import EditorId

traitRef AppInterface:
  method platform*(self: AppInterface): Platform
  method configProvider*(self: AppInterface): ConfigProvider
  method getEventHandlerConfig*(self: AppInterface, context: string): EventHandlerConfig
  method setRegisterTextAsync*(self: AppInterface, text: string, register: string): Future[void]
  method getRegisterTextAsync*(self: AppInterface, register: string): Future[string]
  method recordCommand*(self: AppInterface, command: string, args: string)
  method openWorkspaceFile*(self: AppInterface, path: string, workspace: WorkspaceFolder): Option[DocumentEditor]
  method openFile*(self: AppInterface, path: string): Option[DocumentEditor]
  method handleUnknownDocumentEditorAction*(self: AppInterface, editor: DocumentEditor, action: string, args: JsonNode): EventResponse
  method handleUnknownPopupAction*(self: AppInterface, popup: Popup, action: string, args: string): EventResponse
  method handleModeChanged*(self: AppInterface, editor: DocumentEditor, oldMode: string, newMode: string)
  method invokeCallback*(self: AppInterface, context: string, args: JsonNode): bool
  method invokeAnyCallback*(self: AppInterface, context: string, args: JsonNode): JsonNode
  method registerEditor*(self: AppInterface, editor: DocumentEditor): void
  method unregisterEditor*(self: AppInterface, editor: DocumentEditor): void
  method tryActivateEditor*(self: AppInterface, editor: DocumentEditor)
  method getEditorForId*(self: AppInterface, id: EditorId): Option[DocumentEditor]
  method getPopupForId*(self: AppInterface, id: EditorId): Option[Popup]
  method createSelectorPopup*(self: AppInterface): Popup
  method pushSelectorPopup*(self: AppInterface, popup: SelectorPopupBuilder): ISelectorPopup
  method pushPopup*(self: AppInterface, popup: Popup)
  method popPopup*(self: AppInterface, popup: Popup)
  method popPopup*(self: AppInterface, popup: EditorId)
  method openSymbolsPopup*(self: AppInterface, symbols: seq[Symbol], handleItemSelected: proc(symbol: Symbol), handleItemConfirmed: proc(symbol: Symbol), handleCanceled: proc())
  method getAllDocuments*(self: AppInterface): seq[Document]

var gAppInterface*: AppInterface = nil