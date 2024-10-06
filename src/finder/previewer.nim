import misc/[util, custom_logger]
import document_editor
import finder

export previewer, finder

logCategory "previewer"

type
  Previewer* = ref object of RootObj

method previewItem*(self: Previewer, item: FinderItem, editor: DocumentEditor) {.base, gcsafe, raises: [].} = discard
method delayPreview*(self: Previewer) {.base, gcsafe, raises: [].} = discard
method deinit*(self: Previewer) {.base, gcsafe, raises: [].} = discard
