import std/[options, tables, sets]
import vmath, bumpy
import misc/[id, custom_logger, util, event, response]
import dap_client, config_provider, command_service, events, dynamic_view, document, document_editor, layout
import platform/platform
import finder/[previewer]
import workspaces/workspace, vfs, vfs_service, language_server_dynamic
import ui/node
import nimsumtree/[rope, buffer]
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
    vfs*: Arc[VFS2]
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

    variableViews*: seq[VariablesView]

    languageServer*: LanguageServerDebugger

  ThreadsView* = ref object of DynamicView
    targetSelectionIndex*: Option[int]
    baseIndex*: int
    scrollOffset*: float
  StacktraceView* = ref object of DynamicView
    targetSelectionIndex*: Option[int]
    baseIndex*: int
    scrollOffset*: float
  VariablesView* = ref object of DynamicView
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
    filterVersion*: int = 0
    evaluation*: EvaluateResponse
    evaluationName*: string
    eventHandler*: EventHandler

  OutputView* = ref object of DynamicView
  ToolbarView* = ref object of DynamicView

  LanguageServerDebugger* = ref object of LanguageServerDynamic
    debugger*: Debugger
    evaluations*: Table[tuple[file: string, range: Selection, expression: string], Response[EvaluateResponse]]
