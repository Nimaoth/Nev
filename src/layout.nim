import std/[tables, options, json, sugar, deques, sets, os]
import results
import platform/platform
import misc/[custom_async, custom_logger, rect_utils, myjsonutils, util, jsonex, array_set]
import scripting/expose
import workspaces/workspace
import finder/finder
import service, platform_service, dispatch_tables, document, document_editor, view, events, config_provider, popup, selector_popup_builder, vfs, vfs_service, session, layouts, command_service
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
    commands: CommandService
    vfs: VFS
    popups*: seq[Popup]
    layout*: Layout
    layoutName*: string = "default"
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
proc preRender*(self: LayoutService)

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
  proc resolve(id: Id): View =
    return layouts.getView(id).get(nil)

  # debugf"{self.desc}.createViews: {config}"
  if config.hasKey("children"):
    let children = config["children"]
    checkJson children.kind == JArray, "'children' must be an array"
    var i = 0
    for c in children.elems:
      if c.kind == JNull:
        continue
      defer:
        inc i
      if i < self.children.len:
        if self.children[i] != nil and self.children[i] of Layout:
          self.children[i].Layout.createViews(c, layouts)
        elif self.childTemplate != nil:
          let newChild = self.childTemplate.copy()
          self.children.add(newChild)
          self.activeIndex = self.activeIndex.clamp(0, self.children.high)
          newChild.createViews(c, layouts)
        else:
          let view = layouts.getExistingView(c)
          if view != nil:
            self.children[i] = layouts.getExistingView(c)
            self.activeIndex = self.activeIndex.clamp(0, self.children.high)
      elif c.hasKey("kind"):
        let subLayout = createLayout(c, resolve)
        self.children.add(subLayout)
        self.activeIndex = self.activeIndex.clamp(0, self.children.high)
      elif self.childTemplate != nil:
        let newChild = self.childTemplate.copy()
        self.children.add(newChild)
        self.activeIndex = self.activeIndex.clamp(0, self.children.high)
        newChild.createViews(c, layouts)
      else:
        let view = layouts.getExistingView(c)
        if view != nil:
          self.children.add(view)
          self.activeIndex = self.activeIndex.clamp(0, self.children.high)

  if config.hasKey("activeIndex"):
    let activeIndex = config["activeIndex"]
    checkJson activeIndex.kind == JInt, "'activeIndex' must be an integer"
    self.activeIndex = activeIndex.getInt.clamp(0, self.children.high)

  if config.hasKey("maximize"):
    self.maximize = config["maximize"].jsonTo(bool)

  if config.hasKey("temporary"):
    self.temporary = config["temporary"].jsonTo(bool)

  # todo: this is not nice
  if self of AutoLayout:
    if config.hasKey("split-ratios"):
      self.AutoLayout.splitRatios = config["split-ratios"].jsonTo(seq[float])

method createViews(self: CenterLayout, config: JsonNode, layouts: LayoutService) {.raises: [ValueError].} =
  if config.kind == JNull:
    return

  checkJson config.kind == JObject, "Expected object"
  proc resolve(id: Id): View =
    return layouts.getView(id).get(nil)

  # debugf"CenterLayout.createViews: {config}"
  if config.hasKey("children"):
    let children = config["children"]
    checkJson children.kind == JArray, "'children' must be an array"
    for i, c in children.elems:
      if c.kind == JNull:
        continue

      if i < self.children.len:
        if self.children[i] != nil and self.children[i] of Layout:
          self.children[i].Layout.createViews(c, layouts)
        elif c.hasKey("kind"):
          let subLayout = createLayout(c, resolve)
          self.children[i] = subLayout
          self.activeIndex = i
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

  if config.hasKey("split-ratios"):
    self.splitRatios = config["split-ratios"].jsonTo(array[4, float])

  if config.hasKey("temporary"):
    self.temporary = config["temporary"].jsonTo(bool)

proc updateLayoutTree(self: LayoutService) =
  try:
    let config = self.config.runtime.get("ui.layout", newJexObject())

    var layoutReferences = newSeq[(string, string)]()

    for key, value in config.fields.pairs:
      if value.kind == JString:
        layoutReferences.add (key, value.getStr)
      else:
        let view = createLayout(value.toJson)
        if view != nil and view of Layout:
          self.layouts[key] = view.Layout
        else:
          self.layouts[key] = AlternatingLayout(children: @[view])

    for (key, target) in layoutReferences:
      if target in self.layouts:
        let l = self.layouts[target].copy()
        assert l != nil
        self.layouts[key] = l
      else:
        log lvlError, &"Unknown layout '{target}' referenced by 'ui.layout.{key}'"

    if self.layoutName in self.layouts:
      self.layout = self.layouts[self.layoutName]

    if self.layout == nil:
      self.layout = AlternatingLayout(children: @[])
  except Exception as e:
    log lvlError, &"Failed to create layout from config: {e.msg}"

func serviceName*(_: typedesc[LayoutService]): string = "LayoutService"

addBuiltinService(LayoutService, PlatformService, ConfigService, DocumentEditorService, Workspace, VFSService, SessionService, CommandService)

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
  self.commands = self.services.getService(CommandService).get
  self.uiSettings = UiSettings.new(self.config.runtime)

  discard self.platform.onPreRender.subscribe (_: Platform) => self.preRender()

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
    result["layout"] = self.layoutName.toJson

    var discardedViews = initHashSet[Id]()
    var viewStates = newJArray()
    for view in self.allViews:
      let state = view.saveState()
      if state != nil:
        viewStates.add state
      else:
        discardedViews.incl view.id
    result["views"] = viewStates

    let layouts = newJObject()
    for key, layout in self.layouts:
      let saved = layout.saveLayout(discardedViews)
      if saved != nil:
        layouts[key] = saved
    result["layouts"] = layouts

  proc load(data: JsonNode) =
    try:
      log lvlInfo, &"Restore layout from session"
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

      if data.hasKey("layout"):
        self.layoutName = data["layout"].jsonTo(string)
        if self.layoutName in self.layouts:
          self.layout = self.layouts[self.layoutName]

    except Exception as e:
      log lvlError, &"Failed to create layout from session data: {e.msg}\n{data.pretty}"

  self.session.addSaveHandler "layout", save, load

  discard self.config.runtime.onConfigChanged.subscribe proc(key: string) =
    if key == "" or key.startsWith("ui.layout"):
      var states = initTable[string, JsonNode]()
      for (name, layout) in self.layouts.pairs:
        let state = layout.saveLayout(initHashSet[Id]())
        if state != nil:
          states[name] = state

      self.updateLayoutTree()
      for (name, state) in states.pairs:
        try:
          self.layouts[name].createViews(state, self)
        except Exception as e:
          log lvlError, &"Failed to create layout from session data: {e.msg}\n{state.pretty}"

      if self.layoutName in states:
        self.layout = self.layouts[self.layoutName]

  self.updateLayoutTree()

  return ok()

proc preRender*(self: LayoutService) =
  self.layout.forEachVisibleView proc(v: View): bool =
    v.checkDirty()
    if v.dirty:
      self.platform.requestRender()
      self.platform.logNextFrameTime = true

method desc*(self: EditorView): string =
  if self.document == nil:
    &"EditorView(pending '{self.path}')"
  else:
    &"EditorView('{self.document.filename}')"

method kind*(self: EditorView): string = "editor"

method display*(self: EditorView): string = self.document.filename

method saveState*(self: EditorView): JsonNode =
  if self.document.filename == "":
    return nil
  if not EditorSettings.new(self.editor.config).saveInSession.get(true):
    return nil

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

proc anyUnsavedChanges*(self: LayoutService): bool =
  for view in self.allViews:
    if view of EditorView:
      let doc = view.EditorView.document
      let isDirty = not doc.requiresLoad and doc.lastSavedRevision != doc.revision
      if isDirty:
        return true
  return false

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

proc getActiveEditor*(self: LayoutService): Option[DocumentEditor] =
  if self.commands.commandLineMode:
    return self.commands.commandLineEditor.some

  if self.popups.len > 0 and self.popups[self.popups.high].getActiveEditor().getSome(editor):
    return editor.some

  if self.tryGetCurrentEditorView().getSome(view):
    return view.editor.some

  return DocumentEditor.none

proc getView*(self: LayoutService, id: Id): Option[View] =
  ## Returns the index of the view for the given editor.
  for i, view in self.allViews:
    if view.id == id:
      return view.some

  return View.none

proc getView*(self: LayoutService, id: int32): Option[View] =
  ## Returns the index of the view for the given editor.
  for i, view in self.allViews:
    if view.id2 == id:
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

proc registerView*(self: LayoutService, view: View) =
  self.allViews.incl view

proc addView*(self: LayoutService, view: View, slot: string = "", focus: bool = true, addToHistory: bool = true) =
  # debugf"addView {view.desc()} slot = '{slot}', focus = {focus}, addToHistory = {addToHistory}"
  self.allViews.incl view
  let slot = if slot == "":
    self.layout.slots.getOrDefault("default", "")
  else:
    slot

  let prevActiveView = self.layout.activeLeafView()
  if focus and addToHistory:
    self.recordFocusHistoryEntry(prevActiveView)

  discard self.layout.removeView(view)
  let ejectedView = self.layout.addView(view, slot, focus).catch:
    log lvlError, &"Failed to add view: {getCurrentExceptionMsg()}"
    return

  self.layout.collapseTemporaryViews()

  if ejectedView != nil and ejectedView.id != idNone():
    self.viewHistory.addLast(ejectedView.id)
    self.allViews.removeShift(ejectedView)
    self.allViews.add(ejectedView)

  # Force immediate load for new file since we're making it visible anyways
  if view of EditorView and view.EditorView.document.requiresLoad:
    view.EditorView.document.load()

  view.markDirty()
  self.platform.requestRender()

proc createAndAddView*(self: LayoutService, document: Document, slot: string = ""): Option[DocumentEditor] =
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

proc changeSplitSize*(self: LayoutService, change: float, vertical: bool) {.expose("layout").} =
  discard self.layout.changeSplitSize(change, vertical)

proc toggleMaximizeViewLocal*(self: LayoutService, slot: string = "**") {.expose("layout").} =
  let view = self.layout.getView(slot)
  if view != nil and view of Layout:
    let layout = view.Layout
    layout.maximize = not layout.maximize
    self.platform.requestRender()

proc toggleMaximizeView*(self: LayoutService) {.expose("layout").} =
  self.maximizeView = not self.maximizeView
  self.platform.requestRender()

proc setMaxViews*(self: LayoutService, slot: string, maxViews: int = int.high) {.expose("layout").} =
  ## Set the maximum number of views that can be open at the same time
  let view = self.layout.getView(slot)
  if view != nil and view of Layout:
    let layout = view.Layout
    layout.maxChildren = maxViews

  self.platform.requestRender()

proc getHiddenViews*(self: LayoutService): seq[View] =
  var res = self.allViews
  self.layout.forEachVisibleView proc(v: View): bool =
    res.removeShift(v)
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
    for v in self.layout.visibleLeafViews():
      if v == view:
        return
    discard self.layout.removeView(view)
    self.addView(view, slot=slot, focus=false, addToHistory=addToHistory)

  self.platform.requestRender()

proc showView*(self: LayoutService, viewId: Id, slot: string = "", focus: bool = true, addToHistory: bool = true) =
  if self.getView(viewId).getSome(view):
    self.showView(view, slot, focus, addToHistory)

proc showView*(self: LayoutService, viewId: int32, slot: string = "", focus: bool = true, addToHistory: bool = true) =
  if self.getView(viewId).getSome(view):
    self.showView(view, slot, focus, addToHistory)

proc showEditor*(self: LayoutService, editorId: EditorId, slot: string = "", focus: bool = true) {.expose("layout").} =
  ## Make the given editor visible
  let editor = self.editors.getEditorForId(editorId).getOr:
    log lvlError, &"No editor with id {editorId} exists"
    return

  assert editor.getDocument().isNotNil

  log lvlInfo, &"showEditor editorId={editorId}, filename={editor.getDocument().filename}"
  if self.getViewForEditor(editor).getSome(view):
    self.showView(view, slot, focus)

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

  try:
    var remove = true
    if restoreHidden:
      let hiddenViews = self.getHiddenViews()
      if hiddenViews.len > 0:
        let activeSlot = self.layout.getSlot(view)
        discard self.layout.addView(hiddenViews.last, activeSlot)
        remove = false

    if remove:
      discard self.layout.removeView(view)
      self.layout.collapseTemporaryViews()

    if keepHidden:
      return

    # remove from all other layouts as well
    for l in self.layouts.values:
      if l != self.layout:
        discard l.removeView(view)
        l.collapseTemporaryViews()

    self.allViews.removeShift(view)
    view.close()
    if view of EditorView:
      self.editors.closeEditor(view.EditorView.editor)

  except LayoutError as e:
    log lvlError, "Failed to close view: " & e.msg

proc closeView*(self: LayoutService, viewId: int32, keepHidden: bool = false, restoreHidden: bool = true) =
  if self.getView(viewId).getSome(view):
    self.closeView(view, keepHidden, restoreHidden)

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

proc hideActiveView*(self: LayoutService, closeOpenPopup: bool = true) {.expose("layout").} =
  ## Hide the active view, removing it from the current layout tree.
  ## To reopen the view, use commands like `show-last-hidden-view` or `choose-open`.
  let view = self.layout.activeLeafView()
  if view == nil:
    return

  # todo: do we want to add it to the view history here?
  discard self.layout.removeView(view)
  self.layout.collapseTemporaryViews()
  self.platform.requestRender()

proc closeActiveView*(self: LayoutService, closeOpenPopup: bool = true, restoreHidden: bool = true) {.expose("layout").} =
  ## Permanently close the active view.
  if closeOpenPopup and self.popups.len > 0:
    self.popPopup()
  else:
    let view = self.layout.activeLeafView()
    if view == nil:
      log lvlError, &"Failed to destroy view"
      return

    self.closeView(view, keepHidden = false, restoreHidden = restoreHidden)

proc hideOtherViews*(self: LayoutService) {.expose("layout").} =
  ## Hides all views except for the active one.
  let view = self.layout.activeLeafView()
  if view == nil:
    return

  let views = self.layout.leafViews()
  for v in views:
    if v != view:
      discard self.layout.removeView(v)
  self.layout.collapseTemporaryViews()

  self.platform.requestRender()

proc closeOtherViews*(self: LayoutService) {.expose("layout").} =
  ## Permanently closes all views except for the active one.
  let view = self.layout.activeLeafView()
  if view == nil:
    return

  let views = self.layout.leafViews()
  for v in views:
    if v != view:
      self.closeView(v, restoreHidden = false)

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

proc focusView*(self: LayoutService, slot: string) {.expose("layout").} =
  let view = self.layout.getView(slot)
  if view != nil:
    self.tryActivateView(view)
  self.platform.requestRender()

proc focusNextView*(self: LayoutService, slot: string = "") {.expose("layout").} =
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

proc focusPrevView*(self: LayoutService, slot: string = "") {.expose("layout").} =
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

proc openPrevView*(self: LayoutService) {.expose("layout").} =
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

proc openNextView*(self: LayoutService) {.expose("layout").} =
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

proc openLastView*(self: LayoutService) {.expose("layout").} =
  let hiddenViews = self.getHiddenViews()
  if hiddenViews.len == 0:
    return

  let view = hiddenViews.last
  let slot = self.layout.activeLeafSlot()
  log lvlInfo, &"openLastView viewId={view.id}, view={view.desc} in '{slot}'"
  self.showView(view, slot)
  self.platform.requestRender()

proc setLayout*(self: LayoutService, layout: string) {.expose("layout").} =
  if layout in self.layouts:
    self.layout = self.layouts[layout]
    self.layoutName = layout
    if self.layout.numLeafViews == 0:
      self.openLastView()
    self.platform.requestRender()
  else:
    log lvlError, &"Unknown layout '{layout}'"

proc setActiveViewIndex*(self: LayoutService, slot: string, index: int) {.expose("layout").} =
  let view = self.layout.getView(slot)
  if view != nil and view of Layout:
    let layout = view.Layout
    layout.activeIndex = index.clamp(0, layout.children.high)
  self.platform.requestRender()

proc moveActiveViewFirst*(self: LayoutService) {.expose("layout").} =
  let layout = self.layout.activeLeafLayout()
  let currentView = layout.activeLeafView()
  let firstView = if layout.children.len > 0: layout.children[0] else: nil
  if currentView != nil and firstView != nil and currentView != firstView:
    let prevSlot = layout.getSlot(firstView)
    let currentSlot = layout.getSlot(currentView)
    try:
      discard layout.addView(firstView, currentSlot)
      discard layout.addView(currentView, prevSlot)
    except LayoutError:
      discard
    self.platform.requestRender()
  self.platform.requestRender()

proc moveActiveViewPrev*(self: LayoutService) {.expose("layout").} =
  let layout = self.layout.activeLeafLayout()
  let currentView = layout.activeLeafView()
  let prevView = layout.tryGetPrevView()
  if currentView != nil and prevView != nil:
    let prevSlot = layout.getSlot(prevView)
    let currentSlot = layout.getSlot(currentView)
    try:
      discard layout.addView(prevView, currentSlot)
      discard layout.addView(currentView, prevSlot)
    except LayoutError:
      discard
    self.platform.requestRender()

proc moveActiveViewNext*(self: LayoutService) {.expose("layout").} =
  let layout = self.layout.activeLeafLayout()
  let currentView = layout.activeLeafView()
  let nextView = layout.tryGetNextView()
  if currentView != nil and nextView != nil:
    let nextSlot = layout.getSlot(nextView)
    let currentSlot = layout.getSlot(currentView)
    try:
      discard layout.addView(nextView, currentSlot)
      discard layout.addView(currentView, nextSlot)
    except LayoutError:
      discard
    self.platform.requestRender()

proc moveActiveViewNextAndGoBack*(self: LayoutService) {.expose("layout").} =
  if self.viewHistory.len == 0:
    return

  let viewId = self.viewHistory.popLast
  let view = self.getView(viewId).getOr:
    log lvlError, &"No view with id {viewId} exists"
    return

  let layout = self.layout.activeLeafLayout()
  let currentView = layout.activeLeafView()
  let nextView = layout.tryGetNextView()
  if currentView != nil and nextView != nil:
    let nextSlot = layout.getSlot(nextView)
    let currentSlot = layout.getSlot(currentView)
    try:
      discard layout.addView(currentView, nextSlot)
      discard layout.addView(view, currentSlot)
    except LayoutError:
      discard
    self.viewHistory.addLast(nextView.id)

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
    let oldSlot = self.layout.getSlot(view)
    discard self.layout.removeView(view)
    discard self.layout.addView(view, slot).catch:
      log lvlError, &"Failed to move view to slot '{slot}': {getCurrentExceptionMsg()}"
      try:
        discard self.layout.addView(view, oldSlot)
      except LayoutError:
        discard
      return
    self.layout.collapseTemporaryViews()

proc wrapLayout(self: LayoutService, layout: JsonNode, slot: string = "**") {.expose("layout").} =
  ## Wraps the active view with the specified layout.
  ## You can either pass a JSON object specifying a layout configuration (like in a settings file)
  ## or a string representing the name of a layout.
  let newLayout = if layout.kind == JString:
    let name = layout.getStr
    if name in self.layouts:
      self.layouts[name].copy()
    else:
      log lvlError, &"Unknown layout '{name}'"
      return
  else:
    try:
      let v = createLayout(layout)
      if v != nil and v of Layout:
        v.Layout
      else:
        log lvlError, &"Not a layout: {layout}"
        return
    except ValueError as e:
      log lvlError, &"Failed to create layout from config: {e.msg}"
      return

  try:
    var parentLayout = self.layout.getView(slot)
    if parentLayout != nil and not (parentLayout of Layout):
      parentLayout = self.layout.parentLayout(parentLayout)

    if parentLayout != nil and parentLayout of Layout:
      let parentLayout = parentLayout.Layout
      let childView = parentLayout.activeLeafView()
      assert parentLayout.addView(newLayout, "*") == childView
      discard newLayout.addView(childView, "+")

      var hiddenViews = self.allViews
      self.layout.forEachView proc(v: View): bool =
        hiddenViews.removeShift(v)
      if hiddenViews.len > 0:
        discard newLayout.addView(hiddenViews.last, "+")
  except LayoutError:
    discard

proc chooseLayout(self: LayoutService) {.expose("layout").} =
  var builder = SelectorPopupBuilder()
  builder.scope = "layout".some
  builder.scaleX = 0.4
  builder.scaleY = 0.3

  var res = newSeq[FinderItem]()
  for name in self.layouts.keys:
    res.add FinderItem(
      displayName: name,
    )

  let finder = newFinder(newStaticDataSource(res), filterAndSort=true)
  builder.finder = finder.some

  let oldLayout = self.layoutName

  builder.handleCanceled = proc(popup: ISelectorPopup) =
    self.setLayout(oldLayout)

  builder.handleItemSelected = proc(popup: ISelectorPopup, item: FinderItem) =
    self.setLayout(item.displayName)

  builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
    self.setLayout(item.displayName)
    return true

  discard self.pushSelectorPopup(builder)

proc logLayout*(self: LayoutService) {.expose("layout").} =
  log lvlInfo, self.layout.saveLayout(initHashSet[Id]()).pretty

proc open*(self: LayoutService, path: string, slot: string = "") {.expose("layout").} =
  ## Opens the specified file. Relative paths are relative to the main workspace.
  ## `path` - File path to open.
  ## `slot` - Where in the layout to put the opened file. If not specified the default slot is used.
  var path = path
  let vfs = self.vfs.getVFS(path, maxDepth = 1).vfs
  if vfs != nil and vfs.prefix == "" and not path.isAbsolute:
    path = self.workspace.getAbsolutePath(path)
  discard self.openFile(path, slot)

addGlobalDispatchTable "layout", genDispatchTable("layout")
