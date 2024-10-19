import std/[options, os, json, sugar]
import vmath
import misc/[custom_async, custom_logger, util, myjsonutils, disposable_ref]
import text/[text_document, text_editor]
import scripting/expose
import workspaces/workspace
import finder/[finder, previewer, workspace_file_previewer]
import platform/[platform, filesystem]
import service, dispatch_tables, platform_service
import selector_popup, vcs, layout

logCategory "vcs_api"

proc getVCSService(): Option[VCSService] =
  {.gcsafe.}:
    if gServices.isNil: return VCSService.none
    return gServices.getService(VCSService)

static:
  addInjector(VCSService, getVCSService)

proc getChangedFilesFromGitAsync(self: VCSService, workspace: Workspace, all: bool): Future[ItemList] {.async.} =
  let vcsList = self.getAllVersionControlSystems()
  var items = newSeq[FinderItem]()

  for vcs in vcsList:
    let fileInfos = await vcs.getChangedFiles()

    for info in fileInfos:
      let (directory, name) = info.path.splitPath
      var relativeDirectory = workspace.getRelativePathSync(directory).get(directory)

      if relativeDirectory == ".":
        relativeDirectory = ""

      if info.stagedStatus != None and info.stagedStatus != Untracked:
        var info1 = info
        info1.unstagedStatus = None

        var info2 = info
        info2.stagedStatus = None

        items.add FinderItem(
          displayName: $info1.stagedStatus & $info1.unstagedStatus & " " & name,
          data: $ %info1,
          detail: relativeDirectory & "\t" & vcs.root,
        )
        items.add FinderItem(
          displayName: $info2.stagedStatus & $info2.unstagedStatus & " " & name,
          data: $ %info2,
          detail: relativeDirectory & "\t" & vcs.root,
        )
      else:
        items.add FinderItem(
          displayName: $info.stagedStatus & $info.unstagedStatus & " " & name,
          data: $ %info,
          detail: relativeDirectory & "\t" & vcs.root,
        )

    if not all:
      break

  return newItemList(items)

proc stageSelectedFileAsync(popup: SelectorPopup, self: VCSService,
    source: AsyncCallbackDataSource): Future[void] {.async.} =

  log lvlInfo, fmt"Stage selected entry ({popup.selected})"

  let item = popup.getSelectedItem().getOr:
    return

  let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
    log lvlError, fmt"Failed to parse file info from item: {item}"
    return
  debugf"staged selected {fileInfo}"

  if self.getVcsForFile(fileInfo.path).getSome(vcs):
    let res = await vcs.stageFile(fileInfo.path)
    debugf"add finished: {res}"
    if popup.textEditor.isNil:
      return

    source.retrigger()

proc unstageSelectedFileAsync(popup: SelectorPopup, self: VCSService,
    source: AsyncCallbackDataSource): Future[void] {.async.} =

  log lvlInfo, fmt"Unstage selected entry ({popup.selected})"

  let item = popup.getSelectedItem().getOr:
    return

  let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
    log lvlError, fmt"Failed to parse file info from item: {item}"
    return
  debugf"unstaged selected {fileInfo}"

  if self.getVcsForFile(fileInfo.path).getSome(vcs):
    let res = await vcs.unstageFile(fileInfo.path)
    debugf"unstage finished: {res}"
    if popup.textEditor.isNil:
      return

    source.retrigger()

proc revertSelectedFileAsync(popup: SelectorPopup, self: VCSService,
    source: AsyncCallbackDataSource): Future[void] {.async.} =

  log lvlInfo, fmt"Revert selected entry ({popup.selected})"

  let item = popup.getSelectedItem().getOr:
    return

  let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
    log lvlError, fmt"Failed to parse file info from item: {item}"
    return
  debugf"revert-selected {fileInfo}"

  if self.getVcsForFile(fileInfo.path).getSome(vcs):
    let res = await vcs.revertFile(fileInfo.path)
    debugf"revert finished: {res}"
    if popup.textEditor.isNil:
      return

    source.retrigger()

proc diffStagedFileAsync(self: VCSService, workspace: Workspace, path: string): Future[void] {.async.} =
  log lvlInfo, fmt"Diff staged '({path})'"

  let stagedDocument = newTextDocument(self.services, self.fs, path, load = false,
    workspaceFolder = workspace.some, createLanguageServer = false)
  stagedDocument.staged = true
  stagedDocument.readOnly = true

  let layout = self.services.getService(LayoutService).get
  if layout.createAndAddView(stagedDocument).getSome(editor):
    editor.TextDocumentEditor.updateDiff()

proc chooseGitActiveFiles*(self: VCSService, all: bool = false) {.expose("vcs").} =
  defer:
    if self.services.getService(PlatformService).getSome(platform):
      platform.platform.requestRender()

  let workspace = self.workspace

  let source = newAsyncCallbackDataSource () => self.getChangedFilesFromGitAsync(workspace, all)
  var finder = newFinder(source, filterAndSort=true)

  let previewer = newWorkspaceFilePreviewer(workspace, self.fs, self.services,
    openNewDocuments=true)

  var popup = newSelectorPopup(self.services, self.fs, "git".some, finder.some,
    previewer.Previewer.toDisposableRef.some)

  popup.scale.x = 1
  popup.scale.y = 0.9
  popup.previewScale = 0.75

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
      log lvlError, fmt"Failed to parse git file info from item: {item}"
      return true

    if fileInfo.stagedStatus != None:
      asyncSpawn self.diffStagedFileAsync(workspace, fileInfo.path)

    else:
      let currentVersionEditor = self.services.getService(LayoutService).get.openWorkspaceFile(fileInfo.path)
      if currentVersionEditor.getSome(editor):
        if editor of TextDocumentEditor:
          editor.TextDocumentEditor.updateDiff()
          if popup.getPreviewSelection().getSome(selection):
            editor.TextDocumentEditor.selection = selection
            editor.TextDocumentEditor.centerCursor()

    return true

  popup.addCustomCommand "stage-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    asyncSpawn popup.stageSelectedFileAsync(self, source)
    return true

  popup.addCustomCommand "unstage-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    asyncSpawn popup.unstageSelectedFileAsync(self, source)
    return true

  popup.addCustomCommand "revert-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    asyncSpawn popup.revertSelectedFileAsync(self, source)
    return true

  popup.addCustomCommand "diff-staged", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    let item = popup.getSelectedItem().getOr:
      return

    let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
      log lvlError, fmt"Failed to parse get file info from item: {item}"
      return true
    debugf"diff-staged {fileInfo}"

    asyncSpawn self.diffStagedFileAsync(workspace, fileInfo.path)
    return true

  let layout = self.services.getService(LayoutService).get
  layout.pushPopup popup

addGlobalDispatchTable "vcs", genDispatchTable("vcs")
