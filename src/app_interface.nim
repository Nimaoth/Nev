import std/[json, options]
import misc/[traits, custom_async]
import platform/platform
import workspaces/workspace
import finder/[finder, previewer]
import events, popup, document_editor, document, config_provider, selector_popup_builder
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
  method handleModeChanged*(self: AppInterface, editor: DocumentEditor, oldMode: string, newMode: string)
  method invokeCallback*(self: AppInterface, context: string, args: JsonNode): bool
  method invokeAnyCallback*(self: AppInterface, context: string, args: JsonNode): JsonNode
  method registerEditor*(self: AppInterface, editor: DocumentEditor): void
  method unregisterEditor*(self: AppInterface, editor: DocumentEditor): void
  method tryActivateEditor*(self: AppInterface, editor: DocumentEditor)
  method getActiveEditor*(self: AppInterface): Option[DocumentEditor]
  method getEditorForId*(self: AppInterface, id: EditorId): Option[DocumentEditor]
  method getEditorForPath*(self: AppInterface, path: string): Option[DocumentEditor]
  method getPopupForId*(self: AppInterface, id: EditorId): Option[Popup]
  method createSelectorPopup*(self: AppInterface): Popup
  method setLocationList*(self: AppInterface, list: seq[FinderItem],
    previewer: Option[Previewer] = Previewer.none)
  method pushSelectorPopup*(self: AppInterface, popup: SelectorPopupBuilder): ISelectorPopup
  method pushPopup*(self: AppInterface, popup: Popup)
  method popPopup*(self: AppInterface, popup: Popup)
  method popPopup*(self: AppInterface, popup: EditorId)
  method getAllDocuments*(self: AppInterface): seq[Document]
  method getDocument*(self: AppInterface, path: string,
    workspace: Option[WorkspaceFolder] = WorkspaceFolder.none, app: bool = false): Option[Document]
  method getOrOpenDocument*(self: AppInterface, path: string,
    workspace: Option[WorkspaceFolder] = WorkspaceFolder.none, app: bool = false, load: bool = true
    ): Option[Document]
  method tryCloseDocument*(self: AppInterface, document: Document, force: bool): bool
  method onEditorRegisteredEvent*(self: AppInterface): var Event[DocumentEditor]
  method onEditorDeregisteredEvent*(self: AppInterface): var Event[DocumentEditor]

var gAppInterface*: AppInterface = nil