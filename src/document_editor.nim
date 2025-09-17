import std/[json, tables, options, sets, hashes]
import vmath, bumpy
import misc/[event, custom_logger, id, custom_async, util, array_set, generational_seq]
import platform/[platform]
import scripting/expose
import document, events, input, service, platform_service, dispatch_tables, config_provider

from scripting_api import EditorId

{.push gcsafe.}
{.push raises: [].}

logCategory "document-editor"

declareSettings EditorSettings, "editor":
  ## Any editor with this set to true will be stored in the session and restored on startup.
  declare saveInSession, bool, true

type
  EditorIdNew* = distinct uint64
  DocumentEditor* = ref object of RootObj
    id*: EditorIdNew
    userId*: Id
    renderHeader*: bool
    fillAvailableSpace*: bool
    lastContentBounds*: Rect
    onMarkedDirty*: Event[void]
    mDirty: bool ## Set to true to trigger rerender
    active: bool
    onActiveChanged*: Event[DocumentEditor]
    config*: ConfigStore
    editorSettings*: EditorSettings

  DocumentFactory* = ref object of RootObj
  DocumentEditorFactory* = ref object of RootObj

  DocumentEditorService* = ref object of Service
    platform: Platform
    editors*: Table[EditorIdNew, DocumentEditor]
    pinnedEditors*: HashSet[EditorIdNew]
    pinnedDocuments*: seq[Document]
    onEditorRegistered*: Event[DocumentEditor]
    onEditorDeregistered*: Event[DocumentEditor]

    documents*: GenerationalSeq[Document, DocumentId]
    allEditors*: GenerationalSeq[DocumentEditor, EditorIdNew]

    documentFactories: seq[DocumentFactory]
    editorFactories: seq[DocumentEditorFactory]

    commandLineEditor*: DocumentEditor

proc `==`*(a, b: EditorIdNew): bool {.borrow.}
proc hash*(vr: EditorIdNew): Hash {.borrow.}
proc `$`*(vr: EditorIdNew): string {.borrow.}

func serviceName*(_: typedesc[DocumentEditorService]): string = "DocumentEditorService"

addBuiltinService(DocumentEditorService)

method init*(self: DocumentEditorService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"DocumentEditorService.init"
  self.pinnedEditors = initHashSet[EditorIdNew]()
  return ok()

method canOpenFile*(self: DocumentFactory, path: string): bool {.base, gcsafe, raises: [].} = discard
method createDocument*(self: DocumentFactory, services: Services, path: string, load: bool): Document {.base, gcsafe, raises: [].} = discard

method canEditDocument*(self: DocumentEditorFactory, document: Document): bool {.base, gcsafe, raises: [].} = discard
method createEditor*(self: DocumentEditorFactory, services: Services, document: Document): DocumentEditor {.base, gcsafe, raises: [].} = discard

func id*(self: DocumentEditor): EditorIdNew = self.id

proc init*(self: DocumentEditor) =
  self.userId = newId()

  self.renderHeader = true
  self.fillAvailableSpace = true

func dirty*(self: DocumentEditor): bool = self.mDirty

proc markDirty*(self: DocumentEditor, notify: bool = true) =
  if not self.mDirty and notify:
    self.mDirty = true
    self.onMarkedDirty.invoke()
  else:
    self.mDirty = true

proc resetDirty*(self: DocumentEditor) =
  self.mDirty = false

method handleActivate*(self: DocumentEditor) {.base, gcsafe, raises: [].} = discard
method handleDeactivate*(self: DocumentEditor) {.base, gcsafe, raises: [].} = discard

method getNamespace*(self: DocumentEditor): string {.base, gcsafe, raises: [].} = discard

proc `active=`*(self: DocumentEditor, newActive: bool) =
  let changed = if newActive != self.active:
    self.markDirty()
    true
  else:
    false

  self.active = newActive
  if changed:
    if self.active:
      self.handleActivate()
    else:
      self.handleDeactivate()
    self.onActiveChanged.invoke(self)
    assert self.active == newActive

func active*(self: DocumentEditor): bool = self.active

method deinit*(self: DocumentEditor) {.base, gcsafe, raises: [].} =
  discard

method canEdit*(self: DocumentEditor, document: Document): bool {.base, gcsafe, raises: [].} =
  return false

method getDocument*(self: DocumentEditor): Document {.base, gcsafe, raises: [].} = discard

method handleAction*(self: DocumentEditor, action: string, arg: string, record: bool = true): Option[JsonNode] {.base, gcsafe, raises: [].} = discard

method getEventHandlers*(self: DocumentEditor, inject: Table[string, EventHandler]): seq[EventHandler] {.base, gcsafe, raises: [].} =
  return @[]

method handleDocumentChanged*(self: DocumentEditor) {.base, gcsafe, raises: [].} =
  discard

method unregister*(self: DocumentEditor) {.base, gcsafe, raises: [].} =
  discard

method handleScroll*(self: DocumentEditor, scroll: Vec2, mousePosWindow: Vec2) {.base, gcsafe, raises: [].} =
  discard

method handleMousePress*(self: DocumentEditor, button: MouseButton, mousePosWindow: Vec2, modifiers: Modifiers) {.base, gcsafe, raises: [].} =
  discard

method handleMouseRelease*(self: DocumentEditor, button: MouseButton, mousePosWindow: Vec2) {.base, gcsafe, raises: [].} =
  discard

method handleMouseMove*(self: DocumentEditor, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) {.base, gcsafe, raises: [].} =
  discard

method getStateJson*(self: DocumentEditor): JsonNode {.base, gcsafe, raises: [].} =
  return newJObject()

method restoreStateJson*(self: DocumentEditor, state: JsonNode) {.base, gcsafe, raises: [].} =
  discard

method getStatisticsString*(self: DocumentEditor): string {.base, gcsafe, raises: [].} = discard

proc addDocumentFactory*(self: DocumentEditorService, factory: DocumentFactory) =
  self.documentFactories.add(factory)

proc addDocumentEditorFactory*(self: DocumentEditorService, factory: DocumentEditorFactory) =
  self.editorFactories.add(factory)

proc registerDocument*(self: DocumentEditorService, document: Document) =
  document.id = self.documents.add(document)

proc unregisterDocument*(self: DocumentEditorService, document: Document) =
  self.documents.del(document.id)

proc registerEditor*(self: DocumentEditorService, editor: DocumentEditor): void =
  editor.id = self.allEditors.add(editor)
  self.editors[editor.id] = editor
  self.onEditorRegistered.invoke editor

proc unregisterEditor*(self: DocumentEditorService, editor: DocumentEditor): void =
  self.allEditors.del(editor.id)

  self.editors.del(editor.id)
  self.onEditorDeregistered.invoke editor

proc getAllDocuments*(self: DocumentEditorService): seq[Document] =
  for it in self.editors.values:
    result.incl it.getDocument

proc getDocument*(self: DocumentEditorService, path: string, usage = ""): Option[Document] =
  for document in self.documents:
    if document.filename != "" and document.filename == path and document.usage == usage:
      return document.some

  return Document.none

proc getDocument*(self: DocumentEditorService, id: DocumentId): Option[Document] =
  return self.documents.tryGet(id)

proc getEditor*(self: DocumentEditorService, id: EditorIdNew): Option[DocumentEditor] =
  return self.allEditors.tryGet(id)

proc getEditorsForDocument*(self: DocumentEditorService, document: Document): seq[DocumentEditor] =
  for editor in self.allEditors:
    if editor.getDocument() == document:
      result.add editor

proc getEditorForId*(self: DocumentEditorService, id: EditorIdNew): Option[DocumentEditor] =
  self.editors.withValue(id, editor):
    return editor[].some

  return DocumentEditor.none

proc openDocument*(self: DocumentEditorService, path: string, load = true): Option[Document] =
  try:
    log lvlInfo, &"Open new document '{path}'"

    var document: Document = nil
    for factory in self.documentFactories:
      if factory.canOpenFile(path):
        document = factory.createDocument(self.services, path, load)
        break

    if document == nil:
      log lvlError, &"Failed to create document for '{path}'"
      return Document.none
    return document.some

  except CatchableError:
    log(lvlError, fmt"[openDocument] Failed to load file '{path}': {getCurrentExceptionMsg()}")
    return Document.none

proc getOrOpenDocument*(self: DocumentEditorService, path: string, load = true): Option[Document] =
  result = self.getDocument(path)
  if result.isSome:
    return

  return self.openDocument(path, load)

proc getPlatform*(self: DocumentEditorService): Platform =
  if self.platform == nil:
    if self.services.getService(PlatformService).getSome(platformService):
      self.platform = platformService.platform

  return self.platform

proc createEditorForDocument*(self: DocumentEditorService, document: Document): Option[DocumentEditor] =
  for factory in self.editorFactories:
    if factory.canEditDocument(document):
      result = factory.createEditor(self.services, document).some
      break

  if result.isNone:
    log lvlError, &"Failed to create editor for document '{document.filename}'"
    return

  discard result.get.onMarkedDirty.subscribe proc() =
    let platform = self.getPlatform()
    if platform.isNotNil:
      platform.requestRender()

proc tryCloseDocument*(self: DocumentEditorService, document: Document) =
  # log lvlInfo, fmt"tryCloseDocument: '{document.filename}'"

  if document in self.pinnedDocuments:
    # log lvlInfo, &"Document '{document.filename}' is pinned, don't close"
    return

  var hasAnotherEditor = false
  for id, editor in self.editors.pairs:
    if editor.getDocument() == document:
      hasAnotherEditor = true
      break

  if not hasAnotherEditor:
    document.deinit()

proc closeEditor*(self: DocumentEditorService, editor: DocumentEditor) =
  let document = editor.getDocument()
  log lvlInfo, fmt"closeEditor: '{editor.getDocument().filename}'"

  if editor.id in self.pinnedEditors:
    log lvlWarn, &"Can't close editor {editor.id} for '{editor.getDocument().filename}' because it's pinned"
    return

  editor.deinit()

  self.tryCloseDocument(document)

###########################################################################

proc getDocumentEditorService(): Option[DocumentEditorService] =
  {.gcsafe.}:
    if gServices.isNil: return DocumentEditorService.none
    return gServices.getService(DocumentEditorService)

static:
  addInjector(DocumentEditorService, getDocumentEditorService)

proc getAllEditors*(self: DocumentEditorService): seq[EditorId] {.expose("editors").} =
  for id in self.editors.keys:
    result.add id.EditorId

proc getExistingEditor*(self: DocumentEditorService, path: string): Option[EditorId] {.expose("editors").} =
  ## Returns an existing editor for the given file if one exists,
  ## or none otherwise.
  defer:
    log lvlInfo, &"getExistingEditor {path} -> {result}"

  if path.len == 0:
    return EditorId.none

  for id, editor in self.editors.pairs:
    if editor.getDocument() == nil:
      continue
    if editor.getDocument().filename != path:
      continue
    return id.EditorId.some

  return EditorId.none

addGlobalDispatchTable "editors", genDispatchTable("editors")
