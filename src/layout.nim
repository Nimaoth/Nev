import std/[tables, options, json, sugar, sequtils, deques]
import bumpy
import results
import platform/platform
import misc/[custom_async, custom_logger, rect_utils, myjsonutils, util, jsonex, array_set]
import scripting/expose
import workspaces/workspace
import service, platform_service, dispatch_tables, document, document_editor, view, events, config_provider, popup, selector_popup_builder, vfs, vfs_service, session, layouts
from scripting_api import EditorId

export layouts

{.push gcsafe.}
{.push raises: [].}

logCategory "layout"

type
  LayoutProperties* = ref object
    props: Table[string, float32]

  EditorView* = ref object of View
    path: string
    document*: Document # todo: remove
    editor*: DocumentEditor

  PushSelectorPopupImpl = proc(self: LayoutService, builder: SelectorPopupBuilder): ISelectorPopup {.gcsafe, raises: [].}

  CreateView* = proc(config: JsonNode): View {.gcsafe, raises: [ValueError].}

  LayoutService* = ref object of Service
    platform: Platform
    workspace: Workspace
    config: ConfigService
    uiSettings: UiSettings
    editors: DocumentEditorService
    session: SessionService
    vfs: VFS
    popups*: seq[Popup]
    layout*: Layout
    layouts*: Table[string, Layout]
    layoutProps*: LayoutProperties
    maximizeView*: bool
    focusHistory*: Deque[Id]
    viewHistory*: Deque[Id]

    onEditorRegistered*: Event[DocumentEditor]
    onEditorDeregistered*: Event[DocumentEditor]

    pinnedDocuments*: seq[Document]

    pushSelectorPopupImpl: PushSelectorPopupImpl
    activeView*: View
    allViews*: seq[View]

    viewFactories: Table[string, CreateView]

var gPushSelectorPopupImpl*: PushSelectorPopupImpl

proc getView*(self: LayoutService, id: Id): Option[View]

proc addViewFactory*(self: LayoutService, name: string, create: CreateView, override: bool = false) =
  if not override and name in self.viewFactories:
    log lvlError, &"Trying to define duplicate view factory '{name}'"
    return
  self.viewFactories[name] = create

proc getExistingView(self: LayoutService, config: JsonNode): View {.raises: [ValueError].} =
  if config.kind == JNull:
    return nil

  if config.hasKey("id"):
    if self.getView(config["id"].jsonTo(Id)).getSome(view):
      return view
  log lvlError, &"Missing or invalid id for {config}"
  return nil

method createViews(self: Layout, config: JsonNode, layouts: LayoutService) {.base, raises: [ValueError].} =
  if config.kind == JNull:
    return

  checkJson config.kind == JObject, "Expected object"

  # debugf"{self.desc}.createViews: {config}"
  if config.hasKey("children"):
    let children = config["children"]
    checkJson children.kind == JArray, "'children' must be an array"
    for i, c in children.elems:
      if i < self.children.len:
        if self.children[i] != nil and self.children[i] of Layout:
          self.children[i].Layout.createViews(c, layouts)
        elif self.childTemplate != nil:
          let newChild = self.childTemplate.copy()
          self.children.add(newChild)
          self.activeIndex = self.activeIndex.clamp(0, self.children.high)
          newChild.createViews(c, layouts)
        else:
          self.children[i] = layouts.getExistingView(c)
          self.activeIndex = self.activeIndex.clamp(0, self.children.high)
      elif self.childTemplate != nil:
        let newChild = self.childTemplate.copy()
        self.children.add(newChild)
        self.activeIndex = self.activeIndex.clamp(0, self.children.high)
        newChild.createViews(c, layouts)
      else:
        self.children.add(layouts.getExistingView(c))
        self.activeIndex = self.activeIndex.clamp(0, self.children.high)
  if config.hasKey("activeIndex"):
    let activeIndex = config["activeIndex"]
    checkJson activeIndex.kind == JInt, "'activeIndex' must be an integer"
    self.activeIndex = activeIndex.getInt.clamp(0, self.children.high)

method createViews(self: MainLayout, config: JsonNode, layouts: LayoutService) {.raises: [ValueError].} =
  if config.kind == JNull:
    return

  checkJson config.kind == JObject, "Expected object"

  # debugf"MainLayout.createViews: {config}"
  if config.hasKey("children"):
    let children = config["children"]
    checkJson children.kind == JArray, "'children' must be an array"
    for i, c in children.elems:
      if c.kind == JNull:
        continue

      if i < self.children.len:
        if self.children[i] != nil and self.children[i] of Layout:
          self.children[i].Layout.createViews(c, layouts)
        elif self.childTemplates[i] != nil:
          let newChild = self.childTemplates[i].copy()
          self.children[i] = newChild
          self.activeIndex = i
          newChild.createViews(c, layouts)
        else:
          self.children[i] = layouts.getExistingView(c)
          self.activeIndex = i
      else:
        log lvlError, &"Too many children for main layout (max 5): {children.len}"
  if config.hasKey("activeIndex"):
    let activeIndex = config["activeIndex"]
    checkJson activeIndex.kind == JInt, "'activeIndex' must be an integer"
    let i = activeIndex.getInt.clamp(0, self.children.high)
    if self.children[i] != nil:
      self.activeIndex = i

proc updateLayoutTree(self: LayoutService) =
  try:
    # let config = self.uiSettings.layout.get()
    let config = self.config.runtime.get("ui.layout", newJexObject())
    # debugf"updateLayoutTree\n{config.pretty}"

    for key, value in config.fields.pairs:
      let view = createLayout(value.toJson)
      if view of Layout:
        self.layouts[key] = view.Layout
      else:
        self.layouts[key] = AlternatingLayout(children: @[view])

    if "default" in self.layouts:
      self.layout = self.layouts["default"]

    if self.layout == nil:
      self.layout = AlternatingLayout(children: @[])
  except Exception as e:
    log lvlError, &"Failed to create layout from config: {e.msg}"

func serviceName*(_: typedesc[LayoutService]): string = "LayoutService"

addBuiltinService(LayoutService, PlatformService, ConfigService, DocumentEditorService, Workspace, VFSService, SessionService)

method init*(self: LayoutService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"LayoutService.init"
  self.platform = self.services.getService(PlatformService).get.platform
  assert self.platform != nil
  self.config = self.services.getService(ConfigService).get
  self.editors = self.services.getService(DocumentEditorService).get
  self.vfs = self.services.getService(VFSService).get.vfs
  self.layout = HorizontalLayout()
  self.layout_props = LayoutProperties(props: {"main-split": 0.5.float32}.toTable)
  self.pushSelectorPopupImpl = ({.gcsafe.}: gPushSelectorPopupImpl)
  self.workspace = self.services.getService(Workspace).get
  self.session = self.services.getService(SessionService).get
  self.uiSettings = UiSettings.new(self.config.runtime)

  self.addViewFactory "editor", proc(config: JsonNode): View {.raises: [ValueError].} =
    type Config = object
      id: Id
      path: string
      state: JsonNode
    let config = config.jsonTo(Config, Joptions(allowExtraKeys: true, allowMissingKeys: true))

    let document = self.editors.getOrOpenDocument(config.path).getOr:
      log(lvlError, fmt"Failed to restore file '{config.path}' from session")
      return nil

    assert document != nil
    let editor = self.editors.createEditorForDocument(document).getOr:
      log(lvlError, fmt"Failed to create editor for '{config.path}'")
      return nil

    if config.state != nil:
      editor.restoreStateJson(config.state)

    return EditorView(mId: config.id, document: document, editor: editor)

  proc save(): JsonNode =
    result = newJObject()
    let layouts = newJObject()
    for key, layout in self.layouts:
      let saved = layout.saveLayout()
      if saved != nil:
        layouts[key] = saved
    result["layouts"] = layouts

    var all = newJArray()
    for view in self.allViews:
      let state = view.saveState()
      if state != nil:
        all.add state
    result["views"] = all

  proc load(data: JsonNode) =
    try:
      self.updateLayoutTree()

      if data.hasKey("views"):
        let views = data["views"]
        checkJson views.kind == JArray, &"Expected array, got {views}"
        for state in views.elems:
          if not state.hasKey("kind"):
            log lvlError, &"Failed to restore view from session state: missing field kind"
            continue

          let kindJson = state["kind"]
          if kindJson.kind != JString:
            log lvlError, &"Failed to restore view from session state: invalid field kind, expected string, got {kindJson}"
            continue

          let kind = kindJson.getStr
          if kind in self.viewFactories:
            self.allViews.add self.viewFactories[kind](state)

          else:
            log lvlError, &"Invalid kind for view: '{kind}'"

      if data.hasKey("layouts"):
        let layouts = data["layouts"]
        checkJson layouts.kind == JObject, &"Expected object, got {layouts}"
        for key, state in layouts.fields.pairs:
          if key in self.layouts:
            self.layouts[key].createViews(state, self)

    except Exception as e:
      log lvlError, &"Failed to create layout from session data: {e.msg}\n{data.pretty}"

  self.session.addSaveHandler "layout", save, load

  discard self.config.runtime.onConfigChanged.subscribe proc(key: string) =
    if key == "" or key.startsWith("ui.layout"):
      let state = self.layout.saveLayout()

      self.updateLayoutTree()
      if state != nil:
        try:
          self.layout.createViews(state, self)
        except Exception as e:
          log lvlError, &"Failed to create layout from session data: {e.msg}\n{state.pretty}"

  self.updateLayoutTree()

  return ok()

proc preRender*(self: LayoutService) =
  discard

method desc*(self: EditorView): string =
  if self.document == nil:
    &"EditorView(pending '{self.path}')"
  else:
    &"EditorView('{self.document.filename}')"

method kind*(self: EditorView): string = "editor"

method display*(self: EditorView): string = self.document.filename

method saveLayout*(self: EditorView): JsonNode =
  result = newJObject()
  result["id"] = self.id.toJson

method saveState*(self: EditorView): JsonNode =
  result = newJObject()
  result["kind"] = self.kind.toJson
  result["id"] = self.id.toJson
  result["path"] = self.document.filename.toJson
  result["state"] = self.editor.getStateJson()

method activate*(view: EditorView) =
  view.active = true
  view.editor.active = true

method deactivate*(view: EditorView) =
  view.active = true
  view.editor.active = false

method markDirty*(view: EditorView, notify: bool = true) =
  view.markDirtyBase()
  view.editor.markDirty(notify)

method getEventHandlers*(view: EditorView, inject: Table[string, EventHandler]): seq[EventHandler] =
  view.editor.getEventHandlers(inject)

method getActiveEditor*(self: EditorView): Option[DocumentEditor] =
  self.editor.some

proc tryGetCurrentView*(self: LayoutService): Option[View] =
  let view = self.layout.activeLeafView()
  if view != nil:
    view.some
  else:
    View.none

proc tryGetCurrentEditorView*(self: LayoutService): Option[EditorView] =
  if self.tryGetCurrentView().getSome(view) and view of EditorView:
    view.EditorView.some
  else:
    EditorView.none

proc getPopupForId*(self: LayoutService, id: EditorId): Option[Popup] =
  for popup in self.popups:
    if popup.id == id:
      return popup.some

  return Popup.none

proc getActiveViewEditor*(self: LayoutService): Option[DocumentEditor] =
  if self.tryGetCurrentEditorView().getSome(view):
    return view.editor.some

  return DocumentEditor.none

proc getView*(self: LayoutService, id: Id): Option[View] =
  ## Returns the index of the view for the given editor.
  for i, view in self.allViews:
    if view.id == id:
      return view.some

  return View.none

proc getViewForEditor*(self: LayoutService, editor: DocumentEditor): Option[EditorView] =
  ## Returns the index of the view for the given editor.
  for i, view in self.allViews:
    if view of EditorView and view.EditorView.editor == editor:
      return view.EditorView.some

  return EditorView.none

proc recordFocusHistoryEntry(self: LayoutService, view: View) =
  if view == nil or view.id == idNone():
    return
  if self.focusHistory.len == 0 or self.focusHistory.peekLast() != view.id:
    self.focusHistory.addLast(view.id)

  # todo: make max size configurable
  while self.focusHistory.len > 1000:
    self.focusHistory.popFirst()

proc addView*(self: LayoutService, view: View, slot: string = "", focus: bool = true, addToHistory: bool = true) =
  # debugf"addView {view.desc()} slot = '{slot}', focus = {focus}, addToHistory = {addToHistory}"
  let maxViews = self.uiSettings.maxViews.get()

  self.allViews.incl view
  let slot = if slot == "":
    self.layout.defaultSlot
  else:
    slot

  let prevActiveView = self.layout.activeLeafView()
  if focus and addToHistory:
    self.recordFocusHistoryEntry(prevActiveView)

  discard self.layout.removeView(view)
  let ejectedView = self.layout.addView(view, slot, focus)

  if ejectedView != nil and ejectedView.id != idNone():
    self.viewHistory.addLast(ejectedView.id)

  # Force immediate load for new file since we're making it visible anyways
  if view of EditorView and view.EditorView.document.requiresLoad:
    view.EditorView.document.load()

  view.markDirty()
  self.platform.requestRender()

proc createView*(self: LayoutService, document: Document): View =
  if self.editors.createEditorForDocument(document).getSome(editor):
    return EditorView(document: document, editor: editor)
  return nil

# todo: change return type to Option[View]
proc createView*(self: LayoutService, filename: string): View =
  let document = self.editors.getOrOpenDocument(filename).getOr:
    log(lvlError, fmt"Failed to restore file {filename} from previous session")
    return nil

  return self.createView(document)

proc createAndAddView*(self: LayoutService, document: Document, slot: string = ""): Option[DocumentEditor] =
  # debugf"createAndAddView '{document.filename}'"
  if self.editors.createEditorForDocument(document).getSome(editor):
    var view = EditorView(document: document, editor: editor)
    self.addView(view, slot=slot)
    return editor.some
  return DocumentEditor.none

proc tryActivateView*(self: LayoutService, view: View) =
  if self.popups.len > 0:
    return
  let prevActiveView = self.layout.activeLeafView()
  let activated = self.layout.tryActivateView proc(v: View): bool =
    return view == v
  if activated:
    self.recordFocusHistoryEntry(prevActiveView)

  self.platform.requestRender()

proc tryActivateEditor*(self: LayoutService, editor: DocumentEditor) =
  if self.popups.len > 0:
    return
  if self.getViewForEditor(editor).getSome(view):
    self.tryActivateView(view)

proc pushPopup*(self: LayoutService, popup: Popup) =
  popup.init()
  self.popups.add(popup)
  discard popup.onMarkedDirty.subscribe () => self.platform.requestRender()
  self.platform.requestRender()

proc popPopup*(self: LayoutService, popup: Popup = nil) =
  if self.popups.len > 0 and (popup == nil or self.popups[self.popups.high] == popup):
    self.popups[self.popups.high].deinit()
    discard self.popups.pop()
  self.platform.requestRender()

proc pushSelectorPopup*(self: LayoutService, builder: SelectorPopupBuilder): ISelectorPopup =
  self.pushSelectorPopupImpl(self, builder)

iterator visibleEditors*(self: LayoutService): DocumentEditor =
  ## Returns a list of all editors which are currently shown
  for view in self.layout.visibleLeafViews():
    if view of EditorView:
      yield view.EditorView.editor

###########################################################################

proc getLayoutService(): Option[LayoutService] =
  {.gcsafe.}:
    if gServices.isNil: return LayoutService.none
    return gServices.getService(LayoutService)

static:
  addInjector(LayoutService, getLayoutService)

proc changeLayoutProp*(self: LayoutService, prop: string, change: float32) {.expose("layout").} =
  self.layout_props.props.mgetOrPut(prop, 0) += change
  self.platform.requestRender(true)

proc toggleMaximizeView*(self: LayoutService) {.expose("layout").} =
  self.maximizeView = not self.maximizeView
  self.platform.requestRender()

proc setMaxViews*(self: LayoutService, slot: string, maxViews: int = int.high) {.expose("layout").} =
  ## Set the maximum number of views that can be open at the same time
  ## Closes any views that exceed the new limit
  # debugf"setMaxViews {maxViews}, slot = '{slot}'"
  let view = self.layout.getView(slot)
  if view != nil and view of Layout:
    let layout = view.Layout
    layout.maxChildren = maxViews

  self.uiSettings.maxViews.set(maxViews)
  self.platform.requestRender()

proc getHiddenViews*(self: LayoutService): seq[View] =
  var res = self.allViews
  self.layout.forEachVisibleView proc(v: View): bool =
    res.removeSwap(v)
  return res

proc getVisibleViews*(self: LayoutService): seq[View] =
  var res = newSeq[View]()
  self.layout.forEachVisibleView proc(v: View): bool =
    res.add(v)
  return res

proc getNumVisibleViews*(self: LayoutService): int {.expose("layout").} =
  ## Returns the amount of visible views
  var res = 0
  self.layout.forEachView proc(v: View): bool =
    if not (v of Layout):
      inc res
  return res

proc getNumHiddenViews*(self: LayoutService): int {.expose("layout").} =
  ## Returns the amount of hidden views
  return self.getHiddenViews().len

proc showView*(self: LayoutService, view: View, slot: string = "", focus: bool = true, addToHistory: bool = true) =
  ## Make the given view visible
  # debugf"showView {view.desc()}, slot = '{slot}', focus = {focus}, addToHistory = {addToHistory}"

  let prevActiveView = self.layout.activeLeafView()
  if focus:
    let activated = self.layout.tryActivateView proc(v: View): bool =
      return view == v

    if activated:
      if addToHistory:
        self.recordFocusHistoryEntry(prevActiveView)
      return

    self.addView(view, slot=slot, focus=true, addToHistory=addToHistory)

  else:
    discard self.layout.removeView(view)
    self.addView(view, slot=slot, focus=false, addToHistory=addToHistory)

  self.platform.requestRender()

proc showView*(self: LayoutService, viewId: Id, slot: string = "", focus: bool = true, addToHistory: bool = true) =
  if self.getView(viewId).getSome(view):
    self.showView(view, slot, focus, addToHistory)

proc showEditor*(self: LayoutService, editorId: EditorId) {.expose("layout").} =
  ## Make the given editor visible
  let editor = self.editors.getEditorForId(editorId).getOr:
    log lvlError, &"No editor with id {editorId} exists"
    return

  assert editor.getDocument().isNotNil

  log lvlInfo, &"showEditor editorId={editorId}, filename={editor.getDocument().filename}"
  if self.getViewForEditor(editor).getSome(view):
    self.showView(view) # todo, slot, focus)

proc getOrOpenEditor*(self: LayoutService, path: string): Option[EditorId] {.expose("layout").} =
  ## Returns an existing editor for the given file if one exists,
  ## otherwise a new editor is created for the file.
  ## The returned editor will not be shown automatically.
  defer:
    log lvlInfo, &"getOrOpenEditor {path} -> {result}"

  if path.len == 0:
    return EditorId.none

  if self.editors.getExistingEditor(path).getSome(id):
    return id.some

  let path = self.workspace.getAbsolutePath(path)
  let document = self.editors.openDocument(path).getOr:
    return EditorId.none

  if self.editors.createEditorForDocument(document).getSome(editor):
    return editor.id.some

  return EditorId.none

proc tryOpenExisting*(self: LayoutService, path: string, appFile: bool = false, slot: string = ""): Option[DocumentEditor] =
  # debugf"tryOpenExisting '{path}'"
  for i, view in self.allViews:
    if view of EditorView and view.EditorView.document.filename == path:
      log(lvlInfo, fmt"Reusing open editor in view {i}")
      self.showView(view, slot = slot)
      return view.EditorView.editor.some

  return DocumentEditor.none

proc tryOpenExisting*(self: LayoutService, editor: EditorId, addToHistory = true, slot: string = ""): Option[DocumentEditor] =
  # debugf"tryOpenExisting '{editor}'"
  for i, view in self.allViews:
    if view of EditorView and view.EditorView.editor.id == editor:
      log(lvlInfo, fmt"Reusing open editor in view {i}")
      self.showView(view, slot = slot)
      return view.EditorView.editor.some

  return DocumentEditor.none

proc openWorkspaceFile*(self: LayoutService, path: string, slot: string = ""): Option[DocumentEditor] =
  defer:
    self.platform.requestRender()

  let path = self.workspace.getAbsolutePath(path)

  log lvlInfo, fmt"[openWorkspaceFile] Open file '{path}' in workspace {self.workspace.name} ({self.workspace.id})"
  if self.tryOpenExisting(path, slot = slot).getSome(editor):
    log lvlInfo, fmt"[openWorkspaceFile] found existing editor"
    return editor.some

  let document = self.editors.getOrOpenDocument(path).getOr:
    log(lvlError, fmt"Failed to load file {path}")
    return DocumentEditor.none

  return self.createAndAddView(document, slot = slot)

proc openFile*(self: LayoutService, path: string, slot: string = ""): Option[DocumentEditor] =
  defer:
    self.platform.requestRender()

  let path = self.vfs.normalize(path)

  log lvlInfo, fmt"[openFile] Open file '{path}'"
  if self.tryOpenExisting(path, false, slot = slot).getSome(ed):
    log lvlInfo, fmt"[openFile] found existing editor"
    return ed.some

  log lvlInfo, fmt"Open file '{path}'"

  let document = self.editors.getOrOpenDocument(path).getOr:
    log(lvlError, fmt"Failed to load file {path}")
    return DocumentEditor.none

  return self.createAndAddView(document, slot = slot)

proc closeView*(self: LayoutService, view: View, keepHidden: bool = false, restoreHidden: bool = true) =
  ## Closes the current view.
  self.platform.requestRender()

  # if keepHidden:
  #   debugf"hideView '{view.desc()}'"
  # else:
  #   debugf"closeView '{view.desc()}'"

  discard self.layout.removeView(view)
  if keepHidden:
    return

  # remove from all other layouts as well
  for l in self.layouts.values:
    if l != self.layout:
      discard l.removeView(view)

  self.allViews.removeSwap(view)
  view.close()
  if view of EditorView:
    self.editors.closeEditor(view.EditorView.editor)

proc tryCloseDocument*(self: LayoutService, document: Document, force: bool): bool =
  if document in self.pinnedDocuments:
    log lvlWarn, &"Can't close document '{document.filename}' because it's pinned"
    return false

  logScope lvlInfo, &"tryCloseDocument: '{document.filename}', force: {force}"

  let editorsToClose = self.editors.getEditorsForDocument(document)
  if editorsToClose.len > 0 and not force:
    log lvlInfo, &"Don't close document because there are still {editorsToClose.len} editors using it"
    return false

  for editor in editorsToClose:
    log lvlInfo, &"Force close editor for '{document.filename}'"
    if self.getViewForEditor(editor).getSome(view):
      self.closeView(view)
    else:
      editor.deinit()

  self.editors.documents.del(document)
  document.deinit()
  return true

proc closeCurrentView*(self: LayoutService, keepHidden: bool = true, restoreHidden: bool = true, closeOpenPopup: bool = true) {.expose("layout").} =
  # debugf"closeCurrentView"
  if closeOpenPopup and self.popups.len > 0:
    self.popPopup()
  else:
    let view = self.layout.activeLeafView()
    if view == nil:
      log lvlError, &"Failed to destroy view"
      return

    self.closeView(view, keepHidden = keepHidden, restoreHidden = restoreHidden)

proc closeOtherViews*(self: LayoutService, keepHidden: bool = true) {.expose("layout").} =
  ## Closes all views except for the current one. If `keepHidden` is true the views are not closed but hidden instead.

  let view = self.layout.activeLeafView()
  if view == nil:
    return

  let views = self.layout.leafViews()
  for v in views:
    if v != view:
      self.closeView(v, keepHidden = keepHidden)

  self.platform.requestRender()

proc moveCurrentViewToTop*(self: LayoutService) {.expose("layout").} =
  # todo
  # if self.views.len > 0:
  #   let view = self.views[self.currentView]
  #   self.views.delete(self.currentView)
  #   self.views.insert(view, 0)
  self.platform.requestRender()

proc focusViewLeft*(self: LayoutService) {.expose("layout").} =
  let view = self.layout.tryGetViewLeft()
  if view != nil:
    self.tryActivateView(view)
  self.platform.requestRender()

proc focusViewRight*(self: LayoutService) {.expose("layout").} =
  let view = self.layout.tryGetViewRight()
  if view != nil:
    self.tryActivateView(view)
  self.platform.requestRender()

proc focusViewUp*(self: LayoutService) {.expose("layout").} =
  let view = self.layout.tryGetViewUp()
  if view != nil:
    self.tryActivateView(view)
  self.platform.requestRender()

proc focusViewDown*(self: LayoutService) {.expose("layout").} =
  let view = self.layout.tryGetViewDown()
  if view != nil:
    self.tryActivateView(view)
  self.platform.requestRender()

proc setLayout*(self: LayoutService, layout: string) {.expose("layout").} =
  if layout in self.layouts:
    self.layout = self.layouts[layout]
    self.platform.requestRender()
  else:
    log lvlError, &"Unknown layout '{layout}'"

proc focusView*(self: LayoutService, slot: string) {.expose("layout").} =
  let view = self.layout.getView(slot)
  if view != nil:
    self.tryActivateView(view)
  self.platform.requestRender()

proc nextView*(self: LayoutService, slot: string = "") {.expose("layout").} =
  let view = self.layout.getView(slot)
  if view != nil and view of Layout:
    let layout = view.Layout
    var i = layout.activeIndex + 1
    while i < layout.children.len:
      if layout.children[i] != nil:
        break
      inc i
    if i < layout.children.len:
      layout.activeIndex = i
    else:
      for i in 0..<layout.activeIndex:
        if layout.children[i] != nil:
          layout.activeIndex = i
          break
  self.platform.requestRender()

proc prevView*(self: LayoutService, slot: string = "") {.expose("layout").} =
  let view = self.layout.getView(slot)
  if view != nil and view of Layout:
    let layout = view.Layout
    var i = layout.activeIndex - 1
    while i >= 0:
      if layout.children[i] != nil:
        break
      dec i
    if i >= 0:
      layout.activeIndex = i
    else:
      for i in countdown(layout.children.high, layout.activeIndex + 1):
        if layout.children[i] != nil:
          layout.activeIndex = i
          break
  self.platform.requestRender()

proc openPreviousEditor*(self: LayoutService) {.expose("layout").} =
  if self.focusHistory.len == 0:
    return

  let activeView = self.layout.activeLeafView()
  let activeViewId = if activeView != nil:
    activeView.id
  else:
    idNone()

  while self.focusHistory.len > 0:
    let viewId = self.focusHistory.popLast
    if viewId == activeViewId:
      continue

    if self.focusHistory.len == 0 or self.focusHistory.peekFirst() != activeViewId:
      self.focusHistory.addFirst activeViewId

    self.showView(viewId, addToHistory = false)
    break

proc openNextEditor*(self: LayoutService) {.expose("layout").} =
  if self.focusHistory.len == 0:
    return

  let activeView = self.layout.activeLeafView()
  let activeViewId = if activeView != nil:
    activeView.id
  else:
    idNone()

  while self.focusHistory.len > 0:
    let viewId = self.focusHistory.popFirst
    if viewId == activeViewId:
      continue

    if self.tryGetCurrentView().getSome(view):
      if self.focusHistory.len == 0 or self.focusHistory.peekLast() != view.id:
        self.focusHistory.addLast view.id

    self.showView(viewId, addToHistory = false)
    break

proc openLastEditor*(self: LayoutService) {.expose("layout").} =
  if self.viewHistory.len == 0:
    return

  let viewId = self.viewHistory.popLast
  let view = self.getView(viewId).getOr:
    log lvlError, &"No view with id {viewId} exists"
    return

  let slot = self.layout.activeLeafSlot()
  log lvlInfo, &"openLastEditor viewId={viewId}, view={view.desc} in '{slot}'"
  self.showView(view, slot)
  self.platform.requestRender()

proc setActiveIndex*(self: LayoutService, slot: string, index: int) {.expose("layout").} =
  let view = self.layout.getView(slot)
  if view != nil and view of Layout:
    let layout = view.Layout
    layout.activeIndex = index.clamp(0, layout.children.high)
  self.platform.requestRender()

proc moveCurrentViewPrev*(self: LayoutService) {.expose("layout").} =
  # todo
  # if self.views.len > 0:
  #   let view = self.views[self.currentView]
  #   let index = (self.currentView + self.views.len - 1) mod self.views.len
  #   self.views.delete(self.currentView)
  #   self.views.insert(view, index)
  self.platform.requestRender()

proc moveCurrentViewNext*(self: LayoutService) {.expose("layout").} =
  # todo
  # if self.views.len > 0:
  #   let view = self.views[self.currentView]
  #   let index = (self.currentView + 1) mod self.views.len
  #   self.views.delete(self.currentView)
  #   self.views.insert(view, index)
  self.platform.requestRender()

proc moveCurrentViewNextAndGoBack*(self: LayoutService) {.expose("layout").} =
  # todo
  self.platform.requestRender()

proc splitView*(self: LayoutService, slot: string = "") {.expose("layout").} =
  defer:
    self.platform.requestRender()

  if self.tryGetCurrentEditorView().getSome(view):
    discard self.createAndAddView(view.document, slot = slot)

proc moveView*(self: LayoutService, slot: string) {.expose("layout").} =
  defer:
    self.platform.requestRender()

  let view = self.layout.activeLeafView()
  if view != nil:
    discard self.layout.removeView(view)
    discard self.layout.addView(view, slot)

addGlobalDispatchTable "layout", genDispatchTable("layout")
