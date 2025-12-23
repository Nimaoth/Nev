import std/[strutils, options, json, tables, sugar, strtabs, streams, sets, sequtils, enumerate, osproc]
import misc/[id, custom_async, custom_logger, util, connection, myjsonutils, event, response, jsonex]
import scripting/[expose]
import dap_client, dispatch_tables, config_provider, service, selector_popup_builder, events, view, session, document_editor, layout, platform_service
import text/text_editor
import text/language/[language_server_base, lsp_types]
import platform/platform
import finder/[previewer, finder, data_previewer]
import workspaces/workspace, plugin_service, vfs, vfs_service
import nimsumtree/[rope, buffer]
import vmath, bumpy

import chroma

import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil

{.push gcsafe.}
{.push raises: [].}

logCategory "debugger"

let debuggerCurrentLineId = newId()

type
  DebuggerConnectionKind = enum Tcp = "tcp", Stdio = "stdio", Websocket = "websocket"

  ActiveView* {.pure.} = enum Threads, StackTrace, Variables, Output
  DebuggerState* {.pure.} = enum None, Starting, Paused, Running

  VariableCursor* = object
    scope*: int
    path*: seq[tuple[index: int, varRef: VariablesReference]]

  BreakpointInfo* = object
    path: string
    enabled: bool = true
    breakpoint: SourceBreakpoint
    anchor: Option[Anchor]

  Debugger* = ref object of Service
    platform*: Platform
    events: EventHandlerService
    config: ConfigService
    plugins: PluginService
    workspace: Workspace
    editors: DocumentEditorService
    layout: LayoutService
    vfs: VFS
    client: Option[DapClient]
    lastConfiguration*: Option[string]
    activeView*: ActiveView = ActiveView.Variables
    currentThreadIndex*: int
    currentFrameIndex*: int
    maxVariablesScrollOffset*: float
    debuggerState*: DebuggerState = DebuggerState.None
    eventHandler: EventHandler
    threadsEventHandler: EventHandler
    stackTraceEventHandler: EventHandler
    outputEventHandler: EventHandler

    breakpointsEnabled*: bool = true

    lastEditor: Option[TextDocumentEditor]
    outputEditor*: TextDocumentEditor

    currentStopData*: OnStoppedData

    # Data setup in the editor and sent to the server
    breakpoints: Table[string, seq[BreakpointInfo]]
    documentCallbacks: Table[string, tuple[document: TextDocument, id: Id]]

    # Cached data from server
    timestamp*: int = 1
    threads: seq[ThreadInfo]
    stackTraces: Table[ThreadId, StackTraceResponse]
    scopes*: Table[(ThreadId, FrameId), Scopes]
    variables*: Table[(ThreadId, FrameId, VariablesReference), Variables]

    variableViews: seq[VariablesView]

    languageServer: LanguageServerDebugger

  ThreadsView* = ref object of View
    targetSelectionIndex*: Option[int]
    baseIndex*: int
    scrollOffset*: float
  StacktraceView* = ref object of View
    targetSelectionIndex*: Option[int]
    baseIndex*: int
    scrollOffset*: float
  VariablesView* = ref object of View
    sizeOffset*: Vec2
    renderHeader*: bool = true
    targetSelectionIndex*: Option[int]
    baseIndex*: VariableCursor
    scrollOffset*: float
    variablesCursor*: VariableCursor
    lastRenderedCursors*: seq[tuple[bounds: Rect, cursor: VariableCursor]]
    collapsedVariables*: HashSet[(ThreadId, FrameId, VariablesReference)]
    variablesFilter*: string = ""
    filteredVariables*: HashSet[(int, VariablesReference)]
    filteredCursors*: seq[VariableCursor]
    filterVersion: int = 0
    evaluation*: EvaluateResponse
    evaluationName*: string
    eventHandler: EventHandler

  OutputView* = ref object of View
  ToolbarView* = ref object of View

  LanguageServerDebugger* = ref object of LanguageServer
    debugger: Debugger
    evaluations: Table[tuple[file: string, range: Selection, expression: string], Response[EvaluateResponse]]

proc newLanguageServerDebugger(debugger: Debugger): LanguageServerDebugger =
  var server = new LanguageServerDebugger
  server.name = "debugger"
  server.debugger = debugger
  server.refetchWorkspaceSymbolsOnQueryChange = false
  return server

method dump*(self: ThreadsView): string = "ThreadsView" & $(self[])
method dump*(self: StacktraceView): string = "StacktraceView" & $(self[])
method dump*(self: VariablesView): string = "VariablesView" & $(self[])
method dump*(self: OutputView): string = "OutputView" & $(self[])
method dump*(self: ToolbarView): string = "ToolbarView" & $(self[])

method kind*(self: ThreadsView): string = "debugger.threads"
method kind*(self: StacktraceView): string = "debugger.stacktrace"
method kind*(self: VariablesView): string = "debugger.variables"
method kind*(self: OutputView): string = "debugger.output"
method kind*(self: ToolbarView): string = "debugger.toolbar"

method desc*(self: ThreadsView): string = "Threads"
method desc*(self: StacktraceView): string = "Stacktrace"
method desc*(self: VariablesView): string = "Variables"
method desc*(self: OutputView): string = "Output"
method desc*(self: ToolbarView): string = "Toolbar"

method display*(self: ThreadsView): string = "Threads"
method display*(self: StacktraceView): string = "Stacktrace"
method display*(self: VariablesView): string = "Variables"
method display*(self: OutputView): string = "Output"
method display*(self: ToolbarView): string = "Toolbar"

method copy*(self: ThreadsView): View = self
method copy*(self: StacktraceView): View = self
method copy*(self: VariablesView): View = self
method copy*(self: OutputView): View = self
method copy*(self: ToolbarView): View = self

method saveLayout*(self: ThreadsView, discardedViews: HashSet[Id]): JsonNode =
  result = newJObject()
  result["kind"] = "debugger.threads".toJson

method saveLayout*(self: StacktraceView, discardedViews: HashSet[Id]): JsonNode =
  result = newJObject()
  result["kind"] = "debugger.stacktrace".toJson

method saveLayout*(self: VariablesView, discardedViews: HashSet[Id]): JsonNode =
  result = newJObject()
  result["kind"] = "debugger.variables".toJson

method saveLayout*(self: OutputView, discardedViews: HashSet[Id]): JsonNode =
  result = newJObject()
  result["kind"] = "debugger.output".toJson

method saveLayout*(self: ToolbarView, discardedViews: HashSet[Id]): JsonNode =
  result = newJObject()
  result["kind"] = "debugger.toolbar".toJson

method saveState*(self: ThreadsView): JsonNode =
  result = newJObject()
  result["kind"] = "debugger.threads".toJson

method saveState*(self: StacktraceView): JsonNode =
  result = newJObject()
  result["kind"] = "debugger.stacktrace".toJson

method saveState*(self: VariablesView): JsonNode =
  result = newJObject()
  result["kind"] = "debugger.variables".toJson

method saveState*(self: OutputView): JsonNode =
  result = newJObject()
  result["kind"] = "debugger.output".toJson

method saveState*(self: ToolbarView): JsonNode =
  result = newJObject()
  result["kind"] = "debugger.toolbar".toJson

func serviceName*(_: typedesc[Debugger]): string = "Debugger"
addBuiltinService(Debugger, SessionService, DocumentEditorService, LayoutService, EventHandlerService, ConfigService)

proc applyBreakpointSignsToEditor(self: Debugger, editor: TextDocumentEditor)
proc handleAction(self: Debugger, action: string, arg: string): EventResponse
proc updateVariables(self: Debugger, containerVarRef: VariablesReference, maxDepth: int, force: bool = false) {.async.}
proc updateScopes(self: Debugger, threadId: ThreadId, frameIndex: int, force: bool) {.async.}
proc updateStackTrace(self: Debugger, threadId: Option[ThreadId]) {.async.}
proc getStackTrace(self: Debugger, threadId: Option[ThreadId]): Future[Option[ThreadId]] {.async.}
proc listenToDocumentChanges*(self: Debugger, document: TextDocument)

var gDebugger: Debugger = nil

proc getDebugger*(): Option[Debugger] =
  {.gcsafe.}:
    if gServices.isNil: return Debugger.none
    return gServices.getService(Debugger)

var gCurrentVariablesView: VariablesView = nil
proc pushVariablesView*(view: VariablesView): VariablesView =
  {.gcsafe.}:
    result = gCurrentVariablesView
    gCurrentVariablesView = view
proc popVariablesView*(view: VariablesView) =
  {.gcsafe.}:
    gCurrentVariablesView = view
proc getVariablesView*(): Option[VariablesView] =
  {.gcsafe.}:
    if gCurrentVariablesView != nil:
      return gCurrentVariablesView.some
    if gServices.isNil: return VariablesView.none
    if gServices.getService(LayoutService).get.tryGetCurrentView().getSome(view) and view of VariablesView:
      return view.VariablesView.some
    return VariablesView.none

static:
  addInjector(Debugger, getDebugger)
  addInjector(VariablesView, getVariablesView)

proc `&`*(ids: (ThreadId, FrameId), varRef: VariablesReference):
    tuple[thread: ThreadId, frame: FrameId, varRef: VariablesReference] =
  (ids[0], ids[1], varRef)

proc updateBreakpointsForFile(self: Debugger, path: string) =
  let doc = self.editors.getDocument(path)
  if doc.isNone or not (doc.get of TextDocument):
    log lvlWarn, &"Failed to update breakpoints for '{path}': document not found"
    return

  let document = doc.get.TextDocument
  self.listenToDocumentChanges(document)
  if not document.isReady:
    return

  self.breakpoints.withValue(path, val):
    for b in val[].mitems:
      if b.anchor.isSome:
        let resolved = b.anchor.get.summaryOpt(Point, document.buffer.snapshot)
        if resolved.isSome:
          b.breakpoint.line = resolved.get.row.int + 1
      b.anchor = document.buffer.snapshot.anchorAfter(point(b.breakpoint.line - 1, 0)).some

  for editor in self.editors.getEditorsForDocument(document):
    if editor of TextDocumentEditor:
      self.applyBreakpointSignsToEditor(editor.TextDocumentEditor)

proc flushBreakpointsForFile(self: Debugger, path: string) =
  self.updateBreakpointsForFile(path)
  if self.client.getSome(client):
    if self.breakpointsEnabled:
      var bs: seq[SourceBreakpoint]
      self.breakpoints.withValue(path, val):
        for b in val[]:
          if b.enabled:
            bs.add b.breakpoint

      asyncSpawn client.setBreakpoints(Source(path: self.vfs.localize(path).some), bs)
    else:
      asyncSpawn client.setBreakpoints(Source(path: self.vfs.localize(path).some), @[])

proc handleEditorRegistered*(self: Debugger, editor: DocumentEditor) =
  if not (editor of TextDocumentEditor):
    return
  let editor = editor.TextDocumentEditor
  if editor.document.isNil:
    return

  discard editor.document.addLanguageServer(self.languageServer)

  if not editor.document.isReady:
    var id = new Id
    id[] = editor.document.onLoaded.subscribe proc(args: tuple[document: TextDocument, changed: seq[Selection]]) =
      args.document.onLoaded.unsubscribe(id[])
      self.updateBreakpointsForFile(args.document.filename)
  else:
    self.updateBreakpointsForFile(editor.document.filename)

proc findVariable(self: VariablesView, filter: string) {.async.}
proc refilterVariables(self: VariablesView, debugger: Debugger) =
  inc self.filterVersion
  self.filteredVariables.clear()
  self.filteredCursors.setLen(0)
  if self.variablesFilter.len > 0:
    asyncSpawn self.findVariable(self.variablesFilter)
  debugger.platform.requestRender()

proc createVariablesView*(debugger: Debugger): VariablesView =
  let self = VariablesView()
  debugger.variableViews.add self

  return self

proc waitForApp(self: Debugger) {.async: (raises: []).} =
  try:
    # todo
    await sleepAsync(10.milliseconds)
  except CancelledError:
    discard

  let document = newTextDocument(self.services, createLanguageServer=false)
  document.usage = "debugger-output"
  document.setReadOnly(true)
  self.outputEditor = newTextEditor(document, self.services)
  self.outputEditor.usage = "debugger-output"
  self.outputEditor.renderHeader = true
  self.outputEditor.disableCompletions = true

  discard self.outputEditor.onMarkedDirty.subscribe () =>
    self.platform.requestRender()

  assignEventHandler(self.eventHandler, self.events.getEventHandlerConfig("debugger")):
    onAction:
      self.handleAction action, arg
    # onInput:
    #   self.handleInput input

  assignEventHandler(self.threadsEventHandler, self.events.getEventHandlerConfig("debugger.threads")):
    onAction:
      self.handleAction action, arg
    # onInput:
    #   self.handleInput input

  assignEventHandler(self.stackTraceEventHandler, self.events.getEventHandlerConfig("debugger.stacktrace")):
    onAction:
      self.handleAction action, arg
    # onInput:
    #   self.handleInput input

  assignEventHandler(self.outputEventHandler, self.events.getEventHandlerConfig("debugger.output")):
    onAction:
      self.handleAction action, arg
    # onInput:
    #   self.handleInput input

method init*(self: Debugger): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"Debugger.init"
  {.gcsafe.}:
    gDebugger = self

  self.languageServer = newLanguageServerDebugger(self)
  self.editors = self.services.getService(DocumentEditorService).get
  self.layout = self.services.getService(LayoutService).get
  self.vfs = self.services.getService(VFSService).get.vfs
  self.events = self.services.getService(EventHandlerService).get
  self.config = self.services.getService(ConfigService).get
  self.plugins = self.services.getService(PluginService).get
  self.platform = self.services.getService(PlatformService).get.platform
  self.workspace = self.services.getService(Workspace).get

  discard self.editors.onEditorRegistered.subscribe (e: DocumentEditor) {.gcsafe, raises: [].} =>
    self.handleEditorRegistered(e)

  self.layout.addViewFactory "debugger.threads", proc(config: JsonNode): View {.raises: [ValueError].} =
    return ThreadsView()

  self.layout.addViewFactory "debugger.stacktrace", proc(config: JsonNode): View {.raises: [ValueError].} =
    return StacktraceView()

  self.layout.addViewFactory "debugger.variables", proc(config: JsonNode): View {.raises: [ValueError].} =
    let view = self.createVariablesView()
    return view

  self.layout.addViewFactory "debugger.output", proc(config: JsonNode): View {.raises: [ValueError].} =
    return OutputView()

  self.layout.addViewFactory "debugger.toolbar", proc(config: JsonNode): View {.raises: [ValueError].} =
    return ToolbarView()

  proc save(): JsonNode =
    result = newJObject()
    var breakpoints = newJArray()
    for (file, bps) in self.breakpoints.pairs:
      for bp in bps:
        breakpoints.elems.add(%*{
          "path": bp.path,
          "enabled": bp.enabled,
          "breakpoint": bp.breakpoint,
        })

    result["breakpoints"] = breakpoints

  proc load(data: JsonNode) =
    try:
      log lvlInfo, &"Restore debugger from session"
      if data.hasKey("breakpoints"):
        for b in data["breakpoints"]:
          try:
            let bp = b.jsonTo(BreakpointInfo, opt = Joptions(allowMissingKeys: true, allowExtraKeys: true))

            if bp.path notin self.breakpoints:
              self.breakpoints[bp.path] = @[]

            self.breakpoints[bp.path].add bp

          except Exception as e:
            log lvlError, &"Failed to restore breakpoint from session: {e.msg}\n{b.pretty}"

      for path in self.breakpoints.keys:
        self.flushBreakpointsForFile(path)

    except Exception as e:
      log lvlError, &"Failed to restore debugger state from session: {e.msg}\n{data.pretty}"

  let session = self.services.getService(SessionService).get
  session.addSaveHandler "debugger", save, load

  asyncSpawn self.waitForApp()

  return ok()

proc currentThread*(self: Debugger): Option[ThreadInfo] =
  if self.currentThreadIndex >= 0 and self.currentThreadIndex < self.threads.len:
    return self.threads[self.currentThreadIndex].some
  return ThreadInfo.none

proc getThreads*(self: Debugger): lent seq[ThreadInfo] =
  return self.threads

proc getStackTrace*(self: Debugger, threadId: ThreadId): Option[StackTraceResponse] =
  if self.stackTraces.contains(threadId):
    return self.stackTraces[threadId].some
  return StackTraceResponse.none

proc isCollapsed*(self: VariablesView, ids: (ThreadId, FrameId, VariablesReference)): bool =
  ids in self.collapsedVariables

proc deleteLastVariableFilterChar(self: VariablesView) {.expose("debugger").} =
  if self.variablesFilter.len > 0:
    self.variablesFilter.setLen(self.variablesFilter.len - 1)
    self.refilterVariables(getDebugger().get)

proc clearVariableFilter(self: VariablesView) {.expose("debugger").} =
  if self.variablesFilter.len > 0:
    self.variablesFilter.setLen(0)
    self.refilterVariables(getDebugger().get)

proc isSelected*(self: VariablesView, r: VariablesReference, index: int): bool =
  return self.variablesCursor.path.len > 0 and
    self.variablesCursor.path[self.variablesCursor.path.high] == (index, r)

proc isScopeSelected*(self: VariablesView, index: int): bool =
  return self.variablesCursor.path.len == 0 and self.variablesCursor.scope == index

proc selectedVariable*(self: VariablesView): Option[tuple[index: int, varRef: VariablesReference]] =
  if self.variablesCursor.path.len > 0:
    return self.variablesCursor.path[self.variablesCursor.path.high].some

proc currentStackTrace*(self: Debugger): Option[ptr StackTraceResponse] =
  if self.currentThread().getSome(t):
    self.stackTraces.withValue(t.id, val):
      return val.some

proc currentStackFrame*(self: Debugger): Option[ptr StackFrame] =
  if self.currentStackTrace().getSome(stack) and
      self.currentFrameIndex in 0..stack[].stackFrames.high:
    return stack[].stackFrames[self.currentFrameIndex].addr.some

proc currentScopes*(self: Debugger): Option[ptr Scopes] =
  if self.currentThread().getSome(t) and self.currentStackFrame().getSome(frame):
    self.scopes.withValue((t.id, frame[].id), val):
      return val.some

proc currentVariablesContext*(self: Debugger): Option[tuple[thread: ThreadId, frame: FrameId]] =
  if self.currentThread().getSome(t) and self.currentStackFrame().getSome(frame):
    return (t.id, frame[].id).some

proc currentVariablesContext*(self: Debugger, varRef: VariablesReference):
    Option[tuple[thread: ThreadId, frame: FrameId, varRef: VariablesReference]] =
  if self.currentThread().getSome(t) and self.currentStackFrame().getSome(frame):
    return (t.id, frame[].id, varRef).some

proc tryOpenFileInWorkspace(self: Debugger, path: string, location: Cursor, slot: string = "") {.async.} =
  let editor = self.layout.openFile(path, slot = slot)

  if editor.getSome(editor) and editor of TextDocumentEditor:
    let textEditor = editor.TextDocumentEditor
    textEditor.targetSelection = location.toSelection
    textEditor.scrollToCursor(location, scrollBehaviour = CenterMargin.some)

    let lineSelection = ((location.line, 0), (location.line, textEditor.lineLength(location.line)))
    textEditor.addCustomHighlight(debuggerCurrentLineId, lineSelection, "editorError.foreground",
      color(1, 1, 1, 0.3))
    asyncSpawn textEditor.updateInlayHintsAsync()
    self.lastEditor = textEditor.some

proc reevaluateCursorRefs*(self: Debugger, cursor: VariableCursor): VariableCursor =
  let scopes = self.currentScopes().getOr:
    return VariableCursor()

  result.scope = cursor.scope.clamp(0, scopes[].scopes.high)
  if scopes[].scopes.len == 0:
    return

  let ids = self.currentVariablesContext().getOr:
    return

  let scope {.cursor.} = scopes[].scopes[result.scope]
  if not self.variables.contains(ids & scope.variablesReference) or
      self.variables[ids & scope.variablesReference].variables.len == 0:
    return

  var varRef = scope.variablesReference
  var variables = self.variables[ids & varRef].addr
  for i, item in cursor.path:
    let index = item.index.clamp(0, variables[].variables.high)
    if index < 0:
      break

    result.path.add (index, varRef)
    varRef = variables[].variables[index].variablesReference
    if not self.variables.contains(ids & varRef) or self.variables[ids & varRef].variables.len == 0:
      break

    variables = self.variables[ids & varRef].addr

proc reevaluateCurrentCursor*(self: VariablesView, debugger: Debugger) =
  self.variablesCursor = debugger.reevaluateCursorRefs(self.variablesCursor)
  debugger.platform.requestRender()

proc clampCursor*(self: Debugger, cursor: VariableCursor): VariableCursor =
  let scopes = self.currentScopes().getOr:
    return VariableCursor()

  result = cursor
  if result.scope >= scopes[].scopes.len:
    result = VariableCursor()
    return

  let ids = self.currentVariablesContext().getOr:
    result = VariableCursor()
    return

  while result.path.len > 0:
    let (index, varRef) = result.path[result.path.high]
    if not self.variables.contains(ids & varRef) or self.variables[ids & varRef].variables.len == 0:
      discard result.path.pop()
      continue

    result.path[result.path.high].index = index.clamp(0, self.variables[ids & varRef].variables.high)
    return

proc lastChild*(self: VariablesView, debugger: Debugger, cursor: VariableCursor): VariableCursor =
  let scopes = debugger.currentScopes().getOr:
    return VariableCursor()

  let ids = debugger.currentVariablesContext().getOr:
    result = VariableCursor()
    return

  result = cursor
  if result.path.len == 0 and result.scope in 0..scopes[].scopes.high:
    let scope = scopes[].scopes[result.scope]

    if self.isCollapsed(ids & scope.variablesReference):
      return

    if not debugger.variables.contains(ids & scope.variablesReference):
      return

    let variables {.cursor.} = debugger.variables[ids & scope.variablesReference]
    if variables.variables.len == 0:
      return

    result.path.add (variables.variables.high, scope.variablesReference)

  elif result.path.len == 0 and result.scope == -1:
    if not debugger.variables.contains(ids & self.evaluation.variablesReference):
      return

    let variables {.cursor.} = debugger.variables[ids & self.evaluation.variablesReference]
    if variables.variables.len == 0:
      return

    result.path.add (variables.variables.high, self.evaluation.variablesReference)

  while result.path.len > 0:
    let (index, r) = result.path[result.path.high]
    let variables {.cursor.} = debugger.variables[ids & r]
    result.path[result.path.high].index =
      result.path[result.path.high].index.clamp(0, variables.variables.high)
    if variables.variables.len == 0:
      return
    let childRef = variables.variables[index.clamp(0, variables.variables.high)].variablesReference
    if self.isCollapsed(ids & childRef):
      return
    if not debugger.variables.contains(ids & childRef) or debugger.variables[ids & childRef].variables.len == 0:
      return

    result.path.add (debugger.variables[ids & childRef].variables.high, childRef)

proc selectFirstVariable*(self: VariablesView) {.expose("debugger").} =
  let debugger = getDebugger().getOr:
    return
  if self.variablesCursor.scope == -1:
    # Evaluation
    self.variablesCursor.path.setLen(0)
  else:
    # Scopes
    self.variablesCursor = VariableCursor()
  debugger.platform.requestRender()

proc selectLastVariable*(self: VariablesView) {.expose("debugger").} =
  let debugger = getDebugger().getOr:
    return
  let scopes = debugger.currentScopes().getOr:
    return

  if self.variablesCursor.scope == -1:
    # Evaluation
    self.variablesCursor = self.lastChild(debugger, VariableCursor(scope: -1))
  else:
    # Scopes
    if scopes[].scopes.len == 0 or debugger.variables.len == 0:
      self.variablesCursor = VariableCursor()
      debugger.platform.requestRender()
      return

    self.variablesCursor = self.lastChild(debugger, VariableCursor(scope: scopes[].scopes.high))
  debugger.platform.requestRender()

proc prevThread*(self: Debugger) {.expose("debugger").} =
  if self.threads.len == 0:
    return

  dec self.currentThreadIndex
  if self.currentThreadIndex < 0:
    self.currentThreadIndex = self.threads.high

  self.currentFrameIndex = 0

  if self.currentThread().getSome(t) and not self.stackTraces.contains(t.id):
    asyncSpawn self.updateStackTrace(t.id.some)
  self.platform.requestRender()

proc nextThread*(self: Debugger) {.expose("debugger").} =
  if self.threads.len == 0:
    return

  inc self.currentThreadIndex
  if self.currentThreadIndex > self.threads.high:
    self.currentThreadIndex = 0

  self.currentFrameIndex = 0

  if self.currentThread().getSome(t) and not self.stackTraces.contains(t.id):
    asyncSpawn self.updateStackTrace(t.id.some)
  self.platform.requestRender()

proc prevStackFrame*(self: Debugger) {.expose("debugger").} =
  let thread = self.currentThread().getOr:
    return

  if not self.stackTraces.contains(thread.id):
    return

  let stack {.cursor.} = self.stackTraces[thread.id]

  dec self.currentFrameIndex
  if self.currentFrameIndex < 0:
    self.currentFrameIndex = stack.stackFrames.high

  for view in self.variableViews:
    view.variablesCursor = VariableCursor()

  if self.currentThread().getSome(t):
    asyncSpawn self.updateScopes(t.id, self.currentFrameIndex, force=false)
  self.platform.requestRender()

proc nextStackFrame*(self: Debugger) {.expose("debugger").} =
  let thread = self.currentThread().getOr:
    return

  if not self.stackTraces.contains(thread.id):
    return

  let stack {.cursor.} = self.stackTraces[thread.id]

  inc self.currentFrameIndex
  if self.currentFrameIndex > stack.stackFrames.high:
    self.currentFrameIndex = 0

  for view in self.variableViews:
    view.variablesCursor = VariableCursor()

  if self.currentThread().getSome(t):
    asyncSpawn self.updateScopes(t.id, self.currentFrameIndex, force=false)
  self.platform.requestRender()

proc openFileForCurrentFrame*(self: Debugger, slot: string = "") {.expose("debugger").} =
  if self.currentStackFrame().getSome(frame) and
      frame[].source.isSome and
      frame[].source.get.path.getSome(path):
    asyncSpawn self.tryOpenFileInWorkspace(path, (frame[].line - 1, frame[].column - 1), slot)

proc prevVariable*(self: VariablesView, skipChildren: bool = false) {.expose("debugger").} =
  let debugger = getDebugger().getOr:
    return
  let scopes = debugger.currentScopes().getOr:
    return

  if self.filteredCursors.len > 0:
    let i = self.filteredCursors.find(self.variablesCursor)
    if i != -1:
      let i2 = (i + self.filteredCursors.len - 1) mod self.filteredCursors.len
      self.variablesCursor = self.filteredCursors[i2]
      debugger.platform.requestRender()
      return
    else:
      self.variablesCursor = self.filteredCursors[self.filteredCursors.high]
      debugger.platform.requestRender()
      return

  if scopes[].scopes.len == 0 or debugger.variables.len == 0:
    return

  let ids = debugger.currentVariablesContext().getOr:
    return

  self.variablesCursor = debugger.clampCursor(self.variablesCursor)

  if self.variablesCursor.path.len == 0:
    if self.variablesCursor.scope > 0:
      dec self.variablesCursor.scope
      if not skipChildren:
        self.variablesCursor = self.lastChild(debugger, VariableCursor(scope: self.variablesCursor.scope))
      return

  else:
    let (index, currentRef) = self.variablesCursor.path[self.variablesCursor.path.high]
    if not debugger.variables.contains(ids & currentRef):
      return

    if index > 0:
      dec self.variablesCursor.path[self.variablesCursor.path.high].index
      if not skipChildren:
        self.variablesCursor = self.lastChild(debugger, self.variablesCursor)
      return

    if not skipChildren:
      discard self.variablesCursor.path.pop

proc nextVariable*(self: VariablesView, skipChildren: bool = false) {.expose("debugger").} =
  let debugger = getDebugger().getOr:
    return
  let scopes = debugger.currentScopes().getOr:
    return

  if self.filteredCursors.len > 0:
    let i = self.filteredCursors.find(self.variablesCursor)
    if i != -1:
      let i2 = (i + 1) mod self.filteredCursors.len
      self.variablesCursor = self.filteredCursors[i2]
      debugger.platform.requestRender()
      return
    else:
      self.variablesCursor = self.filteredCursors[0]
      debugger.platform.requestRender()
      return

  let ids = debugger.currentVariablesContext().getOr:
    return

  if scopes[].scopes.len == 0 or debugger.variables.len == 0:
    return

  self.variablesCursor = debugger.clampCursor(self.variablesCursor)

  if self.variablesCursor.path.len == 0:
    if self.variablesCursor.scope in 0..scopes[].scopes.high:
      let scope = scopes[].scopes[self.variablesCursor.scope]
      let collapsed = self.isCollapsed(ids & scope.variablesReference)
      if not skipChildren and
          debugger.variables.contains(ids & scope.variablesReference) and
          debugger.variables[ids & scope.variablesReference].variables.len > 0 and
          not collapsed:
        self.variablesCursor.path.add (0, scope.variablesReference)
        return

      if self.variablesCursor.scope + 1 < scopes[].scopes.len:
        self.variablesCursor = VariableCursor(scope: self.variablesCursor.scope + 1)
        return
    elif self.variablesCursor.scope == -1 and self.evaluation.variablesReference != 0.VariablesReference:
      self.variablesCursor.path.add (0, self.evaluation.variablesReference)
      return

  else:
    var descending = true
    var cursor = self.variablesCursor
    while cursor.path.len > 0:
      let (index, currentRef) = cursor.path[cursor.path.high]
      if debugger.variables.contains(ids & currentRef):
        let variables {.cursor.} = debugger.variables[ids & currentRef]

        if index < variables.variables.len:
          let childrenRef = variables.variables[index].variablesReference
          let collapsed = self.isCollapsed(ids & childrenRef)
          if not skipChildren and descending and childrenRef != 0.VariablesReference and
              debugger.variables.contains(ids & childrenRef) and
              debugger.variables[ids & childrenRef].variables.len > 0 and
              not collapsed:
            cursor.path.add (0, childrenRef)
            self.variablesCursor = cursor
            return

          if index < variables.variables.high:
            inc cursor.path[cursor.path.high].index
            self.variablesCursor = cursor
            return

      if skipChildren:
        return

      descending = false
      discard cursor.path.pop

    if cursor.scope >= 0 and cursor.scope + 1 < scopes[].scopes.len:
      cursor = VariableCursor(scope: cursor.scope + 1)
      self.variablesCursor = cursor
      return

    if cursor.scope >= 0:
      self.variablesCursor = self.lastChild(debugger, VariableCursor(
        scope: scopes[].scopes.high,
        path: @[(int.high, scopes[].scopes[scopes[].scopes.high].variablesReference)],
      ))

proc movePrev*(self: VariablesView, debugger: Debugger, cursor: VariableCursor): Option[VariableCursor] =
  let scopes = debugger.currentScopes().getOr:
    return VariableCursor.none

  if scopes[].scopes.len == 0 or debugger.variables.len == 0:
    return VariableCursor.none

  let ids = debugger.currentVariablesContext().getOr:
    return VariableCursor.none

  var cursor = debugger.clampCursor(cursor)
  if cursor.path.len == 0:
    if cursor.scope > 0:
      cursor = self.lastChild(debugger, VariableCursor(scope: cursor.scope - 1))
      return cursor.some

    return VariableCursor.none
  else:
    let (index, currentRef) = cursor.path[cursor.path.high]
    if not debugger.variables.contains(ids & currentRef):
      return VariableCursor.none

    if index > 0:
      dec cursor.path[cursor.path.high].index
      let l = cursor
      cursor = self.lastChild(debugger, cursor)
      return cursor.some

    discard cursor.path.pop
    return cursor.some

proc moveNext*(self: VariablesView, debugger: Debugger, cursor: VariableCursor): Option[VariableCursor] =
  let scopes = debugger.currentScopes().getOr:
    return

  let ids = debugger.currentVariablesContext().getOr:
    return

  if scopes[].scopes.len == 0 or debugger.variables.len == 0:
    return

  var cursor = debugger.clampCursor(cursor)
  if cursor.path.len == 0:
    if cursor.scope in 0..scopes[].scopes.high:
      let scope = scopes[].scopes[cursor.scope]
      let collapsed = self.isCollapsed(ids & scope.variablesReference)
      if debugger.variables.contains(ids & scope.variablesReference) and
          debugger.variables[ids & scope.variablesReference].variables.len > 0 and
          not collapsed:
        cursor.path.add (0, scope.variablesReference)
        return cursor.some

      if cursor.scope + 1 < scopes[].scopes.len:
        cursor = VariableCursor(scope: cursor.scope + 1)
        return cursor.some

    elif self.variablesCursor.scope == -1 and self.evaluation.variablesReference != 0.VariablesReference:
      cursor.path.add (0, self.evaluation.variablesReference)
      return cursor.some

    return VariableCursor.none

  else:
    var descending = true
    while cursor.path.len > 0:
      let (index, currentRef) = cursor.path[cursor.path.high]
      if not debugger.variables.contains(ids & currentRef):
        return VariableCursor.none

      let variables {.cursor.} = debugger.variables[ids & currentRef]

      if index < variables.variables.len:
        let childrenRef = variables.variables[index].variablesReference
        let collapsed = self.isCollapsed(ids & childrenRef)
        if descending and childrenRef != 0.VariablesReference and
            debugger.variables.contains(ids & childrenRef) and
            debugger.variables[ids & childrenRef].variables.len > 0 and
            not collapsed:
          cursor.path.add (0, childrenRef)
          return cursor.some

        if index < variables.variables.high:
          inc cursor.path[cursor.path.high].index
          return cursor.some

      descending = false
      discard cursor.path.pop

    if cursor.scope != -1 and cursor.scope + 1 < scopes[].scopes.len:
      cursor = VariableCursor(scope: cursor.scope + 1)
      return cursor.some

    return VariableCursor.none

proc expandVariable*(self: VariablesView) {.expose("debugger").} =
  let debugger = getDebugger().getOr:
    return
  let scopes = debugger.currentScopes().getOr:
    log lvlError, &"Failed to expand scope, no scope"
    return

  let ids = debugger.currentVariablesContext().getOr:
    log lvlError, &"Failed to expand scope, no ids"
    return

  if scopes[].scopes.len == 0 or debugger.variables.len == 0:
    log lvlError, &"Failed to expand scope, no scopes or variables"
    return

  self.variablesCursor = debugger.clampCursor(self.variablesCursor)
  if self.selectedVariable().getSome(v):
    if debugger.variables.contains(ids & v.varRef):
      let va {.cursor.} = debugger.variables[ids & v.varRef].variables[v.index]

      if va.variablesReference != 0.VariablesReference:
        self.collapsedVariables.excl ids & va.variablesReference
        asyncSpawn debugger.updateVariables(va.variablesReference, 0)
    else:
      log lvlError, &"Failed to find variable {ids & v.varRef}"

  elif self.variablesCursor.scope in 0..scopes[].scopes.high:
    self.collapsedVariables.excl ids & scopes[].scopes[self.variablesCursor.scope].variablesReference

  self.refilterVariables(debugger)
  debugger.platform.requestRender()

proc expandVariableChildren*(self: VariablesView) {.expose("debugger").} =
  let debugger = getDebugger().getOr:
    return
  let scopes = debugger.currentScopes().getOr:
    log lvlError, &"Failed to expand scope, no scope"
    return

  let ids = debugger.currentVariablesContext().getOr:
    log lvlError, &"Failed to expand scope, no ids"
    return

  if scopes[].scopes.len == 0 or debugger.variables.len == 0:
    log lvlError, &"Failed to expand scope, no scopes or variables"
    return

  self.variablesCursor = debugger.clampCursor(self.variablesCursor)
  if self.selectedVariable().getSome(v):
    if debugger.variables.contains(ids & v.varRef):
      let va {.cursor.} = debugger.variables[ids & v.varRef].variables[v.index]

      if va.variablesReference != 0.VariablesReference:
        self.collapsedVariables.excl ids & va.variablesReference

        if debugger.variables.contains(ids & va.variablesReference):
          for childVariable in debugger.variables[ids & va.variablesReference].variables:
            self.collapsedVariables.excl ids & childVariable.variablesReference
            if childVariable.variablesReference != 0.VariablesReference:
              asyncSpawn debugger.updateVariables(childVariable.variablesReference, 0)
        else:
          asyncSpawn debugger.updateVariables(va.variablesReference, 0)
    else:
      log lvlError, &"Failed to find variable {ids & v.varRef}"

  elif self.variablesCursor.scope in 0..scopes[].scopes.high:
    self.collapsedVariables.excl ids & scopes[].scopes[self.variablesCursor.scope].variablesReference

  debugger.platform.requestRender()

proc collapseVariable*(self: VariablesView) {.expose("debugger").} =
  let debugger = getDebugger().getOr:
    return
  let scopes = debugger.currentScopes().getOr:
    return

  let ids = debugger.currentVariablesContext().getOr:
    return

  if scopes[].scopes.len == 0 or debugger.variables.len == 0:
    return

  self.variablesCursor = debugger.clampCursor(self.variablesCursor)
  if self.selectedVariable().getSome(v):
    if debugger.variables.contains(ids & v.varRef):
      let va {.cursor.} = debugger.variables[ids & v.varRef].variables[v.index]

      if va.variablesReference == 0.VariablesReference or
        (ids & va.variablesReference) in self.collapsedVariables or
        not debugger.variables.contains(ids & va.variablesReference):

        let currentLen = self.variablesCursor.path.len
        if currentLen > 0:
          discard self.variablesCursor.path.pop()

      elif va.variablesReference != 0.VariablesReference:
        self.collapsedVariables.incl ids & va.variablesReference

  elif self.variablesCursor.scope in 0..scopes[].scopes.high:
    self.collapsedVariables.incl ids & scopes[].scopes[self.variablesCursor.scope].variablesReference

  debugger.platform.requestRender()

proc expandOrCollapseVariable*(self: VariablesView) {.expose("debugger").} =
  let debugger = getDebugger().getOr:
    return
  let ids = debugger.currentVariablesContext().getOr:
    return
  if self.variablesCursor.path.len > 0:
    let varIndex = self.variablesCursor.path[^1]
    let key = ids & varIndex.varRef
    if key in debugger.variables:
      let vars {.cursor.} = debugger.variables[key]
      if varIndex.index in 0..vars.variables.high:
        let va {.cursor.} = vars.variables[varIndex.index]
        if va.variablesReference != 0.VariablesReference:
          if self.isCollapsed(ids & va.variablesReference) or (ids & va.variablesReference) notin debugger.variables:
            self.expandVariable()
          else:
            self.collapseVariable()
          return

proc collapseVariableChildren*(self: VariablesView) {.expose("debugger").} =
  let debugger = getDebugger().getOr:
    return
  let scopes = debugger.currentScopes().getOr:
    return

  let ids = debugger.currentVariablesContext().getOr:
    return

  if scopes[].scopes.len == 0 or debugger.variables.len == 0:
    return

  self.variablesCursor = debugger.clampCursor(self.variablesCursor)
  if self.selectedVariable().getSome(v):
    if debugger.variables.contains(ids & v.varRef):
      let va {.cursor.} = debugger.variables[ids & v.varRef].variables[v.index]

      if debugger.variables.contains(ids & va.variablesReference):
        for childVariable in debugger.variables[ids & va.variablesReference].variables:
          self.collapsedVariables.incl ids & childVariable.variablesReference

  elif self.variablesCursor.scope in 0..scopes[].scopes.high:
    self.collapsedVariables.incl ids & scopes[].scopes[self.variablesCursor.scope].variablesReference

  debugger.platform.requestRender()

proc evaluateHoverAsync(self: Debugger, useMouseHover: bool) {.async.} =
  let frame = self.currentStackFrame()
  if frame.isNone:
    return

  if self.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    let editor = view.editor.TextDocumentEditor
    let timestamp = self.timestamp
    if self.client.getSome(client):
      var range = if useMouseHover:
        editor.mouseHoverLocation.toSelection
      else:
        editor.selection
      if range.isEmpty:
        let move = self.config.runtime.get("debugger.hover.move", "(word)")
        range = editor.getSelectionForMove(range.last, move, 1, true)
      let expression = editor.getText(range)
      var evaluation = await client.evaluate(expression, editor.document.localizedPath, range.first.line, range.first.column, frame.get.id)
      if evaluation.isError:
        log lvlWarn, &"Failed to evaluate {expression}: {evaluation}"
        return

      if timestamp != self.timestamp:
        return

      let view = self.createVariablesView()
      view.renderHeader = false
      view.evaluation = evaluation.result
      view.evaluationName = expression
      view.variablesCursor.scope = -1
      editor.showHover(view, range.first)
      if evaluation.result.variablesReference != 0.VariablesReference:
        asyncSpawn self.updateVariables(evaluation.result.variablesReference, 0)

proc evaluateHover*(self: Debugger) {.expose("debugger").} =
  asyncSpawn self.evaluateHoverAsync(useMouseHover = false)

proc evaluateMouseHover*(self: Debugger) {.expose("debugger").} =
  asyncSpawn self.evaluateHoverAsync(useMouseHover = true)

proc stopDebugSession*(self: Debugger) {.expose("debugger").} =
  log lvlInfo, "[stopDebugSession] Stopping session"
  if self.client.isNone:
    log lvlWarn, "No active debug session"
    return

  if self.lastEditor.isSome:
    self.lastEditor.get.clearCustomHighlights(debuggerCurrentLineId)
    self.lastEditor.get.updateInlayHints()

  asyncSpawn self.client.get.disconnect(restart=false)
  self.client.get.deinit()
  self.client = DapClient.none

  self.debuggerState = DebuggerState.None
  self.threads.setLen 0
  self.stackTraces.clear()
  self.variables.clear()
  self.platform.requestRender()

proc stopDebugSessionDelayedAsync*(self: Debugger) {.async.} =
  let oldClient = self.client.getOr:
    return

  await sleepAsync(500.milliseconds)

  # Make sure to not stop the debug session if the client changed since this was triggered
  if self.client.getSome(client) and client == oldClient:
    self.stopDebugSession()

proc stopDebugSessionDelayed*(self: Debugger) {.expose("debugger").} =
  asyncSpawn self.stopDebugSessionDelayedAsync()

template tryGet(json: untyped, field: untyped, T: untyped, default: untyped, els: untyped): untyped =
  block:
    let val = json.fields.getOrDefault(field, default)
    val.jsonTo(T).catch:
      els

# todo
# proc getFreePort*(): Port =
#   var server = newAsyncHttpServer()
#   server.listen(Port(0))
#   let port = server.getPort()
#   server.close()
#   return port

proc createConnectionWithType(self: Debugger, name: string): Future[Option[Connection]] {.async.} =
  log lvlInfo, &"Try create debugger connection '{name}'"

  let config = self.config.runtime.get("debugger.type." & name, newJexNull())
  if config.isNil or config.kind != JObject:
    log lvlError, &"No/invalid debugger type configuration with name '{name}' found: {config}"
    return Connection.none

  let connectionType = config.tryGet("connection", DebuggerConnectionKind, "stdio".newJexString):
    log lvlError, &"No/invalid debugger connection type in {config.pretty}"
    return Connection.none

  case connectionType
  of Tcp:
    if config.hasKey("path"):
      let path = config.tryGet("path", string, newJexNull()):
        log lvlError, &"No/invalid debugger executable path in {config.pretty}"
        return Connection.none
      let args = config.tryGet("args", seq[string], newJexArray()):
        log lvlError, &"No/invalid debugger args in {config.pretty}"
        return Connection.none

      # let port = getFreePort().int
      let port = config.tryGet("port", int, 5678.newJexInt):
        log lvlError, &"No/invalid debugger port in {config.pretty}"
        return Connection.none

      log lvlInfo, &"Start process {path} {args}"
      discard startProcess(path, args = args, options = {poUsePath, poDaemon})

      # todo: need to wait for process to open port?
      debugf"wait..."
      await sleepAsync(1500.milliseconds)

      try:
        debugf"connect..."
        let connection = newAsyncSocketConnection("127.0.0.1", port.Port).await
        debugf"connected"
        return connection.Connection.some
      except CatchableError as e:
        log lvlError, &"Failed to connect to debug adapter localhost:{port}"
        return Connection.none

    else:
      let host = config.tryGet("host", string, "127.0.0.1".newJexString):
        log lvlError, &"No/invalid debugger host in {config.pretty}"
        return Connection.none
      let port = config.tryGet("port", int, 5678.newJexInt):
        log lvlError, &"No/invalid debugger port in {config.pretty}"
        return Connection.none
      try:
        return newAsyncSocketConnection(host, port.Port).await.Connection.some
      except CatchableError as e:
        log lvlError, &"Failed to connect to debug adapter {host}:{port}"
        return Connection.none

    # let host = config.tryGet("host", string, "127.0.0.1".newJexString):
    #   log lvlError, &"No/invalid debugger host in {config.pretty}"
    #   return Connection.none
    # let port = config.tryGet("port", int, 5678.newJexInt):
    #   log lvlError, &"No/invalid debugger port in {config.pretty}"
    #   return Connection.none
    # try:
    #   return newAsyncSocketConnection(host, port.Port).await.Connection.some
    # except CatchableError as e:
    #   log lvlError, &"Failed to connect to debug adapter {host}:{port}"
    #   return Connection.none


  of Stdio:
    let exePath = config.tryGet("path", string, newJexNull()):
      log lvlError, &"No/invalid debugger path in {config.pretty}"
      return Connection.none
    let args = config.tryGet("args", seq[string], newJexArray()):
      log lvlError, &"No/invalid debugger args in {config.pretty}"
      return Connection.none
    return newAsyncProcessConnection(exePath, args).await.Connection.some

  of Websocket:
    log lvlError, &"Websocket connection not implemented yet!"

  return Connection.none

proc updateStackTrace(self: Debugger, threadId: Option[ThreadId]) {.async.} =
  discard await self.getStackTrace(threadId)

proc getStackTrace(self: Debugger, threadId: Option[ThreadId]): Future[Option[ThreadId]] {.async.} =
  let threadId = if threadId.getSome(id):
    id
  elif self.currentThread.getSome(thread):
    thread.id
  else:
    return ThreadId.none

  let timestamp = self.timestamp
  if self.client.getSome(client):
    var stackTrace = await client.stackTrace(threadId)
    if stackTrace.isError:
      log lvlError, &"Failed to get stacktrace for thread {threadId}: {stackTrace}"
      return ThreadId.none
    if timestamp != self.timestamp:
      return
    self.stackTraces[threadId] = stackTrace.result
    self.currentFrameIndex = 0
    self.platform.requestRender()

    asyncSpawn self.updateScopes(threadId, self.currentFrameIndex, force=false)

  return threadId.some

proc updateVariables(self: Debugger, containerVarRef: VariablesReference, maxDepth: int, force: bool = false) {.async.} =
  let ids = self.currentVariablesContext().getOr:
    return

  let containerId = ids & containerVarRef
  if not force and self.variables.contains(containerId) and self.variables[containerId].timestamp == self.timestamp:
    return

  let timestamp = self.timestamp
  if self.client.getSome(client):
    var variables = await client.variables(containerVarRef)
    if variables.isError:
      log lvlError, &"Failed to get variables {containerVarRef}: {variables}"
      return

    if timestamp != self.timestamp:
      return

    variables.result.timestamp = self.timestamp

    var childrenToUpdate = newSeq[int]()
    if self.variables.contains(containerId) and self.variables[containerId].timestamp != self.timestamp:
      # Variable was fetched before
      var varsToDelete = newSeq[VariablesReference]()
      for i, oldChild in self.variables[containerId].variables:
        let oldChildId = ids & oldChild.variablesReference
        if i < variables.result.variables.len:
          var newChild = variables.result.variables[i].addr
          let newChildId = ids & newChild.variablesReference

          if self.variables.contains(oldChildId):
            childrenToUpdate.add i
            self.variables[newChildId] = self.variables[oldChildId]
            varsToDelete.add oldChildId.varRef

            for view in self.variableViews:
              for p in view.variablesCursor.path.mitems:
                if p.varRef == oldChildId.varRef:
                  p.varRef = newChildId.varRef

              for p in view.baseIndex.path.mitems:
                if p.varRef == oldChildId.varRef:
                  p.varRef = newChildId.varRef

          for view in self.variableViews:
            if view.collapsedVariables.contains(oldChildId):
              view.collapsedVariables.excl(oldChildId)
              view.collapsedVariables.incl(newChildId)

          if oldChild.name == newChild.name and oldChild.value != newChild.value:
            newChild.valueChanged = true.some

      # Remove old cached values
      for v in varsToDelete:
        self.variables.del(ids & v)

    self.variables[containerId] = variables.result
    self.platform.requestRender()

    if maxDepth <= 0 and childrenToUpdate.len == 0:
      return

    if childrenToUpdate.len > 0:
      let vars {.cursor.} = self.variables[containerId]
      let futures = collect:
        for i in childrenToUpdate:
          if i in 0..vars.variables.high and vars.variables[i].variablesReference != 0.VariablesReference:

            var notCollapsedInAnyView = false
            for view in self.variableViews:
              if not view.collapsedVariables.contains(ids & vars.variables[i].variablesReference):
                notCollapsedInAnyView = true
                break
            if notCollapsedInAnyView:
              self.updateVariables(vars.variables[i].variablesReference, maxDepth - 1, force)

      await futures.allFutures
    else:
      let futures = collect:
        for variable in variables.result.variables:
          if variable.variablesReference != 0.VariablesReference:
            self.updateVariables(variable.variablesReference, maxDepth - 1, force)

      await futures.allFutures

proc updateScopes(self: Debugger, threadId: ThreadId, frameIndex: int, force: bool) {.async.} =
  if self.client.getSome(client):
    self.stackTraces.withValue(threadId, stack):
      if frameIndex notin 0..stack[].stackFrames.high:
        return

      let frame {.cursor.} = stack[].stackFrames[frameIndex]

      let timestamp = self.timestamp
      if force or not self.scopes.contains((threadId, frame.id)):
        var scopes = await client.scopes(frame.id)
        if scopes.isError:
          return

        if timestamp != self.timestamp:
          return

        scopes.result.timestamp = self.timestamp
        self.scopes[(threadId, frame.id)] = scopes.result
      self.platform.requestRender()

      let futures = collect:
        for scope in self.scopes[(threadId, frame.id)].scopes:
          if force or not self.variables.contains((threadId, frame.id, scope.variablesReference)):
            self.updateVariables(scope.variablesReference, 0)

      await futures.allFutures

      if timestamp != self.timestamp:
        return

      # todo
      # self.reevaluateCurrentCursor()

proc handleStoppedAsync(self: Debugger, data: OnStoppedData) {.async.} =
  log(lvlInfo, &"onStopped {data}")
  self.platform.focusWindow()

  self.timestamp.inc()
  self.debuggerState = DebuggerState.Paused
  self.currentStopData = data
  self.platform.requestRender()
  self.languageServer.evaluations.clear()

  let timestamp = self.timestamp

  if self.client.getSome(client):
    let threads = await client.getThreads
    if threads.isError:
      log lvlError, &"Failed to get threads: {threads}"
      return

    if timestamp != self.timestamp:
      return

    self.threads = threads.result.threads
    self.platform.requestRender()

  if data.threadId.getSome(id):
    let threadIndex = self.threads.findIt(it.id == id)
    if threadIndex >= 0:
      self.currentThreadIndex = threadIndex
    else:
      self.currentThreadIndex = 0

  if self.lastEditor.isSome:
    self.lastEditor.get.clearCustomHighlights(debuggerCurrentLineId)
    self.lastEditor = TextDocumentEditor.none

  let threadId = await self.getStackTrace(data.threadId)
  if timestamp != self.timestamp:
    return
  self.platform.requestRender()

  if threadId.getSome(threadId) and self.stackTraces.contains(threadId):
    asyncSpawn self.updateScopes(threadId, self.currentFrameIndex, force=true)
    let stack {.cursor.} = self.stackTraces[threadId]

    if stack.stackFrames.len == 0:
      return

    let frame {.cursor.} = stack.stackFrames[0]

    if frame.source.isSome and frame.source.get.path.getSome(path):
      await self.tryOpenFileInWorkspace(path, (frame.line - 1, frame.column - 1))

proc handleStopped(self: Debugger, data: OnStoppedData) =
  asyncSpawn self.handleStoppedAsync(data)

proc handleContinued(self: Debugger, data: OnContinuedData) =
  log(lvlInfo, &"onContinued {data}")
  self.debuggerState = DebuggerState.Running
  if self.lastEditor.isSome:
    self.lastEditor.get.clearCustomHighlights(debuggerCurrentLineId)
    self.lastEditor.get.updateInlayHints()
  self.languageServer.evaluations.clear()
  self.platform.requestRender()

proc handleTerminated(self: Debugger, data: Option[OnTerminatedData]) =
  log(lvlInfo, &"onTerminated {data}")
  if self.lastEditor.isSome:
    self.lastEditor.get.clearCustomHighlights(debuggerCurrentLineId)
    self.lastEditor = TextDocumentEditor.none
  self.stopDebugSessionDelayed()
  self.platform.requestRender()

proc handleOutput(self: Debugger, data: OnOutputData) =
  if self.outputEditor.isNil:
    log(lvlInfo, &"[dap-{data.category}] {data.output}")
    return

  if data.category == "stdout".some or data.category == "stderr".some:
    let document = self.outputEditor.document

    let selection = document.lastCursor.toSelection
    let cursorAtEnd = self.outputEditor.selection == selection
    discard document.edit([selection], [selection], [data.output.replace("\r\n", "\n")])

    if cursorAtEnd:
      self.outputEditor.selection = document.lastCursor.toSelection
      self.outputEditor.setNextSnapBehaviour(ScrollSnapBehaviour.Always)
      self.outputEditor.scrollToCursor()

  else:
    log(lvlInfo, &"[dap-{data.category}] {data.output}")

proc setClient(self: Debugger, client: DAPClient) =
  assert self.client.isNone
  self.client = client.some

  discard client.onInitialized.subscribe (data: OnInitializedData) =>
    log(lvlInfo, &"onInitialized")
  discard client.onStopped.subscribe (data: OnStoppedData) => self.handleStopped(data)
  discard client.onContinued.subscribe (data: OnContinuedData) => self.handleContinued(data)
  discard client.onExited.subscribe (data: OnExitedData) =>
    log(lvlInfo, &"onExited {data}")
  discard client.onTerminated.subscribe (data: Option[OnTerminatedData]) => self.handleTerminated(data)
  discard client.onThread.subscribe (data: OnThreadData) =>
    log(lvlInfo, &"onThread {data}")
  discard client.onOutput.subscribe (data: OnOutputData) => self.handleOutput(data)
  discard client.onBreakpoint.subscribe (data: OnBreakpointData) =>
    log(lvlInfo, &"onBreakpoint {data}")
  discard client.onModule.subscribe (data: OnModuleData) =>
    log(lvlInfo, &"onModule {data}")
  discard client.onLoadedSource.subscribe (data: OnLoadedSourceData) =>
    log(lvlInfo, &"onLoadedSource {data}")
  discard client.onProcess.subscribe (data: OnProcessData) =>
    log(lvlInfo, &"onProcess {data}")
  discard client.onCapabilities.subscribe (data: OnCapabilitiesData) =>
    log(lvlInfo, &"onCapabilities {data}")
  discard client.onProgressStart.subscribe (data: OnProgressStartData) =>
    log(lvlInfo, &"onProgressStart {data}")
  discard client.onProgressUpdate.subscribe (data: OnProgressUpdateData) =>
    log(lvlInfo, &"onProgressUpdate {data}")
  discard client.onProgressEnd.subscribe (data: OnProgressEndData) =>
    log(lvlInfo, &"onProgressEnd {data}")
  discard client.onInvalidated.subscribe (data: OnInvalidatedData) =>
    log(lvlInfo, &"onInvalidated {data}")
  discard client.onMemory.subscribe (data: OnMemoryData) =>
    log(lvlInfo, &"onMemory {data}")

proc runConfigurationAsync(self: Debugger, name: string) {.async.} =
  if self.client.isSome:
    self.stopDebugSession()

  self.debuggerState = DebuggerState.Starting

  assert self.client.isNone
  log lvlInfo, &"[runConfigurationAsync] Launch '{name}'"

  let config = self.config.runtime.get("debugger.configuration." & name, newJexNull())
  if config.isNil or config.kind != JObject:
    log lvlError, &"No/invalid configuration with name '{name}' found: {config}"
    self.debuggerState = DebuggerState.None
    return

  let request = config.tryGet("request", string, "launch".newJexString):
    log lvlError, &"No/invalid debugger request in {config.pretty}"
    self.debuggerState = DebuggerState.None
    return

  let typ = config.tryGet("type", string, newJexNull()):
    log lvlError, &"No/invalid debugger type in {config.pretty}"
    self.debuggerState = DebuggerState.None
    return

  let connection = await self.createConnectionWithType(typ)
  if connection.isNone:
    log lvlError, &"Failed to create connection for typ '{typ}'"
    self.debuggerState = DebuggerState.None
    return

  self.lastConfiguration = name.some

  let client = newDAPClient(connection.get)
  self.setClient(client)
  await client.initialize()
  if not client.waitInitialized.await:
    log lvlError, &"Client failed to initialized"
    client.deinit()
    self.client = DAPClient.none
    self.debuggerState = DebuggerState.None
    return

  case request
  of "launch":
    await client.launch(config.toJson)

  of "attach":
    await client.attach(config.toJson)

  else:
    log lvlError, &"Invalid request type '{request}', expected 'launch' or 'attach'"
    self.client = DAPClient.none
    client.deinit()
    self.debuggerState = DebuggerState.None
    return

  let setBreakpointFutures = collect:
    for file, breakpoints in self.breakpoints.pairs:
      client.setBreakpoints(Source(path: self.vfs.localize(file).some), breakpoints.mapIt(it.breakpoint))

  for fut in setBreakpointFutures:
    await fut

  let threads = await client.getThreads
  if threads.isError:
    log lvlError, &"Failed to get threads: {threads}"
    self.debuggerState = DebuggerState.None
    return

  self.threads = threads.result.threads

  await client.configurationDone()
  self.debuggerState = DebuggerState.Running

proc runConfiguration*(self: Debugger, name: string) {.expose("debugger").} =
  asyncSpawn self.runConfigurationAsync(name)

proc chooseRunConfiguration(self: Debugger) {.expose("debugger").} =
  var builder = SelectorPopupBuilder()
  builder.scope = "choose-run-configuration".some
  builder.previewScale = 0.7
  builder.scaleX = 0.5
  builder.scaleY = 0.5

  let config = self.config.runtime.get("debugger.configuration", newJexObject())
  if config.kind != JObject:
    log lvlError, &"No/invalid debugger configuration: {config}"
    return

  var res = newSeq[FinderItem]()
  for (name, config) in config.fields.pairs:
    res.add FinderItem(
      displayName: name,
      data: config.pretty,
    )

  builder.previewer = newDataPreviewer(self.services, language="javascript".some).Previewer.some

  let finder = newFinder(newStaticDataSource(res), filterAndSort=true)
  builder.finder = finder.some

  builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
    self.runConfiguration(item.displayName)
    true

  discard self.layout.pushSelectorPopup(builder)

proc runLastConfiguration*(self: Debugger) {.expose("debugger").} =
  if self.lastConfiguration.getSome(name):
    asyncSpawn self.runConfigurationAsync(name)
  else:
    self.chooseRunConfiguration()

proc applyBreakpointSignsToEditor(self: Debugger, editor: TextDocumentEditor) =
  editor.clearSigns("breakpoints")

  if editor.document.isNil:
    return

  if not self.breakpoints.contains(editor.document.filename):
    return

  for breakpoint in self.breakpoints[editor.document.filename]:
    let sign = if self.breakpointsEnabled and breakpoint.enabled:
      "🛑"
    else:
      "B "
    let color = if self.breakpointsEnabled and breakpoint.enabled:
      "error"
    else:
      ""
    discard editor.addSign(idNone(), breakpoint.breakpoint.line - 1, sign,
      group = "breakpoints", color = color, width = 2)

proc flushBreakpointsForFileDelayedAsync(self: Debugger, path: string, delay: int) {.async.} =
  try:
    await sleepAsync(delay.milliseconds)
  except CatchableError:
    discard
  self.flushBreakpointsForFile(path)

proc flushBreakpointsForFileDelayed(self: Debugger, path: string, delay: int) =
  asyncSpawn self.flushBreakpointsForFileDelayedAsync(path, delay)

proc listenToDocumentChanges*(self: Debugger, document: TextDocument) =
  if document.filename notin self.documentCallbacks:
    let id = document.onSaved.subscribe proc() =
      self.flushBreakpointsForFileDelayed(document.filename, 1000)
    let id2 = document.textChanged.subscribe proc(doc: TextDocument) =
      self.updateBreakpointsForFile(document.filename)
    self.documentCallbacks[document.filename] = (document, id)

proc toggleBreakpointAt*(self: Debugger, editorId: EditorId, line: int) {.expose("debugger").} =
  ## Line is 0-based
  if self.editors.getEditorForId(editorId.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    let path = editor.TextDocumentEditor.document.filename
    if not self.breakpoints.contains(path):
      self.breakpoints[path] = @[]

    let snapshot = editor.TextDocumentEditor.document.buffer.snapshot.clone()

    for i, breakpoint in self.breakpoints[path]:
      if breakpoint.breakpoint.line == line + 1:
        # Breakpoint already exists, remove
        self.breakpoints[path].removeSwap(i)
        self.flushBreakpointsForFile(path)
        return

    self.breakpoints[path].add BreakpointInfo(
      path: path,
      breakpoint: SourceBreakpoint(line: line + 1),
      anchor: snapshot.anchorAfter(point(line, 0)).some,
    )

    self.flushBreakpointsForFile(path)

proc toggleBreakpoint*(self: Debugger) {.expose("debugger").} =
  if self.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    self.toggleBreakpointAt(view.editor.id.EditorId, view.editor.TextDocumentEditor.selection.last.line)

proc removeBreakpoint*(self: Debugger, path: string, line: int) {.expose("debugger").} =
  ## Line is 1-based
  log lvlInfo, &"removeBreakpoint {path}:{line}"
  if not self.breakpoints.contains(path):
    return

  for i, breakpoint in self.breakpoints[path]:
    if breakpoint.breakpoint.line == line:
      self.breakpoints[path].removeSwap(i)

      self.flushBreakpointsForFile(path)
      return

proc toggleBreakpointEnabled*(self: Debugger, path: string, line: int) {.expose("debugger").} =
  ## Line is 1-based
  log lvlInfo, &"toggleBreakpointEnabled {path}:{line}"
  if not self.breakpoints.contains(path):
    return

  for breakpoint in self.breakpoints[path].mitems:
    if breakpoint.breakpoint.line == line:
      breakpoint.enabled = not breakpoint.enabled

      self.flushBreakpointsForFile(path)
      return

proc toggleAllBreakpointsEnabled*(self: Debugger) {.expose("debugger").} =
  log lvlInfo, "toggleAllBreakpointsEnabled"

  var anyEnabled = false
  for file, breakpoints in self.breakpoints.pairs:
    for b in breakpoints:
      if b.enabled:
        anyEnabled = true
        break

  for file, breakpoints in self.breakpoints.mpairs:
    for b in breakpoints.mitems:
      b.enabled = not anyEnabled

  for path in self.breakpoints.keys:
    self.flushBreakpointsForFile(path)

proc toggleBreakpointsEnabled*(self: Debugger) {.expose("debugger").} =
  log lvlInfo, "toggleBreakpointsEnabled"

  self.breakpointsEnabled = not self.breakpointsEnabled

  for path in self.breakpoints.keys:
    self.flushBreakpointsForFile(path)

type
  BreakpointPreviewer* = ref object of Previewer
    editor: TextDocumentEditor
    tempDocument: TextDocument
    getPreviewTextImpl: proc(item: FinderItem): string {.gcsafe, raises: [].}

proc newBreakpointPreviewer*(services: Services, language = string.none,
    getPreviewTextImpl: proc(item: FinderItem): string {.gcsafe, raises: [].} = nil): BreakpointPreviewer =

  new result

  result.tempDocument = newTextDocument(services, language=language, createLanguageServer=false)
  result.tempDocument.usage = "debugger-temp"
  result.tempDocument.readOnly = true
  result.getPreviewTextImpl = getPreviewTextImpl

method deinit*(self: BreakpointPreviewer) =
  logScope lvlInfo, &"[deinit] Destroying data file previewer"
  if self.tempDocument.isNotNil:
    self.tempDocument.deinit()

  self[] = default(typeof(self[]))

method delayPreview*(self: BreakpointPreviewer) =
  discard

method previewItem*(self: BreakpointPreviewer, item: FinderItem, editor: DocumentEditor) =
  if not (editor of TextDocumentEditor):
    return

  self.editor = editor.TextDocumentEditor
  self.editor.setDocument(self.tempDocument)
  self.editor.selection = (0, 0).toSelection
  self.editor.scrollToTop()

  if self.getPreviewTextImpl.isNotNil:
    self.tempDocument.content = self.getPreviewTextImpl(item)
  else:
    self.tempDocument.content = item.data

proc editBreakpoints(self: Debugger) {.expose("debugger").} =
  var builder = SelectorPopupBuilder()
  builder.scope = "breakpoints".some
  builder.previewScale = 0.5
  builder.scaleX = 0.6
  builder.scaleY = 0.5

  proc getBreakpointFinderItems(): seq[FinderItem] =
    var res = newSeq[FinderItem]()
    for (file, breakpoints) in self.breakpoints.pairs:

      for b in breakpoints:
        let enabledText = if b.enabled: "✅" else: "❌"
        res.add FinderItem(
          displayName: &"{enabledText} {file}:{b.breakpoint.line}",
          data: b.toJson.pretty,
        )
    res

  builder.previewer = newBreakpointPreviewer(self.services, language="javascript".some).Previewer.some

  let source = newSyncDataSource(getBreakpointFinderItems)
  let finder = newFinder(source, filterAndSort=true)
  builder.finder = finder.some

  builder.customActions["delete-breakpoint"] = proc(popup: ISelectorPopup, args: JsonNode): bool {.gcsafe, raises: [].} =
    if popup.getSelectedItem().getSome(item):
      # let b = item.data.parseJson.jsonTo(BreakpointInfo).catch:
      #   log lvlError, &"Failed to parse BreakpointInfo: {getCurrentExceptionMsg()}"
      #   return

      # self.removeBreakpoint(b.path, b.breakpoint.line)
      source.retrigger()

    true

  builder.customActions["toggle-breakpoint-enabled"] = proc(popup: ISelectorPopup, args: JsonNode): bool {.gcsafe, raises: [].} =
    if popup.getSelectedItem().getSome(item):
      # let b = item.data.parseJson.jsonTo(BreakpointInfo).catch:
      #   log lvlError, &"Failed to parse BreakpointInfo: {getCurrentExceptionMsg()}"
      #   return

      # self.toggleBreakpointEnabled(b.path, b.breakpoint.line)
      source.retrigger()

    true

  builder.customActions["toggle-all-breakpoints-enabled"] = proc(popup: ISelectorPopup, args: JsonNode): bool {.gcsafe, raises: [].} =
    self.toggleAllBreakpointsEnabled()
    source.retrigger()
    true

  discard self.layout.pushSelectorPopup(builder)

proc pauseExecution*(self: Debugger) {.expose("debugger").} =
  if self.currentThread.getSome(thread) and self.client.getSome(client):
    asyncSpawn client.pauseExecution(thread.id)

proc continueExecution*(self: Debugger) {.expose("debugger").} =
  if self.debuggerState != DebuggerState.Paused:
    return
  if self.currentThread.getSome(thread) and self.client.getSome(client):
    asyncSpawn client.continueExecution(thread.id)

proc stepOver*(self: Debugger) {.expose("debugger").} =
  if self.currentThread.getSome(thread) and self.client.getSome(client):
    asyncSpawn client.next(thread.id)

proc stepIn*(self: Debugger) {.expose("debugger").} =
  if self.currentThread.getSome(thread) and self.client.getSome(client):
    asyncSpawn client.stepIn(thread.id)

proc stepOut*(self: Debugger) {.expose("debugger").} =
  if self.currentThread.getSome(thread) and self.client.getSome(client):
    asyncSpawn client.stepOut(thread.id)

proc closeAllViews(self: Debugger, T: typedesc) =
  let existing = self.layout.getViews(T)
  for v in existing:
    self.layout.closeView(v, keepHidden = false, restoreHidden = false)

proc toggleView(self: Debugger, T: typedesc, slot: string, focus: bool) =
  let existing = self.layout.getViews(T)
  for v in existing:
    if self.layout.isViewVisible(v):
      self.layout.closeView(v, keepHidden = false, restoreHidden = false)
    else:
      self.layout.showView(v, slot, focus = focus)

  if existing.len == 0:
    let view = T()
    when T is VariablesView:
      self.variableViews.add view
    self.layout.addView(view, slot, focus = focus)

proc closeDebuggerViews*(self: Debugger) {.expose("debugger").} =
  self.variableViews.setLen(0)
  self.closeAllViews(ThreadsView)
  self.closeAllViews(StacktraceView)
  self.closeAllViews(VariablesView)
  self.closeAllViews(OutputView)
  self.closeAllViews(ToolbarView)

proc closeDebuggerThreads*(self: Debugger) {.expose("debugger").} =
  self.closeAllViews(ThreadsView)

proc closeDebuggerStacktrace*(self: Debugger) {.expose("debugger").} =
  self.closeAllViews(StacktraceView)

proc closeDebuggerVariables*(self: Debugger) {.expose("debugger").} =
  self.variableViews.setLen(0)
  self.closeAllViews(VariablesView)

proc closeDebuggerOutput*(self: Debugger) {.expose("debugger").} =
  self.closeAllViews(OutputView)

proc closeDebuggerToolbar*(self: Debugger) {.expose("debugger").} =
  self.closeAllViews(ToolbarView)

proc showDebuggerThreads*(self: Debugger, focus: bool = true, slot: string = "#debugger-threads") {.expose("debugger").} =
  let existing = self.layout.getViews(ThreadsView)
  if existing.len > 0:
    self.layout.showView(existing[0], slot, focus = focus)
  else:
    self.layout.addView(ThreadsView(), slot, focus = focus)

proc showDebuggerStacktrace*(self: Debugger, focus: bool = true, slot: string = "#debugger-stacktrace") {.expose("debugger").} =
  let existing = self.layout.getViews(StacktraceView)
  if existing.len > 0:
    self.layout.showView(existing[0], slot, focus = focus)
  else:
    self.layout.addView(StacktraceView(), slot, focus = focus)

proc showDebuggerVariables*(self: Debugger, focus: bool = true, slot: string = "#debugger-variables") {.expose("debugger").} =
  let existing = self.layout.getViews(VariablesView)
  if existing.len > 0:
    self.layout.showView(existing[0], slot, focus = focus)
  else:
    let view = self.createVariablesView()
    self.layout.addView(view, slot, focus = focus)

proc showDebuggerOutput*(self: Debugger, focus: bool = true, slot: string = "#debugger-output") {.expose("debugger").} =
  let existing = self.layout.getViews(OutputView)
  if existing.len > 0:
    self.layout.showView(existing[0], slot, focus = focus)
  else:
    self.layout.addView(OutputView(), slot, focus = focus)

proc showDebuggerToolbar*(self: Debugger, focus: bool = true, slot: string = "#debugger-toolbar") {.expose("debugger").} =
  let existing = self.layout.getViews(ToolbarView)
  if existing.len > 0:
    self.layout.showView(existing[0], slot, focus = focus)
  else:
    self.layout.addView(ToolbarView(), slot, focus = focus)

proc toggleDebuggerThreads*(self: Debugger, focus: bool = true, slot: string = "#debugger-threads") {.expose("debugger").} =
  self.toggleView(ThreadsView, slot, focus)

proc toggleDebuggerStacktrace*(self: Debugger, focus: bool = true, slot: string = "#debugger-stacktrace") {.expose("debugger").} =
  self.toggleView(StacktraceView, slot, focus)

proc toggleDebuggerVariables*(self: Debugger, focus: bool = true, slot: string = "#debugger-variables") {.expose("debugger").} =
  self.toggleView(VariablesView, slot, focus)

proc toggleDebuggerOutput*(self: Debugger, focus: bool = true, slot: string = "#debugger-output") {.expose("debugger").} =
  self.toggleView(OutputView, slot, focus)

proc toggleDebuggerToolbar*(self: Debugger, focus: bool = true, slot: string = "#debugger-toolbar") {.expose("debugger").} =
  self.toggleView(ToolbarView, slot, focus)

genDispatcher("debugger")
addGlobalDispatchTable "debugger", genDispatchTable("debugger")

proc handleAction(self: Debugger, action: string, arg: string): EventResponse =
  # debugf"[textedit] handleAction {action}, '{args}'"

  try:
    var args = newJArray()
    for a in newStringStream(arg).parseJsonFragments():
      args.add a

    # debugf"dispatch {action}, {args}"
    if dispatch(action, args).isSome:
      return Handled
  except:
    log(lvlError, fmt"Failed to dispatch action '{action} {arg}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

  return Ignored

method getEventHandlers*(view: ThreadsView, inject: Table[string, EventHandler]): seq[EventHandler] =
  let debugger = ({.gcsafe.}: gDebugger)
  result.add debugger.eventHandler
  result.add debugger.threadsEventHandler

method getEventHandlers*(view: StacktraceView, inject: Table[string, EventHandler]): seq[EventHandler] =
  let debugger = ({.gcsafe.}: gDebugger)
  result.add debugger.eventHandler
  result.add debugger.stackTraceEventHandler

method getEventHandlers*(view: VariablesView, inject: Table[string, EventHandler]): seq[EventHandler] =
  let debugger = ({.gcsafe.}: gDebugger)
  result.add debugger.eventHandler
  if view.eventHandler == nil:
    assignEventHandler(view.eventHandler, debugger.events.getEventHandlerConfig("debugger.variables")):
      onAction:
        let old = pushVariablesView(view)
        defer:
          popVariablesView(old)
        debugger.handleAction action, arg
      onInput:
        view.variablesFilter.add input
        view.refilterVariables(debugger)
        Handled
  result.add view.eventHandler

method getEventHandlers*(view: OutputView, inject: Table[string, EventHandler]): seq[EventHandler] =
  let debugger = ({.gcsafe.}: gDebugger)
  result.add debugger.eventHandler
  if debugger.outputEditor.isNotNil:
    result.add debugger.outputEditor.getEventHandlers(inject)

method getEventHandlers*(view: ToolbarView, inject: Table[string, EventHandler]): seq[EventHandler] =
  let debugger = ({.gcsafe.}: gDebugger)
  result.add debugger.eventHandler

proc findVariable(self: VariablesView, debugger: Debugger, filter: string, vr: VariablesReference, cursor: VariableCursor, filterVersion: int) {.async.} =
  let thread = debugger.currentThread()
  if thread.isNone:
    return
  let frame = debugger.currentStackFrame()
  if frame.isNone:
    return
  let key = (thread.get.id, frame.get.id, vr)
  if key in debugger.variables:
    let variables {.cursor.} = debugger.variables[key]
    for i, v in variables.variables:
      var cursor2 = cursor
      cursor2.path.add((i, vr))
      if v.name.contains(filter):
        self.filteredVariables.incl (i, vr)
        self.filteredCursors.add cursor2
        debugger.platform.requestRender()

      let key2 = (thread.get.id, frame.get.id, v.variablesReference)
      await self.findVariable(debugger, filter, v.variablesReference, cursor2, filterVersion)

proc findVariable(self: VariablesView, filter: string) {.async.} =
  let debugger = getDebugger().getOr:
    return
  let scopes = debugger.currentScopes()
  if scopes.isNone:
    return
  let version = self.filterVersion
  if self.variablesCursor.scope == -1:
    let vr = self.evaluation.variablesReference
    var cursor = VariableCursor(scope: -1)
    await self.findVariable(debugger, filter, vr, cursor, version)
    if self.filterVersion != version:
      return
    if self.filteredCursors.len > 0:
      let i = self.filteredCursors.find(self.variablesCursor)
      if i == -1:
        self.nextVariable()
  else:
    for scopeIndex, s in scopes.get.scopes:
      let vr = s.variablesReference
      var cursor = VariableCursor(scope: scopeIndex)
      await self.findVariable(debugger, filter, vr, cursor, version)
      if self.filterVersion != version:
        return
      if self.filteredCursors.len > 0:
        let i = self.filteredCursors.find(self.variablesCursor)
        if i == -1:
          self.nextVariable()

method getInlayHints*(self: LanguageServerDebugger, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.async.} =
  result = newSeq[language_server_base.InlayHint]().success

  if self.debugger.debuggerState != Paused:
    return

  let frame = self.debugger.currentStackFrame()
  if frame.isNone:
    return

  if self.debugger.client.getSome(client):
    let doc = self.debugger.editors.getDocument(filename)
    if doc.isNone or not (doc.get of TextDocument):
      return

    let document = doc.get.TextDocument
    let timestamp = self.debugger.timestamp
    let decls = document.getDeclarationsInRange(selection)
    var inlayHints = newSeq[language_server_base.InlayHint]()

    let futures = collect:
      for decl in decls:
        let key = (filename, decl.name, decl.value)
        # todo: use cached evaluations
        if key in self.evaluations:
          self.evaluations[key].toFuture
        else:
          client.evaluate(decl.value, document.localizedPath, decl.name.first.line, decl.name.first.column, frame.get.id)

    await futures.allFutures
    if timestamp != self.debugger.timestamp:
      return

    for i in 0..decls.high:
      let eval = futures[i].read
      self.evaluations[(filename, decls[i].name, decls[i].value)] = eval
      if eval.isError:
        continue

      var nl = eval.result.result.find('\n')
      if nl == -1:
        let eq = eval.result.result.find("= ")
        if eq != -1:
          inlayHints.add language_server_base.InlayHint(
            location: decls[i].decl.last,
            label: eval.result.result[eq..^1].strip(),
            paddingLeft: true,
          )
        else:
          inlayHints.add language_server_base.InlayHint(
            location: decls[i].decl.last,
            label: eval.result.result,
            paddingLeft: true,
          )
      else:
        var label = ""
        for i, line in enumerate(eval.result.result.splitLines):
          if i == 0:
            var eq = line.find("= ")
            if eq != -1:
              label.add line[eq..^1].strip()
              continue
          if i > 0:
            label.add " "
          label.add line.strip()
          if label.len > 60: # todo: make this configurable
            label.add "..."
            break

        inlayHints.add language_server_base.InlayHint(
          location: decls[i].decl.last,
          label: label,
          paddingLeft: true,
        )

    result = inlayHints.success
