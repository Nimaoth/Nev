import std/[tables, options, json, sugar, sequtils]
import bumpy
import results
import platform/platform
import misc/[custom_async, custom_logger, rect_utils, myjsonutils, util, jsonex]
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
    layoutProps*: LayoutProperties
    maximizeView*: bool
    currentViewInternal*: int
    views*: seq[View]
    hiddenViews*: seq[View]
    activeEditorInternal*: Option[EditorId]
    editorHistory*: Deque[EditorId]

    onEditorRegistered*: Event[DocumentEditor]
    onEditorDeregistered*: Event[DocumentEditor]

    pinnedDocuments*: seq[Document]

    pushSelectorPopupImpl: PushSelectorPopupImpl
    activeView*: View
    allViews*: seq[View]

var gPushSelectorPopupImpl*: PushSelectorPopupImpl

method desc*(self: EditorView): string =
  if self.document == nil:
    &"EditorView(pending '{self.path}')"
  else:
    &"EditorView('{self.document.filename}')"
method kind*(self: EditorView): string = "editor"
method display*(self: EditorView): string = self.document.filename
method saveLayout*(self: EditorView): JsonNode =
  result = newJObject()
  result["kind"] = self.kind.toJson
  result["path"] = self.document.filename.toJson
  result["state"] = self.editor.getStateJson()

proc createLayout(self: LayoutService, config: JsonNodeEx): View {.raises: [ValueError].} =
  if config.kind == JNull:
    return nil

  checkJson config.hasKey("kind") and config["kind"].kind == Jstring, "Expected field 'kind' of type string"
  let kind = config["kind"].getStr
  debugf"createLayout '{kind}': {config}"

  template createChildren(res: Layout): untyped =
    if config.hasKey("children"):
      let children = config["children"]
      checkJson children.kind == JArray, "'children' must be an array"
      for i, c in children.elems:
        res.children.add self.createLayout(c)
      if res.children.len > 0 and res.children[0] of Layout:
        res.childTemplate = res.children[0].Layout.copy()
    if config.hasKey("activeIndex"):
      let activeIndex = config["activeIndex"]
      checkJson activeIndex.kind == JInt, "'activeIndex' must be an integer"
      res.activeIndex = activeIndex.getInt

  case kind
  of "main":
    let res = MainLayout(children: newSeq[View](5))
    if config.hasKey("children"):
      let children = config["children"]
      checkJson children.kind == JArray, "'children' must be an array"
      for i, c in children.elems:
        if i < res.children.len:
          res.children[i] = self.createLayout(c)
    else:
      if config.hasKey("left"):
        res.left = self.createLayout(config["left"])
      if config.hasKey("right"):
        res.right = self.createLayout(config["right"])
      if config.hasKey("top"):
        res.top = self.createLayout(config["top"])
      if config.hasKey("bottom"):
        res.bottom = self.createLayout(config["bottom"])
      if config.hasKey("center"):
        res.center = self.createLayout(config["center"])

    if config.hasKey("activeIndex"):
      let activeIndex = config["activeIndex"]
      checkJson activeIndex.kind == JInt, "'activeIndex' must be an integer"
      res.activeIndex = activeIndex.getInt

    return res

  of "horizontal":
    let res = HorizontalLayout()
    res.createChildren()
    return res

  of "vertical":
    let res = VerticalLayout()
    res.createChildren()
    return res

  of "alternating":
    let res = AlternatingLayout()
    res.createChildren()
    return res

  of "tab":
    let res = TabLayout()
    res.createChildren()
    return res

  of "editor":
    checkJson config.hasKey("path") and config["path"].kind == JString, "kind 'editor' requires 'path' field of type string"
    let path = config["path"].getStr
    debugf"create initial document for '{path}'"

    # Reuse existing hidden view
    for i, v in self.hiddenViews:
      if v of EditorView and v.EditorView.document.filename == path:
        self.hiddenViews.removeSwap(i)
        debugf"createLayout: reusing existing view for '{path}'"
        return v

    let document = self.editors.getOrOpenDocument(path).getOr:
      log(lvlError, fmt"Failed to restore file '{path}' from session")
      return nil

    assert document != nil
    let editor = self.editors.createEditorForDocument(document).getOr:
      log(lvlError, fmt"Failed to create editor for '{path}'")
      return nil

    if config.hasKey("state"):
      editor.restoreStateJson(config["state"].toJson)
    return EditorView(document: document, editor: editor)

  else:
    raise newException(ValueError, &"Invalid kind for layout: '{kind}'")

method createViews(self: Layout, config: JsonNodeEx, layouts: LayoutService) {.base, raises: [ValueError].} =
  if config.kind == JNull:
    return

  checkJson config.kind == JObject, "Expected object"

  debugf"createViews '{self.desc}': {config}"
  if config.hasKey("children"):
    let children = config["children"]
    checkJson children.kind == JArray, "'children' must be an array"
    for i, c in children.elems:
      if i < self.children.len:
        if self.children[i] != nil and self.children[i] of Layout:
          self.children[i].Layout.createViews(c, layouts)
        else:
          self.children[i] = layouts.createLayout(c)
          self.activeIndex = max(self.activeIndex, 0)
      elif self.childTemplate != nil:
        let newChild = self.childTemplate.copy()
        self.children.add(newChild)
        self.activeIndex = max(self.activeIndex, 0)
        newChild.createViews(c, layouts)
      else:
        self.children.add(layouts.createLayout(c))
        self.activeIndex = max(self.activeIndex, 0)
  if config.hasKey("activeIndex"):
    let activeIndex = config["activeIndex"]
    checkJson activeIndex.kind == JInt, "'activeIndex' must be an integer"
    self.activeIndex = activeIndex.getInt

# method createViews(self: MainLayout, config: JsonNodeEx, layouts: LayoutService) {.raises: [ValueError].} =
#   if config.hasKey("children"):
#     let children = config["children"]
#     checkJson children.kind == JArray, "'children' must be an array"
#     for i, c in children.elems:
#       if i < res.children.len:
#         res.children[i] = self.createLayout(c)
#   else:
#     if config.hasKey("left"):
#       res.left = self.createLayout(config["left"])
#     if config.hasKey("right"):
#       res.right = self.createLayout(config["right"])
#     if config.hasKey("top"):
#       res.top = self.createLayout(config["top"])
#     if config.hasKey("bottom"):
#       res.bottom = self.createLayout(config["bottom"])
#     if config.hasKey("center"):
#       res.center = self.createLayout(config["center"])

#   if config.hasKey("activeIndex"):
#     let activeIndex = config["activeIndex"]
#     checkJson activeIndex.kind == JInt, "'activeIndex' must be an integer"
#     res.activeIndex = activeIndex.getInt

#   return res

proc updateLayoutTree(self: LayoutService) =
  try:
    # let config = self.uiSettings.layout.get()
    let config = self.config.runtime.get("ui.layout", newJexObject())
    debugf"updateLayoutTree\n{config.pretty}"
    let view = self.createLayout(config)
    if view of Layout:
      self.layout = view.Layout
    else:
      self.layout = AlternatingLayout(children: @[view])
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

  proc save(): JsonNode =
    debugf"save layout in session"
    result = newJObject()
    result["views"] = self.layout.saveLayout()
    var hidden = newJArray()
    for view in self.hiddenViews:
      hidden.add view.saveLayout()
    result["hidden"] = hidden

  proc load(data: JsonNode) =
    debugf"load layout from session:\n{data.pretty}"
    try:
      self.updateLayoutTree()
      if data.hasKey("kind"):
        self.layout.createViews(data.toJsonex, self)
      elif data.hasKey("views"):
        self.layout.createViews(data["views"].toJsonex, self)

      if data.hasKey("hidden"):
        let hidden = data["hidden"]
        checkJson hidden.kind == JArray, &"Expected array, got {hidden}"
        for state in hidden.elems:
          let view = self.createLayout(state.toJsonEx)
          self.hiddenViews.add(view)
    except Exception as e:
      log lvlError, &"Failed to create layout from session data: {e.msg}\n{data.pretty}"

  self.session.addSaveHandler "layout", save, load

  # self.session.onSessionRestored.subscribe proc(_: SessionService) =
  #   discard

  discard self.config.runtime.onConfigChanged.subscribe proc(key: string) =
    if key == "" or key.startsWith("ui.layout"):
    # if key.startsWith("ui.layout"):
      let state = self.layout.saveLayout()
      self.layout.forEachView proc(v: View): bool =
        if not (v of Layout):
          self.hiddenViews.add v

      self.updateLayoutTree()
      try:
        self.layout.createViews(state.toJsonEx, self)
      except Exception as e:
        log lvlError, &"Failed to create layout from session data: {e.msg}\n{state.pretty}"

  self.updateLayoutTree()

  return ok()

proc preRender*(self: LayoutService) =
  # ensure all editor views have a document created from the path
  var viewsToRemove = newSeq[View]()
  self.layout.forEachView proc(v: View): bool =
    if v of EditorView:
      let view = v.EditorView
      if view.document == nil:
        debugf"create initial document for view {view.desc}"
        view.document = self.editors.getOrOpenDocument(view.path).getOr:
          log(lvlError, fmt"Failed to restore file {view.path} from previous session")
          return

      assert view.document != nil
      if view.editor == nil:
        if self.editors.createEditorForDocument(view.document).getSome(editor):
          view.editor = editor
        else:
          viewsToRemove.add(view)

  for view in viewsToRemove:
    debugf"remove view because it failed to load: {view.desc}"
    discard self.layout.removeView(view)

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

proc currentView*(self: LayoutService): int = self.currentViewInternal

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

proc updateActiveEditor*(self: LayoutService, addToHistory = true) =
  if self.tryGetCurrentEditorView().getSome(view):
    if addToHistory and self.activeEditorInternal.getSome(id) and id != view.editor.id:
      self.editorHistory.addLast id
    self.activeEditorInternal = view.editor.id.some

proc `currentView=`*(self: LayoutService, newIndex: int, addToHistory = true) =
  self.currentViewInternal = newIndex
  self.updateActiveEditor(addToHistory)

method addView*(self: Layout, view: View, path: string = ""): View {.base.} =
  debugf"{self.desc}.addView {view.desc()} to slot '{path}'"
  let (slot, subPath) = path.extractSlot
  case slot
  of "+":
    if self.childTemplate != nil:
      let newChild = self.childTemplate.copy()
      self.children.add(newChild)
      self.activeIndex = self.children.high
      return newChild.addView(view, subPath)
    else:
      self.children.add(view)
      self.activeIndex = self.children.high
  of "", "*":
    if self.children.len > 0:
      if self.children[self.activeIndex] != nil and self.children[self.activeIndex] of Layout:
        return self.children[self.activeIndex].Layout.addView(view, subPath)
      else:
        result = self.children[self.activeIndex]
        self.children[self.activeIndex] = view
    else:
      if self.childTemplate != nil:
        let newChild = self.childTemplate.copy()
        self.children.add(newChild)
        self.activeIndex = self.children.high
        return newChild.addView(view, subPath)
      else:
        self.children.add(view)
        self.activeIndex = self.children.high

method addView*(self: MainLayout, view: View, path: string = ""): View =
  debugf"MainLayout.addView {view.desc()} to slot '{path}'"
  var index = 4
  let (slot, subPath) = path.extractSlot
  case slot
  of "", "*": index = self.activeIndex
  of "left": index = 0
  of "right": index = 1
  of "top": index = 2
  of "bottom": index = 3
  of "center": index = 4

  if self.children[index] != nil and self.children[index] of Layout:
    self.activeIndex = index
    return self.children[index].Layout.addView(view, subPath)
  else:
    result = self.children[index]
    self.children[index] = view
    self.activeIndex = index

# method addView*(self: AlternatingLayout, view: View, slot: string = "") =
#   debugf"addView {view.desc()} append={append}"
#   let maxViews = self.uiSettings.maxViews.get()

#   discard self.layout.removeView(view)
#   self.layout.addView(view)

#   while maxViews > 0 and self.views.len > maxViews:
#     self.views[self.views.high].deactivate()
#     self.hiddenViews.add self.views.pop()

#   if append:
#     self.currentView = self.views.high

#   if self.views.len == maxViews:
#     self.views[self.currentView].deactivate()
#     self.hiddenViews.add self.views[self.currentView]
#     self.views[self.currentView] = view
#   elif append:
#     self.views.add view
#   else:
#     if self.currentView < 0:
#       self.currentView = 0
#     self.views.insert(view, self.currentView)

#   if self.currentView < 0:
#     self.currentView = 0

proc addView*(self: LayoutService, view: View, addToHistory = true, append = false, slot: string = "") =
  debugf"addView {view.desc()} append={append}"
  let maxViews = self.uiSettings.maxViews.get()

  let slot = if slot == "":
    self.uiSettings.defaultSlot.get()
  else:
    slot

  discard self.layout.removeView(view)
  let ejectedView = self.layout.addView(view, slot)

  self.hiddenViews.removeSwap(view)
  if self.allViews.find(view) != -1:
    self.allViews.add view
  if ejectedView != nil:
    self.hiddenViews.add(ejectedView)

  # while maxViews > 0 and self.views.len > maxViews:
  #   self.views[self.views.high].deactivate()
  #   self.hiddenViews.add self.views.pop()

  # if append:
  #   self.currentView = self.views.high

  # if self.views.len == maxViews:
  #   self.views[self.currentView].deactivate()
  #   self.hiddenViews.add self.views[self.currentView]
  #   self.views[self.currentView] = view
  # elif append:
  #   self.views.add view
  # else:
  #   if self.currentView < 0:
  #     self.currentView = 0
  #   self.views.insert(view, self.currentView)

  if self.currentView < 0:
    self.currentView = 0

  # Force immediate load for new file since we're making it visible anyways
  if view of EditorView and view.EditorView.document.requiresLoad:
    view.EditorView.document.load()

  view.markDirty()
  self.updateActiveEditor(addToHistory)
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

proc createAndAddView*(self: LayoutService, document: Document, append: bool = false, slot: string = ""): Option[DocumentEditor] =
  debugf"createAndAddView '{document.filename}'"
  if self.editors.createEditorForDocument(document).getSome(editor):
    var view = EditorView(document: document, editor: editor)
    self.addView(view, append=append, slot=slot)
    return editor.some
  return DocumentEditor.none

method tryActivateView*(self: Layout, predicate: proc(view: View): bool {.gcsafe, raises: [].}): bool {.base.} =
  for i, c in self.children:
    if c == nil:
      continue
    if predicate(c):
      self.activeIndex = i
      return true
    if c of Layout:
      if c.Layout.tryActivateView(predicate):
        self.activeIndex = i
        return true

  return false

proc tryActivateEditor*(self: LayoutService, editor: DocumentEditor) =
  if self.popups.len > 0:
    return
  discard self.layout.tryActivateView proc(view: View): bool =
    return view of EditorView and view.EditorView.editor == editor
  self.platform.requestRender()

proc tryActivateView*(self: LayoutService, view: View) =
  if self.popups.len > 0:
    return
  discard self.layout.tryActivateView proc(v: View): bool =
    return view == v
  self.platform.requestRender()

proc getActiveViewEditor*(self: LayoutService): Option[DocumentEditor] =
  if self.tryGetCurrentEditorView().getSome(view):
    return view.editor.some

  return DocumentEditor.none

proc getViewForEditor*(self: LayoutService, editor: DocumentEditor): Option[EditorView] =
  ## Returns the index of the view for the given editor.
  for i, view in self.views:
    if view of EditorView and view.EditorView.editor == editor:
      return view.EditorView.some
  for i, view in self.hiddenViews:
    if view of EditorView and view.EditorView.editor == editor:
      return view.EditorView.some

  return EditorView.none

proc getViewIndexForEditor*(self: LayoutService, editor: DocumentEditor): Option[int] =
  ## Returns the index of the view for the given editor.
  for i, view in self.views:
    if view of EditorView and view.EditorView.editor == editor:
      return i.some

  return int.none

proc getViewIndexForEditor*(self: LayoutService, editorId: EditorId): Option[int] =
  ## Returns the index of the view for the given editor id.
  for i, view in self.views:
    if view of EditorView and view.EditorView.editor.id == editorId:
      return i.some

  return int.none

proc getHiddenViewForEditor*(self: LayoutService, editor: DocumentEditor): Option[int] =
  ## Returns the index of the hidden view for the given editor id.
  for i, view in self.hiddenViews:
    if view of EditorView and view.EditorView.editor == editor:
      return i.some

  return int.none

proc getHiddenViewForEditor*(self: LayoutService, editorId: EditorId): Option[int] =
  ## Returns the index of the hidden view for the given editor.
  for i, view in self.hiddenViews:
    if view of EditorView and view.EditorView.editor.id == editorId:
      return i.some

  return int.none

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
  for view in self.views:
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

proc setMaxViews*(self: LayoutService, maxViews: int, openExisting: bool = false) {.expose("layout").} =
  ## Set the maximum number of views that can be open at the same time
  ## Closes any views that exceed the new limit
  debugf"setMaxViews {maxViews}, openExisting = {openExisting}"

  log lvlInfo, fmt"[setMaxViews] {maxViews}"
  self.uiSettings.maxViews.set(maxViews)
  while maxViews > 0 and self.views.len > maxViews:
    self.views[self.views.high].deactivate()
    self.hiddenViews.add self.views.pop()

  while openExisting and self.views.len < maxViews and self.hiddenViews.len > 0:
    self.views.add self.hiddenViews.pop()

  self.currentView = self.currentView.clamp(0, self.views.high)

  self.updateActiveEditor(false)
  self.platform.requestRender()

proc getEditorInView*(self: LayoutService, index: int): EditorId {.expose("layout").} =
  if index >= 0 and index < self.views.len and self.views[index] of EditorView:
    return self.views[index].EditorView.editor.id

  return EditorId(-1)

proc getVisibleEditors*(self: LayoutService): seq[EditorId] {.expose("layout").} =
  ## Returns a list of all editors which are currently shown
  for view in self.views:
    if view of EditorView:
      result.add view.EditorView.editor.id

proc getHiddenEditors*(self: LayoutService): seq[EditorId] {.expose("layout").} =
  ## Returns a list of all editors which are currently hidden
  for view in self.hiddenViews:
    if view of EditorView:
      result.add view.EditorView.editor.id

proc getNumVisibleViews*(self: LayoutService): int {.expose("layout").} =
  ## Returns the amount of visible views
  var res = 0
  self.layout.forEachView proc(v: View): bool =
    if not (v of Layout):
      inc res
  return res

proc getNumHiddenViews*(self: LayoutService): int {.expose("layout").} =
  ## Returns the amount of hidden views
  return self.hiddenViews.len

proc showView*(self: LayoutService, view: View, viewIndex: Option[int] = int.none) =
  ## Make the given view visible
  ## If viewIndex is none, the view will be opened in the currentView,
  ## Otherwise the view will be opened in the view with the given index.
  debugf"showView {view.desc()}, viewIndex = {viewIndex}"

  for i, v in self.views:
    if v == view:
      self.currentView = i
      return

  var hiddenView = -1
  for i, v in self.hiddenViews:
    if v == view:
      hiddenView = i
      break

  if hiddenView >= 0:
    self.hiddenViews.removeSwap(hiddenView)

  if viewIndex.getSome(_):
    # todo
    log lvlError, &"Not implemented: showView(view, {viewIndex})"
  else:
    let oldView = self.views[self.currentView]
    oldView.deactivate()
    self.hiddenViews.add oldView

    self.views[self.currentView] = view
    view.activate()

proc showEditor*(self: LayoutService, editorId: EditorId, viewIndex: Option[int] = int.none) {.expose("layout").} =
  ## Make the given editor visible
  ## If viewIndex is none, the editor will be opened in the currentView,
  ## Otherwise the editor will be opened in the view with the given index.
  debugf"showEditor {editorId}, viewIndex = {viewIndex}"

  let editor = self.editors.getEditorForId(editorId).getOr:
    log lvlError, &"No editor with id {editorId} exists"
    return

  assert editor.getDocument().isNotNil

  log lvlInfo, &"showEditor editorId={editorId}, viewIndex={viewIndex}, filename={editor.getDocument().filename}"

  for i, view in self.views:
    if view of EditorView and view.EditorView.editor == editor:
      self.currentView = i
      return

  let hiddenView = self.getHiddenViewForEditor(editor)
  let view: View = if hiddenView.getSome(index):
    let view = self.hiddenViews[index]
    self.hiddenViews.removeSwap(index)
    view
  else:
    EditorView(document: editor.getDocument(), editor: editor)

  if viewIndex.getSome(_):
    # todo
    log lvlError, &"Not implemented: showEditor({editorId}, {viewIndex})"
  else:
    let oldView = self.views[self.currentView]
    oldView.deactivate()
    self.hiddenViews.add oldView

    self.views[self.currentView] = view
    view.activate()

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

proc tryOpenExisting*(self: LayoutService, path: string, appFile: bool = false, append: bool = false): Option[DocumentEditor] =
  debugf"tryOpenExisting '{path}'"
  for i, view in self.views:
    if view of EditorView and view.EditorView.document.filename == path:
      log(lvlInfo, fmt"Reusing open editor in view {i}")
      self.currentView = i
      return view.EditorView.editor.some

  for i, view in self.hiddenViews:
    if view of EditorView and view.EditorView.document.filename == path:
      log(lvlInfo, fmt"Reusing hidden view")
      self.hiddenViews.delete i
      self.addView(view, append=append)
      return view.EditorView.editor.some

  return DocumentEditor.none

proc tryOpenExisting*(self: LayoutService, editor: EditorId, addToHistory = true): Option[DocumentEditor] =
  debugf"tryOpenExisting '{editor}'"
  self.platform.requestRender()
  var res = DocumentEditor.none
  let activated = self.layout.tryActivateView proc(v: View): bool =
    if v of EditorView and v.EditorView.editor.id == editor:
      res = v.EditorView.editor.some
      return true

  if activated:
    return res

  for i, view in self.hiddenViews:
    if view of EditorView and view.EditorView.editor.id == editor:
      log(lvlInfo, fmt"Reusing hidden view")
      self.hiddenViews.delete i
      self.addView(view, addToHistory)
      return view.EditorView.editor.some

  return DocumentEditor.none

proc openWorkspaceFile*(self: LayoutService, path: string, append: bool = false, slot: string = ""): Option[DocumentEditor] =
  defer:
    self.platform.requestRender()

  let path = self.workspace.getAbsolutePath(path)

  log lvlInfo, fmt"[openWorkspaceFile] Open file '{path}' in workspace {self.workspace.name} ({self.workspace.id})"
  if self.tryOpenExisting(path, append = append).getSome(editor):
    log lvlInfo, fmt"[openWorkspaceFile] found existing editor"
    return editor.some

  let document = self.editors.getOrOpenDocument(path).getOr:
    log(lvlError, fmt"Failed to load file {path}")
    return DocumentEditor.none

  return self.createAndAddView(document, append = append, slot = slot)

proc openFile*(self: LayoutService, path: string, slot: string = ""): Option[DocumentEditor] =
  defer:
    self.platform.requestRender()

  let path = self.vfs.normalize(path)

  log lvlInfo, fmt"[openFile] Open file '{path}'"
  if self.tryOpenExisting(path, false, append = false).getSome(ed):
    log lvlInfo, fmt"[openFile] found existing editor"
    return ed.some

  log lvlInfo, fmt"Open file '{path}'"

  let document = self.editors.getOrOpenDocument(path).getOr:
    log(lvlError, fmt"Failed to load file {path}")
    return DocumentEditor.none

  return self.createAndAddView(document, slot = slot)

proc closeView*(self: LayoutService, view: View, restoreHidden: bool = true) =
  ## Closes the current view.
  debugf"closeView '{view.desc()}'"

  let viewIndex = self.views.find(view)
  let hiddenViewIndex = self.hiddenViews.find(view)
  if viewIndex == -1 and hiddenViewIndex == -1:
    # Already closed
    log lvlError, &"Trying to close non existing view"
    return

  log lvlInfo, &"closeView {viewIndex}:{hiddenViewIndex}, restoreHidden: {restoreHidden}"

  if viewIndex != -1:
    self.views.delete viewIndex

  if hiddenViewIndex != -1:
    self.hiddenViews.delete hiddenViewIndex

  if restoreHidden and self.hiddenViews.len > 0 and viewIndex != -1:
    let viewToRestore = self.hiddenViews.pop
    self.views.insert(viewToRestore, viewIndex)

  if self.views.len == 0:
    if self.hiddenViews.len > 0:
      let view = self.hiddenViews.pop
      self.addView view
    else:
      discard
      # todo
      # open some default file/view

  view.close()
  if view of EditorView:
    self.editors.closeEditor(view.EditorView.editor)

  self.platform.requestRender()

proc closeView*(self: LayoutService, index: int, keepHidden: bool = true, restoreHidden: bool = true) {.expose("layout").} =
  ## Closes the current view. If `keepHidden` is true the view is not closed but hidden instead.
  log lvlInfo, &"closeView {index}, keepHidden: {keepHidden}, restoreHidden: {restoreHidden}"
  let view = self.views[index]
  self.views.delete index

  if restoreHidden and self.hiddenViews.len > 0:
    let viewToRestore = self.hiddenViews.pop
    self.views.insert(viewToRestore, index)

  if self.views.len == 0:
    if self.hiddenViews.len > 0:
      let view = self.hiddenViews.pop
      self.addView view
    else:
      discard
      # todo
      # self.help()

  if keepHidden:
    self.hiddenViews.add view
  else:
    view.close()
    if view of EditorView:
      self.editors.closeEditor(view.EditorView.editor)

  self.platform.requestRender()

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
    if self.getViewIndexForEditor(editor).getSome(index):
      self.closeView(index, keepHidden = false, restoreHidden = true)
    elif self.getHiddenViewForEditor(editor).getSome(index):
      self.hiddenViews.removeShift(index)
    else:
      editor.deinit()

  self.editors.documents.del(document)

  document.deinit()

  return true

proc closeCurrentView*(self: LayoutService, keepHidden: bool = true, restoreHidden: bool = true, closeOpenPopup: bool = true) {.expose("layout").} =
  debugf"closeCurrentView"
  if closeOpenPopup and self.popups.len > 0:
    self.popPopup()
  else:
    let view = self.layout.activeLeafView()
    if view == nil:
      log lvlError, &"Failed to destroy view"
      return

    discard self.layout.removeView(view)
    if keepHidden:
      self.hiddenViews.add(view)
    else:
      view.close()
      if view of EditorView:
        self.editors.closeEditor(view.EditorView.editor)

    # self.closeView(self.currentView, keepHidden, restoreHidden)
    self.currentView = self.currentView.clamp(0, self.views.len - 1)

proc closeOtherViews*(self: LayoutService, keepHidden: bool = true) {.expose("layout").} =
  ## Closes all views except for the current one. If `keepHidden` is true the views are not closed but hidden instead.

  let view = self.views[self.currentView]

  for i, view in self.views:
    if i != self.currentView:
      if keepHidden:
        self.hiddenViews.add view
      else:
        view.close()
        if view of EditorView:
          self.editors.closeEditor(view.EditorView.editor)

  self.views.setLen 1
  self.views[0] = view
  self.currentView = 0
  self.platform.requestRender()

proc moveCurrentViewToTop*(self: LayoutService) {.expose("layout").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    self.views.delete(self.currentView)
    self.views.insert(view, 0)
  self.currentView = 0
  self.platform.requestRender()

proc focusViewLeft*(self: LayoutService) {.expose("layout").} =
  let view = self.layout.tryGetViewLeft()
  if view != nil:
    debugf"focus view left {view.desc}"
    self.tryActivateView(view)
  self.platform.requestRender()

proc focusViewRight*(self: LayoutService) {.expose("layout").} =
  let view = self.layout.tryGetViewRight()
  if view != nil:
    debugf"focus view right {view.desc}"
    self.tryActivateView(view)
  self.platform.requestRender()

proc focusViewUp*(self: LayoutService) {.expose("layout").} =
  let view = self.layout.tryGetViewUp()
  if view != nil:
    debugf"focus view up {view.desc}"
    self.tryActivateView(view)
  self.platform.requestRender()

proc focusViewDown*(self: LayoutService) {.expose("layout").} =
  let view = self.layout.tryGetViewDown()
  if view != nil:
    debugf"focus view down {view.desc}"
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

proc setActiveIndex*(self: LayoutService, slot: string, index: int) {.expose("layout").} =
  let view = self.layout.getView(slot)
  if view != nil and view of Layout:
    let layout = view.Layout
    layout.activeIndex = index.clamp(0, layout.children.high)
  self.platform.requestRender()

proc moveCurrentViewPrev*(self: LayoutService) {.expose("layout").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    let index = (self.currentView + self.views.len - 1) mod self.views.len
    self.views.delete(self.currentView)
    self.views.insert(view, index)
    self.currentView = index
  self.platform.requestRender()

proc moveCurrentViewNext*(self: LayoutService) {.expose("layout").} =
  if self.views.len > 0:
    let view = self.views[self.currentView]
    let index = (self.currentView + 1) mod self.views.len
    self.views.delete(self.currentView)
    self.views.insert(view, index)
    self.currentView = index
  self.platform.requestRender()

proc openLastEditor*(self: LayoutService) {.expose("layout").} =
  debugf"openLastEditor"
  if self.hiddenViews.len > 0:
    let view = self.hiddenViews.pop()
    self.addView(view, addToHistory=false, append=false)

proc moveCurrentViewNextAndGoBack*(self: LayoutService) {.expose("layout").} =
  if self.views.len > 0 and self.hiddenViews.len > 0:
    let maxViews = self.uiSettings.maxViews.get()
    let lastView = self.hiddenViews.pop()
    let view = self.views[self.currentView]
    let index = (self.currentView + 1) mod maxViews
    if index < self.views.len:
      self.hiddenViews.add(self.views[index])
      self.views[self.currentView] = lastView
      self.views[index] = view
    else:
      self.views[self.currentView] = lastView
      self.views.add(view)

  self.platform.requestRender()

proc splitView*(self: LayoutService) {.expose("layout").} =
  defer:
    self.platform.requestRender()

  if self.tryGetCurrentEditorView().getSome(view):
    discard self.createAndAddView(view.document, append = true)

proc moveView*(self: LayoutService, slot: string) {.expose("layout").} =
  defer:
    self.platform.requestRender()

  let view = self.layout.activeLeafView()
  if view != nil:
    discard self.layout.removeView(view)
    let ejectedView = self.layout.addView(view, slot)
    if ejectedView != nil:
      self.hiddenViews.add(ejectedView)

addGlobalDispatchTable "layout", genDispatchTable("layout")
