import misc/[util, custom_logger]
import document_editor
import finder, view
from nuigi import UiBuilder

export previewer, finder

{.push gcsafe.}
{.push raises: [].}

logCategory "previewer"

type
  Previewer* = ref object of RootObj
    activateImpl*: proc (self: Previewer) {.gcsafe, raises: {}.}
    deactivateImpl*: proc (self: Previewer) {.gcsafe, raises: {}.}
    previewItemImpl*: proc (self: Previewer, item: FinderItem, editor: DocumentEditor) {.gcsafe, raises: [].}
    previewItemImpl2*: proc (self: Previewer, item: FinderItem): View {.gcsafe, raises: [].}
    delayPreviewImpl*: proc (self: Previewer) {.gcsafe, raises: [].}
    deinitImpl*: proc (self: Previewer) {.gcsafe, raises: [].}
    renderNuiImpl*: proc(self: Previewer, nui: var UiBuilder) {.gcsafe, raises: [].}

proc activate*(self: Previewer) =
  if self.activateImpl != nil:
    self.activateImpl(self)
proc deactivate*(self: Previewer) =
  if self.deactivateImpl != nil:
    self.deactivateImpl(self)
proc previewItem*(self: Previewer, item: FinderItem, editor: DocumentEditor) =
  if self.previewItemImpl != nil:
    self.previewItemImpl(self, item, editor)
proc previewItem*(self: Previewer, item: FinderItem): View =
  if self.previewItemImpl2 != nil:
    return self.previewItemImpl2(self, item)
proc delayPreview*(self: Previewer) =
  if self.delayPreviewImpl != nil:
    self.delayPreviewImpl(self)
proc deinit*(self: Previewer) =
  if self.deinitImpl != nil:
    self.deinitImpl(self)

proc renderNui*(self: Previewer, nui: var UiBuilder) =
  if self.renderNuiImpl != nil:
    self.renderNuiImpl(self, nui)

proc render*(self: Previewer, nui: var UiBuilder) =
  self.renderNui(nui)
