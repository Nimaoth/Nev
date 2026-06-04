import std/[json, tables, options]
import misc/[myjsonutils]
import finder, previewer
import document_editor

type ISelectorPopup* = object
  getSearchString*: proc(): string {.gcsafe, raises: [].}
  closed*: proc(): bool {.gcsafe, raises: [].}
  getSelectedItem*: proc(): Option[FinderItem] {.gcsafe, raises: [].}
  pop*: proc() {.gcsafe, raises: [].}
  preview*: proc(item: FinderItem) {.gcsafe, raises: [].}
  getPreviewEditor*: proc(): DocumentEditor {.gcsafe, raises: [].}
  inLayout*: proc(): bool {.gcsafe, raises: [].}

type
  SelectorPopupBuilder* = object
    scope*: Option[string]
    title*: string
    scaleX*: float = 0.5
    scaleY*: float = 0.5
    slot*: string # "" to push it as a popup, non-empty to put it in the specified slot
    previewScale*: float = 0.5
    maxDisplayNameWidth*: int = 50
    maxColumnWidth*: int = 60
    previewVisible*: bool = true
    sizeToContentY*: bool = false
    handleItemSelected*: proc(popup: ISelectorPopup, item: FinderItem) {.gcsafe, raises: [].}
    handleItemConfirmed*: proc(popup: ISelectorPopup, item: FinderItem): bool {.gcsafe, raises: [].}
    handleCanceled*: proc(popup: ISelectorPopup) {.gcsafe, raises: [].}
    customActions*: Table[string, proc(popup: ISelectorPopup, args: JsonNode): bool {.gcsafe, raises: [].}]
    finder*: Option[Finder]
    previewer*: Option[Previewer]
