import std/[tables, options, json, sugar]
import bumpy
import results
import platform/platform
import misc/[custom_async, custom_logger, rect_utils, myjsonutils, util, jsonex]
import scripting/expose
import workspaces/workspace
import service, platform_service, dispatch_tables, document, document_editor, view, events, config_provider, popup, selector_popup_builder, vfs, vfs_service, session
from scripting_api import EditorId

{.push gcsafe.}
{.push raises: [].}

logCategory "layout"

type
  Layout* = ref object of View
    children*: seq[View]
    activeIndex*: int
  HorizontalLayout* = ref object of Layout
  VerticalLayout* = ref object of Layout
  AlternatingLayout* = ref object of Layout

  TabLayout* = ref object of Layout

  MainLayout* = ref object of Layout

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

func serviceName*(_: typedesc[LayoutService]): string = "LayoutService"

addBuiltinService(LayoutService, PlatformService, ConfigService, DocumentEditorService, Workspace, VFSService, SessionService)

method desc*(self: View): string {.base.} = "View"
method desc*(self: EditorView): string =
  if self.document == nil:
    &"EditorView(pending '{self.path}')"
  else:
    &"EditorView('{self.document.filename}')"
method desc*(self: Layout): string = "Layout"
method desc*(self: MainLayout): string = "MainLayout"
method desc*(self: HorizontalLayout): string = "HorizontalLayout"
method desc*(self: VerticalLayout): string = "VerticalLayout"
method desc*(self: AlternatingLayout): string = "AlternatingLayout"
method desc*(self: TabLayout): string = "TabLayout"

method kind*(self: View): string {.base.} = ""
method kind*(self: EditorView): string = "editor"
method kind*(self: MainLayout): string = "main"
method kind*(self: HorizontalLayout): string = "horizontal"
method kind*(self: VerticalLayout): string = "vertical"
method kind*(self: AlternatingLayout): string = "alternating"
method kind*(self: TabLayout): string = "tab"

method display*(self: View): string {.base.} = ""
method display*(self: EditorView): string = self.document.filename

method activeLeafView*(self: View): View {.base.} = self
method activeLeafView*(self: Layout): View =
  if self.activeIndex in 0..self.children.high and self.children[self.activeIndex] != nil:
    return self.children[self.activeIndex].activeLeafView()

method removeView*(self: Layout, view: View): bool {.base.} =
  for i, c in self.children:
    if c == view:
      self.children.removeShift(i)
      self.activeIndex = min(self.activeIndex, self.children.high)
      return true
    if c of Layout:
      if c.Layout.removeView(view):
        return true

  return false

method removeView*(self: MainLayout, view: View): bool =
  for i, c in self.children:
    if c == view:
      self.children[i] = nil
      for k in countdown(self.children.high, 0):
        if self.children[k] != nil:
          self.activeIndex = k
          break
      return true
    if c of Layout:
      if c.Layout.removeView(view):
        return true

  return false

method saveLayout*(self: View): JsonNode {.base.} = nil
method saveLayout*(self: EditorView): JsonNode =
  result = newJObject()
  result["kind"] = self.kind.toJson
  result["path"] = self.document.filename.toJson
  result["state"] = self.editor.getStateJson()

method saveLayout*(self: Layout): JsonNode =
  result = newJObject()
  result["kind"] = self.kind.toJson
  var children = newJArray()
  for i, c in self.children:
    if c == nil:
      children.add newJNull()
    else:
      children.add c.saveLayout()

  result["activeIndex"] = self.activeIndex.toJson
  result["children"] = children

proc left*(self: MainLayout): View = self.children[0]
proc right*(self: MainLayout): View = self.children[1]
proc top*(self: MainLayout): View = self.children[2]
proc bottom*(self: MainLayout): View = self.children[3]
proc center*(self: MainLayout): View = self.children[4]
proc `left=`*(self: MainLayout, view: View) = self.children[0] = view
proc `right=`*(self: MainLayout, view: View) = self.children[1] = view
proc `top=`*(self: MainLayout, view: View) = self.children[2] = view
proc `bottom=`*(self: MainLayout, view: View) = self.children[3] = view
proc `center=`*(self: MainLayout, view: View) = self.children[4] = view

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

proc updateLayoutTree(self: LayoutService) =
  try:
    let config = self.config.runtime.get("layout", newJexObject())
    debugf"updateLayoutTree\n{config.pretty}"
    let view = self.createLayout(config)
    if view of Layout:
      self.layout = view.Layout
    else:
      self.layout = AlternatingLayout(children: @[view])
  except Exception as e:
    log lvlError, &"Failed to create layout from config: {e.msg}"

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
    return self.layout.saveLayout()

  proc load(data: JsonNode) =
    debugf"load layout from session:\n{data.pretty}"
    try:
      let view = self.createLayout(data.toJsonex)
      if view of Layout:
        self.layout = view.Layout
      else:
        self.layout = AlternatingLayout(children: @[view])
    except Exception as e:
      log lvlError, &"Failed to create layout from session data: {e.msg}\n{data.pretty}"

  self.session.addSaveHandler "layout", save, load

  # self.session.onSessionRestored.subscribe proc(_: SessionService) =
  #   discard

  discard self.config.runtime.onConfigChanged.subscribe proc(key: string) =
    if key == "" or key == "layout":
      self.updateLayoutTree()

  self.updateLayoutTree()

  return ok()

proc forEachViewImpl(self: Layout, cb: proc(view: View): bool {.gcsafe, raises: [].}): bool =
  for i, c in self.children:
    if c == nil:
      continue
    if cb(c):
      return
    if c of Layout:
      if c.Layout.forEachViewImpl(cb):
        return

proc forEachView*(self: Layout, cb: proc(view: View): bool {.gcsafe, raises: [].}) =
  discard self.forEachViewImpl(cb)

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

method layoutViews*(layout: Layout, props: LayoutProperties, bounds: Rect, views: int): seq[Rect] {.base.} =
  return @[bounds]

method layoutViews*(layout: HorizontalLayout, props: LayoutProperties, bounds: Rect, views: int): seq[Rect] =
  let mainSplit = props.props.getOrDefault("main-split", 0.5)
  result = @[]
  var rect = bounds
  for i in 0..<views:
    let ratio = if i == 0 and views > 1: mainSplit else: 1.0 / (views - i).float32
    let (view_rect, remaining) = rect.splitV(ratio.percent)
    rect = remaining
    result.add view_rect

method layoutViews*(layout: VerticalLayout, props: LayoutProperties, bounds: Rect, views: int): seq[Rect] =
  let mainSplit = props.props.getOrDefault("main-split", 0.5)
  result = @[]
  var rect = bounds
  for i in 0..<views:
    let ratio = if i == 0 and views > 1: mainSplit else: 1.0 / (views - i).float32
    let (view_rect, remaining) = rect.splitH(ratio.percent)
    rect = remaining
    result.add view_rect

method layoutViews*(layout: AlternatingLayout, props: LayoutProperties, bounds: Rect, views: int): seq[Rect] =
  let mainSplit = props.props.getOrDefault("main-split", 0.5)
  result = @[]
  var rect = bounds
  for i in 0..<views:
    let ratio = if i == 0 and views > 1: mainSplit elif i == views - 1: 1.0 else: 0.5
    let (view_rect, remaining) = if i mod 2 == 0: rect.splitV(ratio.percent) else: rect.splitH(ratio.percent)
    rect = remaining
    result.add view_rect

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

method addView*(self: Layout, view: View, slot: string = "") {.base.} =
  debugf"Layout.addView {view.desc()} to slot '{slot}'"
  self.children.add(view)

# method addView*(self: Layout, view: View, slot: string = "") {.base.} =
#   self.children.add(view)

method addView*(self: MainLayout, view: View, slot: string = "") =
  debugf"MainLayout.addView {view.desc()} to slot '{slot}'"
  var index = 4
  case slot
  of "":
    for i in 0..<self.children.len:
      if self.children[i] == nil:
        index = i
        break
  of "left": index = 0
  of "right": index = 1
  of "top": index = 2
  of "bottom": index = 3
  of "center": index = 4

  if self.children[index] != nil and self.children[index] of Layout:
    self.children[index].Layout.addView(view, slot)
  else:
    self.children[index] = view

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

  discard self.layout.removeView(view)
  self.layout.addView(view, slot)

  self.hiddenViews.removeSwap(view)
  if self.allViews.find(view) != -1:
    self.allViews.add view

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

proc createAndAddView*(self: LayoutService, document: Document, append: bool = false): Option[DocumentEditor] =
  debugf"createAndAddView '{document.filename}'"
  if self.editors.createEditorForDocument(document).getSome(editor):
    var view = EditorView(document: document, editor: editor)
    self.addView(view, append=append)
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
  return self.views.len

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

proc openWorkspaceFile*(self: LayoutService, path: string, append: bool = false): Option[DocumentEditor] =
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

  return self.createAndAddView(document, append = append)

proc openFile*(self: LayoutService, path: string): Option[DocumentEditor] =
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

  return self.createAndAddView(document)

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

proc nextView*(self: LayoutService) {.expose("layout").} =
  self.currentView = if self.views.len == 0: 0 else: (self.currentView + 1) mod self.views.len
  self.platform.requestRender()

proc prevView*(self: LayoutService) {.expose("layout").} =
  self.currentView = if self.views.len == 0: 0 else: (self.currentView + self.views.len - 1) mod self.views.len
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

addGlobalDispatchTable "layout", genDispatchTable("layout")
