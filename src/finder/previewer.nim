import misc/[util, custom_logger]
import document_editor
import finder, view
import ui/node

export previewer, finder

{.push gcsafe.}
{.push raises: [].}

logCategory "previewer"

type
  Previewer* = ref object of RootObj
    activateImpl*: proc (self: DynamicPreviewer) {.gcsafe, raises: {}.}
    deactivateImpl*: proc (self: DynamicPreviewer) {.gcsafe, raises: {}.}
    previewItemImpl*: proc (self: DynamicPreviewer, item: FinderItem, editor: DocumentEditor) {.gcsafe, raises: [].}
    previewItemImpl2*: proc (self: DynamicPreviewer, item: FinderItem): View {.gcsafe, raises: [].}
    delayPreviewImpl*: proc (self: DynamicPreviewer) {.gcsafe, raises: [].}
    deinitImpl*: proc (self: DynamicPreviewer) {.gcsafe, raises: [].}
    renderImpl*: proc(self: DynamicPreviewer, builder: UINodeBuilder): seq[OverlayFunction] {.gcsafe, raises: [].}

  DynamicPreviewer* = Previewer

proc activate*(self: DynamicPreviewer) =
  if self.activateImpl != nil:
    self.activateImpl(self)
proc deactivate*(self: DynamicPreviewer) =
  if self.deactivateImpl != nil:
    self.deactivateImpl(self)
proc previewItem*(self: DynamicPreviewer, item: FinderItem, editor: DocumentEditor) =
  if self.previewItemImpl != nil:
    self.previewItemImpl(self, item, editor)
proc previewItem*(self: DynamicPreviewer, item: FinderItem): View =
  if self.previewItemImpl2 != nil:
    return self.previewItemImpl2(self, item)
proc delayPreview*(self: DynamicPreviewer) =
  if self.delayPreviewImpl != nil:
    self.delayPreviewImpl(self)
proc deinit*(self: DynamicPreviewer) =
  if self.deinitImpl != nil:
    self.deinitImpl(self)

proc render*(self: DynamicPreviewer, builder: UINodeBuilder): seq[OverlayFunction] =
  if self.renderImpl != nil:
    return self.renderImpl(self, builder)
  return @[]
