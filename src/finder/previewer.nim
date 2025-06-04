import misc/[util, custom_logger]
import document_editor
import finder, view

export previewer, finder

{.push gcsafe.}
{.push raises: [].}

logCategory "previewer"

type
  Previewer* = ref object of RootObj

method activate*(self: Previewer) {.base.} = discard
method deactivate*(self: Previewer) {.base.} = discard
method previewItem*(self: Previewer, item: FinderItem, editor: DocumentEditor) {.base, gcsafe, raises: [].} = discard
method previewItem*(self: Previewer, item: FinderItem): View {.base, gcsafe, raises: [].} = nil
method delayPreview*(self: Previewer) {.base, gcsafe, raises: [].} = discard
method deinit*(self: Previewer) {.base, gcsafe, raises: [].} = discard
