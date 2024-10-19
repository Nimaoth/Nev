import std/[sugar, options, json, tables]
import vmath
import misc/[util, rect_utils, myjsonutils, disposable_ref]
import selector_popup_builder, layout, selector_popup
from scripting_api as api import Selection, ToggleBool, toToggleBool, applyTo
import finder/[finder, previewer]
import platform/filesystem

{.push gcsafe.}

proc pushSelectorPopupImpl(self: LayoutService, builder: SelectorPopupBuilder): ISelectorPopup =
  let fs = ({.gcsafe.}: fs)
  var popup = newSelectorPopup(self.services, fs, builder.scope, builder.finder, builder.previewer.toDisposableRef)
  popup.scale.x = builder.scaleX
  popup.scale.y = builder.scaleY
  popup.previewScale = builder.previewScale
  popup.sizeToContentY = builder.sizeToContentY
  popup.previewVisible = builder.previewVisible
  popup.maxDisplayNameWidth = builder.maxDisplayNameWidth
  popup.maxColumnWidth = builder.maxColumnWidth

  if builder.handleItemSelected.isNotNil:
    popup.handleItemSelected = proc(item: FinderItem) =
      builder.handleItemSelected(popup.asISelectorPopup, item)

  if builder.handleItemConfirmed.isNotNil:
    popup.handleItemConfirmed = proc(item: FinderItem): bool =
      return builder.handleItemConfirmed(popup.asISelectorPopup, item)

  if builder.handleCanceled.isNotNil:
    popup.handleCanceled = proc() =
      builder.handleCanceled(popup.asISelectorPopup)

  for command, handler in builder.customActions.pairs:
    capture handler:
      popup.addCustomCommand command, proc(popup: SelectorPopup, args: JsonNode): bool =
        return handler(popup.asISelectorPopup, args)

  self.pushPopup popup

gPushSelectorPopupImpl = pushSelectorPopupImpl
