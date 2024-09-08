import std/[tables, json, options, strformat, strutils, os]
import misc/[util, custom_logger, delayed_task, custom_async, myjsonutils]
import workspaces/workspace
import text/[text_editor, text_document]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import finder, previewer
import vcs/vcs
import app_interface, config_provider, vfs

logCategory "workspace-file-previewer"

type
  WorkspaceFilePreviewer* = ref object of Previewer
    workspace: Workspace
    vfs: Option[VFS]
    configProvider: ConfigProvider
    editor: TextDocumentEditor
    tempDocument: TextDocument
    reuseExistingDocuments: bool
    openNewDocuments: bool
    revision: int
    triggerLoadTask: DelayedTask
    currentPath: string
    currentIsFile: Option[bool]
    currentLocation: Option[Cursor]
    currentStaged: bool
    currentDiff: bool

proc newWorkspaceFilePreviewer*(workspace: Workspace, configProvider: ConfigProvider,
    openNewDocuments: bool = false, reuseExistingDocuments: bool = true): WorkspaceFilePreviewer =
  new result
  result.workspace = workspace

  result.openNewDocuments = openNewDocuments
  result.reuseExistingDocuments = reuseExistingDocuments
  result.tempDocument = newTextDocument(configProvider, workspaceFolder=workspace.some,
    createLanguageServer=false)
  result.tempDocument.readOnly = true

proc newWorkspaceFilePreviewer*(workspace: Workspace, vfs: VFS, configProvider: ConfigProvider,
    openNewDocuments: bool = false, reuseExistingDocuments: bool = true): WorkspaceFilePreviewer =
  new result
  result.workspace = workspace
  result.vfs = vfs.some

  result.openNewDocuments = openNewDocuments
  result.reuseExistingDocuments = reuseExistingDocuments
  result.tempDocument = newTextDocument(configProvider, workspaceFolder=workspace.some,
    createLanguageServer=false)
  result.tempDocument.readOnly = true

method deinit*(self: WorkspaceFilePreviewer) =
  logScope lvlInfo, &"[deinit] Destroying workspace file previewer"
  if self.triggerLoadTask.isNotNil:
    self.triggerLoadTask.deinit()
  if self.tempDocument.isNotNil:
    self.tempDocument.deinit()

  self[] = default(typeof(self[]))

proc parsePathAndLocationFromItemData*(item: FinderItem):
    Option[tuple[path: string, location: Option[Cursor], isFile: Option[bool]]] =
  if item.data.WorkspacePath.decodePath().getSome(ws):
    return (ws.path, Cursor.none, bool.none).some

  if not item.data.startsWith("{"):
    return (item.data, Cursor.none, bool.none).some

  let jsonData = item.data.parseJson.catch:
    return

  if jsonData.kind != JObject:
    return

  if not jsonData.hasKey "path":
    return

  let path = jsonData["path"]
  if path.kind != JString:
    return

  let isFile = if jsonData.hasKey("isFile") and jsonData["isFile"].kind == JBool:
    jsonData["isFile"].getBool.some
  else:
    bool.none

  var cursor: Option[Cursor] = if jsonData.hasKey "line":
    (
      jsonData["line"].getInt,
      jsonData.fields.getOrDefault("column", % 0).getInt,
    ).some.catch:
      Cursor.none
  else:
    Cursor.none

  return (path.getStr, cursor, isFile).some

proc loadAsync(self: WorkspaceFilePreviewer): Future[void] {.async.} =
  let revision = self.revision
  let path = self.currentPath
  let location = self.currentLocation
  let editor = self.editor

  let app = editor.app

  logScope lvlDebug, &"loadAsync {path}"

  let document = if self.currentStaged or not self.reuseExistingDocuments:
    Document.none
  elif self.openNewDocuments:
    app.getOrOpenDocument(path, app=false)
  else:
    app.getDocument(path, app=false)

  if document.getSome(document):
    if not (document of TextDocument):
      log lvlError, &"No support for non text documents yet."
      return

    log lvlInfo, &"[loadAsync] Show preview using existing document for '{path}'"
    editor.setDocument(document.TextDocument)

  elif self.tempDocument.isNotNil:
    logScope lvlInfo, &"[loadAsync] Show preview using temp document for '{path}'"
    var content = ""

    if self.currentIsFile.getSome(isFile):
      if isFile:
        if self.vfs.getSome(vfs):
          content = vfs.read(path).await.get("")
        else:
          await self.workspace.loadFile(path, content.addr)
      else:
        let listing = await self.workspace.getDirectoryListing(path)

        for dir in listing.folders:
          let name = dir.extractFilename
          content.add &"🗀 {name}\n"

        for file in listing.files:
          let name = file.extractFilename
          content.add &"🗎  {name}\n"

    else:
      # Just assume it's a file, returns empty string when it's a directory which is fine
      if self.vfs.getSome(vfs):
        content = vfs.read(path).await.get("")
      else:
        await self.workspace.loadFile(path, content.addr)

    if editor.document.isNil:
      log lvlInfo, fmt"Discard file load of '{path}' because preview editor was destroyed"
      return

    if self.revision > revision or editor.document.isNil:
      log lvlInfo, fmt"Discard file load of '{path}' because a newer one was requested"
      return

    self.tempDocument.workspace = self.workspace.some
    self.tempDocument.setFileAndContent(path, content.move)
    editor.setDocument(self.tempDocument)

  if location.getSome(location):
    editor.targetSelection = location.toSelection
    editor.centerCursor()
  else:
    editor.targetSelection = (0, 0).toSelection
    editor.scrollToTop()

  if self.currentDiff:
    self.editor.document.staged = self.currentStaged
    self.editor.updateDiff(gotoFirstDiff=true)
  else:
    self.editor.document.staged = false
    self.editor.closeDiff()

  editor.markDirty()

method delayPreview*(self: WorkspaceFilePreviewer) =
  if self.triggerLoadTask.isNotNil and self.triggerLoadTask.isActive:
    self.triggerLoadTask.reschedule()

method previewItem*(self: WorkspaceFilePreviewer, item: FinderItem, editor: DocumentEditor) =
  if not (editor of TextDocumentEditor):
    return

  logScope lvlDebug, &"previewItem {item}"

  inc self.revision
  self.editor = editor.TextDocumentEditor

  var path: string
  var location: Option[Cursor]
  var isFile = bool.none

  let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).some.catch: VCSFileInfo.none
  if fileInfo.isSome:
    path = fileInfo.get.path
  else:
    let infos = item.parsePathAndLocationFromItemData.getOr:
      log lvlError, fmt"Failed to preview item because of invalid data format. " &
        fmt"Expected path or json object with path property {item}"
      return
    path = infos.path
    location = infos.location
    isFile = infos.isFile

  if fileInfo.getSome(fileInfo) and not fileInfo.isUntracked:
    self.currentDiff = true
    if fileInfo.stagedStatus != None:
      self.currentStaged = true
    else:
      self.currentStaged = false
  else:
    self.currentDiff = false
    self.currentStaged = false

  log lvlInfo, &"[previewItem] Request preview for '{path}' at {location}"

  self.currentPath = path
  self.currentLocation = location
  self.currentIsFile = isFile

  if self.editor.document.filename == path and self.editor.document.staged == self.currentStaged:
    if location.getSome(location):
      self.editor.targetSelection = location.toSelection
      self.editor.centerCursor()
    else:
      self.editor.targetSelection = (0, 0).toSelection
      self.editor.scrollToTop()

    if self.currentDiff:
      self.editor.document.staged = self.currentStaged
      self.editor.updateDiff(gotoFirstDiff=true)
    else:
      self.editor.document.staged = false
      self.editor.closeDiff()

    self.triggerLoadTask.pause()

  else:
    if self.triggerLoadTask.isNil:
      self.triggerLoadTask = startDelayed(100, repeat=false):
        asyncCheck self.loadAsync()
    else:
      self.triggerLoadTask.reschedule()
