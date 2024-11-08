import std/[tables, json, options, strformat, strutils]
import misc/[util, custom_logger, delayed_task, custom_async, myjsonutils, array_set]
import text/[text_editor, text_document]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import finder, previewer
import vcs/vcs
import app_interface, vfs, service, document_editor

import nimsumtree/[rope]

logCategory "file-previewer"

type
  FilePreviewer* = ref object of Previewer
    services*: Services
    editors*: DocumentEditorService
    vfs: VFS
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
    currentLoadTask: Future[void]

proc newFilePreviewer*(vfs: VFS, services: Services,
    openNewDocuments: bool = false, reuseExistingDocuments: bool = true): FilePreviewer =
  new result
  result.services = services
  result.editors = services.getService(DocumentEditorService).get
  result.vfs = vfs

  result.openNewDocuments = openNewDocuments
  result.reuseExistingDocuments = reuseExistingDocuments
  result.tempDocument = newTextDocument(services, createLanguageServer=false)
  result.tempDocument.readOnly = true

  result.editors.pinnedDocuments.incl result.tempDocument

method deinit*(self: FilePreviewer) =
  logScope lvlInfo, &"[deinit] Destroying file previewer"

  self.editors.pinnedDocuments.excl self.tempDocument

  if self.triggerLoadTask.isNotNil:
    self.triggerLoadTask.deinit()
  if self.tempDocument.isNotNil:
    self.tempDocument.deinit()

  self[] = default(typeof(self[]))

proc parsePathAndLocationFromItemData*(item: FinderItem):
    Option[tuple[path: string, location: Option[Cursor], isFile: Option[bool]]] {.gcsafe, raises: [].} =
  try:
    if not item.data.startsWith("{"):
      return (item.data, Cursor.none, bool.none).some

    let jsonData = item.data.parseJson.catch:
      return

    if jsonData.kind != JObject:
      return

    if not jsonData.hasKey "path":
      return

    let path = jsonData.fields["path"]
    if path.kind != JString:
      return

    let isFile = if jsonData.hasKey("isFile") and jsonData.fields["isFile"].kind == JBool:
      jsonData.fields["isFile"].getBool.some
    else:
      bool.none

    var cursor: Option[Cursor] = if jsonData.hasKey "line":
      (
        jsonData.fields["line"].getInt,
        jsonData.fields.getOrDefault("column", % 0).getInt,
      ).some.catch:
        Cursor.none
    else:
      Cursor.none

    return (path.getStr, cursor, isFile).some

  except:
    return

proc loadAsync(self: FilePreviewer): Future[void] {.async.} =
  let revision = self.revision
  let path = self.currentPath
  let location = self.currentLocation
  let editor = self.editor

  logScope lvlInfo, &"loadAsync '{path}'"

  let isFile = self.currentIsFile.get(true)
  let document = if self.currentStaged or not self.reuseExistingDocuments or not isFile:
    Document.none
  elif self.openNewDocuments:
    self.editors.getOrOpenDocument(path)
  else:
    self.editors.getDocument(path)

  if document.getSome(document):
    if not (document of TextDocument):
      log lvlError, &"No support for non text documents yet."
      return

    log lvlInfo, &"[loadAsync] Show preview using existing document for '{path}'"
    editor.setDocument(document.TextDocument)

  elif self.tempDocument.isNotNil:
    logScope lvlInfo, &"[loadAsync] Show preview using temp document for '{path}'"
    var content = Rope.new()

    var fileKind = if self.currentIsFile.getSome(isFile):
      if isFile:
        FileKind.File
      else:
        FileKind.Directory
    elif self.vfs.getFileKind(path).await.getSome(kind):
      kind
    else:
      log lvlError, &"Unknown file or directory '{path}'"
      return

    case fileKind
    of FileKind.File:
      try:
        self.vfs.readRope(path, content.addr).await
      except IOError as e:
        log lvlError, &"Failed to load file: {e.msg}"
        content = Rope.new(e.msg)

    of FileKind.Directory:
      let listing = await self.vfs.getDirectoryListing(path)

      for name in listing.folders:
        content.add &"🗀 {name}\n"

      for name in listing.files:
        content.add &"🗎  {name}\n"

    if editor.document.isNil:
      log lvlInfo, fmt"Discard file load of '{path}' because preview editor was destroyed"
      return

    if self.revision > revision or editor.document.isNil:
      log lvlInfo, fmt"Discard file load of '{path}' because a newer one was requested"
      return

    if editor.document.isNil:
      log lvlInfo, fmt"Discard file load of '{path}' because preview editor was destroyed"
      return

    if self.revision > revision or editor.document.isNil:
      log lvlInfo, fmt"Discard file load of '{path}' because a newer one was requested"
      return

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

method delayPreview*(self: FilePreviewer) =
  if self.triggerLoadTask.isNotNil and self.triggerLoadTask.isActive:
    self.triggerLoadTask.reschedule()

method previewItem*(self: FilePreviewer, item: FinderItem, editor: DocumentEditor) =
  if not (editor of TextDocumentEditor):
    return

  logScope lvlInfo, &"previewItem {item}"

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
        if self.currentLoadTask != nil:
          self.currentLoadTask.cancelSoon()
          self.currentLoadTask = nil
        self.currentLoadTask = self.loadAsync()
    else:
      self.triggerLoadTask.reschedule()
