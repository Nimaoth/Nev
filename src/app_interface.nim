import std/[json, options]
import platform/platform
import workspaces/workspace
import language/language_server_base
import traits, events, document_editor, popup, config_provider
from scripting_api import EditorId

traitRef AppInterface:
  method platform*(self: AppInterface): Platform
  method configProvider*(self: AppInterface): ConfigProvider
  method getEventHandlerConfig*(self: AppInterface, context: string): EventHandlerConfig
  method setRegisterText*(self: AppInterface, text: string, register: string)
  method getRegisterText*(self: AppInterface, register: string): string
  method openWorkspaceFile*(self: AppInterface, path: string, workspace: WorkspaceFolder): Option[DocumentEditor]
  method openFile*(self: AppInterface, path: string): Option[DocumentEditor]
  method handleUnknownDocumentEditorAction*(self: AppInterface, editor: DocumentEditor, action: string, args: JsonNode): EventResponse
  method handleUnknownPopupAction*(self: AppInterface, popup: Popup, action: string, args: string): EventResponse
  method handleModeChanged*(self: AppInterface, editor: DocumentEditor, oldMode: string, newMode: string)
  method invokeCallback*(self: AppInterface, context: string, args: JsonNode): bool
  method registerEditor*(self: AppInterface, editor: DocumentEditor): void
  method unregisterEditor*(self: AppInterface, editor: DocumentEditor): void
  method getEditorForId*(self: AppInterface, id: EditorId): Option[DocumentEditor]
  method getPopupForId*(self: AppInterface, id: EditorId): Option[Popup]
  method createSelectorPopup*(self: AppInterface): Popup
  method pushPopup*(self: AppInterface, popup: Popup)
  method popPopup*(self: AppInterface, popup: Popup)
  method openSymbolsPopup*(self: AppInterface, symbols: seq[Symbol], handleItemSelected: proc(symbol: Symbol), handleItemConfirmed: proc(symbol: Symbol), handleCanceled: proc())

var gAppInterface*: AppInterface = nil