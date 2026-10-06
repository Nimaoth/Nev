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

  DebuggerVarChild* = object
    ## One lazily listed child row: precomposed display strings plus the
    ## container holding *its* children (0.VariablesReference = leaf).
    name*: string
    typ*: string
    value*: string
    childRef*: VariablesReference

  DebuggerVarNode* = object
    ## Cached listing for one tree key: the container holding this node's
    ## children (0.VariablesReference = leaf) plus the fetched children.
    ## `fetched=false` means a DAP fetch is in flight (or not yet requested).
    childRef*: VariablesReference
    fetched*: bool
    children*: seq[DebuggerVarChild]

  DebuggerVarCache* = ref object
    ## Listing cache for the variables tree (see file_explorer's
    ## VirtualFileSystemCursorCache): every cursor operation is a single
    ## hashtable lookup. Listings are copied out of the debugger tables and
    ## dropped wholesale whenever the context or table version changes, so
    ## copies can never go stale. Expansion state itself lives in the tree
    ## widget (keyed by stable index paths), not here.
    debugger*: Debugger
    view*: VariablesView
    ids*: (ThreadId, FrameId)
    version*: int
    valid*: bool
    nodes*: Table[string, DebuggerVarNode]

  DebuggerVarLocation* = ref object
    ## A position in the variables tree (see file_explorer's
    ## VirtualFileSystemCursorLocation): parent-linked, so exitChild is a
    ## pointer hop and row data rides along without any table lookup.
    parent*: DebuggerVarLocation
    key*: string
    scopeIdx*: int
    index*: int
    path*: seq[int]
    name*: string
    typ*: string
    value*: string
    container*: VariablesReference

  DebuggerVariablesCursor* = ref object of TreeCursor
    cache*: DebuggerVarCache
    location*: DebuggerVarLocation

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
    # Bumped on every variables/scopes table store; the variables tree cache
    # (DebuggerVarCache) drops its listings when this changes.
    varCacheVersion*: int = 0
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
    evaluation*: EvaluateResponse
    evaluationName*: string
    eventHandler*: EventHandler
    # Lazy listing cache for the tree table (see DebuggerVarCache).
    varCache*: DebuggerVarCache
    # In-flight async children fetches, guarded so lazy rows don't spam DAP.
    pendingVariableFetches*: HashSet[(ThreadId, FrameId, VariablesReference)]

  OutputView* = ref object of View
  ToolbarView* = ref object of View

  LanguageServerDebugger* = ref object of LanguageServer
    debugger*: Debugger
    evaluations*: Table[tuple[file: string, range: rope.Range[Point], expression: string], Response[EvaluateResponse]]

const DebuggerVarRootKey* = "vars"
  ## Key of the hidden tree root (its children are the scopes).

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


