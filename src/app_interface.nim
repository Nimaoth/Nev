import std/[json, options]
import misc/[traits, custom_async]
import platform/platform
import finder/[finder, previewer]
import popup, document_editor, config_provider, selector_popup_builder, register
import service
export service

traitRef AppInterface:
  method setRegisterTextAsync*(self: AppInterface, text: string, register: string): Future[void] {.gcsafe, raises: [].}
  method getRegisterTextAsync*(self: AppInterface, register: string): Future[string] {.gcsafe, raises: [].}
  method setRegisterAsync*(self: AppInterface, register: string, value: sink Register): Future[void] {.gcsafe, raises: [].}
  method getRegisterAsync*(self: AppInterface, register: string, res: ptr Register): Future[bool] {.gcsafe, raises: [].}
  method recordCommand*(self: AppInterface, command: string, args: string) {.gcsafe, raises: [].}
  method openWorkspaceFile*(self: AppInterface, path: string, append: bool = false): Option[DocumentEditor] {.gcsafe, raises: [].}
  method getActiveEditor*(self: AppInterface): Option[DocumentEditor] {.gcsafe, raises: [].}
  method createSelectorPopup*(self: AppInterface): Popup {.gcsafe, raises: [].}
  method setLocationList*(self: AppInterface, list: seq[FinderItem],
    previewer: Option[Previewer] = Previewer.none) {.gcsafe, raises: [].}
  method pushSelectorPopup*(self: AppInterface, popup: SelectorPopupBuilder): ISelectorPopup {.gcsafe, raises: [].}
  method getServices*(self: AppInterface): Services {.gcsafe, raises: [].}

var gAppInterface*: AppInterface = nil
