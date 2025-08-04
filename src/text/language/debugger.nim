import std/[strutils, options, json, tables, sugar, strtabs, streams, sets, sequtils]
import misc/[id, custom_async, custom_logger, util, connection, myjsonutils, event, response, jsonex]
import scripting/[expose]
import dap_client, dispatch_tables, app_interface, config_provider, selector_popup_builder, events, view, session, document_editor, layout, platform_service
import text/text_editor
import platform/platform
import finder/[previewer, finder, data_previewer]
import workspaces/workspace, plugin_service

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
    scope: int
    path: seq[tuple[index: int, varRef: VariablesReference]]

  BreakpointInfo* = object
    path: string
    enabled: bool = true
    breakpoint: SourceBreakpoint

  Debugger* = ref object of Service
    platform: Platform
    events: EventHandlerService
    config: ConfigService
    plugins: PluginService
    workspace: Workspace
    editors: DocumentEditorService
    layout: LayoutService
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
    variablesEventHandler: EventHandler
    outputEventHandler: EventHandler

    variablesCursor: VariableCursor
    variablesScrollOffset*: float
    collapsedVariables: HashSet[(ThreadId, FrameId, VariablesReference)]

    breakpointsEnabled*: bool = true

    lastEditor: Option[TextDocumentEditor]
    outputEditor*: TextDocumentEditor

    # Data setup in the editor and sent to the server
    breakpoints: Table[string, seq[BreakpointInfo]]

    # Cached data from server
    threads: seq[ThreadInfo]
    stackTraces: Table[ThreadId, StackTraceResponse]
    scopes*: Table[(ThreadId, FrameId), Scopes]
    variables*: Table[(ThreadId, FrameId, VariablesReference), Variables]

func serviceName*(_: typedesc[Debugger]): string = "Debugger"
addBuiltinService(Debugger, SessionService, DocumentEditorService, LayoutService, EventHandlerService, ConfigService)

proc applyBreakpointSignsToEditor(self: Debugger, editor: TextDocumentEditor)
proc handleAction(self: Debugger, action: string, arg: string): EventResponse
proc updateVariables(self: Debugger, variablesReference: VariablesReference, maxDepth: int) {.async.}
proc updateScopes(self: Debugger, threadId: ThreadId, frameIndex: int, force: bool) {.async.}
proc updateStackTrace(self: Debugger, threadId: Option[ThreadId]) {.async.}
proc getStackTrace(self: Debugger, threadId: Option[ThreadId]): Future[Option[ThreadId]] {.async.}

var gDebugger: Debugger = nil

proc getDebugger*(): Option[Debugger] =
  {.gcsafe.}:
    if gServices.isNil: return Debugger.none
    return gServices.getService(Debugger)

static:
  addInjector(Debugger, getDebugger)

proc `&`*(ids: (ThreadId, FrameId), varRef: VariablesReference):
    tuple[thread: ThreadId, frame: FrameId, varRef: VariablesReference] =
  (ids[0], ids[1], varRef)

proc getEventHandlers*(inject: Table[string, EventHandler]): seq[EventHandler] =
  {.gcsafe.}:
    result.add gDebugger.eventHandler
    case gDebugger.activeView
    of ActiveView.Threads: result.add gDebugger.threadsEventHandler
    of ActiveView.StackTrace: result.add gDebugger.stackTraceEventHandler
    of ActiveView.Variables: result.add gDebugger.variablesEventHandler
    of ActiveView.Output:
      if gDebugger.outputEditor.isNotNil:
        result.add gDebugger.outputEditor.getEventHandlers(inject)

proc getStateJson*(self: Debugger): JsonNode =
  return %*{
    "breakpoints": self.breakpoints,
  }

proc updateBreakpointsForFile(self: Debugger, path: string) =
  if self.layout.tryOpenExisting(path).getSome(editor) and editor of TextDocumentEditor:
    self.applyBreakpointSignsToEditor(editor.TextDocumentEditor)

  if self.client.getSome(client):
    if self.breakpointsEnabled:
      var bs: seq[SourceBreakpoint]
      self.breakpoints.withValue(path, val):
        for b in val[]:
          if b.enabled:
            bs.add b.breakpoint
      asyncSpawn client.setBreakpoints(Source(path: path.some), bs)
    else:
      asyncSpawn client.setBreakpoints(Source(path: path.some), @[])

proc handleEditorRegistered*(self: Debugger, editor: DocumentEditor) =
  if not (editor of TextDocumentEditor):
    return
  let editor = editor.TextDocumentEditor
  if editor.document.isNil:
    return

  if editor.document.isLoadingAsync:
    var id = new Id
    id[] = editor.document.onLoaded.subscribe proc(args: tuple[document: TextDocument, changed: seq[Selection]]) =
      args.document.onLoaded.unsubscribe(id[])
      self.applyBreakpointSignsToEditor(editor)
  else:
    self.applyBreakpointSignsToEditor(editor)

proc handleSessionRestored(self: Debugger, session: SessionService) =
  try:
    if session.sessionData.isNotNil and session.sessionData.kind == JObject:
      if session.sessionData.fields.contains("breakpoints"):
        self.breakpoints = session.sessionData["breakpoints"].jsonTo(Table[string, seq[BreakpointInfo]])
  except:
    discard

proc waitForApp(self: Debugger) {.async: (raises: []).} =
  while ({.gcsafe.}: gAppInterface).isNil:
    try:
      await sleepAsync(10.milliseconds)
    except CancelledError:
      discard

  let document = newTextDocument(self.services, createLanguageServer=false)
  self.outputEditor = newTextEditor(document, self.services)
  self.outputEditor.usage = "debugger-output"
  self.outputEditor.renderHeader = false
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

  assignEventHandler(self.variablesEventHandler, self.events.getEventHandlerConfig("debugger.variables")):
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

  self.collapsedVariables = initHashSet[(ThreadId, FrameId, VariablesReference)]()
  self.editors = self.services.getService(DocumentEditorService).get
  self.layout = self.services.getService(LayoutService).get
  self.events = self.services.getService(EventHandlerService).get
  self.config = self.services.getService(ConfigService).get
  self.plugins = self.services.getService(PluginService).get
  self.platform = self.services.getService(PlatformService).get.platform
  self.workspace = self.services.getService(Workspace).get

  discard self.services.getService(SessionService).get.onSessionRestored.subscribe (session: SessionService) => self.handleSessionRestored(session)

  discard self.editors.onEditorRegistered.subscribe (e: DocumentEditor) {.gcsafe, raises: [].} =>
    self.handleEditorRegistered(e)

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

proc isCollapsed*(self: Debugger, ids: (ThreadId, FrameId, VariablesReference)): bool =
  ids in self.collapsedVariables

proc prevDebuggerView*(self: Debugger) {.expose("debugger").} =
  self.activeView = case self.activeView
  of ActiveView.Threads: ActiveView.Output
  of ActiveView.StackTrace: ActiveView.Threads
  of ActiveView.Variables: ActiveView.StackTrace
  of ActiveView.Output: ActiveView.Variables

proc nextDebuggerView*(self: Debugger) {.expose("debugger").} =
  self.activeView = case self.activeView
  of ActiveView.Threads: ActiveView.StackTrace
  of ActiveView.StackTrace: ActiveView.Variables
  of ActiveView.Variables: ActiveView.Output
  of ActiveView.Output: ActiveView.Threads

proc setDebuggerView*(self: Debugger, view: string) {.expose("debugger").} =
  self.activeView = view.parseEnum[:ActiveView].catch:
    log lvlError, &"Invalid view '{view}'"
    return

proc isSelected*(self: Debugger, r: VariablesReference, index: int): bool =
  return self.variablesCursor.path.len > 0 and
    self.variablesCursor.path[self.variablesCursor.path.high] == (index, r)

proc isScopeSelected*(self: Debugger, index: int): bool =
  return self.variablesCursor.path.len == 0 and self.variablesCursor.scope == index

proc selectedVariable*(self: Debugger): Option[tuple[index: int, varRef: VariablesReference]] =
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

proc reevaluateCurrentCursor*(self: Debugger) =
  self.variablesCursor = self.reevaluateCursorRefs(self.variablesCursor)

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

proc clampCurrentCursor*(self: Debugger) =
  self.variablesCursor = self.clampCursor(self.variablesCursor)

proc lastChild*(self: Debugger, cursor: VariableCursor): VariableCursor =
  let scopes = self.currentScopes().getOr:
    return VariableCursor()

  let ids = self.currentVariablesContext().getOr:
    result = VariableCursor()
    return

  result = cursor
  if result.path.len == 0:
    let scope = scopes[].scopes[result.scope]

    if self.isCollapsed(ids & scope.variablesReference):
      return

    if not self.variables.contains(ids & scope.variablesReference):
      return

    let variables {.cursor.} = self.variables[ids & scope.variablesReference]
    if variables.variables.len == 0:
      return

    result.path.add (variables.variables.high, scope.variablesReference)

  while true:
    let (index, r) = result.path[result.path.high]
    let variables {.cursor.} = self.variables[ids & r]
    result.path[result.path.high].index =
      result.path[result.path.high].index.clamp(0, variables.variables.high)
    if variables.variables.len == 0:
      return
    let childRef = variables.variables[index.clamp(0, variables.variables.high)].variablesReference
    if self.isCollapsed(ids & childRef):
      return
    if not self.variables.contains(ids & childRef) or self.variables[ids & childRef].variables.len == 0:
      return

    result.path.add (self.variables[ids & childRef].variables.high, childRef)

proc selectFirstVariable*(self: Debugger) {.expose("debugger").} =
  self.variablesScrollOffset = 0
  self.variablesCursor = VariableCursor()

proc selectLastVariable*(self: Debugger) {.expose("debugger").} =
  let scopes = self.currentScopes().getOr:
    return

  if scopes[].scopes.len == 0 or self.variables.len == 0:
    self.variablesScrollOffset = 0
    self.variablesCursor = VariableCursor()
    return

  self.variablesCursor = self.lastChild(VariableCursor(scope: scopes[].scopes.high))
  self.variablesScrollOffset = self.maxVariablesScrollOffset

proc prevThread*(self: Debugger) {.expose("debugger").} =
  if self.threads.len == 0:
    return

  dec self.currentThreadIndex
  if self.currentThreadIndex < 0:
    self.currentThreadIndex = self.threads.high

  self.currentFrameIndex = 0

  if self.currentThread().getSome(t) and not self.stackTraces.contains(t.id):
    asyncSpawn self.updateStackTrace(t.id.some)

proc nextThread*(self: Debugger) {.expose("debugger").} =
  if self.threads.len == 0:
    return

  inc self.currentThreadIndex
  if self.currentThreadIndex > self.threads.high:
    self.currentThreadIndex = 0

  self.currentFrameIndex = 0

  if self.currentThread().getSome(t) and not self.stackTraces.contains(t.id):
    asyncSpawn self.updateStackTrace(t.id.some)

proc prevStackFrame*(self: Debugger) {.expose("debugger").} =
  let thread = self.currentThread().getOr:
    return

  if not self.stackTraces.contains(thread.id):
    return

  let stack {.cursor.} = self.stackTraces[thread.id]

  dec self.currentFrameIndex
  if self.currentFrameIndex < 0:
    self.currentFrameIndex = stack.stackFrames.high

  self.variablesCursor = VariableCursor()

  if self.currentThread().getSome(t):
    asyncSpawn self.updateScopes(t.id, self.currentFrameIndex, force=false)

proc nextStackFrame*(self: Debugger) {.expose("debugger").} =
  let thread = self.currentThread().getOr:
    return

  if not self.stackTraces.contains(thread.id):
    return

  let stack {.cursor.} = self.stackTraces[thread.id]

  inc self.currentFrameIndex
  if self.currentFrameIndex > stack.stackFrames.high:
    self.currentFrameIndex = 0

  self.variablesCursor = VariableCursor()

  if self.currentThread().getSome(t):
    asyncSpawn self.updateScopes(t.id, self.currentFrameIndex, force=false)

proc openFileForCurrentFrame*(self: Debugger, slot: string = "") {.expose("debugger").} =
  if self.currentStackFrame().getSome(frame) and
      frame[].source.isSome and
      frame[].source.get.path.getSome(path):
    asyncSpawn self.tryOpenFileInWorkspace(path, (frame[].line - 1, frame[].column - 1), slot)

proc prevVariable*(self: Debugger) {.expose("debugger").} =
  let scopes = self.currentScopes().getOr:
    return

  if scopes[].scopes.len == 0 or self.variables.len == 0:
    return

  let ids = self.currentVariablesContext().getOr:
    return

  self.clampCurrentCursor()

  if self.variablesCursor.path.len == 0:
    if self.variablesCursor.scope > 0:
      self.variablesCursor = self.lastChild(VariableCursor(scope: self.variablesCursor.scope - 1))
      if self.variablesScrollOffset > 0:
        self.variablesScrollOffset -= self.platform.totalLineHeight
      return

  else:
    if self.variablesCursor.path.len == 0 and self.variablesCursor.scope > 0:
      self.variablesCursor = self.lastChild(VariableCursor(
        scope: self.variablesCursor.scope - 1,
        path: @[(int.high, scopes[].scopes[self.variablesCursor.scope - 1].variablesReference)],
      ))
      if self.variablesScrollOffset > 0:
        self.variablesScrollOffset -= self.platform.totalLineHeight
      return

    let (index, currentRef) = self.variablesCursor.path[self.variablesCursor.path.high]
    if not self.variables.contains(ids & currentRef):
      return

    if index > 0:
      dec self.variablesCursor.path[self.variablesCursor.path.high].index
      self.variablesCursor = self.lastChild(self.variablesCursor)
      if self.variablesScrollOffset > 0:
        self.variablesScrollOffset -= self.platform.totalLineHeight
      return

    discard self.variablesCursor.path.pop
    if self.variablesScrollOffset > 0:
      self.variablesScrollOffset -= self.platform.totalLineHeight

proc nextVariable*(self: Debugger) {.expose("debugger").} =
  let scopes = self.currentScopes().getOr:
    return

  let ids = self.currentVariablesContext().getOr:
    return

  if scopes[].scopes.len == 0 or self.variables.len == 0:
    return

  self.clampCurrentCursor()

  if self.variablesCursor.path.len == 0:
    let scope = scopes[].scopes[self.variablesCursor.scope]
    let collapsed = self.isCollapsed(ids & scope.variablesReference)
    if self.variables.contains(ids & scope.variablesReference) and
        self.variables[ids & scope.variablesReference].variables.len > 0 and
        not collapsed:
      self.variablesCursor.path.add (0, scope.variablesReference)
      if self.variablesScrollOffset < self.maxVariablesScrollOffset:
        self.variablesScrollOffset += self.platform.totalLineHeight
      return

    if self.variablesCursor.scope + 1 < scopes[].scopes.len:
      self.variablesCursor = VariableCursor(scope: self.variablesCursor.scope + 1)
      if self.variablesScrollOffset < self.maxVariablesScrollOffset:
        self.variablesScrollOffset += self.platform.totalLineHeight
      return

  else:
    var descending = true
    while self.variablesCursor.path.len > 0:
      let (index, currentRef) = self.variablesCursor.path[self.variablesCursor.path.high]
      if not self.variables.contains(ids & currentRef):
        return

      let variables {.cursor.} = self.variables[ids & currentRef]

      if index < variables.variables.len:
        let childrenRef = variables.variables[index].variablesReference
        let collapsed = self.isCollapsed(ids & childrenRef)
        if descending and childrenRef != 0.VariablesReference and
            self.variables.contains(ids & childrenRef) and
            self.variables[ids & childrenRef].variables.len > 0 and
            not collapsed:
          self.variablesCursor.path.add (0, childrenRef)
          if self.variablesScrollOffset < self.maxVariablesScrollOffset:
            self.variablesScrollOffset += self.platform.totalLineHeight
          return

        if index < variables.variables.high:
          inc self.variablesCursor.path[self.variablesCursor.path.high].index
          if self.variablesScrollOffset < self.maxVariablesScrollOffset:
            self.variablesScrollOffset += self.platform.totalLineHeight
          return

      descending = false
      discard self.variablesCursor.path.pop

    if self.variablesCursor.scope + 1 < scopes[].scopes.len:
      self.variablesCursor = VariableCursor(scope: self.variablesCursor.scope + 1)
      if self.variablesScrollOffset < self.maxVariablesScrollOffset:
        self.variablesScrollOffset += self.platform.totalLineHeight
      return

    self.variablesCursor = self.lastChild(VariableCursor(
      scope: scopes[].scopes.high,
      path: @[(int.high, scopes[].scopes[scopes[].scopes.high].variablesReference)],
    ))

proc expandVariable*(self: Debugger) {.expose("debugger").} =
  let scopes = self.currentScopes().getOr:
    return

  let ids = self.currentVariablesContext().getOr:
    return

  if scopes[].scopes.len == 0 or self.variables.len == 0:
    return

  self.clampCurrentCursor()
  if self.selectedVariable().getSome(v):
    if self.variables.contains(ids & v.varRef):
      let va {.cursor.} = self.variables[ids & v.varRef].variables[v.index]

      if va.variablesReference != 0.VariablesReference:
        self.collapsedVariables.excl ids & va.variablesReference
        asyncSpawn self.updateVariables(va.variablesReference, 0)

  else:
    self.collapsedVariables.excl ids & scopes[].scopes[self.variablesCursor.scope].variablesReference

proc collapseVariable*(self: Debugger) {.expose("debugger").} =
  let scopes = self.currentScopes().getOr:
    return

  let ids = self.currentVariablesContext().getOr:
    return

  if scopes[].scopes.len == 0 or self.variables.len == 0:
    return

  self.clampCurrentCursor()
  if self.selectedVariable().getSome(v):
    if self.variables.contains(ids & v.varRef):
      let va {.cursor.} = self.variables[ids & v.varRef].variables[v.index]

      if va.variablesReference == 0.VariablesReference or
        (ids & va.variablesReference) in self.collapsedVariables or
        not self.variables.contains(ids & va.variablesReference):

        let currentLen = self.variablesCursor.path.len
        if currentLen > 0:
          while self.variablesCursor.path.len >= currentLen:
            self.prevVariable()

      elif va.variablesReference != 0.VariablesReference:
        self.collapsedVariables.incl ids & va.variablesReference

  else:
    self.collapsedVariables.incl ids & scopes[].scopes[self.variablesCursor.scope].variablesReference

proc stopDebugSession*(self: Debugger) {.expose("debugger").} =
  log lvlInfo, "[stopDebugSession] Stopping session"
  if self.client.isNone:
    log lvlWarn, "No active debug session"
    return

  asyncSpawn self.client.get.disconnect(restart=false)
  self.client.get.deinit()
  self.client = DapClient.none

  self.debuggerState = DebuggerState.None
  self.threads.setLen 0
  self.stackTraces.clear()
  self.variables.clear()

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
    discard
    # todo

    # if config.hasKey("path"):
    #   let path = config.tryGet("path", string, newJexNull()):
    #     log lvlError, &"No/invalid debugger executable path in {config.pretty}"
    #     return Connection.none

    #   let port = getFreePort().int
    #   log lvlInfo, &"Start process {path} with port {port}"
    #   discard startProcess(path, args = @["-p", $port], options = {poUsePath, poDaemon})

    #   # todo: need to wait for process to open port?
    #   await sleepAsync(500.milliseconds)

    #   return newAsyncSocketConnection("127.0.0.1", port.Port).await.Connection.some

    # else:
    #   let host = config.tryGet("host", string, "127.0.0.1".newJexString):
    #     log lvlError, &"No/invalid debugger host in {config.pretty}"
    #     return Connection.none
    #   let port = config.tryGet("port", int, 5678.newJexInt):
    #     log lvlError, &"No/invalid debugger port in {config.pretty}"
    #     return Connection.none
    #   return newAsyncSocketConnection(host, port.Port).await.Connection.some

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

  if self.client.getSome(client):
    let stackTrace = await client.stackTrace(threadId)
    if stackTrace.isError:
      log lvlError, &"Failed to get stacktrace for thread {threadId}: {stackTrace}"
      return ThreadId.none
    self.stackTraces[threadId] = stackTrace.result

    asyncSpawn self.updateScopes(threadId, self.currentFrameIndex, force=false)

  return threadId.some

proc updateVariables(self: Debugger, variablesReference: VariablesReference, maxDepth: int) {.async.} =
  let ids = self.currentVariablesContext().getOr:
    return

  if self.client.getSome(client):
    let variables = await client.variables(variablesReference)
    if variables.isError:
      return

    self.variables[ids & variablesReference] = variables.result
    if maxDepth == 0:
      return

    let futures = collect:
      for variable in variables.result.variables:
        if variable.variablesReference != 0.VariablesReference:
          self.updateVariables(variable.variablesReference, maxDepth - 1)

    await futures.allFutures

proc updateScopes(self: Debugger, threadId: ThreadId, frameIndex: int, force: bool) {.async.} =
  if self.client.getSome(client):
    self.stackTraces.withValue(threadId, stack):
      if frameIndex notin 0..stack[].stackFrames.high:
        return

      let frame {.cursor.} = stack[].stackFrames[frameIndex]

      let scopes = if force or not self.scopes.contains((threadId, frame.id)):
        let scopes = await client.scopes(frame.id)
        if scopes.isError:
          return
        self.scopes[(threadId, frame.id)] = scopes.result
        scopes.result
      else:
        self.scopes[(threadId, frame.id)]

      let futures = collect:
        for scope in scopes.scopes:
          if force or not self.variables.contains((threadId, frame.id, scope.variablesReference)):
            self.updateVariables(scope.variablesReference, 0)

      await futures.allFutures

      self.reevaluateCurrentCursor()

proc handleStoppedAsync(self: Debugger, data: OnStoppedData) {.async.} =
  log(lvlInfo, &"onStopped {data}")

  self.threads.setLen 0
  self.stackTraces.clear()
  self.variables.clear()

  if self.client.getSome(client):
    let threads = await client.getThreads
    if threads.isError:
      log lvlError, &"Failed to get threads: {threads}"
      return

    self.threads = threads.result.threads

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

  if threadId.getSome(threadId) and self.stackTraces.contains(threadId):
    asyncSpawn self.updateScopes(threadId, self.currentFrameIndex, force=true)
    let stack {.cursor.} = self.stackTraces[threadId]

    if stack.stackFrames.len == 0:
      return

    let frame {.cursor.} = stack.stackFrames[0]

    if frame.source.isSome and frame.source.get.path.getSome(path):
      await self.tryOpenFileInWorkspace(path, (frame.line - 1, frame.column - 1))

proc handleStopped(self: Debugger, data: OnStoppedData) =
  self.debuggerState = DebuggerState.Paused
  asyncSpawn self.handleStoppedAsync(data)

proc handleContinued(self: Debugger, data: OnContinuedData) =
  log(lvlInfo, &"onContinued {data}")
  self.debuggerState = DebuggerState.Running
  self.scopes.clear()
  self.variables.clear()
  if self.lastEditor.isSome:
    self.lastEditor.get.clearCustomHighlights(debuggerCurrentLineId)

proc handleTerminated(self: Debugger, data: Option[OnTerminatedData]) =
  log(lvlInfo, &"onTerminated {data}")
  if self.lastEditor.isSome:
    self.lastEditor.get.clearCustomHighlights(debuggerCurrentLineId)
    self.lastEditor = TextDocumentEditor.none
  self.stopDebugSessionDelayed()

proc handleOutput(self: Debugger, data: OnOutputData) =
  if self.outputEditor.isNil:
    log(lvlInfo, &"[dap-{data.category}] {data.output}")
    return

  if data.category == "stdout".some:
    let document = self.outputEditor.document

    let selection = document.lastCursor.toSelection
    discard document.edit([selection], [selection], [data.output.replace("\r\n", "\n")])

    if self.outputEditor.selection == selection:
      self.outputEditor.selection = document.lastCursor.toSelection
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
      client.setBreakpoints(Source(path: file.some), breakpoints.mapIt(it.breakpoint))

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

proc toggleBreakpointAt*(self: Debugger, editorId: EditorId, line: int) {.expose("debugger").} =
  ## Line is 0-based
  if self.editors.getEditorForId(editorId).getSome(editor) and editor of TextDocumentEditor:
    let path = editor.TextDocumentEditor.document.filename
    if not self.breakpoints.contains(path):
      self.breakpoints[path] = @[]

    for i, breakpoint in self.breakpoints[path]:
      if breakpoint.breakpoint.line == line + 1:
        # Breakpoint already exists, remove
        self.breakpoints[path].removeSwap(i)
        self.updateBreakpointsForFile(path)
        return

    self.breakpoints[path].add BreakpointInfo(
      path: path,
      breakpoint: SourceBreakpoint(line: line + 1),
    )

    self.updateBreakpointsForFile(path)

proc toggleBreakpoint*(self: Debugger) {.expose("debugger").} =
  if self.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    self.toggleBreakpointAt(view.editor.id, view.editor.TextDocumentEditor.selection.last.line)

proc removeBreakpoint*(self: Debugger, path: string, line: int) {.expose("debugger").} =
  ## Line is 1-based
  log lvlInfo, &"removeBreakpoint {path}:{line}"
  if not self.breakpoints.contains(path):
    return

  for i, breakpoint in self.breakpoints[path]:
    if breakpoint.breakpoint.line == line:
      self.breakpoints[path].removeSwap(i)

      self.updateBreakpointsForFile(path)
      return

proc toggleBreakpointEnabled*(self: Debugger, path: string, line: int) {.expose("debugger").} =
  ## Line is 1-based
  log lvlInfo, &"toggleBreakpointEnabled {path}:{line}"
  if not self.breakpoints.contains(path):
    return

  for breakpoint in self.breakpoints[path].mitems:
    if breakpoint.breakpoint.line == line:
      breakpoint.enabled = not breakpoint.enabled

      self.updateBreakpointsForFile(path)
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
    self.updateBreakpointsForFile(path)

proc toggleBreakpointsEnabled*(self: Debugger) {.expose("debugger").} =
  log lvlInfo, "toggleBreakpointsEnabled"

  self.breakpointsEnabled = not self.breakpointsEnabled

  for path in self.breakpoints.keys:
    self.updateBreakpointsForFile(path)

type
  BreakpointPreviewer* = ref object of Previewer
    editor: TextDocumentEditor
    tempDocument: TextDocument
    getPreviewTextImpl: proc(item: FinderItem): string {.gcsafe, raises: [].}

proc newBreakpointPreviewer*(services: Services, language = string.none,
    getPreviewTextImpl: proc(item: FinderItem): string {.gcsafe, raises: [].} = nil): BreakpointPreviewer =

  new result

  result.tempDocument = newTextDocument(services, language=language, createLanguageServer=false)
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
      let b = item.data.parseJson.jsonTo(BreakpointInfo).catch:
        log lvlError, &"Failed to parse BreakpointInfo: {getCurrentExceptionMsg()}"
        return

      self.removeBreakpoint(b.path, b.breakpoint.line)
      source.retrigger()

    true

  builder.customActions["toggle-breakpoint-enabled"] = proc(popup: ISelectorPopup, args: JsonNode): bool {.gcsafe, raises: [].} =
    if popup.getSelectedItem().getSome(item):
      let b = item.data.parseJson.jsonTo(BreakpointInfo).catch:
        log lvlError, &"Failed to parse BreakpointInfo: {getCurrentExceptionMsg()}"
        return

      self.toggleBreakpointEnabled(b.path, b.breakpoint.line)
      source.retrigger()

    true

  builder.customActions["toggle-all-breakpoints-enabled"] = proc(popup: ISelectorPopup, args: JsonNode): bool {.gcsafe, raises: [].} =
    self.toggleAllBreakpointsEnabled()
    source.retrigger()
    true

  discard self.layout.pushSelectorPopup(builder)

proc continueExecution*(self: Debugger) {.expose("debugger").} =
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

proc showDebuggerView*(self: Debugger, slot: string = "#debugger") {.expose("debugger").} =
  # todo: reuse existing
  self.layout.addView(DebuggerView(), slot)

genDispatcher("debugger")
addGlobalDispatchTable "debugger", genDispatchTable("debugger")

proc handleAction(self: Debugger, action: string, arg: string): EventResponse =
  # debugf"[textedit] handleAction {action}, '{args}'"

  try:
    var args = newJArray()
    for a in newStringStream(arg).parseJsonFragments():
      args.add a

    if self.plugins.invokeAnyCallback(action, args).isNotNil:
      return Handled

    # debugf"dispatch {action}, {args}"
    if dispatch(action, args).isSome:
      return Handled
  except:
    log(lvlError, fmt"Failed to dispatch action '{action} {arg}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

  return Ignored

method getEventHandlers*(view: DebuggerView, inject: Table[string, EventHandler]): seq[EventHandler] =
  debugger.getEventHandlers(inject)

method getActiveEditor*(self: DebuggerView): Option[DocumentEditor] =
  {.gcsafe.}:
    if gDebugger.isNil or gDebugger.activeView != ActiveView.Output or gDebugger.outputEditor.isNil:
      return DocumentEditor.none
    return gDebugger.outputEditor.DocumentEditor.some
