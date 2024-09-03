import std/[json, tables, options]
import misc/[traits, myjsonutils]
import finder/[finder, previewer]

traitRef ISelectorPopup:
  method getSearchString*(self: ISelectorPopup): string
  method closed*(self: ISelectorPopup): bool
  method getSelectedItem*(self: ISelectorPopup): Option[FinderItem]

type
  SelectorPopupBuilder* = object
    scope*: Option[string]
    scaleX*: float = 0.5
    scaleY*: float = 0.5
    previewScale*: float = 0.5
    previewVisible*: bool = true
    sizeToContentY*: bool = false
    handleItemSelected*: proc(popup: ISelectorPopup, item: FinderItem)
    handleItemConfirmed*: proc(popup: ISelectorPopup, item: FinderItem): bool
    handleCanceled*: proc(popup: ISelectorPopup)
    customActions*: Table[string, proc(popup: ISelectorPopup, args: JsonNode): bool]
    finder*: Option[Finder]
    previewer*: Option[Previewer]
