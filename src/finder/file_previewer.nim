import std/[tables, json, options, strformat, strutils]
import misc/[util, custom_logger, delayed_task, custom_async, myjsonutils, array_set, jsonex, rope_utils]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import finder, previewer
import vcs/vcs
import vfs, service, document_editor
import document, text_component, move_component, text_editor_component, command_component

import nimsumtree/[rope, arc]

logCategory "file-previewer"

type
  FilePreviewer* = ref object of Previewer
    services*: Services
    editors*: DocumentEditorService
    vfs: Arc[VFS2]
    editor*: DocumentEditor
    tempDocument: Document
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

proc newFilePreviewer*(vfs: Arc[VFS2], services: Services,
    openNewDocuments: bool = false, reuseExistingDocuments: bool = true): FilePreviewer =
  new result
  result.services = services
  result.editors = services.getService(DocumentEditorService).get
  result.vfs = vfs

  result.openNewDocuments = openNewDocuments
  result.reuseExistingDocuments = reuseExistingDocuments
  result.tempDocument = result.editors.createDocument("text", "", load = false, %%*{
    "usage": "temp-preview",
    "createLanguageServer": false,
  })
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

proc loadAsync(self: FilePreviewer): Future[void] {.async.} =
  let revision = self.revision
  let path = self.currentPath
  let location = self.currentLocation
  let editor = self.editor
  let isFile = self.currentIsFile.get(true)

  logScope lvlInfo, &"loadAsync '{path}', (staged: {self.currentStaged}, is file: {isFile}, reuse existing: {self.reuseExistingDocuments}, open new: {self.openNewDocuments})"

  let document = if self.currentStaged or not self.reuseExistingDocuments or not isFile:
    Document.none
  elif self.openNewDocuments:
    self.editors.getOrOpenDocument(path)
  else:
    self.editors.getDocument(path)

  if document.getSome(document):
    log lvlInfo, &"[loadAsync] Show preview using existing document for '{path}'"
    editor.setDocument(document)

  elif self.tempDocument.isNotNil:
    logScope lvlInfo, &"[loadAsync] Show preview using temp document for '{path}'"
    var content = Rope.new()

    var fileKind = FileKind.File
    if self.currentIsFile.getSome(isFile):
      if isFile:
        fileKind = FileKind.File
      else:
        fileKind = FileKind.Directory
    else:
      let kind = self.vfs.getFileKind(path).await
      if kind.isSome:
        fileKind = kind.get
      else:
        log lvlError, &"Unknown file or directory '{path}'"
        return

    case fileKind
    of FileKind.File:
      try:
        self.vfs.readRope(path, content.addr).await
      except InvalidUtf8Error as e:
        log lvlWarn, &"Failed to load file: {e.msg}"
        content = Rope.new(e.msg)
      except IOError as e:
        log lvlError, &"Failed to load file: {e.msg}"
        content = Rope.new(e.msg)

    of FileKind.Directory:
      let listing = await self.vfs.getDirectoryListing(path)

      for name in listing.folders:
        content.add &"D {name}\n"

      for name in listing.files:
        content.add &"F {name}\n"

    if editor.currentDocument.isNil:
      log lvlInfo, fmt"Discard file load of '{path}' because preview editor was destroyed"
      return

    if self.revision > revision or editor.currentDocument.isNil:
      log lvlInfo, fmt"Discard file load of '{path}' because a newer one was requested"
      return

    if editor.currentDocument.isNil:
      log lvlInfo, fmt"Discard file load of '{path}' because preview editor was destroyed"
      return

    if self.revision > revision or editor.currentDocument.isNil:
      log lvlInfo, fmt"Discard file load of '{path}' because a newer one was requested"
      return

    self.tempDocument.getTextComponent().get.setFileAndContent(path, content.move)
    editor.setDocument(self.tempDocument)

  let te = editor.getTextEditorComponent().get

  if location.getSome(location):
    te.targetSelection = location.toSelection.toRange
    te.centerCursor(location.toPoint)
  else:
    te.targetSelection = point(0, 0).toRange
    te.scrollToCursor(point(0, 0))

  if self.currentDiff:
    self.editor.getCommandComponent().get.executeCommand(&"""start-diff "" true {self.currentStaged}""")
  else:
    self.editor.getCommandComponent().get.executeCommand(&"""close-diff""")

  editor.markDirty()

method delayPreview*(self: FilePreviewer) =
  if self.triggerLoadTask.isNotNil and self.triggerLoadTask.isActive:
    self.triggerLoadTask.reschedule()

method previewItem*(self: FilePreviewer, item: FinderItem, editor: DocumentEditor) =
  # logScope lvlInfo, &"previewItem {item}"

  inc self.revision
  self.editor = editor

  var path: string
  var location: Option[Cursor]
  var isFile = bool.none

  let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo, Joptions(allowExtraKeys: true)).some.catch: VCSFileInfo.none
  if fileInfo.isSome:
    path = fileInfo.get.path
    isFile = true.some
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

  # log lvlInfo, &"[previewItem] Request preview for '{path}' at {location}"

  self.currentPath = path
  self.currentLocation = location
  self.currentIsFile = isFile
  let te = editor.getTextEditorComponent().get

  if self.editor.currentDocument.filename == path and self.editor.currentDocument.staged == self.currentStaged:
    if location.getSome(location):
      te.targetSelection = location.toSelection.toRange
      te.centerCursor(location.toPoint)
    else:
      te.targetSelection = point(0, 0).toRange
      te.scrollToCursor(point(0, 0))

    if self.currentDiff:
      self.editor.getCommandComponent().get.executeCommand(&"""start-diff "" true {self.currentStaged}""")
    else:
      self.editor.getCommandComponent().get.executeCommand(&"""close-diff""")

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
