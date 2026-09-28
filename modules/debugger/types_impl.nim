import std/[options, tables, sets]
import misc/[id, custom_logger, util, event, response]
import dap_client, config_provider, command_service, input_handler/input_handler, view, document, document_editor, layout/layout
import platform
import previewer
import workspace, vfs, vfs_service
import language_server
import nimsumtree/[rope, buffer]
import nuigi/widgets/tree_table
import types

export types

import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil

type
  DebuggerConnectionKind* = enum Tcp = "tcp", Stdio = "stdio", Websocket = "websocket"

  ActiveView* {.pure.} = enum Threads, StackTrace, Variables, Output
  DebuggerState* {.pure.} = enum None, Starting, Paused, Running

  VariableCursor* = object
    scope*: int
    path*: seq[tuple[index: int, varRef: VariablesReference]]

  DebuggerVariablesCursor* = ref object of TreeCursor
    ## Tree-table cursor for the variables view (see file_explorer's
    ## VirtualFileSystemCursor). Navigation state is just the TreeCursor index
    ## path @[scopeIdx, childIdx...] (hidden root is @[]); variable identities
    ## are resolved live through the debugger tables so cursors never go stale
    ## across DAP refetches and rows never need precalculating.
    debugger*: Debugger
    view*: VariablesView

  BreakpointInfo* = object
    path*: string
    enabled*: bool = true
    breakpoint*: SourceBreakpoint
    anchor*: Option[Anchor]

  Debugger* = ref object of DebuggerService
    platform*: Platform
    events*: EventHandlerService
    config*: ConfigService
    workspace*: Workspace
    editors*: DocumentEditorService
    layout*: LayoutService
    commands*: CommandService
    vfs*: VFS
    client*: Option[DapClient]
    lastConfiguration*: Option[string]
    activeView*: ActiveView = ActiveView.Variables
    currentThreadIndex*: int
    currentFrameIndex*: int
    maxVariablesScrollOffset*: float
    debuggerState*: DebuggerState = DebuggerState.None
    eventHandler*: EventHandler
    threadsEventHandler*: EventHandler
    stackTraceEventHandler*: EventHandler
    outputEventHandler*: EventHandler

    breakpointsEnabled*: bool = true

    readOnlyEditors*: seq[DocumentEditor]
    lastEditor*: Option[DocumentEditor]
    outputEditor*: DocumentEditor

    currentStopData*: OnStoppedData

    # Data setup in the editor and sent to the server
    breakpoints*: Table[string, seq[BreakpointInfo]]
    documentCallbacks*: Table[string, tuple[document: Document, onSavedId: Id, onTextChangedId: Id]]

    # Cached data from server
    timestamp*: int = 1
    threads*: seq[ThreadInfo]
    stackTraces*: Table[ThreadId, StackTraceResponse]
    scopes*: Table[(ThreadId, FrameId), Scopes]
    variables*: Table[(ThreadId, FrameId, VariablesReference), Variables]

    watchExpressions*: seq[string]

    variableViews*: seq[VariablesView]

    languageServer*: LanguageServerDebugger

  ThreadsView* = ref object of View
  StacktraceView* = ref object of View
  VariablesView* = ref object of View
    variablesCursor*: VariableCursor
    collapsedVariables*: HashSet[(ThreadId, FrameId, VariablesReference)]
    variablesFilter*: string = ""
    filteredVariables*: HashSet[(int, VariablesReference)]
    filteredCursors*: seq[VariableCursor]
    filterVersion*: int = 0
    evaluation*: EvaluateResponse
    evaluationName*: string
    eventHandler*: EventHandler
    # NUI tree-table state (render.nim): cached TreeTable storage so keyboard
    # commands can drive the same expansion the tree widget owns.
    varTree*: TreeTable
    varTreeValid*: bool = false
    varTreeIds*: (ThreadId, FrameId)
    # In-flight async children fetches, guarded so lazy rows don't spam DAP.
    pendingVariableFetches*: HashSet[(ThreadId, FrameId, VariablesReference)]

  OutputView* = ref object of View
  ToolbarView* = ref object of View

  LanguageServerDebugger* = ref object of LanguageServer
    debugger*: Debugger
    evaluations*: Table[tuple[file: string, range: rope.Range[Point], expression: string], Response[EvaluateResponse]]

proc debuggerVarCursorKey*(path: seq[int]): string {.gcsafe, raises: [].} =
  ## Stable index-based key shared by the cursor override (render.nim) and the
  ## keyboard tree writes (debugger.nim). Indices (not varRefs) stay valid
  ## across DAP refetches that remap variable references.
  try:
    if path.len == 0:
      return "dbgvar:root"
    result = "dbgvar:s" & $path[0]
    for i in 1 ..< path.len:
      result.add "/" & $path[i]
  except:
    result = "dbgvar:root"

proc variableCursorIndexPath*(cursor: VariableCursor): seq[int] {.gcsafe, raises: [].} =
  ## Maps a VariableCursor to a tree-table index path: @[scope, childIdx...].
  ## Scope rows are @[scopeIdx], the (hidden) root is @[].
  try:
    result = newSeqOfCap[int](cursor.path.len + 1)
    result.add(cursor.scope)
    for (index, _) in cursor.path:
      result.add(index)
  except:
    result = @[]

proc findVarTreeNode*(tree: TreeTable, key: string): int {.gcsafe, raises: [].} =
  ## Finds an active expanded slot by cursor key. Uses only public TreeTable
  ## fields (free slots have nil cursors). Returns -1 when absent/nil.
  try:
    if tree == nil:
      return -1
    for i in 0 ..< tree.nodes.len:
      if tree.nodes[i].cursor != nil and tree.nodes[i].cursor.cursorKey() == key:
        return i
    return -1
  except:
    return -1

proc isVarTreeExpanded*(tree: TreeTable, key: string): bool {.gcsafe, raises: [].} =
  try:
    return findVarTreeNode(tree, key) >= 0
  except:
    return false
