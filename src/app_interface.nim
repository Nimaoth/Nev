import std/[options]
import misc/[traits]
import finder/[finder, previewer]
import popup, document_editor
import service
export service

traitRef AppInterface:
  method getActiveEditor*(self: AppInterface): Option[DocumentEditor] {.gcsafe, raises: [].}
  method createSelectorPopup*(self: AppInterface): Popup {.gcsafe, raises: [].}
  method setLocationList*(self: AppInterface, list: seq[FinderItem],
    previewer: Option[Previewer] = Previewer.none) {.gcsafe, raises: [].}
  method getServices*(self: AppInterface): Services {.gcsafe, raises: [].}

var gAppInterface*: AppInterface = nil
