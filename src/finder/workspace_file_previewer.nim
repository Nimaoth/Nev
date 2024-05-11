import std/[tables, json, options, strformat, strutils]
import misc/[util, custom_logger, delayed_task, custom_async]
import workspaces/workspace
import text/[text_editor, text_document]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import finder, previewer

logCategory "workspace-file-previewer"

type
  WorkspaceFilePreviewer* = ref object of Previewer
    workspace: WorkspaceFolder
    editor: TextDocumentEditor
    revision: int
    triggerLoadTask: DelayedTask
    currentPath: string
    currentLocation: Option[Cursor]

proc newWorkspaceFilePreviewer*(workspace: WorkspaceFolder): WorkspaceFilePreviewer =
  new result
  result.workspace = workspace

proc parsePathAndLocationFromItemData*(item: FinderItem): Option[(string, Option[Cursor])] =
  if item.data.WorkspacePath.decodePath().getSome(ws):
    return (ws.path, Cursor.none).some

  if not item.data.startsWith("{"):
    return (item.data, Cursor.none).some

  let jsonData = item.data.parseJson.catch:
    return

  if jsonData.kind != JObject:
    return

  if not jsonData.hasKey "path":
    return

  let path = jsonData["path"]
  if path.kind != JString:
    return

  var cursor: Option[Cursor] = if jsonData.hasKey "line":
    (
      jsonData["line"].getInt,
      jsonData.fields.getOrDefault("column", % 0).getInt,
    ).some.catch:
      Cursor.none
  else:
    Cursor.none

  return (path.getStr, cursor).some

proc loadAsync(self: WorkspaceFilePreviewer): Future[void] {.async.} =
  let revision = self.revision
  let path = self.currentPath
  let location = self.currentLocation
  let editor = self.editor

  log lvlInfo, &"[loadAsync] Load preview for '{path}'"
  let content = self.workspace.loadFile(path).await
  if editor.document.isNil:
    log lvlInfo, fmt"Discard file load of 'path' because preview editor was destroyed"
    return

  if self.revision > revision or editor.document.isNil:
    log lvlInfo, fmt"Discard file load of 'path' because a newer one was requested"
    return

  editor.document.setFileAndContent(path, content)
  if location.getSome(location):
    editor.selection = location.toSelection
    editor.centerCursor()
  else:
    editor.selection = (0, 0).toSelection
    editor.scrollToTop()

  editor.markDirty()

method delayPreview*(self: WorkspaceFilePreviewer) =
  if self.triggerLoadTask.isNotNil:
    self.triggerLoadTask.reschedule()

method previewItem*(self: WorkspaceFilePreviewer, item: FinderItem, editor: DocumentEditor) =
  if not (editor of TextDocumentEditor):
    return

  let (path, location) = item.parsePathAndLocationFromItemData.getOr:
    log lvlError, fmt"Failed to preview item because of invalid data format. " &
      fmt"Expected path or json object with path property {item}"
    return

  inc self.revision
  self.editor = editor.TextDocumentEditor

  log lvlInfo, &"[previewItem] Request preview for '{path}' at {location}"
  if self.editor.document.filename == path:
    if location.getSome(location):
      self.editor.selection = location.toSelection
      self.editor.centerCursor()
    else:
      self.editor.selection = (0, 0).toSelection
      self.editor.scrollToTop()

  else:
    self.currentPath = path
    self.currentLocation = location

    if self.triggerLoadTask.isNil:
      self.triggerLoadTask = startDelayed(100, repeat=false):
        asyncCheck self.loadAsync()
    else:
      self.triggerLoadTask.reschedule()
