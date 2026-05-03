import std/[tables, options, sets, hashes, json]
import bumpy
import misc/[event, custom_logger, id, custom_async, util, generational_seq, jsonex]
import ui/node
import events
import component

export component

include dynlib_export

import platform/[platform]
import document, service, config_provider

from scripting_api import EditorId

{.push gcsafe.}
{.push raises: [].}

logCategory "document-editor"

type
  EditorIdNew* = distinct uint64
  DocumentEditor* = ref object of ComponentOwner
    id*: EditorIdNew
    userId*: Id
    currentDocument*: Document
    renderHeader*: bool
    fillAvailableSpace*: bool
    lastContentBounds*: Rect
    onMarkedDirty*: Event[void]
    mDirty: bool ## Set to true to trigger rerender
    active: bool
    usage*: string # Unique string identifying what the editor is used for,
                   # e.g. command-line/preview/search-bar
    namespace*: string
    onActiveChanged*: Event[DocumentEditor]
    onDocumentChanged*: Event[tuple[old: Document]]
    config*: ConfigStore

    renderImpl*: proc(self: DocumentEditor, builder: UINodeBuilder): seq[proc() {.closure, gcsafe, raises: [].}] {.gcsafe, raises: [].}
    getStateImpl*: proc(self: DocumentEditor): JsonNode {.gcsafe, raises: [].}
    restoreStateImpl*: proc(self: DocumentEditor, state: JsonNode) {.gcsafe, raises: [].}
    deinitImpl*: proc(self: DocumentEditor) {.gcsafe, raises: [].}
    handleActionImpl*: proc(self: DocumentEditor, action: string, arg: string, record: bool): Option[JsonNode] {.gcsafe, raises: [].}
    setDocumentImpl*: proc(self: DocumentEditor, document: Document) {.gcsafe, raises: [].}
    getEventHandlersImpl*: proc(self: DocumentEditor, inject: Table[string, EventHandler]): seq[EventHandler] {.gcsafe, raises: [].}
    handleActivateImpl*: proc(self: DocumentEditor) {.gcsafe, raises: [].}
    handleDeactivateImpl*: proc(self: DocumentEditor) {.gcsafe, raises: [].}
    getMemoryStatsImpl*: proc(self: DocumentEditor): JsonNode {.gcsafe, raises: [].}

  DocumentFactory* = ref object of RootObj
    priority*: int = 0
    kind*: string
    canOpenFileImpl*: proc(self: DocumentFactory, path: string): bool {.gcsafe, raises: [].}
    createDocumentImpl*: proc(self: DocumentFactory, services: Services, path: string, load: bool, options: JsonNodeEx = nil, id = Id.none): Document {.gcsafe, raises: [].}

  DocumentEditorFactory* = ref object of RootObj
    priority*: int = 0
    canEditDocumentImpl*: proc(self: DocumentEditorFactory, document: Document, options: JsonNodeEx = nil): bool {.gcsafe, raises: [].}
    createEditorImpl*: proc(self: DocumentEditorFactory, services: Services, document: Document, options: JsonNodeEx = nil): DocumentEditor {.gcsafe, raises: [].}

  DocumentEditorService* = ref object of Service
    platform: Platform
    # editors*: Table[EditorIdNew, DocumentEditor]
    pinnedEditors*: HashSet[EditorIdNew]
    pinnedDocuments*: seq[Document]
    onEditorRegistered*: Event[DocumentEditor]
    onEditorDeregistered*: Event[DocumentEditor]

    documents*: GenerationalSeq[Document, DocumentId]
    allEditors*: GenerationalSeq[DocumentEditor, EditorIdNew]

    documentFactories: seq[DocumentFactory]
    editorFactories: seq[DocumentEditorFactory]

    commandLineEditor*: DocumentEditor # todo: remove this

proc `==`*(a, b: EditorIdNew): bool {.borrow.}
proc hash*(vr: EditorIdNew): Hash {.borrow.}
proc `$`*(vr: EditorIdNew): string {.borrow.}

func serviceName*(_: typedesc[DocumentEditorService]): string = "DocumentEditorService"

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

proc render*(self: DocumentEditor, builder: UINodeBuilder): seq[proc() {.closure, gcsafe, raises: [].}] {.gcsafe, raises: [].} =
  if self.renderImpl != nil:
    return self.renderImpl(self, builder)
  return @[]

proc getEventHandlers*(self: DocumentEditor, inject: Table[string, EventHandler]): seq[EventHandler] {.inline.} =
  if self.getEventHandlersImpl != nil:
    return self.getEventHandlersImpl(self, inject)
  return newSeq[EventHandler]()

proc handleActivate*(self: DocumentEditor) =
  if self.handleActivateImpl != nil:
    self.handleActivateImpl(self)

proc handleDeactivate*(self: DocumentEditor) =
  if self.handleDeactivateImpl != nil:
    self.handleDeactivateImpl(self)

proc getMemoryStats*(self: DocumentEditor): JsonNode =
  if self.getMemoryStatsImpl != nil:
    return self.getMemoryStatsImpl(self)
  return newJObject()

func active*(self: DocumentEditor): bool = self.active

{.push apprtl.}
proc getEditorDocument*(self: DocumentEditor): Document
proc getDocument*(self: DocumentEditorService, id: DocumentId): Option[Document]
proc getEditor*(self: DocumentEditorService, id: EditorIdNew): Option[DocumentEditor]
proc getDocumentByPath*(self: DocumentEditorService, path: string, usage = ""): Option[Document]
proc getEditorsForDocument*(self: DocumentEditorService, document: Document): seq[DocumentEditor]
proc documentEditorCreateEditorForDocument(self: DocumentEditorService, document: Document, options: JsonNodeEx = nil): Option[DocumentEditor]
proc documentEditorCreateDocument*(self: DocumentEditorService, kind: string, path: string, load: bool, options: JsonNodeEx, id = Id.none): Document
proc documentEditorSetActive(self: DocumentEditor, newActive: bool)
proc documentEditorGetOrOpenDocument(self: DocumentEditorService, path: string, load: bool = true, id = Id.none): Option[Document] {.gcsafe, raises: [].}
proc documentEditorAddDocumentFactory(self: DocumentEditorService, factory: DocumentFactory)
proc documentEditorAddDocumentEditorFactory(self: DocumentEditorService, factory: DocumentEditorFactory)
proc documentEditorGetExistingEditor(self: DocumentEditorService, path: string): Option[EditorId]
proc documentEditorGetAllEditors(self: DocumentEditorService): seq[EditorId]
proc documentEditorOpenDocument(self: DocumentEditorService, path: string, load = true, id = Id.none): Option[Document]
proc documentEditorCloseEditor(self: DocumentEditorService, editor: DocumentEditor)
proc documentEditorTryCloseDocument(self: DocumentEditorService, document: Document)
proc documentEditorRegisterDocument(self: DocumentEditorService, document: Document)
proc documentEditorUnregisterDocument(self: DocumentEditorService, document: Document)
proc documentEditorRegisterEditor(self: DocumentEditorService, editor: DocumentEditor)
proc documentEditorUnregisterEditor(self: DocumentEditorService, editor: DocumentEditor)
{.pop.}


# Nice wrappers
{.push inline.}
proc createDocument*(self: DocumentEditorService, kind: string, path: string, load: bool, options: JsonNodeEx = nil, id = Id.none): Document = documentEditorCreateDocument(self, kind, path, load, options, id)
proc getOrOpenDocument*(self: DocumentEditorService, path: string, load = true, id = Id.none): Option[Document] = documentEditorGetOrOpenDocument(self, path, load, id)
proc addDocumentFactory*(self: DocumentEditorService, factory: DocumentFactory) = documentEditorAddDocumentFactory(self, factory)
proc addDocumentEditorFactory*(self: DocumentEditorService, factory: DocumentEditorFactory) = documentEditorAddDocumentEditorFactory(self, factory)
proc getExistingEditor*(self: DocumentEditorService, path: string): Option[EditorId] = documentEditorGetExistingEditor(self, path)
proc getAllEditors*(self: DocumentEditorService): seq[EditorId] = documentEditorGetAllEditors(self)
proc openDocument*(self: DocumentEditorService, path: string, load = true, id = Id.none): Option[Document] = documentEditorOpenDocument(self, path, load, id)
proc closeEditor*(self: DocumentEditorService, editor: DocumentEditor) = documentEditorCloseEditor(self, editor)
proc tryCloseDocument*(self: DocumentEditorService, document: Document) = documentEditorTryCloseDocument(self, document)
proc createEditorForDocument*(self: DocumentEditorService, document: Document, options: JsonNodeEx = nil): Option[DocumentEditor] = documentEditorCreateEditorForDocument(self, document, options)
proc registerDocument*(self: DocumentEditorService, document: Document) = documentEditorRegisterDocument(self, document)
proc unregisterDocument*(self: DocumentEditorService, document: Document) = documentEditorUnregisterDocument(self, document)
proc registerEditor*(self: DocumentEditorService, editor: DocumentEditor) = documentEditorRegisterEditor(self, editor)
proc unregisterEditor*(self: DocumentEditorService, editor: DocumentEditor) = documentEditorUnregisterEditor(self, editor)

proc `active=`*(self: DocumentEditor, newActive: bool) = documentEditorSetActive(self, newActive)
{.pop.}

proc setDocument*(self: DocumentEditor, document: Document) =
  if self.setDocumentImpl != nil:
    self.setDocumentImpl(self, document)

proc getStateJson*(self: DocumentEditor): JsonNode {.gcsafe, raises: [].} =
  if self.getStateImpl != nil:
    return self.getStateImpl(self)
  return newJObject()

proc restoreStateJson*(self: DocumentEditor, state: JsonNode) {.gcsafe, raises: [].} =
  if self.restoreStateImpl != nil:
    self.restoreStateImpl(self, state)

proc deinit*(self: DocumentEditor) {.gcsafe, raises: [].} =
  if self.deinitImpl != nil:
    self.deinitImpl(self)

proc handleAction*(self: DocumentEditor, action: string, arg: string, record: bool): Option[JsonNode] =
  if self.handleActionImpl != nil:
    return self.handleActionImpl(self, action, arg, record)
  return JsonNode.none

proc anyUnsavedChanges*(self: DocumentEditorService): bool =
  for editor in self.allEditors:
    let doc = editor.currentDocument
    assert doc != nil
    let isDirty = doc.isBackedByFile and not doc.requiresLoad and doc.lastSavedRevision != doc.revision
    if isDirty:
      return true
  return false

when implModule:
  import std/[json, algorithm]
  import misc/[array_set]
  import vmath
  import input, platform_service, dispatch_tables

  addBuiltinService(DocumentEditorService)

  declareSettings EditorSettings, "editor":
    ## Any editor with this set to true will be stored in the session and restored on startup.
    declare saveInSession, bool, true

  method createUI*(self: DocumentEditor, builder: UINodeBuilder): seq[OverlayFunction] {.base.} =
    discard

  method init*(self: DocumentEditorService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    log lvlInfo, &"DocumentEditorService.init"
    self.pinnedEditors = initHashSet[EditorIdNew]()
    return ok()

  proc canOpenFile*(self: DocumentFactory, path: string): bool =
    if self.canOpenFileImpl != nil:
      return self.canOpenFileImpl(self, path)
    else:
      return false

  proc createDocument*(self: DocumentFactory, services: Services, path: string, load: bool, options: JsonNodeEx = nil, id = Id.none): Document =
    if self.createDocumentImpl != nil:
      return self.createDocumentImpl(self, services, path, load, options, id)
    else:
      return nil

  proc canEditDocument*(self: DocumentEditorFactory, document: Document, options: JsonNodeEx = nil): bool {.gcsafe, raises: [].} =
    if self.canEditDocumentImpl != nil:
      return self.canEditDocumentImpl(self, document, options)
    else:
      return false
  proc createEditor*(self: DocumentEditorFactory, services: Services, document: Document, options: JsonNodeEx = nil): DocumentEditor {.gcsafe, raises: [].} =
    if self.createEditorImpl != nil:
      return self.createEditorImpl(self, services, document, options)
    else:
      return nil

  method canEdit*(self: DocumentEditor, document: Document): bool {.base, gcsafe, raises: [].} =
    return false

  proc getDocument*(self: DocumentEditor): Document {.gcsafe, raises: [].} = self.currentDocument

  method handleDocumentChanged*(self: DocumentEditor) {.base, gcsafe, raises: [].} =
    discard

  method handleScroll*(self: DocumentEditor, scroll: Vec2, mousePosWindow: Vec2) {.base, gcsafe, raises: [].} =
    discard

  method handleMousePress*(self: DocumentEditor, button: MouseButton, mousePosWindow: Vec2, modifiers: Modifiers) {.base, gcsafe, raises: [].} =
    discard

  method handleMouseRelease*(self: DocumentEditor, button: MouseButton, mousePosWindow: Vec2) {.base, gcsafe, raises: [].} =
    discard

  method handleMouseMove*(self: DocumentEditor, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) {.base, gcsafe, raises: [].} =
    discard

  method getStatisticsString*(self: DocumentEditor): string {.base, gcsafe, raises: [].} = discard

  proc documentEditorSetActive(self: DocumentEditor, newActive: bool) =
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

  proc getEditorDocument*(self: DocumentEditor): Document = self.getDocument()

  proc documentEditorCreateDocument*(self: DocumentEditorService, kind: string, path: string, load: bool, options: JsonNodeEx, id = Id.none): Document =
    for factory in self.documentFactories:
      if factory.kind == kind and factory.canOpenFile(path):
        return factory.createDocument(self.services, path, load, options, id)
    log lvlError, &"No document factory found for '{kind}'"
    return nil

  proc documentEditorAddDocumentFactory(self: DocumentEditorService, factory: DocumentFactory) =
    self.documentFactories.add(factory)
    self.documentFactories.sort(proc(a, b: DocumentFactory): int = cmp(a.priority, b.priority), Descending)

  proc documentEditorAddDocumentEditorFactory(self: DocumentEditorService, factory: DocumentEditorFactory) =
    self.editorFactories.add(factory)
    self.editorFactories.sort(proc(a, b: DocumentEditorFactory): int = cmp(a.priority, b.priority), Descending)

  proc documentEditorRegisterDocument(self: DocumentEditorService, document: Document) =
    document.id = self.documents.add(document)

  proc documentEditorUnregisterDocument(self: DocumentEditorService, document: Document) =
    self.documents.del(document.id)

  proc documentEditorRegisterEditor(self: DocumentEditorService, editor: DocumentEditor) =
    editor.id = self.allEditors.add(editor)
    self.onEditorRegistered.invoke editor

  proc documentEditorUnregisterEditor(self: DocumentEditorService, editor: DocumentEditor) =
    self.allEditors.del(editor.id)
    self.onEditorDeregistered.invoke editor

  proc getAllDocuments*(self: DocumentEditorService): seq[Document] =
    for it in self.allEditors:
      result.incl it.getDocument

  proc getDocument*(self: DocumentEditorService, path: string, usage = "", id = Id.none): Option[Document] =
    for document in self.documents:
      if document.filename != "" and document.filename == path and document.usage == usage and (id.isNone or id.get == document.uniqueId):
        return document.some

    return Document.none

  proc getDocumentByPath*(self: DocumentEditorService, path: string, usage = ""): Option[Document] =
    return self.getDocument(path, usage)

  proc getDocument*(self: DocumentEditorService, id: DocumentId): Option[Document] =
    return self.documents.tryGet(id)

  proc getEditor*(self: DocumentEditorService, id: EditorIdNew): Option[DocumentEditor] =
    return self.allEditors.tryGet(id)

  proc getEditorsForDocument*(self: DocumentEditorService, document: Document): seq[DocumentEditor] =
    for editor in self.allEditors:
      if editor.getDocument() == document:
        result.add editor

  proc getEditors*(self: DocumentEditorService, path: string): seq[DocumentEditor] =
    for editor in self.allEditors:
      if editor.getDocument() != nil and editor.getDocument().filename == path:
        result.add editor

  proc documentEditorOpenDocument(self: DocumentEditorService, path: string, load = true, id = Id.none): Option[Document] =
    try:
      log lvlInfo, &"Open new document '{path}'"

      var document: Document = nil
      for factory in self.documentFactories:
        if factory.canOpenFile(path):
          document = factory.createDocument(self.services, path, load, nil, id)
          break

      if document == nil:
        log lvlError, &"Failed to create document for '{path}'"
        return Document.none
      return document.some

    except CatchableError:
      log(lvlError, fmt"[openDocument] Failed to load file '{path}': {getCurrentExceptionMsg()}")
      return Document.none

  proc documentEditorGetOrOpenDocument(self: DocumentEditorService, path: string, load = true, id = Id.none): Option[Document] =
    result = self.getDocument(path, id = id)
    if result.isSome:
      return

    return self.openDocument(path, load, id)

  proc getPlatform*(self: DocumentEditorService): Platform =
    if self.platform == nil:
      if self.services.getService(PlatformService).getSome(platformService):
        self.platform = platformService.platform

    return self.platform

  proc documentEditorCreateEditorForDocument(self: DocumentEditorService, document: Document, options: JsonNodeEx = nil): Option[DocumentEditor] =
    assert document != nil
    for factory in self.editorFactories:
      if factory.canEditDocument(document, options):
        result = factory.createEditor(self.services, document, options).some
        break

    if result.isNone:
      log lvlError, &"Failed to create editor for document '{document.filename}'"
      return

    discard result.get.onMarkedDirty.subscribe proc() =
      let platform = self.getPlatform()
      if platform.isNotNil:
        platform.requestRender()

  proc documentEditorTryCloseDocument(self: DocumentEditorService, document: Document) =
    # log lvlInfo, fmt"tryCloseDocument: '{document.filename}'"

    if document in self.pinnedDocuments:
      # log lvlInfo, &"Document '{document.filename}' is pinned, don't close"
      return

    var hasAnotherEditor = false
    for id, editor in self.allEditors.pairs:
      if editor.getDocument() == document:
        hasAnotherEditor = true
        break

    if not hasAnotherEditor:
      document.deinit()

  proc documentEditorCloseEditor(self: DocumentEditorService, editor: DocumentEditor) =
    let document = editor.getDocument()
    log lvlInfo, fmt"closeEditor: '{editor.getDocument().filename}'"

    if editor.id in self.pinnedEditors:
      log lvlWarn, &"Can't close editor {editor.id} for '{editor.getDocument().filename}' because it's pinned"
      return

    editor.deinit()

    self.tryCloseDocument(document)

  proc documentEditorGetAllEditors(self: DocumentEditorService): seq[EditorId] =
    for id in self.allEditors.keys:
      result.add id.EditorId

  proc documentEditorGetExistingEditor(self: DocumentEditorService, path: string): Option[EditorId] =
    ## Returns an existing editor for the given file if one exists,
    ## or none otherwise.
    defer:
      log lvlInfo, &"getExistingEditor {path} -> {result}"

    if path.len == 0:
      return EditorId.none

    for id, editor in self.allEditors.pairs:
      if editor.getDocument() == nil:
        continue
      if editor.getDocument().filename != path:
        continue
      return id.EditorId.some

    return EditorId.none
