#use status_line text_editor_component command_service
# text_editor_component is needed for OpenEditorPreviewer. todo: OpenEditorPreviewer shouldn't care about text editors
import std/[options, json]
import misc/[custom_async, id]
import service, view, popup, selector_popup_builder, dynamic_view
import document, document_editor
import ui/node
from scripting_api import EditorId

const currentSourcePath2 = currentSourcePath()
include module_base

type
  CreateView* = proc(config: JsonNode): View {.gcsafe, raises: [ValueError].}
  LayoutService* = ref object of DynamicService
    fallbackView*: View

  EditorView* = ref object of DynamicView
    path: string
    document*: Document # todo: remove
    editor*: DocumentEditor

  PushSelectorPopupImpl* = proc(self: LayoutService, builder: SelectorPopupBuilder): ISelectorPopup {.gcsafe, raises: [].}

func serviceName*(_: typedesc[LayoutService]): string = "LayoutService"

# DLL API
{.push modrtl, gcsafe, raises: [].}
proc layoutServicePopups*(self: LayoutService): seq[Popup]
proc layoutServiceAllViews(self: LayoutService): lent seq[View]
proc layoutServiceAddView(self: LayoutService, view: View, slot: string = "", focus: bool = true, addToHistory: bool = true)
proc layoutServiceAddViewRegisterView(self: LayoutService, view: View, last: bool = true)
proc layoutServiceShowView(self: LayoutService, view: View, slot: string = "", focus: bool = true, addToHistory: bool = true)
proc layoutServiceCloseView(self: LayoutService, view: View, keepHidden: bool = false, restoreHidden: bool = true)
proc layoutServiceTryGetCurrentView(self: LayoutService): Option[View]
proc layoutServiceFocusView(self: LayoutService, slot: string)
proc layoutServiceAddViewFactory(self: LayoutService, name: string, create: CreateView, override: bool = false)
proc layoutServicePushSelectorPopup(self: LayoutService, builder: SelectorPopupBuilder): ISelectorPopup
proc layoutServiceOpenFile(self: LayoutService, path: string, slot: string = ""): Option[DocumentEditor]
proc layoutServiceIsViewVisible(self: LayoutService, view: View): bool
proc layoutServiceTryActivateEditor(self: LayoutService, editor: DocumentEditor)
proc layoutServiceTryActivateView(self: LayoutService, view: View)
proc layoutServiceNewEditorView(editor: DocumentEditor, document: Document, id: Option[Id] = Id.none): EditorView
proc layoutServiceGetActiveEditor(self: LayoutService, includeCommandLine: bool = true, includePopups: bool = true): Option[DocumentEditor]
proc layoutServiceShowEditor(self: LayoutService, editorId: EditorId, slot: string = "", focus: bool = true)
proc layoutServiceGetView(self: LayoutService, id: Id): Option[View]
proc layoutServiceGetView2(self: LayoutService, id: int32): Option[View]
proc layoutServiceGetViewForEditor(self: LayoutService, editor: DocumentEditor): Option[View]
proc layoutServiceCloseActiveView(self: LayoutService, closeOpenPopup: bool = true, restoreHidden: bool = true)
proc layoutServiceGetPopupForId(self: LayoutService, id: EditorId): Option[Popup]
proc layoutServicePushPopup(self: LayoutService, popup: Popup)
proc layoutServicePopPopup(self: LayoutService, popup: Popup = nil)
proc layoutServiceCreateAndAddView(self: LayoutService, document: Document, slot: string = ""): Option[DocumentEditor]
proc layoutServiceTryCloseDocument(self: LayoutService, document: Document, force: bool): bool
proc layoutServiceHideActiveView(self: LayoutService, closeOpenPopup: bool = true)
proc layoutServiceHideOtherViews(self: LayoutService)
proc layoutServiceCloseOtherViews(self: LayoutService)
proc layoutServiceFocusViewLeft(self: LayoutService)
proc layoutServiceFocusViewRight(self: LayoutService)
proc layoutServiceFocusViewUp(self: LayoutService)
proc layoutServiceFocusViewDown(self: LayoutService)
proc layoutServiceFocusNextView(self: LayoutService, slot: string = "")
proc layoutServiceFocusPrevView(self: LayoutService, slot: string = "")
proc layoutServiceOpenPrevView(self: LayoutService)
proc layoutServiceOpenNextView(self: LayoutService)
proc layoutServiceOpenLastView(self: LayoutService)
proc layoutServiceSetLayout(self: LayoutService, layout: string)
proc layoutServiceSetActiveViewIndex(self: LayoutService, slot: string, index: int)
proc layoutServiceMoveActiveViewFirst(self: LayoutService)
proc layoutServiceMoveActiveViewPrev(self: LayoutService)
proc layoutServiceMoveActiveViewNext(self: LayoutService)
proc layoutServiceMoveActiveViewNextAndGoBack(self: LayoutService)
proc layoutServiceSplitView(self: LayoutService, slot: string = "")
proc layoutServiceMoveView(self: LayoutService, slot: string)
proc layoutServiceWrapLayout(self: LayoutService, layout: JsonNode, slot: string = "**")
proc layoutServiceOpen(self: LayoutService, path: string, slot: string = "")
proc layoutServiceLayout(self: LayoutService): View
proc layoutServiceRender(self: LayoutService, builder: UINodeBuilder): seq[OverlayFunction]
proc setSelectorPopupBuilderImpl*(impl: PushSelectorPopupImpl)
{.pop.}

{.push modrtl, gcsafe.}
proc layoutServicePromptString(self: LayoutService, title: string = ""): Future[Option[string]] {.async: (raises: []).}
proc layoutServicePrompt(self: LayoutService, choices: seq[string], title: string = ""): Future[Option[string]] {.async: (raises: []).}
{.pop.}

# Nice wrappers
{.push inline}
proc popups*(self: LayoutService): seq[Popup] = self.layoutServicePopups()
proc allViews*(self: LayoutService): lent seq[View] = self.layoutServiceAllViews()
proc addView*(self: LayoutService, view: View, slot: string = "", focus: bool = true, addToHistory: bool = true) = layoutServiceAddView(self, view, slot, focus, addToHistory)
proc registerView*(self: LayoutService, view: View, last = true) = layoutServiceAddViewRegisterView(self, view, last)
proc getView*(self: LayoutService, id: Id): Option[View] = layoutServiceGetView(self, id)
proc getView*(self: LayoutService, id: int32): Option[View] = layoutServiceGetView2(self, id)
proc getViewForEditor*(self: LayoutService, editor: DocumentEditor): Option[View] = layoutServiceGetViewForEditor(self, editor)
proc showView*(self: LayoutService, view: View, slot: string = "", focus: bool = true, addToHistory: bool = true) = self.layoutServiceShowView(view, slot, focus, addToHistory)
proc closeView*(self: LayoutService, view: View, keepHidden: bool = false, restoreHidden: bool = true) = self.layoutServiceCloseView(view, keepHidden, restoreHidden)
proc tryGetCurrentView*(self: LayoutService): Option[View] = self.layoutServiceTryGetCurrentView()
proc focusView*(self: LayoutService, slot: string) = layoutServiceFocusView(self, slot)
proc addViewFactory*(self: LayoutService, name: string, create: CreateView, override: bool = false) = self.layoutServiceAddViewFactory(name, create, override)
proc pushSelectorPopup*(self: LayoutService, builder: SelectorPopupBuilder): ISelectorPopup = self.layoutServicePushSelectorPopup(builder)
proc openFile*(self: LayoutService, path: string, slot: string = ""): Option[DocumentEditor] = self.layoutServiceOpenFile(path, slot)
proc isViewVisible*(self: LayoutService, view: View): bool = self.layoutServiceIsViewVisible(view)
proc promptString*(self: LayoutService, title: string = ""): Future[Option[string]] {.async: (raises: [])} = await layoutServicePromptString(self, title)
proc prompt*(self: LayoutService, choices: seq[string], title: string = ""): Future[Option[string]] {.gcsafe, async: (raises: [])} = await layoutServicePrompt(self, choices, title)
proc tryActivateEditor*(self: LayoutService, editor: DocumentEditor) = layoutServiceTryActivateEditor(self, editor)
proc tryActivateView*(self: LayoutService, view: View) = layoutServiceTryActivateView(self, view)
proc newEditorView*(editor: DocumentEditor, document: Document, id: Option[Id] = Id.none): EditorView = layoutServiceNewEditorView(editor, document, id)
proc getActiveEditor*(self: LayoutService, includeCommandLine: bool = true, includePopups: bool = true): Option[DocumentEditor] = layoutServiceGetActiveEditor(self, includeCommandLine, includePopups)
proc showEditor*(self: LayoutService, editorId: EditorId, slot: string = "", focus: bool = true) = layoutServiceShowEditor(self, editorId, slot, focus)
proc closeActiveView*(self: LayoutService, closeOpenPopup: bool = true, restoreHidden: bool = true) = layoutServiceCloseActiveView(self, closeOpenPopup, restoreHidden)
proc getPopupForId*(self: LayoutService, id: EditorId): Option[Popup] = layoutServiceGetPopupForId(self, id)
proc pushPopup*(self: LayoutService, popup: Popup) = layoutServicePushPopup(self, popup)
proc popPopup*(self: LayoutService, popup: Popup = nil) = layoutServicePopPopup(self, popup)
proc createAndAddView*(self: LayoutService, document: Document, slot: string = ""): Option[DocumentEditor] = layoutServiceCreateAndAddView(self, document, slot)
proc tryCloseDocument*(self: LayoutService, document: Document, force: bool): bool = layoutServiceTryCloseDocument(self, document, force)
proc hideActiveView*(self: LayoutService, closeOpenPopup: bool = true) = layoutServiceHideActiveView(self, closeOpenPopup)
proc hideOtherViews*(self: LayoutService) = layoutServiceHideOtherViews(self)
proc closeOtherViews*(self: LayoutService) = layoutServiceCloseOtherViews(self)
proc focusViewLeft*(self: LayoutService) = layoutServiceFocusViewLeft(self)
proc focusViewRight*(self: LayoutService) = layoutServiceFocusViewRight(self)
proc focusViewUp*(self: LayoutService) = layoutServiceFocusViewUp(self)
proc focusViewDown*(self: LayoutService) = layoutServiceFocusViewDown(self)
proc focusNextView*(self: LayoutService, slot: string = "") = layoutServiceFocusNextView(self, slot)
proc focusPrevView*(self: LayoutService, slot: string = "") = layoutServiceFocusPrevView(self, slot)
proc openPrevView*(self: LayoutService) = layoutServiceOpenPrevView(self)
proc openNextView*(self: LayoutService) = layoutServiceOpenNextView(self)
proc openLastView*(self: LayoutService) = layoutServiceOpenLastView(self)
proc setLayout*(self: LayoutService, layout: string) = layoutServiceSetLayout(self, layout)
proc setActiveViewIndex*(self: LayoutService, slot: string, index: int) = layoutServiceSetActiveViewIndex(self, slot, index)
proc moveActiveViewFirst*(self: LayoutService) = layoutServiceMoveActiveViewFirst(self)
proc moveActiveViewPrev*(self: LayoutService) = layoutServiceMoveActiveViewPrev(self)
proc moveActiveViewNext*(self: LayoutService) = layoutServiceMoveActiveViewNext(self)
proc moveActiveViewNextAndGoBack*(self: LayoutService) = layoutServiceMoveActiveViewNextAndGoBack(self)
proc splitView*(self: LayoutService, slot: string = "") = layoutServiceSplitView(self, slot)
proc moveView*(self: LayoutService, slot: string) = layoutServiceMoveView(self, slot)
proc wrapLayout*(self: LayoutService, layout: JsonNode, slot: string = "**") = layoutServiceWrapLayout(self, layout, slot)
proc open*(self: LayoutService, path: string, slot: string = "") = layoutServiceOpen(self, path, slot)
proc rootLayout*(self: LayoutService): View = layoutServiceLayout(self)
proc render*(self: LayoutService, builder: UINodeBuilder): seq[OverlayFunction] = layoutServiceRender(self, builder)
{.pop.}

proc showView*(self: LayoutService, viewId: Id, slot: string = "", focus: bool = true, addToHistory: bool = true) =
  if self.getView(viewId).getSome(view):
    self.showView(view, slot, focus, addToHistory)

proc showView*(self: LayoutService, viewId: int32, slot: string = "", focus: bool = true, addToHistory: bool = true) =
  if self.getView(viewId).getSome(view):
    self.showView(view, slot, focus, addToHistory)

proc closeView*(self: LayoutService, viewId: int32, keepHidden: bool = false, restoreHidden: bool = true) =
  if self.getView(viewId).getSome(view):
    self.closeView(view, keepHidden, restoreHidden)

proc getViews*(self: LayoutService, T: typedesc): seq[T] =
  var res = newSeq[T]()
  for v in self.allViews:
    if v of T:
      res.add v.T
  return res

# Implementation
when implModule:
  import std/[tables, sugar, deques, sets, os]
  import results
  import platform/platform
  import misc/[custom_logger, rect_utils, myjsonutils, util, jsonex]
  import workspaces/workspace
  import finder/[finder, previewer]
  import platform_service, events, config_provider, vfs, vfs_service, session, layouts, command_service, status_line, theme
  import nimsumtree/arc, command_line

  export layouts

  {.push gcsafe.}
  {.push raises: [].}

  logCategory "layout"

  type
    LayoutProperties* = ref object
      props: Table[string, float32]

    LayoutServiceImpl* = ref object of LayoutService
      platform: Platform
      workspace: Workspace
      config: ConfigService
      uiSettings: UiSettings
      editors: DocumentEditorService
      session: SessionService
      commands: CommandService
      commandLine: CommandLineService
      vfs: VFS
      vfs2: Arc[VFS2]
      mPopups: seq[Popup]
      layout*: Layout
      layoutName*: string = "default"
      layouts*: Table[string, Layout]
      layoutProps*: LayoutProperties
      maximizeView*: bool
      focusHistory*: Deque[Id]
      viewHistory*: Deque[Id]

      onEditorRegistered*: Event[DocumentEditor]
      onEditorDeregistered*: Event[DocumentEditor]

      pushSelectorPopupImpl: PushSelectorPopupImpl
      activeView*: View
      mAllViews*: seq[View]

      viewFactories: Table[string, CreateView]

  var gPushSelectorPopupImpl: PushSelectorPopupImpl

  # todo: the selector popup builder stuff should be in a separate module
  proc setSelectorPopupBuilderImpl*(impl: PushSelectorPopupImpl) =
    {.gcsafe.}:
      gPushSelectorPopupImpl = impl

  proc preRender*(self: LayoutService)

  proc layoutServicePopups*(self: LayoutService): seq[Popup] =
    let self = self.LayoutServiceImpl
    self.mPopups

  proc layoutServiceAllViews(self: LayoutService): lent seq[View] =
    let self = self.LayoutServiceImpl
    self.mAllViews

  proc layoutServiceAddViewFactory(self: LayoutService, name: string, create: CreateView, override: bool = false) =
    let self = self.LayoutServiceImpl
    if not override and name in self.viewFactories:
      log lvlError, &"Trying to define duplicate view factory '{name}'"
      return
    self.viewFactories[name] = create

  proc getExistingView(self: LayoutService, config: JsonNode): View {.raises: [].} =
    let self = self.LayoutServiceImpl
    if config.kind == JNull:
      return nil

    if config.hasKey("id"):
      try:
        if self.getView(config["id"].jsonTo(Id)).getSome(view):
          return view
      except CatchableError:
        discard
    log lvlError, &"Missing or invalid id for {config}"
    return nil

  proc layoutServiceAddViewRegisterView(self: LayoutService, view: View, last = true) =
    assert view != nil
    let self = self.LayoutServiceImpl
    if view notin self.mAllViews:
      if last:
        self.mAllViews.add view
      else:
        self.mAllViews.insert view, 0
      discard view.onMarkedDirty.subscribe () => self.platform.requestRender()

  proc getOrCreateView(self: LayoutService, config: JsonNode): View =
    let self = self.LayoutServiceImpl
    let kind = config["kind"].getStr
    for v in self.mAllViews:
      if v.kind == kind:
        return v

    if kind in self.viewFactories:
      try:
        result = self.viewFactories[kind](config)
        self.registerView(result)
        return result
      except ValueError as e:
        log lvlError, &"Failed to create view using view factory {kind}: {e.msg}"
    return nil

  proc updateLayoutTree(self: LayoutService) =
    let self = self.LayoutServiceImpl
    try:
      let config = self.config.runtime.get("ui.layout", newJexObject())

      var layoutReferences = newSeq[(string, string)]()

      proc createView(config: JsonNode): View =
        return self.getOrCreateView(config)

      for key, value in config.fields.pairs:
        if value.kind == JString:
          layoutReferences.add (key, value.getStr)
        else:
          let view = createLayout(value.toJson, createView = createView)
          if view != nil:
            if view of Layout:
              self.layouts[key] = view.Layout
            else:
              self.layouts[key] = AlternatingLayout(children: @[view])

      for (key, target) in layoutReferences:
        if target in self.layouts:
          let l = self.layouts[target].copy().Layout

          assert l != nil
          self.layouts[key] = l
        else:
          log lvlError, &"Unknown layout '{target}' referenced by 'ui.layout.{key}'"

      if self.layoutName in self.layouts:
        self.layout = self.layouts[self.layoutName]

      if self.layout == nil:
        self.layout = AlternatingLayout(children: @[])
    except Exception as e:
      log lvlError, &"[update-layout-tree] Failed to create layout from config: {e.msg}"

  func serviceName*(_: typedesc[LayoutServiceImpl]): string = "LayoutService"

  proc layoutServiceInit(self: LayoutServiceImpl): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    log lvlInfo, &"LayoutService.init"
    self.platform = self.services.getService(PlatformService).get.platform
    assert self.platform != nil
    self.config = self.services.getService(ConfigService).get
    self.editors = self.services.getService(DocumentEditorService).get
    self.vfs = self.services.getService(VFSService).get.vfs
    self.vfs2 = self.services.getService(VFSService).get.vfs2
    self.layout = HorizontalLayout()
    self.layout_props = LayoutProperties(props: {"main-split": 0.5.float32}.toTable)
    self.pushSelectorPopupImpl = ({.gcsafe.}: gPushSelectorPopupImpl)
    self.workspace = self.services.getService(Workspace).get
    self.session = self.services.getService(SessionService).get
    self.commands = self.services.getService(CommandService).get
    self.commandLine = self.services.getService(CommandLineService).get
    self.uiSettings = UiSettings.new(self.config.runtime)

    discard self.platform.onPreRender.subscribe (_: Platform) => self.preRender()

    self.addViewFactory "editor", proc(config: JsonNode): View {.raises: [ValueError].} =
      type Config = object
        id: Id
        documentId: Option[Id]
        path: string
        state: JsonNode
      let config = config.jsonTo(Config, Joptions(allowExtraKeys: true, allowMissingKeys: true))

      let document = self.editors.getOrOpenDocument(config.path, id = config.documentId).getOr:
        log(lvlError, fmt"Failed to restore file '{config.path}' from session")
        return nil

      assert document != nil
      let editor = self.editors.createEditorForDocument(document).getOr:
        log(lvlError, fmt"Failed to create editor for '{config.path}'")
        return nil

      if config.state != nil:
        editor.restoreStateJson(config.state)

      return newEditorView(editor, document, config.id.some)

    proc save(): JsonNode =
      result = newJObject()
      result["layout"] = self.layoutName.toJson

      var discardedViews = initHashSet[Id]()
      var viewStates = newJArray()
      for view in self.mAllViews:
        if view == nil:
          log lvlError, &"Failed to save view: null view"
          continue
        let state = view.saveState()
        if state != nil:
          if state.kind == JNull:
            log lvlError, &"Failed to save view {view.desc}: null state"
          else:
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
        if data == nil or data.kind != JObject:
          log lvlError, &"Failed to restore layout from session: Expected json object"
          return

        if data.hasKey("views"):
          let views = data["views"]
          checkJson views.kind == JArray, &"Expected array, got {views}"
          for state in views.elems:
            if state.kind != JObject:
              log lvlError, &"Failed to restore view from session: Expected json object, got {state}"
              continue
            if not state.hasKey("kind"):
              log lvlError, &"Failed to restore view from session state: missing field kind"
              continue

            let kindJson = state["kind"]
            if kindJson.kind != JString:
              log lvlError, &"Failed to restore view from session state: invalid field kind, expected string, got {kindJson}"
              continue

            let kind = kindJson.getStr
            if kind in self.viewFactories:
              self.registerView(self.viewFactories[kind](state))

            else:
              log lvlError, &"Invalid kind for view: '{kind}'"

        if data.hasKey("layouts"):
          let layouts = data["layouts"]
          checkJson layouts.kind == JObject, &"Expected object, got {layouts}"
          for key, state in layouts.fields.pairs:
            if key in self.layouts:
              proc resolve(id: Id): View = self.getView(id).get(nil)
              proc createView(config: JsonNode): View = self.getOrCreateView(config)
              proc getExistingView(config: JsonNode): View = self.getExistingView(config)
              self.layouts[key].createViews(state, resolve, createView, getExistingView)
          for layout in self.layouts.values:
            layout.validateActiveIndex()

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
            proc resolve(id: Id): View = self.getView(id).get(nil)
            proc createView(config: JsonNode): View = self.getOrCreateView(config)
            proc getExistingView(config: JsonNode): View = self.getExistingView(config)
            self.layouts[name].createViews(state, resolve, createView, getExistingView)
          except Exception as e:
            log lvlError, &"Failed to create layout from session data: {e.msg}\n{state.pretty}"

        for layout in self.layouts.values:
          layout.validateActiveIndex()

        if self.layoutName in states:
          self.layout = self.layouts[self.layoutName]

    self.updateLayoutTree()

    return ok()

  proc preRender*(self: LayoutService) =
    let self = self.LayoutServiceImpl
    self.layout.forEachVisibleView proc(v: View): bool =
      v.checkDirty()
      if v.dirty:
        self.platform.requestRender()
        self.platform.logNextFrameTime = true

  proc editorViewRender(self: EditorView, builder: UINodeBuilder): seq[OverlayRenderFunc] =
    self.resetDirty()
    self.editor.render(builder)

  proc editorViewDesc(self: EditorView): string =
    if self.document == nil:
      &"EditorView(pending '{self.path}')"
    else:
      &"EditorView('{self.document.filename}')"

  proc editorViewKind(self: EditorView): string = "editor"

  proc editorViewDisplay(self: EditorView): string = self.document.filename

  proc editorViewSaveState(self: EditorView): JsonNode =
    if not self.editor.config.get("editor.save-in-session", true):
      return nil

    result = newJObject()
    result["kind"] = self.kind.toJson
    result["id"] = self.id.toJson
    result["documentId"] = self.document.uniqueId.toJson
    result["path"] = self.document.filename.toJson
    result["state"] = self.editor.getStateJson()

  proc editorViewActivate(view: EditorView) =
    view.active = true
    view.editor.active = true

  proc editorViewDeactivate(view: EditorView) =
    view.active = false
    view.editor.active = false

  proc editorViewMarkDirty(view: EditorView, notify: bool = true) =
    view.markDirtyBase()
    view.editor.markDirty(notify)

  proc editorViewGetEventHandlers(view: EditorView, inject: Table[string, EventHandler]): seq[EventHandler] =
    view.editor.getEventHandlers(inject)

  proc editorViewGetActiveEditor(self: EditorView): Option[DocumentEditor] =
    self.editor.some

  proc layoutServiceNewEditorView(editor: DocumentEditor, document: Document, id: Option[Id] = Id.none): EditorView =
    let self = EditorView(editor: editor, document: document)
    if id.isSome:
      self.mId = id.get

    self.renderImpl = proc(self: View, builder: UINodeBuilder): seq[OverlayRenderFunc] = editorViewRender(self.EditorView, builder)
    # self.closeImpl = proc(self: View) = editorViewClose(self.EditorView)
    self.activateImpl = proc(self: View) = editorViewActivate(self.EditorView)
    self.deactivateImpl = proc(self: View) = editorViewDeactivate(self.EditorView)
    self.markDirtyImpl = proc (self: View, notify: bool) = editorViewMarkDirty(self.EditorView, notify)
    self.getEventHandlersImpl = proc (self: View, inject: Table[string, EventHandler]): seq[EventHandler] = editorViewGetEventHandlers(self.EditorView, inject)
    self.descImpl = proc (self: View): string = editorViewDesc(self.EditorView)
    self.kindImpl = proc (self: View): string = editorViewKind(self.EditorView)
    self.displayImpl = proc (self: View): string = editorViewDisplay(self.EditorView)
    self.saveStateImpl = proc (self: View): JsonNode = editorViewSaveState(self.EditorView)
    self.getActiveEditorImpl = proc (self: View): Option[DocumentEditor] = editorViewGetActiveEditor(self.EditorView)
    # self.onClick = editorViewHandleClick
    # self.onScroll = editorViewHandleScroll
    # self.onDrag = editorViewHandleDrag
    # self.onMove = editorViewHandleMove

    return self

  proc layoutServiceLayout(self: LayoutService): View = self.LayoutServiceImpl.layout

  proc layoutServiceTryGetCurrentView(self: LayoutService): Option[View] =
    let self = self.LayoutServiceImpl
    let view = self.layout.activeLeafView()
    if view != nil:
      view.some
    elif self.fallbackView != nil:
      self.fallbackView.some
    else:
      View.none

  proc tryGetCurrentEditorView*(self: LayoutService): Option[EditorView] =
    let self = self.LayoutServiceImpl
    if self.tryGetCurrentView().getSome(view) and view of EditorView:
      view.EditorView.some
    else:
      EditorView.none

  proc layoutServiceGetPopupForId(self: LayoutService, id: EditorId): Option[Popup] =
    let self = self.LayoutServiceImpl
    for popup in self.mPopups:
      if popup.id == id:
        return popup.some

    return Popup.none

  proc layoutServiceGetActiveEditor(self: LayoutService, includeCommandLine: bool = true, includePopups: bool = true): Option[DocumentEditor] =
    let self = self.LayoutServiceImpl
    if includeCommandLine and self.commandLine.commandLineMode:
      return self.commandLine.commandLineEditor.some

    if includePopups and self.mPopups.len > 0 and self.mPopups[self.mPopups.high].getActiveEditor().getSome(editor):
      return editor.some

    if self.tryGetCurrentView().getSome(view):
      return view.getActiveEditor()

    return DocumentEditor.none

  proc layoutServiceGetView(self: LayoutService, id: Id): Option[View] =
    ## Returns the index of the view for the given editor.
    let self = self.LayoutServiceImpl
    for i, view in self.mAllViews:
      if view.id == id:
        return view.some

    return View.none

  proc layoutServiceGetView2(self: LayoutService, id: int32): Option[View] =
    ## Returns the index of the view for the given editor.
    let self = self.LayoutServiceImpl
    for i, view in self.mAllViews:
      if view.id2 == id:
        return view.some

    return View.none

  proc layoutServiceGetViewForEditor(self: LayoutService, editor: DocumentEditor): Option[View] =
    ## Returns the index of the view for the given editor.
    let self = self.LayoutServiceImpl
    for i, view in self.mAllViews:
      if view.getActiveEditor() == editor.some:
        return view.some

    return View.none

  proc recordFocusHistoryEntry(self: LayoutService, view: View) =
    let self = self.LayoutServiceImpl
    if view == nil or view.id == idNone():
      return
    if self.focusHistory.len == 0 or self.focusHistory.peekLast() != view.id:
      self.focusHistory.addLast(view.id)

    # todo: make max size configurable
    while self.focusHistory.len > 1000:
      self.focusHistory.popFirst()

  proc layoutServiceAddView(self: LayoutService, view: View, slot: string = "", focus: bool = true, addToHistory: bool = true) =
    let self = self.LayoutServiceImpl
    # debugf"addView {view.desc()} slot = '{slot}', focus = {focus}, addToHistory = {addToHistory}"
    self.registerView(view)
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
      self.mAllViews.removeShift(ejectedView)
      self.mAllViews.add(ejectedView)

    # Force immediate load for new file since we're making it visible anyways
    if view of EditorView and view.EditorView.document.requiresLoad:
      view.EditorView.document.load()

    view.markDirty()
    self.platform.requestRender()

  proc layoutServiceCreateAndAddView(self: LayoutService, document: Document, slot: string = ""): Option[DocumentEditor] =
    let self = self.LayoutServiceImpl
    if self.editors.createEditorForDocument(document).getSome(editor):
      var view = newEditorView(editor, document)
      self.addView(view, slot=slot)
      return editor.some
    return DocumentEditor.none

  proc layoutServiceTryActivateView(self: LayoutService, view: View) =
    let self = self.LayoutServiceImpl
    if self.mPopups.len > 0:
      return
    let prevActiveView = self.layout.activeLeafView()
    let activated = self.layout.tryActivateView proc(v: View): bool =
      return view == v
    if activated:
      self.recordFocusHistoryEntry(prevActiveView)

    self.platform.requestRender()

  proc layoutServiceTryActivateEditor(self: LayoutService, editor: DocumentEditor) =
    let self = self.LayoutServiceImpl
    if self.mPopups.len > 0:
      return
    if self.getViewForEditor(editor).getSome(view):
      self.tryActivateView(view)

  proc layoutServicePushPopup(self: LayoutService, popup: Popup) =
    let self = self.LayoutServiceImpl
    popup.init()
    self.mPopups.add(popup)
    discard popup.onMarkedDirty.subscribe () => self.platform.requestRender()
    self.platform.requestRender()

  proc layoutServicePopPopup(self: LayoutService, popup: Popup = nil) =
    let self = self.LayoutServiceImpl
    if self.mPopups.len > 0 and (popup == nil or self.mPopups[self.mPopups.high] == popup):
      let popup = self.mPopups.pop()
      popup.cancel()
      popup.deinit()
    self.platform.requestRender()

  proc layoutServicePushSelectorPopup(self: LayoutService, builder: SelectorPopupBuilder): ISelectorPopup =
    let self = self.LayoutServiceImpl
    self.pushSelectorPopupImpl(self, builder)

  proc layoutServicePromptString(self: LayoutService, title: string = ""): Future[Option[string]] {.rtl, gcsafe, async: (raises: [])} =
    let self = self.LayoutServiceImpl
    defer:
      self.platform.requestRender()

    var fut = newFuture[Option[string]]("App.prompt")

    var builder = SelectorPopupBuilder()
    builder.scope = "prompt".some
    builder.title = title
    builder.scaleX = 0.5
    builder.scaleY = 0.5

    var res = newSeq[FinderItem]()
    let finder = newFinder(newStaticDataSource(res), filterAndSort=true)
    builder.finder = finder.some

    builder.handleCanceled = proc(popup: ISelectorPopup) =
      if not fut.finished:
        fut.complete(string.none)

    builder.customActions["accept"] = proc(popup: ISelectorPopup, args: JsonNode): bool {.gcsafe, raises: [].} =
      fut.complete(popup.getSearchString().some)
      popup.pop()
      true

    builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
      fut.complete(item.displayName.some)
      return true

    discard self.pushSelectorPopup(builder)
    try:
      return await fut
    except CatchableError:
      return string.none

  proc layoutServicePrompt(self: LayoutService, choices: seq[string], title: string = ""): Future[Option[string]] {.rtl, gcsafe, async: (raises: [])} =
    let self = self.LayoutServiceImpl
    defer:
      self.platform.requestRender()

    var fut = newFuture[Option[string]]("App.prompt")

    var builder = SelectorPopupBuilder()
    builder.scope = "prompt".some
    builder.title = title
    builder.scaleX = 0.5
    builder.scaleY = 0.5
    builder.sizeToContentY = true

    var res = newSeq[FinderItem]()
    for choice in choices:
      res.add FinderItem(
        displayName: choice,
      )
    let finder = newFinder(newStaticDataSource(res), filterAndSort=true)
    finder.filterThreshold = float.low
    builder.finder = finder.some

    builder.handleCanceled = proc(popup: ISelectorPopup) =
      fut.complete(string.none)

    builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
      fut.complete(item.displayName.some)
      return true

    discard self.pushSelectorPopup(builder)
    try:
      return await fut
    except CatchableError:
      return string.none

  iterator visibleEditors*(self: LayoutService): DocumentEditor =
    let self = self.LayoutServiceImpl
    ## Returns a list of all editors which are currently shown
    for view in self.layout.visibleLeafViews():
      if view of EditorView:
        yield view.EditorView.editor

  ###########################################################################

  template expose(name: static string, fun: untyped): untyped = fun

  proc changeSplitSize*(self: LayoutService, change: float, vertical: bool) =
    let self = self.LayoutServiceImpl
    discard self.layout.changeSplitSize(change, vertical)

  proc toggleMaximizeViewLocal*(self: LayoutService, slot: string = "**") =
    let self = self.LayoutServiceImpl
    let view = self.layout.getView(slot)
    if view != nil and view of Layout:
      let layout = view.Layout
      layout.maximize = not layout.maximize
      self.platform.requestRender()

  proc toggleMaximizeView*(self: LayoutService) =
    let self = self.LayoutServiceImpl
    self.maximizeView = not self.maximizeView
    self.platform.requestRender()

  proc setMaxViews*(self: LayoutService, slot: string, maxViews: int = int.high) =
    ## Set the maximum number of views that can be open at the same time
    let self = self.LayoutServiceImpl
    let view = self.layout.getView(slot)
    if view != nil and view of Layout:
      let layout = view.Layout
      layout.maxChildren = maxViews

    self.platform.requestRender()

  proc getHiddenViews*(self: LayoutService): seq[View] =
    let self = self.LayoutServiceImpl
    var res = self.mAllViews
    self.layout.forEachVisibleView proc(v: View): bool =
      res.removeShift(v)
    return res

  proc getVisibleViews*(self: LayoutService): seq[View] =
    let self = self.LayoutServiceImpl
    var res = newSeq[View]()
    self.layout.forEachVisibleView proc(v: View): bool =
      res.add(v)
    return res

  proc layoutServiceIsViewVisible(self: LayoutService, view: View): bool =
    let self = self.LayoutServiceImpl
    var res = false
    self.layout.forEachVisibleView proc(v: View): bool =
      if v == view:
        res = true
        return true
    return res

  proc getNumVisibleViews*(self: LayoutService): int =
    ## Returns the amount of visible views
    let self = self.LayoutServiceImpl
    var res = 0
    self.layout.forEachView proc(v: View): bool =
      if not (v of Layout):
        inc res
    return res

  proc getNumHiddenViews*(self: LayoutService): int =
    ## Returns the amount of hidden views
    let self = self.LayoutServiceImpl
    return self.getHiddenViews().len

  proc layoutServiceShowView(self: LayoutService, view: View, slot: string = "", focus: bool = true, addToHistory: bool = true) =
    ## Make the given view visible
    let self = self.LayoutServiceImpl

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

      if self.layout.contains(view):
        var child = view
        var p = self.layout.parentLayout(child)
        while p != nil:
          if not p.isVisible(child):
            discard self.layout.tryActivateView proc(v: View): bool =
              return v == child
          child = p
          p = self.layout.parentLayout(child)

      else:
        discard self.layout.removeView(view)
        self.addView(view, slot=slot, focus=false, addToHistory=addToHistory)

    self.platform.requestRender()

  proc layoutServiceShowEditor(self: LayoutService, editorId: EditorId, slot: string = "", focus: bool = true) =
    ## Make the given editor visible
    let self = self.LayoutServiceImpl
    let editor = self.editors.getEditor(editorId.EditorIdNew).getOr:
      log lvlError, &"No editor with id {editorId} exists"
      return

    assert editor.currentDocument.isNotNil

    log lvlInfo, &"showEditor editorId={editorId}, filename={editor.currentDocument.filename}"
    if self.getViewForEditor(editor).getSome(view):
      self.showView(view, slot, focus)

  proc getOrOpenEditor*(self: LayoutService, path: string): Option[EditorId] =
    ## Returns an existing editor for the given file if one exists,
    ## otherwise a new editor is created for the file.
    ## The returned editor will not be shown automatically.
    let self = self.LayoutServiceImpl
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
      return editor.id.EditorId.some

    return EditorId.none

  proc tryOpenExisting*(self: LayoutService, path: string, slot: string = ""): Option[DocumentEditor] =
    let self = self.LayoutServiceImpl
    # debugf"tryOpenExisting '{path}'"
    for i, view in self.mAllViews:
      if view of EditorView and view.EditorView.document.filename == path:
        log(lvlInfo, fmt"Reusing open editor in view {i}")
        self.showView(view, slot = slot)
        return view.EditorView.editor.some

    return DocumentEditor.none

  proc tryOpenExisting*(self: LayoutService, editor: EditorId, addToHistory = true, slot: string = ""): Option[DocumentEditor] =
    let self = self.LayoutServiceImpl
    # debugf"tryOpenExisting '{editor}'"
    for i, view in self.mAllViews:
      if view of EditorView and view.EditorView.editor.id == editor.EditorIdNew:
        log(lvlInfo, fmt"Reusing open editor in view {i}")
        self.showView(view, slot = slot)
        return view.EditorView.editor.some

    return DocumentEditor.none

  proc layoutServiceOpenFile(self: LayoutService, path: string, slot: string = ""): Option[DocumentEditor] =
    let self = self.LayoutServiceImpl
    defer:
      self.platform.requestRender()

    let path = self.vfs2.normalize(path)

    log lvlInfo, fmt"[openFile] Open file '{path}'"
    if self.tryOpenExisting(path, slot = slot).getSome(ed):
      log lvlInfo, fmt"[openFile] found existing editor"
      return ed.some

    log lvlInfo, fmt"Open file '{path}'"

    let document = self.editors.getOrOpenDocument(path).getOr:
      log(lvlError, fmt"Failed to load file {path}")
      return DocumentEditor.none

    return self.createAndAddView(document, slot = slot)

  proc layoutServiceCloseView(self: LayoutService, view: View, keepHidden: bool = false, restoreHidden: bool = true) =
    ## Closes the current view.
    let self = self.LayoutServiceImpl
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

      self.mAllViews.removeShift(view)
      view.close()
      if view of EditorView:
        self.editors.closeEditor(view.EditorView.editor)

    except LayoutError as e:
      log lvlError, "Failed to close view: " & e.msg

  proc layoutServiceTryCloseDocument(self: LayoutService, document: Document, force: bool): bool =
    let self = self.LayoutServiceImpl
    assert document != nil
    if document in self.editors.pinnedDocuments:
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

    self.editors.tryCloseDocument(document)
    return true

  proc layoutServiceHideActiveView(self: LayoutService, closeOpenPopup: bool = true) =
    ## Hide the active view, removing it from the current layout tree.
    ## To reopen the view, use commands like `show-last-hidden-view` or `choose-open`.
    let self = self.LayoutServiceImpl
    let view = self.layout.activeLeafView()
    if view == nil:
      return

    # todo: do we want to add it to the view history here?
    discard self.layout.removeView(view)
    self.layout.collapseTemporaryViews()
    self.platform.requestRender()

  proc layoutServiceCloseActiveView(self: LayoutService, closeOpenPopup: bool = true, restoreHidden: bool = true) =
    ## Permanently close the active view.
    let self = self.LayoutServiceImpl
    if closeOpenPopup and self.mPopups.len > 0:
      self.popPopup()
    else:
      let view = self.layout.activeLeafView()
      if view == nil:
        log lvlError, &"Failed to destroy view"
        return

      self.closeView(view, keepHidden = false, restoreHidden = restoreHidden)

  proc layoutServiceHideOtherViews(self: LayoutService) =
    ## Hides all views except for the active one.
    let self = self.LayoutServiceImpl
    let view = self.layout.activeLeafView()
    if view == nil:
      return

    let views = self.layout.leafViews()
    for v in views:
      if v != view:
        discard self.layout.removeView(v)
    self.layout.collapseTemporaryViews()

    self.platform.requestRender()

  proc layoutServiceCloseOtherViews(self: LayoutService) =
    ## Permanently closes all views except for the active one.
    let self = self.LayoutServiceImpl
    let view = self.layout.activeLeafView()
    if view == nil:
      return

    let views = self.layout.leafViews()
    for v in views:
      if v != view:
        self.closeView(v, restoreHidden = false)

    self.platform.requestRender()

  proc layoutServiceFocusViewLeft(self: LayoutService) =
    let self = self.LayoutServiceImpl
    let view = self.layout.tryGetViewLeft()
    if view != nil:
      self.tryActivateView(view)
    self.platform.requestRender()

  proc layoutServiceFocusViewRight(self: LayoutService) =
    let self = self.LayoutServiceImpl
    let view = self.layout.tryGetViewRight()
    if view != nil:
      self.tryActivateView(view)
    self.platform.requestRender()

  proc layoutServiceFocusViewUp(self: LayoutService) =
    let self = self.LayoutServiceImpl
    let view = self.layout.tryGetViewUp()
    if view != nil:
      self.tryActivateView(view)
    self.platform.requestRender()

  proc layoutServiceFocusViewDown(self: LayoutService) =
    let self = self.LayoutServiceImpl
    let view = self.layout.tryGetViewDown()
    if view != nil:
      self.tryActivateView(view)
    self.platform.requestRender()

  proc layoutServiceFocusView(self: LayoutService, slot: string) =
    let self = self.LayoutServiceImpl
    let view = self.layout.getView(slot)
    if view != nil:
      self.tryActivateView(view)
    self.platform.requestRender()

  proc layoutServiceFocusNextView(self: LayoutService, slot: string = "") =
    let self = self.LayoutServiceImpl
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

  proc layoutServiceFocusPrevView(self: LayoutService, slot: string = "") =
    let self = self.LayoutServiceImpl
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

  proc layoutServiceOpenPrevView(self: LayoutService) =
    let self = self.LayoutServiceImpl
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

  proc layoutServiceOpenNextView(self: LayoutService) =
    let self = self.LayoutServiceImpl
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

  proc layoutServiceOpenLastView(self: LayoutService) =
    let self = self.LayoutServiceImpl
    for i in countdown(self.mAllViews.high, 0):
      let view = self.mAllViews[i]
      if not self.layout.contains(view):
        let slot = self.layout.activeLeafSlot()
        log lvlInfo, &"openLastView viewId={view.id}, view={view.desc} in '{slot}'"
        self.showView(view, slot)
        self.platform.requestRender()
        break

  proc layoutServiceSetLayout(self: LayoutService, layout: string) =
    let self = self.LayoutServiceImpl
    if layout in self.layouts:
      self.layout = self.layouts[layout]
      self.layoutName = layout
      if self.layout.numLeafViews == 0:
        self.openLastView()
      self.platform.requestRender()
    else:
      log lvlError, &"Unknown layout '{layout}'"

  proc layoutServiceSetActiveViewIndex(self: LayoutService, slot: string, index: int) =
    let self = self.LayoutServiceImpl
    let view = self.layout.getView(slot)
    if view != nil and view of Layout:
      let layout = view.Layout
      layout.activeIndex = index.clamp(0, layout.children.high)
    self.platform.requestRender()

  proc layoutServiceMoveActiveViewFirst(self: LayoutService) =
    let self = self.LayoutServiceImpl
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

  proc layoutServiceMoveActiveViewPrev(self: LayoutService) =
    let self = self.LayoutServiceImpl
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

  proc layoutServiceMoveActiveViewNext(self: LayoutService) =
    let self = self.LayoutServiceImpl
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

  proc layoutServiceMoveActiveViewNextAndGoBack(self: LayoutService) =
    let self = self.LayoutServiceImpl
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

  proc layoutServiceSplitView(self: LayoutService, slot: string = "") =
    let self = self.LayoutServiceImpl
    defer:
      self.platform.requestRender()

    if self.tryGetCurrentEditorView().getSome(view):
      discard self.createAndAddView(view.document, slot = slot)

  proc layoutServiceMoveView(self: LayoutService, slot: string) =
    let self = self.LayoutServiceImpl
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

  proc layoutServiceWrapLayout(self: LayoutService, layout: JsonNode, slot: string = "**") =
    ## Wraps the active view with the specified layout.
    ## You can either pass a JSON object specifying a layout configuration (like in a settings file)
    ## or a string representing the name of a layout.
    let self = self.LayoutServiceImpl
    let newLayout = if layout.kind == JString:
      let name = layout.getStr
      if name in self.layouts:
        self.layouts[name].copy().Layout
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
        log lvlError, &"[wrap-layout] Failed to create layout from config: {e.msg}"
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

        var hiddenViews = self.mAllViews
        self.layout.forEachView proc(v: View): bool =
          hiddenViews.removeShift(v)
        if hiddenViews.len > 0:
          discard newLayout.addView(hiddenViews.last, "+")
    except LayoutError:
      discard

  proc chooseLayout(self: LayoutService) =
    let self = self.LayoutServiceImpl
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

  proc logLayout*(self: LayoutService) =
    let self = self.LayoutServiceImpl
    log lvlInfo, self.layout.saveLayout(initHashSet[Id]()).pretty

  proc logViews*(self: LayoutService) =
    let self = self.LayoutServiceImpl
    for v in self.mAllViews:
      if v != nil:
        debugf"{v}"

  proc layoutServiceOpen(self: LayoutService, path: string, slot: string = "") =
    ## Opens the specified file. Relative paths are relative to the main workspace.
    ## `path` - File path to open.
    ## `slot` - Where in the layout to put the opened file. If not specified the default slot is used.
    let self = self.LayoutServiceImpl
    var path = path
    let vfs = self.vfs2.getVFS(path, maxDepth = 1).vfs
    if vfs.isNotNil and vfs.get.prefix == "" and not path.isAbsolute:
      path = self.workspace.getAbsolutePath(path)
    discard self.openFile(path, slot)

  proc layoutServiceRender(self: LayoutService, builder: UINodeBuilder): seq[OverlayFunction] =
    let self = self.LayoutServiceImpl
    if self.layout == nil:
      return

    let newActiveView = self.layout.activeLeafView()
    if newActiveView != self.activeView and newActiveView != nil:
      if self.activeView != nil:
        self.activeView.deactivate()
      newActiveView.activate()
      self.activeView = newActiveView
      newActiveView.markDirty(notify=false)

    if self.maximizeView:
      let bounds = builder.currentParent.bounds
      builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h):
        let view = self.layout.activeLeafView()
        if view != nil:
          result.add view.createUI(builder)
        elif self.fallbackView != nil:
          result.add self.fallbackView.createUI(builder)
        else:
          builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

    else:
      let visibleViews = self.getNumVisibleViews()
      if visibleViews == 0 and self.fallbackView != nil:
        result.add self.fallbackView.createUI(builder)
      else:
        result.add self.layout.createUI(builder)

  proc chooseOpen*(self: LayoutService, preview: bool = true, scaleX: float = 0.8, scaleY: float = 0.8, previewScale: float = 0.6)

  proc init_module_layout*() {.cdecl, exportc, dynlib.} =
    getServices().addService(LayoutServiceImpl(
      initImpl: proc(self: Service): Future[Result[void, ref CatchableError]] {.gcsafe, async: (raises: []).} =
        return await self.LayoutServiceImpl.layoutServiceInit()
      ),
      @[
        PlatformService.serviceName,
        ConfigService.serviceName,
        DocumentEditorService.serviceName,
        Workspace.serviceName,
        VFSService.serviceName,
        SessionService.serviceName,
        CommandService.serviceName
      ])

    let cmds = getServiceChecked(CommandService)
    let self = getServiceChecked(LayoutServiceImpl)
    if getService(StatusLineService).getSome(statusLine):
      statusLine.addRenderer "layout", proc(builder: UINodeBuilder): seq[OverlayFunction] =
        let layout = self.layout.activeLeafLayout()
        let maximizedText = if self.maximizeView:
          "Fullscreen"
        elif layout != nil:
          let maxText = if layout.maxChildren == int.high: "∞" else: $layout.maxChildren
          if layout.maximize:
            fmt"Max 1/{maxText}"
          else:
            fmt"{layout.children.len}/{maxText}"
        else:
          ""
        let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = &"[Layout {self.layoutName} - {layout.desc} - {maximizedText}]")
        return @[]

      statusLine.addRenderer "layout.min", proc(builder: UINodeBuilder): seq[OverlayFunction] =
        let layout = self.layout.activeLeafLayout()
        let maximizedText = if self.maximizeView:
          "Fullscreen"
        elif layout != nil:
          let maxText = if layout.maxChildren == int.high: "∞" else: $layout.maxChildren
          if layout.maximize:
            fmt"Max 1/{maxText}"
          else:
            fmt"{layout.children.len}/{maxText}"
        else:
          ""
        let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = &"[{maximizedText}]")
        return @[]

    cmds.registerCommand "change-split-size", proc(change: float, vertical: bool) = self.changeSplitSize(change, vertical)
    cmds.registerCommand "toggle-maximize-view-local", proc(slot: Option[string]) = self.toggleMaximizeViewLocal(slot.get("**"))
    cmds.registerCommand "toggle-maximize-view", proc() = self.toggleMaximizeView()
    cmds.registerCommand "set-max-views", proc(slot: string, maxViews: Option[int]) = self.setMaxViews(slot, maxViews.get(int.high))
    cmds.registerCommand "get-num-visible-views", proc(): int = self.getNumVisibleViews()
    cmds.registerCommand "get-num-hidden-views", proc(): int = self.getNumHiddenViews()
    cmds.registerCommand "get-or-open-editor", proc(path: string): Option[EditorId] = self.getOrOpenEditor(path)
    cmds.registerCommand "hide-active-view", proc(closeOpenPopup: Option[bool]) = self.hideActiveView(closeOpenPopup.get(true))
    cmds.registerCommand "close-active-view", proc(closeOpenPopup: Option[bool], restoreHidden: Option[bool]) = self.layoutServiceCloseActiveView(closeOpenPopup.get(true), restoreHidden.get(true))
    cmds.registerCommand "hide-other-views", proc() = self.hideOtherViews()
    cmds.registerCommand "close-other-views", proc() = self.closeOtherViews()
    cmds.registerCommand "focus-view-left", proc() = self.focusViewLeft()
    cmds.registerCommand "focus-view-right", proc() = self.focusViewRight()
    cmds.registerCommand "focus-view-up", proc() = self.focusViewUp()
    cmds.registerCommand "focus-view-down", proc() = self.focusViewDown()
    cmds.registerCommand "focus-view", proc(slot: string) = self.layoutServiceFocusView(slot)
    cmds.registerCommand "focus-next-view", proc(slot: Option[string]) = self.focusNextView(slot.get(""))
    cmds.registerCommand "focus-prev-view", proc(slot: Option[string]) = self.focusPrevView(slot.get(""))
    cmds.registerCommand "open-prev-view", proc() = self.openPrevView()
    cmds.registerCommand "open-next-view", proc() = self.openNextView()
    cmds.registerCommand "open-last-view", proc() = self.openLastView()
    cmds.registerCommand "set-layout", proc(layout: string) = self.setLayout(layout)
    cmds.registerCommand "set-active-view-index", proc(slot: string, index: int) = self.setActiveViewIndex(slot, index)
    cmds.registerCommand "move-active-view-first", proc() = self.moveActiveViewFirst()
    cmds.registerCommand "move-active-view-prev", proc() = self.moveActiveViewPrev()
    cmds.registerCommand "move-active-view-next", proc() = self.moveActiveViewNext()
    cmds.registerCommand "move-active-view-next-and-go-back", proc() = self.moveActiveViewNextAndGoBack()
    cmds.registerCommand "split-view", proc(slot: Option[string]) = self.splitView(slot.get(""))
    cmds.registerCommand "move-view", proc(slot: string) = self.moveView(slot)
    cmds.registerCommand "wrap-layout", proc(layout: JsonNode, slot: Option[string]) = self.wrapLayout(layout, slot.get("**"))
    cmds.registerCommand "choose-layout", proc() = self.chooseLayout()
    cmds.registerCommand "log-layout", proc() = self.logLayout()
    cmds.registerCommand "log-views", proc() = self.logViews()
    cmds.registerCommand "open", proc(path: string, slot: Option[string]) = self.open(path, slot.get(""))
    cmds.registerCommand "choose-open", proc(preview: Option[bool], scaleX: Option[float], scaleY: Option[float], previewScale: Option[float]) = self.chooseOpen(preview.get(true), scaleX.get(0.8), scaleY.get(0.8), previewScale.get(0.6))

  import finder/[open_editor_previewer]
  proc chooseOpen*(self: LayoutService, preview: bool = true, scaleX: float = 0.8, scaleY: float = 0.8, previewScale: float = 0.6) =
    let self = self.LayoutServiceImpl
    defer:
      self.platform.requestRender()

    proc getItems(): seq[FinderItem] {.gcsafe, raises: [].} =
      var items = newSeq[FinderItem]()
      var hiddenViews = self.getHiddenViews()
      let activeView = self.layout.activeLeafView()

      for i in countdown(hiddenViews.high, 0):
        let v = hiddenViews[i]
        if v of EditorView:
          let view = v.EditorView
          let document = view.editor.currentDocument
          let isDirty = not document.requiresLoad and document.lastSavedRevision != document.revision
          let dirtyMarker = if isDirty: " * " else: "   "
          let (directory, name) = document.filename.splitPath
          let (root, relativeDirectory) = self.workspace.getRelativePathAndWorkspaceSync(directory).get(("", directory))
          items.add FinderItem(
            displayName: dirtyMarker & name,
            filterText: name,
            data: $view.editor.id,
            details: @[root // relativeDirectory],
          )

      self.layout.forEachView proc(v: View): bool =
        if v of EditorView:
          let view = v.EditorView
          let document = view.editor.currentDocument
          let isDirty = not document.requiresLoad and document.lastSavedRevision != document.revision
          let dirtyMarker = if isDirty: "* " else: "  "
          let activeMarker = if view.View == activeView:
            "#"
          else:
            "."
          let (directory, name) = document.filename.splitPath
          let (root, relativeDirectory) = self.workspace.getRelativePathAndWorkspaceSync(directory).get(("", directory))
          items.add FinderItem(
            displayName: activeMarker & dirtyMarker & name,
            filterText: name,
            data: $view.editor.id,
            details: @[root // relativeDirectory],
          )

      return items

    let source = newSyncDataSource(getItems)
    var finder = newFinder(source, filterAndSort=true)
    finder.filterThreshold = float.low

    let previewer = if preview:
      newOpenEditorPreviewer(self.services).Previewer.some
    else:
      Previewer.none

    var builder = SelectorPopupBuilder()
    builder.scope = "open".some
    builder.previewScale = previewScale
    builder.scaleX = scaleX
    builder.scaleY = scaleY
    builder.finder = finder.some
    builder.previewer = previewer

    builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
      let editorId = item.data.parseInt.EditorIdNew.catch:
        log lvlError, fmt"Failed to parse editor id from data '{item}'"
        return true

      if self.editors.getEditor(editorId).getSome(editor):
        if self.getViewForEditor(editor).getSome(view):
          self.showView(view)
      return true

    builder.customActions["close-selected"] = proc(popup: ISelectorPopup, args: JsonNode): bool =
      let item = popup.getSelectedItem().getOr:
        return true

      let editorId = item.data.parseInt.EditorIdNew.catch:
        log lvlError, fmt"Failed to parse editor id from data '{item}'"
        return true

      if self.editors.getEditor(editorId).getSome(editor):
        if self.getViewForEditor(editor).getSome(view):
          self.closeView(view, restoreHidden = false)
        else:
          self.editors.closeEditor(editor)

      source.retrigger()
      return true

    discard self.pushSelectorPopup builder
