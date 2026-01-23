import misc/[util, custom_logger]
import document_editor
import finder, view

export previewer, finder

{.push gcsafe.}
{.push raises: [].}

logCategory "previewer"

type
  Previewer* = ref object of RootObj
  DynamicPreviewer* = ref object of Previewer
    activateImpl*: proc (self: DynamicPreviewer) {.gcsafe, raises: {}.}
    deactivateImpl*: proc (self: DynamicPreviewer) {.gcsafe, raises: {}.}
    previewItemImpl*: proc (self: DynamicPreviewer, item: FinderItem, editor: DocumentEditor) {.gcsafe, raises: [].}
    previewItemImpl2*: proc (self: DynamicPreviewer, item: FinderItem): View {.gcsafe, raises: [].}
    delayPreviewImpl*: proc (self: DynamicPreviewer) {.gcsafe, raises: [].}
    deinitImpl*: proc (self: DynamicPreviewer) {.gcsafe, raises: [].}


method activate*(self: Previewer) {.base.} = discard
method deactivate*(self: Previewer) {.base.} = discard
method previewItem*(self: Previewer, item: FinderItem, editor: DocumentEditor) {.base, gcsafe, raises: [].} = discard
method previewItem*(self: Previewer, item: FinderItem): View {.base, gcsafe, raises: [].} = nil
method delayPreview*(self: Previewer) {.base, gcsafe, raises: [].} = discard
method deinit*(self: Previewer) {.base, gcsafe, raises: [].} = discard

method activate*(self: DynamicPreviewer) =
  if self.activateImpl != nil:
    self.activateImpl(self)
method deactivate*(self: DynamicPreviewer) =
  if self.deactivateImpl != nil:
    self.deactivateImpl(self)
method previewItem*(self: DynamicPreviewer, item: FinderItem, editor: DocumentEditor) =
  if self.previewItemImpl != nil:
    self.previewItemImpl(self, item, editor)
method previewItem*(self: DynamicPreviewer, item: FinderItem): View =
  if self.previewItemImpl2 != nil:
    return self.previewItemImpl2(self, item)
method delayPreview*(self: DynamicPreviewer) =
  if self.delayPreviewImpl != nil:
    self.delayPreviewImpl(self)
method deinit*(self: DynamicPreviewer) =
  if self.deinitImpl != nil:
    self.deinitImpl(self)
