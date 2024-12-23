import std/[strutils, macros, genasts, sequtils, sets, algorithm]
import plugin_runtime, keybindings_normal
import misc/[timer, util, myjsonutils, custom_unicode, id]
import input_api

embedSource()

infof"import helix keybindings"

var onModeChangedHandle: Id
var yankedLines: bool = false ## Whether the last thing we yanked was in a line mode

type EditorHelixState = object
  ## Contains state which can vary per editor
  selectLines: bool = false ## Whether entire lines should be selected (e.g. in visual-line mode/when using dd)
  deleteInclusiveEnd: bool = true ## Whether the next time we delete some the selection end should be inclusive
  cursorIncludeEol: bool = false ## Whether the cursor can be after the last character in a line (e.g. in insert mode)
  currentUndoCheckpoint: string = "insert" ## Which checkpoint to undo to (depends on mode)
  revisionBeforeImplicitInsertMacro: int
  cursorMoveMode: SelectionCursor = LastToFirst

var editorStates: Table[EditorId, EditorHelixState]
var helixMotionNextMode = initTable[EditorId, string]()

const editorContext = "editor.text"

proc helixState(editor: TextDocumentEditor): var EditorHelixState =
  if not editorStates.contains(editor.id):
    editorStates[editor.id] = EditorHelixState()
  return editorStates[editor.id]

proc shouldRecortImplicitPeriodMacro(editor: TextDocumentEditor): bool =
  case editor.getUsage()
  of "command-line", "search-bar":
    return false
  else:
    return true

proc recordCurrentCommandInPeriodMacro(editor: TextDocumentEditor) =
  if not isReplayingCommands() and editor.shouldRecortImplicitPeriodMacro():
    setRegisterText("", ".")
    editor.recordCurrentCommand(@["."])

proc startRecordingCurrentCommandInPeriodMacro(editor: TextDocumentEditor) =
  if not isReplayingCommands() and editor.shouldRecortImplicitPeriodMacro():
    startRecordingCommands(".-temp")
    setRegisterText("", ".-temp")
    editor.recordCurrentCommand(@[".-temp"])
    editor.helixState.revisionBeforeImplicitInsertMacro = editor.getRevision

proc helixClamp*(editor: TextDocumentEditor, cursor: Cursor): Cursor =
  var lineLen = editor.lineLength(cursor.line)
  if not editor.helixState.cursorIncludeEol and lineLen > 0: lineLen.dec
  result = (cursor.line, min(cursor.column, lineLen))

proc helixUndo(editor: TextDocumentEditor, enterNormalModeBefore: bool) {.exposeActive(editorContext, "helix-undo").} =
  if enterNormalModeBefore:
    editor.setMode "normal"

  editor.undo(editor.helixState.currentUndoCheckpoint)
  if enterNormalModeBefore:
    if not editor.selections.allEmpty:
      editor.setMode "visual"
    else:
      editor.setMode "normal"

proc helixRedo(editor: TextDocumentEditor, enterNormalModeBefore: bool) {.exposeActive(editorContext, "helix-redo").} =
  if enterNormalModeBefore:
    editor.setMode "normal"

  editor.redo(editor.helixState.currentUndoCheckpoint)
  if enterNormalModeBefore:
    if not editor.selections.allEmpty:
      editor.setMode "visual"
    else:
      editor.setMode "normal"

proc helixMoveCursorColumn(editor: TextDocumentEditor, direction: int, count: int = 1) {.exposeActive(editorContext, "helix-move-cursor-column").} =
  let cursorMoveMode = case editor.mode
  of "normal": Both
  of "visual": Last
  else: Both

  editor.moveCursorColumn(direction * max(count, 1), cursorMoveMode, wrap=false, includeAfter=editor.helixState.cursorIncludeEol)
  # if editor.helixState.selectLines:
  #   editor.helixSelectLine()
  editor.updateTargetColumn()

proc helixMoveCursorLine(editor: TextDocumentEditor, direction: int, count: int = 1, center: bool = false) {.exposeActive(editorContext, "helix-move-cursor-line").} =
  let cursorMoveMode = case editor.mode
  of "normal": Both
  of "visual": Last
  else: Both

  editor.moveCursorLine(direction * max(count, 1), cursorMoveMode, includeAfter=editor.helixState.cursorIncludeEol)
  if center:
    editor.setNextScrollBehaviour(CenterAlways)
  # if editor.helixState.selectLines:
  #   editor.helixSelectLine()

proc helixMoveCursorVisualLine(editor: TextDocumentEditor, direction: int, count: int = 1, center: bool = false) {.exposeActive(editorContext, "helix-move-cursor-visual-line").} =
  let cursorMoveMode = case editor.mode
  of "normal": Both
  of "visual": Last
  else: Both

  if editor.helixState.selectLines:
    editor.moveCursorLine(direction * max(count, 1), cursorMoveMode, includeAfter=editor.helixState.cursorIncludeEol)
  else:
    editor.moveCursorVisualLine(direction * max(count, 1), cursorMoveMode, includeAfter=editor.helixState.cursorIncludeEol)
  if center:
    editor.setNextScrollBehaviour(CenterAlways)
  # if editor.helixState.selectLines:
  #   editor.helixSelectLine()

proc loadHelixKeybindings*() {.expose("load-helix-keybindings").} =
  let t = startTimer()
  defer:
    infof"loadHelixKeybindings: {t.elapsed.ms} ms"

  info "Applying Helix keybindings"

  clearCommands("helix")

  setHandleInputs "helix", false
  setOption "editor.text.helix-motion-action", "helix-select-last-cursor"
  setOption "editor.text.cursor.movement.", "last"
  setOption "editor.text.cursor.movement.normal", "last"
  setOption "editor.text.cursor.wide.", true
  setOption "editor.text.default-mode", "normal"
  setOption "editor.text.inclusive-selection", false

  setHandleInputs "helix.normal", false
  setOption "editor.text.cursor.wide.normal", true

  setHandleInputs "helix.insert", true
  setOption "editor.text.cursor.wide.insert", false

  setHandleInputs "helix.visual", false
  setOption "editor.text.cursor.wide.visual", true
  setOption "editor.text.cursor.movement.visual", "last"

  setHandleInputs "helix.visual-line", false
  setOption "editor.text.cursor.wide.visual-line", true
  setOption "editor.text.cursor.movement.visual-line", "last"

  addModeChangedHandler onModeChangedHandle, proc(editor, oldMode, newMode: auto) {.gcsafe, raises: [].} =
    # infof"onEditorModeChanged: {arg.editor}, {arg.oldMode}, {arg.newMode}"
    if not editor.getCurrentEventHandlers().contains("helix"):
      return

    echo "helix handle mode changed"

    if newMode == "":
      editor.setMode "normal"
      return

    let recordModes = [
      "visual",
      "visual-line",
      "insert",
    ].toHashSet

    # infof"helix: handle mode change {oldMode} -> {newMode}"
    if newMode == "normal":
      if not isReplayingCommands() and isRecordingCommands(".-temp"):
        stopRecordingCommands(".-temp")

        if editor.getRevision > editor.helixState.revisionBeforeImplicitInsertMacro:
          infof"Record implicit macro because document was modified"
          let text = getRegisterText(".-temp")
          setRegisterText(text, ".")
        else:
          infof"Don't record implicit macro because nothing was modified"
    else:
      if oldMode == "normal" and newMode in recordModes:
        editor.startRecordingCurrentCommandInPeriodMacro()

      editor.clearCurrentCommandHistory(retainLast=true)

    editor.helixState.selectLines = newMode == "visual-line"
    editor.helixState.cursorIncludeEol = newMode == "insert"
    editor.helixState.currentUndoCheckpoint = if newMode == "insert": "word" else: "insert"

    case newMode
    of "normal":
      setOption "editor.text.helix-motion-action", "helix-select-last-cursor"
      setOption "editor.text.inclusive-selection", false
    #   helixMotionNextMode[editor.id] = "normal"
      editor.saveCurrentCommandHistory()
      editor.hideCompletions()

    of "insert":
      setOption "editor.text.inclusive-selection", false
    #   setOption "editor.text.helix-motion-action", ""
    #   helixMotionNextMode[editor.id] = "insert"

    of "visual":
      setOption "editor.text.inclusive-selection", true

    else:
      setOption "editor.text.inclusive-selection", false

  addTextCommand "helix#count", "<-1-9><o-0-9>", ""
  addCommand "#count", "<-1-9><o-0-9>", ""

  # Normal mode
  addCommand "editor", ":", "command-line"

  addTextCommandBlockDesc "helix.", "<C-e>", "exit to normal mode":
    editor.selection = editor.selection
    editor.setMode("normal")

  addTextCommandBlockDesc "helix.", "<ESCAPE>", "exit to normal mode and clear things":
    if editor.mode == "normal":
      editor.selection = editor.selection
      editor.clearTabStops()
    editor.setMode("normal")

  addCommandBlockDesc "command-line-low", "<ESCAPE>", "exit to normal mode and clear things":
    if getActiveEditor().isTextEditor(editor):
      if editor.mode == "normal":
        exitCommandLine()
        return

      if editor.mode == "normal":
        editor.clearTabStops()
      editor.setMode("normal")

  addCommandBlock "popup.selector", "<ESCAPE>":
    if getActiveEditor().isTextEditor(editor):
      if editor.mode == "normal":
        if getActivePopup().isSelectorPopup(popup):
          popup.cancel()
        return

      if editor.mode == "normal":
        editor.clearTabStops()
      editor.setMode("normal")

  # Mode switches
  addTextCommandBlock "helix.normal", "a":
    editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, 1, wrap=false).toSelection)
    editor.setMode "insert"
    editor.addNextCheckpoint "insert"
  addTextCommandBlock "helix.", "A":
    editor.moveLast "line", Both
    editor.setMode "insert"
    editor.addNextCheckpoint "insert"
  addTextCommandBlock "helix.normal", "i":
    editor.setMode "insert"
    editor.addNextCheckpoint "insert"
  addTextCommandBlock "helix.", "I":
    editor.moveFirst "line-no-indent", Both
    editor.setMode "insert"
    editor.addNextCheckpoint "insert"
  addTextCommandBlock "helix.normal", "gI":
    editor.moveFirst "line", Both
    editor.setMode "insert"
    editor.addNextCheckpoint "insert"

  addTextCommandBlock "helix.normal", "o":
    editor.moveLast "line", Both
    editor.addNextCheckpoint "insert"
    editor.insertText "\n"
    editor.setMode "insert"

  addTextCommandBlock "helix.normal", "O":
    editor.moveFirst "line", Both
    editor.addNextCheckpoint "insert"
    editor.insertText "\n", autoIndent=false
    editor.helixMoveCursorLine -1
    editor.setMode "insert"

  # Visual mode
  addTextCommandBlock "helix.normal", "v":
    editor.setMode "visual"

  addTextCommand "helix.", "u", "helix-undo", enterNormalModeBefore=true
  addTextCommand "helix.", "<C-r>", "helix-redo", enterNormalModeBefore=true
  addTextCommand "helix.", "U", "helix-redo", enterNormalModeBefore=false

  addTextCommand "helix.", "h", "helix-move-cursor-column", -1
  addTextCommand "helix.", "<LEFT>", "helix-move-cursor-column", -1

  addTextCommand "helix.", "l", "helix-move-cursor-column", 1
  addTextCommand "helix.", "<RIGHT>", "helix-move-cursor-column", 1

  addTextCommand "helix.", "k", "helix-move-cursor-visual-line", -1
  addTextCommand "helix.", "<UP>", "helix-move-cursor-visual-line", -1

  addTextCommand "helix.", "j", "helix-move-cursor-visual-line", 1
  addTextCommand "helix.", "<DOWN>", "helix-move-cursor-visual-line", 1
  addTextCommand "helix.", "<C-j>", "helix-move-cursor-visual-line", 1

  addTextCommand "helix.", "w", "move-selection-next", "vim-word", false, true
