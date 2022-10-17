import document, events

type EditorId* = distinct int

type DocumentEditor* = ref object of RootObj
  id: EditorId
  eventHandler*: EventHandler
  renderHeader*: bool
  fillAvailableSpace*: bool

func id*(self: DocumentEditor): EditorId = self.id
func `==`*(a: EditorId, b: EditorId): bool = a.int == b.int

var nextEditorId = 0

proc init*(self: DocumentEditor) =
  self.id = nextEditorId.EditorId
  nextEditorId += 1

  self.renderHeader = true
  self.fillAvailableSpace = true

method canEdit*(self: DocumentEditor, document: Document): bool {.base.} =
  return false

method createWithDocument*(self: DocumentEditor, document: Document): DocumentEditor {.base, locks: "unknown".} =
  return nil

method getEventHandlers*(self: DocumentEditor): seq[EventHandler] {.base.} =
  return @[]

method handleDocumentChanged*(self: DocumentEditor) {.base, locks: "unknown".} =
  discard