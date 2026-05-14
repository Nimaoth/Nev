import std/[options, os, json, sugar, tables]
import vmath
import misc/[custom_async, custom_logger, util, myjsonutils, disposable_ref, jsonex, rope_utils]
import misc/expose
import workspace
import finder/[finder, previewer, file_previewer]
import platform
import service, dispatch_tables
import selector_popup/builder, vcs, layout/layout, vfs, config_provider
from scripting_api import SelectionCursor, ScrollSnapBehaviour, toSelection
import document_editor, text_editor_component, move_component, command_component

logCategory "vcs_api"

proc getVCSService(): Option[VCSService] =
  {.gcsafe.}:
    if getServices().isNil: return VCSService.none
    return getServices().getService(VCSService)

static:
  addInjector(VCSService, getVCSService)

proc getChangedFilesFromGitAsync(self: VCSService, workspace: Workspace, all: bool): Future[ItemList] {.async: (raises: []).} =
  let vcsList = self.getAllVersionControlSystems()
  var items = newSeq[FinderItem]()

  for vcs in vcsList:
    try:
      let changelists = await vcs.getChangedFiles()

      for changelist in changelists:
        for info in changelist.files:
          var info = info
          let (directory, name) = info.path.splitPath
          var relativeDirectory = workspace.getRelativePathSync(directory).get(directory)
          info.path = self.vfs.normalize(info.path)

          if relativeDirectory == ".":
            relativeDirectory = ""

          items.add FinderItem(
            displayName: $info.stagedStatus & $info.unstagedStatus & " " & name,
            data: $ %info,
            details: @[changelist.id, relativeDirectory, vcs.root],
          )

      if not all:
        break

    except CatchableError:
      log lvlError, &"Failed to get changed files from {vcs.root}"

  return newItemList(items)

proc stageSelectedFileAsync(popup: ISelectorPopup, self: VCSService,
    source: AsyncCallbackDataSource): Future[void] {.async.} =

  log lvlInfo, fmt"Stage selected entry ({popup.getSelectedItem()})"

  let item = popup.getSelectedItem().getOr:
    return

  let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
    log lvlError, fmt"Failed to parse file info from item: {item}"
    return
  debugf"staged selected {fileInfo}"

  let localizedPath = self.vfs.localize(fileInfo.path)
  if self.getVcsForFile(localizedPath).getSome(vcs):
    let res = await vcs.stageFile(localizedPath)
    if popup.closed():
      return
    source.retrigger()

proc unstageSelectedFileAsync(popup: ISelectorPopup, self: VCSService,
    source: AsyncCallbackDataSource): Future[void] {.async.} =

  log lvlInfo, fmt"Unstage selected entry ({popup.getSelectedItem()})"

  let item = popup.getSelectedItem().getOr:
    return

  let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
    log lvlError, fmt"Failed to parse file info from item: {item}"
    return
  debugf"unstaged selected {fileInfo}"

  let localizedPath = self.vfs.localize(fileInfo.path)
  if self.getVcsForFile(localizedPath).getSome(vcs):
    let res = await vcs.unstageFile(localizedPath)
    if popup.closed():
      return
    source.retrigger()

proc revertSelectedFileAsync(popup: ISelectorPopup, self: VCSService,
    source: AsyncCallbackDataSource): Future[void] {.async.} =

  log lvlInfo, fmt"Revert selected entry ({popup.getSelectedItem()})"

  let item = popup.getSelectedItem().getOr:
    return

  let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
    log lvlError, fmt"Failed to parse file info from item: {item}"
    return
  debugf"revert-selected {fileInfo}"

  let localizedPath = self.vfs.localize(fileInfo.path)
  if self.getVcsForFile(localizedPath).getSome(vcs):
    let res = await vcs.revertFile(localizedPath)
    if popup.closed():
      return
    source.retrigger()

proc diffStagedFileAsync(self: VCSService, workspace: Workspace, path: string): Future[void] {.async.} =
  log lvlInfo, fmt"Diff staged '({path})'"

  let stagedDocument = getServiceChecked(DocumentEditorService).createDocument("text", path, load = false, %%*{
    "createLanguageServer": false,
    "staged": true,
    "usage": "staged",
    "settings": {
      "editor.save-in-session": false,
    }
  })
  stagedDocument.readOnly = true

  let layout = self.services.getServiceChecked(LayoutService)
  if layout.createAndAddView(stagedDocument).getSome(editor):
    editor.getCommandComponent().get.executeCommand(&"""update-diff""")

proc chooseGitActiveFiles*(self: VCSService, all: bool = false) {.expose("vcs").} =
  defer:
    if self.services.getService(PlatformService).getSome(platform):
      platform.platform.requestRender()

  let workspace = self.workspace

  let source = newAsyncCallbackDataSource () => self.getChangedFilesFromGitAsync(workspace, all)
  var finder = newFinder(source, filterAndSort=true)

  let previewer = newFilePreviewer(self.vfs, self.services, openNewDocuments=true)

  var popup = SelectorPopupBuilder()
  popup.scope = "git".some
  popup.finder = finder.some
  popup.previewer = previewer.Previewer.some

  for vcs in self.getAllVersionControlSystems():
    popup.title.add &"{vcs.name}: {vcs.status}"
    break

  popup.scaleX = 1
  popup.scaleY = 0.9
  popup.previewScale = 0.75

  popup.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
    let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
      log lvlError, fmt"Failed to parse git file info from item: {item}"
      return true

    if fileInfo.stagedStatus != None:
      asyncSpawn self.diffStagedFileAsync(workspace, self.vfs.localize(fileInfo.path))

    else:
      let currentVersionEditor = self.services.getServiceChecked(LayoutService).openFile(fileInfo.path)
      if currentVersionEditor.getSome(editor):
        if editor.getCommandComponent().getSome(commands):
          commands.executeCommand(&"""update-diff""")

        let previewEditor = popup.getPreviewEditor()
        if previewEditor.isNil:
          return true
        let previewTE = previewEditor.getTextEditorComponent().getOr:
          return true
        if editor.getTextEditorComponent().getSome(te):
          te.selection = previewTE.selection
          te.centerCursor(te.selection.b)

    return true

  popup.customActions["refresh"] = proc(popup: ISelectorPopup, args: JsonNode): bool =
    source.retrigger()
    return true

  popup.customActions["stage-selected"] = proc(popup: ISelectorPopup, args: JsonNode): bool =
    asyncSpawn popup.stageSelectedFileAsync(self, source)
    return true

  popup.customActions["unstage-selected"] = proc(popup: ISelectorPopup, args: JsonNode): bool =
    asyncSpawn popup.unstageSelectedFileAsync(self, source)
    return true

  popup.customActions["revert-selected"] = proc(popup: ISelectorPopup, args: JsonNode): bool =
    asyncSpawn popup.revertSelectedFileAsync(self, source)
    return true

  popup.customActions["diff-staged"] = proc(popup: ISelectorPopup, args: JsonNode): bool =
    let item = popup.getSelectedItem().getOr:
      return

    let fileInfo = item.data.parseJson.jsonTo(VCSFileInfo).catch:
      log lvlError, fmt"Failed to parse get file info from item: {item}"
      return true
    debugf"diff-staged {fileInfo}"

    asyncSpawn self.diffStagedFileAsync(workspace, self.vfs.localize(fileInfo.path))
    return true

  popup.customActions["prev-change"] = proc(popup: ISelectorPopup, args: JsonNode): bool =
    if popup.getPreviewEditor().getTextEditorComponent().getSome(te) and popup.getPreviewEditor().getMoveComponent().getSome(moves):
      te.selection = moves.applyMove(te.selection, "(prev-change)")
      te.centerCursor(te.selection.b)
    return true

  popup.customActions["next-change"] = proc(popup: ISelectorPopup, args: JsonNode): bool =
    if popup.getPreviewEditor().getTextEditorComponent().getSome(te) and popup.getPreviewEditor().getMoveComponent().getSome(moves):
      te.selection = moves.applyMove(te.selection, "(next-change)")
      te.centerCursor(te.selection.b)
    return true

  popup.customActions["stage-change"] = proc(popup: ISelectorPopup, args: JsonNode): bool =
    if popup.getPreviewEditor().getCommandComponent().getSome(commands):
      commands.executeCommand("stage-selected")
    return true

  popup.customActions["revert-change"] = proc(popup: ISelectorPopup, args: JsonNode): bool =
    if popup.getPreviewEditor().getCommandComponent().getSome(commands):
      commands.executeCommand("revert-selected")
    return true

  let layout = self.services.getServiceChecked(LayoutService)
  discard layout.pushSelectorPopup popup

addGlobalDispatchTable "vcs", genDispatchTable("vcs")
