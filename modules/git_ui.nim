#use command_component layout text_editor_component command_service event_service input_handler toast treesitter session
import std/[options, algorithm, strutils, tables, json, sugar]
import service
import component
import vcs

export component

const currentSourcePath2 = currentSourcePath()
include module_base

# Implementation
when implModule:
  import std/[sets, math, sequtils, os, osproc, streams]
  import misc/[custom_logger, util, id, myjsonutils, jsonex, rope_utils, async_process, custom_async, delayed_task]
  import text_component, event_service, document_editor, document, view, layout/layout, command_component, platform
  import nimsumtree/[buffer, clock, rope]
  import command_service, workspace, config_component, text_editor_component, session
  import vfs
  import vmath, chroma
  import theme
  import misc/[render_command]
  import input_handler/input_handler
  import toast
  import nuigi
  import nuigi/widgets
  import nuigi/widgets/dynamic_virtuallist
  import nuigi/widgets/collapsing_header
  import nuigi/layout/flex

  logCategory "git-ui"

  type
    CursorPanel = enum Changelists, Commits, Branches
    UiCursor = object
      case panel: CursorPanel
      of Changelists:
        changelistIndex: int
        fileIndex: int
      of Commits:
        commitIndex: int
      of Branches:
        branchIndex: int

    GitUiView* = ref object of View
      eventHandlers*: Table[string, EventHandler]
      events*: EventHandlerService
      editors*: DocumentEditorService
      platform*: Platform
      vcsService*: VCSService
      themes: ThemeService
      branches*: seq[string]
      lastMessage*: string = "Refreshed"
      lastMessageError*: bool = false
      commitDoc: Document
      commitEditor*: DocumentEditor
      editCommit*: bool
      savedCommitMessage*: string
      commits*: seq[VCSCommitInfo]
      commitsFetched*: bool
      changelists*: seq[tuple[vcs: VersionControlSystem, changelist: VCSChangelist]]
      commitOnMessageSave*: bool = false
      uiId: Id
      scrollOffset: float

      cursor: UiCursor
      hoveredChangelistIndex: int = -1
      hoveredFileIndex: int = -1

      lastUpdate: int = 0
      actionsMenuOpen: bool = false
      repositoryWatches: Table[string, VFSWatchHandle]
      refreshTask: DelayedTask
      refreshPending: bool = false
      refreshing: bool = false
      changelistsExpanded: Table[string, bool]
      commitsExpanded: bool = true
      branchesExpanded: bool = true

    GitChangesNuiStorage = ref object of UiNodeStorageData
      view: GitUiView
      changelistIndex: int
      listStorage: UiDynamicVirtualListStorage
      lastSelected: int = -1
      branchIndexes: seq[int]

  var gitUiViewInstance: GitUiView

  proc saveGitUiSession(view: GitUiView): JsonNode {.gcsafe, raises: [].} =
    result = newJObject()
    let changelists = newJObject()
    for key, expanded in view.changelistsExpanded:
      changelists[key] = %expanded
    result["changelistsExpanded"] = changelists
    result["commitsExpanded"] = %view.commitsExpanded
    result["branchesExpanded"] = %view.branchesExpanded

  proc loadGitUiSession(view: GitUiView, data: JsonNode) {.gcsafe, raises: [].} =
    try:
      if data == nil or data.kind != JObject:
        raise newException(ValueError, "Git UI session data must be an object")
      var changelists: Table[string, bool]
      var commitsExpanded = true
      var branchesExpanded = true
      if data.hasKey("changelistsExpanded"):
        let states = data["changelistsExpanded"]
        if states.kind != JObject:
          raise newException(ValueError, "changelistsExpanded must be an object")
        for key, state in states:
          if state.kind != JBool:
            raise newException(ValueError, "Changelist expansion state must be a boolean")
          changelists[key] = state.getBool()
      for key in ["commitsExpanded", "branchesExpanded"]:
        if data.hasKey(key) and data[key].kind != JBool:
          raise newException(ValueError, key & " must be a boolean")
      if data.hasKey("commitsExpanded"):
        commitsExpanded = data["commitsExpanded"].getBool()
      if data.hasKey("branchesExpanded"):
        branchesExpanded = data["branchesExpanded"].getBool()
      view.changelistsExpanded = changelists
      view.commitsExpanded = commitsExpanded
      view.branchesExpanded = branchesExpanded
      view.markDirty()
    except CatchableError as e:
      log lvlError, "Failed to restore Git UI session state: ", e.msg

  proc gitUiDiffSelected(view: GitUiView) {.raises: [], gcsafe.}
  proc gitUiPush(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiPull(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiFetch(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiStash(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiStashPop(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiResetSoft(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiCommit(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiCommitAmend(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiCommitEditStart(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiCommitEditCancel(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiCommitEditConfirm(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiStageAll(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiStageSelected(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiUnstageSelected(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiRevertSelected(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiSwitchBranch(view: GitUiView) {.gcsafe, raises: [].}
  proc gitUiRefresh(view: GitUiView) {.gcsafe, raises: [].}

  proc commitMessage(view: GitUiView): string =
    $view.commitDoc.getTextComponent().get.content

  proc getGitUiView(): GitUiView =
    {.gcsafe.}:
      if gitUiViewInstance.isNil:
        raise newException(ValueError, "Git UI not initialized")
      gitUiViewInstance

  proc `commitMessage=`(view: GitUiView, message: string) =
    let text = view.commitDoc.getTextComponent().get
    let range = point(0, 0)...text.content.endPoint
    text.withTransaction:
      discard text.edit([range], [range], [message])
    view.commitEditor.getTextEditorComponent().get.selection = text.content.endPoint.toRange

  proc getGitRoot*(self: GitUiView): string =
    if self.vcsService != nil and self.vcsService.workspace != nil:
      return self.vcsService.workspace.getWorkspacePath()
    return ""

  proc runGitCommand*(self: GitUiView, args: seq[string], workingDir: string): Future[seq[string]] {.gcsafe, async: (raises: []).} =
    try:
      return await runProcessAsync("git", args, workingDir = workingDir, log = false)
    except CatchableError:
      return @[]

  proc clampCursor(self: GitUiView) =
    case self.cursor.panel
    of Changelists:
      if self.changelists.len == 0:
        if self.commits.len > 0:
          self.cursor = UiCursor(panel: Commits, commitIndex: 0)
        elif self.branches.len > 0:
          self.cursor = UiCursor(panel: Branches, branchIndex: 0)
        else:
          self.cursor = UiCursor(panel: Changelists, changelistIndex: 0, fileIndex: 0)
      else:
        if self.cursor.changelistIndex >= self.changelists.len:
          let fIdx = self.changelists[self.changelists.high].changelist.files.high
          self.cursor = UiCursor(panel: Changelists, changelistIndex: self.changelists.high, fileIndex: fIdx)
        if self.cursor.fileIndex >= self.changelists[self.cursor.changelistIndex].changelist.files.len:
          self.cursor.fileIndex = self.changelists[self.cursor.changelistIndex].changelist.files.high
    of Commits:
      if self.commits.len == 0:
        if self.changelists.len > 0:
          self.cursor = UiCursor(panel: Changelists, changelistIndex: self.changelists.high, fileIndex: 0)
        elif self.branches.len > 0:
          self.cursor = UiCursor(panel: Branches, branchIndex: 0)
        else:
          self.cursor = UiCursor(panel: Commits, commitIndex: 0)
      else:
        self.cursor.commitIndex = min(self.cursor.commitIndex, self.commits.high)
    of Branches:
      if self.branches.len == 0:
        if self.commits.len > 0:
          self.cursor = UiCursor(panel: Commits, commitIndex: 0)
        elif self.changelists.len > 0:
          self.cursor = UiCursor(panel: Changelists, changelistIndex: 0, fileIndex: 0)
        else:
          self.cursor = UiCursor(panel: Branches, branchIndex: 0)
      else:
        self.cursor.branchIndex = min(self.cursor.branchIndex, self.branches.high)

  proc setMessage(self: GitUiView, msg: string) =
    self.lastMessage = msg
    self.lastMessageError = false
    getServiceChecked(ToastService).showToast("Git", msg, "info")
    self.markDirty()
    let platformService = getServiceChecked(PlatformService)
    platformService.platform.requestedRender = true

  proc setError(self: GitUiView, msg: string) =
    self.lastMessage = msg
    self.lastMessageError = true
    getServiceChecked(ToastService).showToast("Git", msg, "error")
    self.markDirty()
    let platformService = getServiceChecked(PlatformService)
    platformService.platform.requestedRender = true

  proc refreshStatusAsync(self: GitUiView) {.async: (raises: []).} =
    if self.vcsService == nil:
      return
    for vcs in self.vcsService.versionControlSystems:
      vcs.updateStatus()
      break
    self.markDirty()

  proc refreshBranchesAsync(self: GitUiView) {.async: (raises: []).} =
    let root = self.getGitRoot()
    if root.len == 0:
      return
    let output = await self.runGitCommand(@["branch", "-a"], root)
    var branchesSeq: seq[string] = @["HEAD"]
    for line in output:
      if line.len > 0 and not line.startsWith("* "):
        branchesSeq.add line.strip()
    self.branches = branchesSeq
    self.clampCursor()
    self.markDirty()

  proc refreshCommitsAsync(self: GitUiView) {.async: (raises: []).} =
    let root = self.getGitRoot()
    if root.len == 0:
      return

    var commits: seq[VCSCommitInfo] = @[]

    for vcs in self.vcsService.versionControlSystems:
      let stashesFut = vcs.getStashes(5)
      let commitsFut = vcs.getCommitHistory(10)

      try:
        await allFutures(stashesFut, commitsFut)

        for stash in stashesFut.read:
          commits.add VCSCommitInfo(
            id: stash.id,
            description: stash.description,
            date: stash.date,
            author: stash.author,
          )

        for commit in commitsFut.read:
          commits.add commit
      except CatchableError:
        return

      break

    self.commits = commits
    self.commitsFetched = true
    self.clampCursor()
    self.markDirty()
    let platformService = getServiceChecked(PlatformService)
    platformService.platform.requestedRender = true

  proc refreshChangelistsAsync(self: GitUiView) {.async: (raises: []).} =
    if self.vcsService == nil:
      return
    var allChangelists: seq[tuple[vcs: VersionControlSystem, changelist: VCSChangelist]] = @[]
    for vcs in self.vcsService.versionControlSystems:
      try:
        let changelists = await vcs.getChangedFiles()
        for c in changelists:
          allChangelists.add (vcs, c)
      except CatchableError as e:
        log lvlError, &"Failed to get changed files: {e.msg}"
    self.changelists = allChangelists
    self.clampCursor()
    self.markDirty()
    let platformService = getServiceChecked(PlatformService)
    platformService.platform.requestedRender = true

  proc getGitUiViewEventHandler(self: GitUiView, context: string): EventHandler =
    let events = getServiceChecked(EventHandlerService)
    if context notin self.eventHandlers:
      var eventHandler: EventHandler
      assignEventHandler(eventHandler, events.getEventHandlerConfig(context)):
        onAction:
          if getServiceChecked(CommandService).executeCommand(action & " " & arg, false).isSome:
            Handled
          else:
            Ignored
        onInput:
          Ignored

      self.eventHandlers[context] = eventHandler
      return eventHandler

    return self.eventHandlers[context]

  proc getGitUiViewEventHandlers(self: GitUiView, inject: Table[string, EventHandler]): seq[EventHandler] =
    result.add self.getGitUiViewEventHandler("gitui")
    if self.editCommit and self.commitEditor != nil:
      result.add self.commitEditor.getEventHandlers(inject)
      result.add self.getGitUiViewEventHandler("gitui.message")

  proc getOrCreateGitChangesStorage(b: var UiBuilder, node: auto): GitChangesNuiStorage =
    let existing = b.nodeStorageGet(node)
    if existing != nil:
      return cast[GitChangesNuiStorage](existing)
    result = GitChangesNuiStorage()
    b.nodeStorage(node, result)

  proc stageGitFile(view: GitUiView, vcs: VersionControlSystem,
      file: VCSFileInfo) {.async: (raises: []).} =
    let message = if file.stagedStatus != None:
      await vcs.unstageFile(file.path)
    else:
      await vcs.stageFile(file.path)
    view.setMessage(message)
    await view.refreshChangelistsAsync()

  proc revertGitFile(view: GitUiView, vcs: VersionControlSystem,
      file: VCSFileInfo, confirm: bool) {.async: (raises: []).} =
    if confirm:
      let choice = await getServiceChecked(LayoutService).prompt(
        @["Cancel", "Revert"], "Discard changes to " & file.path & "?")
      if choice != "Revert".some:
        return
    let message = await vcs.revertFile(file.path)
    view.setMessage(message)
    await view.refreshChangelistsAsync()

  proc buildGitChangedFileRow(b: var UiBuilder, itemIndex: int,
      userData: int) {.nimcall, gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      discard b.fitY()
      let storage = b.getOrCreateGitChangesStorage(b.frame.nodes[userData].addr)
      let view = storage.view
      let changelistIndex = storage.changelistIndex
      let fileIndex = itemIndex
      let changelist {.cursor.} = view.changelists[changelistIndex].changelist
      let file {.cursor.} = changelist.files[fileIndex]
      b.node("git-ui-file"):
        let selected = view.cursor.panel == Changelists and
          view.cursor.changelistIndex == changelistIndex and
          view.cursor.fileIndex == fileIndex
        let hovered = b.wasHovered(includeChildren = true)
        discard b.fillX().fitY().flexLayout().backendPadding(1).backendGap(1)
          .styleIndex(if selected or hovered: UiStyleIndexMenuItemHover else: UiStyleIndexRow)
          .fillBackground()
        let staged = if file.stagedStatus != None: $file.stagedStatus else: " "
        let unstaged = if file.unstagedStatus != None: $file.unstagedStatus else: " "
        b.layoutHorizontal("git-ui-file-status"):
          discard b.fit().gap(0)
          for (status, label) in [(file.stagedStatus, staged), (file.unstagedStatus, unstaged & " ")]:
            b.node:
              discard b.fit().textStyleIndex(int(UiStyleIndexSmallText)).text(label)
              if status != None:
                let index = case status
                  of Added, Untracked:
                    UiStyleIndexDiffInsertedText
                  of Deleted:
                    UiStyleIndexDiffRemovedText
                  else:
                    UiStyleIndexDiffChangedText
                var statusColor = b.themeStyle(index)[].fillColor
                statusColor.a = 1
                discard b.textColor(statusColor)
        b.node:
          let (_, name) = file.path.splitPath
          discard b.fitY().flex(1, 1, 0).maskChildren().textStyleIndex(int(if selected:
            UiStyleIndexMenuItemHoverText else: UiStyleIndexMenuItemText)).text(name)
        var actionHovered = false
        var actionClicked = false
        if hovered:
          b.layoutHorizontal("file-actions"):
            discard b.fit().backendGap(1)
            if b.button("↶"):
              actionClicked = true
              asyncSpawn view.revertGitFile(view.changelists[changelistIndex].vcs, file, confirm = true)
            if b.button(if file.stagedStatus != None: "−" else: "＋"):
              actionClicked = true
              asyncSpawn view.stageGitFile(view.changelists[changelistIndex].vcs, file)
            actionHovered = b.wasHovered(includeChildren = true)
        if not actionClicked and not actionHovered and b.wasClicked(includeChildren = true):
          view.cursor = UiCursor(panel: Changelists,
            changelistIndex: changelistIndex, fileIndex: fileIndex)
          view.markDirty()
          view.gitUiDiffSelected()

  proc gitListTextHeight(b: var UiBuilder): float32 =
    if b.backendType == UiBackendType.Terminal:
      return 1.0'f32
    let style = b.themeTextStyle(int(UiStyleIndexDefaultText))
    let arrangement = b.getTextArrangement("M", style.fontId, style.fontSize)
    max(1.0'f32, arrangement.size.y)

  proc followGitListSelection(storage: GitChangesNuiStorage, selectedRow,
      rowCount: int, rowHeight: float32) =
    if selectedRow < 0 or selectedRow >= rowCount:
      storage.lastSelected = -1
    elif storage.lastSelected != selectedRow:
      let visible = storage.listStorage.visibleItemRange()
      if selectedRow >= visible.first and selectedRow <= visible.last:
        storage.lastSelected = selectedRow
      else:
        discard storage.listStorage.ensureItemVisible(selectedRow,
          storage.listStorage.viewportHeight, rowHeight)

  proc buildGitCommitRow(b: var UiBuilder, itemIndex: int,
      userData: int) {.nimcall, gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      discard b.fitY()
      let storage = b.getOrCreateGitChangesStorage(b.frame.nodes[userData].addr)
      let view = storage.view
      let commit {.cursor.} = view.commits[itemIndex]
      b.layoutHorizontal("git-ui-commit"):
        let selected = view.cursor.panel == Commits and view.cursor.commitIndex == itemIndex
        let hovered = b.wasHovered(includeChildren = true)
        discard b.fillX().fitY().backendPadding(1).backendGap(1)
          .styleIndex(if selected or hovered: UiStyleIndexMenuItemHover else: UiStyleIndexRow)
          .fillBackground()
        b.node:
          discard b.fit().textStyleIndex(int(UiStyleIndexSmallText)).text(commit.id)
        b.node:
          let description = if commit.description.len > 41:
            commit.description[0 .. 40]
          else:
            commit.description
          discard b.fillX().fitY().maskChildren().textStyleIndex(int(if selected:
            UiStyleIndexMenuItemHoverText else: UiStyleIndexMenuItemText)).text(description)
        if b.wasClicked(includeChildren = true):
          view.cursor = UiCursor(panel: Commits, commitIndex: itemIndex)
          view.markDirty()

  proc buildGitBranchRow(b: var UiBuilder, itemIndex: int,
      userData: int) {.nimcall, gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      discard b.fitY()
      let storage = b.getOrCreateGitChangesStorage(b.frame.nodes[userData].addr)
      let view = storage.view
      let branchIndex = storage.branchIndexes[itemIndex]
      b.node("git-ui-branch"):
        let selected = view.cursor.panel == Branches and view.cursor.branchIndex == branchIndex
        let hovered = b.wasHovered(includeChildren = true)
        discard b.fillX().fitY().backendPadding(1)
          .styleIndex(if selected or hovered: UiStyleIndexMenuItemHover else: UiStyleIndexRow)
          .fillBackground().textStyleIndex(int(if selected:
            UiStyleIndexMenuItemHoverText else: UiStyleIndexMenuItemText))
          .text(view.branches[branchIndex])
        if b.wasClicked(includeChildren = true):
          view.cursor = UiCursor(panel: Branches, branchIndex: branchIndex)
          view.markDirty()

  proc buildGitHistoryList(view: GitUiView, b: var UiBuilder,
      panel: CursorPanel) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      let textHeight = b.gitListTextHeight()
      let rowHeight = textHeight + (if b.backendType == UiBackendType.Terminal: 0.0'f32 else: 2.0'f32)
      b.node(if panel == Commits: "commits" else: "branches"):
        discard b.fillX().fitY().maxHeight(25.0'f32 * textHeight)
        b.nodeStorageParent()
        let storage = b.getOrCreateGitChangesStorage(b.currentNode)
        storage.view = view
        var rowCount = view.commits.len
        var selectedRow = -1
        if panel == Branches:
          storage.branchIndexes.setLen(0)
          for i, branch in view.branches:
            if branch.len > 0:
              if view.cursor.panel == Branches and view.cursor.branchIndex == i:
                selectedRow = storage.branchIndexes.len
              storage.branchIndexes.add i
          rowCount = storage.branchIndexes.len
        elif view.cursor.panel == Commits:
          selectedRow = view.cursor.commitIndex
        storage.listStorage = b.dynamicVirtualList(rowCount, rowHeight,
          (if panel == Commits: buildGitCommitRow else: buildGitBranchRow),
          b.currentNodeIndex)
        storage.followGitListSelection(selectedRow, rowCount, rowHeight)

  proc buildGitChangesList(view: GitUiView, b: var UiBuilder) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      let textHeight = b.gitListTextHeight()
      let rowHeight = textHeight + (if b.backendType == UiBackendType.Terminal: 0.0'f32 else: 2.0'f32)
      b.layoutVertical("changes"):
        discard b.fillX().fitY()
        for i, changelist in view.changelists:
          let key = changelist.vcs.root & "\0" & changelist.changelist.id & "\0" &
            changelist.changelist.description
          discard b.pushId(key)
          var expanded = view.changelistsExpanded.getOrDefault(key, true)
          b.collapsingHeader(changelist.changelist.description, expanded):
            b.node("changelist-files"):
              discard b.fillX().fitY().maxHeight(25.0'f32 * textHeight)
              b.nodeStorageParent()
              let storage = b.getOrCreateGitChangesStorage(b.currentNode)
              storage.view = view
              storage.changelistIndex = i
              let rootIndex = b.currentNodeIndex
              let rowCount = changelist.changelist.files.len
              storage.listStorage = b.dynamicVirtualList(rowCount, rowHeight,
                buildGitChangedFileRow, rootIndex)
              let selectedRow = if view.cursor.panel == Changelists and view.cursor.changelistIndex == i:
                view.cursor.fileIndex
              else:
                -1
              storage.followGitListSelection(selectedRow, rowCount, rowHeight)
          view.changelistsExpanded[key] = expanded
          discard b.popId()

  proc renderGitUiNui*(self: GitUiView, nui: var UiBuilder) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      self.resetDirty()
      if self.lastUpdate == 0:
        self.lastUpdate = 1
        asyncSpawn self.refreshStatusAsync()
        asyncSpawn self.refreshBranchesAsync()
        asyncSpawn self.refreshCommitsAsync()
        asyncSpawn self.refreshChangelistsAsync()

      let panelStyle = if self.active: UiStyleIndexPanelActive else: UiStyleIndexPanel
      let headerStyle = if self.active: UiStyleIndexHeaderActive else: UiStyleIndexHeader
      let sectionGap = if nui.backendType == UiBackendType.Terminal:
        1.0'f32
      else:
        8.0'f32

      template sectionTitle(title: string) =
        nui.node:
          discard nui.fillX().fitY().styleIndex(headerStyle)
            .fillBackground().backendPadding(2)
            .textStyleIndex(int(UiStyleIndexHeaderText)).text(title)

      template menuLabel(label: string) =
        nui.node:
          discard nui.fillX().fitY().backendPadding(1)
            .textStyleIndex(int(UiStyleIndexLabelText)).text(label)

      template menuCommand(label: string, action: untyped) =
        nui.menuItem:
          nui.node:
            discard nui.fillX().fitY().backendPadding(1)
              .textStyleIndex(int(UiStyleIndexMenuItemText)).text(label)
        do:
          discard
        do:
          self.actionsMenuOpen = false
          action

      # NUI-GAP: old view separates sections with separator() DrawBorder rules and
      # keeps inline Commands rows with keybinding hints (commandToKeys, dotted
      # leaders, keyword/comment colors); new replaces rules with sectionTitle
      # bars + gaps and hides commands behind the "…" menu (see §24).
      nui.layoutVertical("git-ui"):
        discard nui.fillX().fillY().styleIndex(panelStyle)
          .fillBackground().padding(0).backendGap(2)
        if nui.wasClicked(includeChildren = true):
          getServiceChecked(LayoutService).tryActivateView(self)

        nui.layoutHorizontal("git-ui-header"):
          discard nui.fillX().fitY().styleIndex(headerStyle)
            .fillBackground().backendPadding(4).backendGap(8).cornerRadius(0)
          nui.node:
            discard nui.fit().textStyleIndex(int(UiStyleIndexHeaderText))
              .text("Git")
          nui.layoutHorizontalReverse:
            discard nui.fillX().fitY().backendGap(4)
            let menuButtonIndex = nui.frame.nodes.len
            if nui.button("…"):
              self.actionsMenuOpen = not self.actionsMenuOpen
            let menuButtonNode = nui.frame.nodes[menuButtonIndex]
            let menuPosition = nui.absoluteNodePosPrev(
              menuButtonNode.id, menuButtonIndex)
            nui.menu(self.actionsMenuOpen,
                menuPosition.x,
                menuPosition.y + menuButtonNode.size.y):
              menuLabel("Repository")
              menuCommand("Refresh", self.gitUiRefresh())
              menuCommand("Push", self.gitUiPush())
              menuCommand("Pull", self.gitUiPull())
              menuCommand("Fetch", self.gitUiFetch())
              menuCommand("Stash", self.gitUiStash())
              menuCommand("Stash Pop", self.gitUiStashPop())
              menuCommand("Reset Soft", self.gitUiResetSoft())

              menuLabel("Commit")
              menuCommand("Commit", self.gitUiCommit())
              menuCommand("Amend", self.gitUiCommitAmend())
              if self.editCommit:
                menuCommand("Cancel Message Edit", self.gitUiCommitEditCancel())
                menuCommand("Confirm Message Edit", self.gitUiCommitEditConfirm())
              else:
                menuCommand("Edit Message", self.gitUiCommitEditStart())

              menuLabel("Changes")
              menuCommand("Stage All", self.gitUiStageAll())
              menuCommand("Stage", self.gitUiStageSelected())
              menuCommand("Unstage", self.gitUiUnstageSelected())
              menuCommand("Revert", self.gitUiRevertSelected())
              menuCommand("Diff", self.gitUiDiffSelected())

              menuLabel("Branches")
              menuCommand("Checkout Selected", self.gitUiSwitchBranch())

        # NUI-GAP: old view scrolls manually (onScroll delta.y*textHeight*2,
        # clamp + rawY, custom fillRect thumb with scrollBar colors); new uses
        # scrollBox so scrollOffset is dead and custom theming is gone (see §24).
        nui.scrollBox:
          discard nui.fillX().fitY()
          nui.layoutVertical("git-ui-content"):
            let scrollbarWidth = if nui.backendType == UiBackendType.Terminal:
              1.0'f32
            else:
              10.0'f32
            discard nui.anchorsX(0, 1).offsetsX(0, -scrollbarWidth).finishAnchors()
              .fitY().backendGap(sectionGap).backendPadding(4)

            # NUI-GAP: old status splits "Status: " + vcs.status into textColor +
            # accentColor panels; new merges into one DefaultText node (see §24).
            sectionTitle("Repository")
            var status = "No repository"
            if self.vcsService != nil:
              for vcs in self.vcsService.versionControlSystems:
                status = if vcs.status.len > 0: vcs.status else: "Clean"
                break
            nui.node:
              discard nui.fillX().fitY()
                .textStyleIndex(int(UiStyleIndexDefaultText))
                .text("Status: " & status)

            # NUI-GAP: old commit editor is wrapped in separator() + inline
            # Cancel/Confirm rows with TextWrap/Multiline; new uses a fixed-height
            # masked box with Cancel/Confirm menu-only (see §24).
            sectionTitle("Commit")
            if self.editCommit:
              nui.node("git-ui-commit-editor"):
                discard nui.fillX().height(
                  if nui.backendType == UiBackendType.Terminal:
                    6.0'f32
                  else:
                    150.0'f32).maskChildren()
                if self.commitEditor != nil:
                  self.commitEditor.renderNui(nui)
            else:
              let message = self.commitMessage
              nui.node("git-ui-commit-message"):
                discard nui.fillX().fitY()
                  .textStyleIndex(int(UiStyleIndexDefaultText))
                  .text(if message.len > 0: message else: "(empty)")
                if nui.wasClicked(includeChildren = true):
                  self.gitUiCommitEditStart()

            if self.changelists.len > 0:
              sectionTitle("Changes")
              self.buildGitChangesList(nui)

            if not self.commitsFetched:
              asyncSpawn self.refreshCommitsAsync()
            if self.commits.len > 0:
              nui.collapsingHeader("Recent Commits", self.commitsExpanded):
                self.buildGitHistoryList(nui, Commits)

            if self.branches.len > 0:
              nui.collapsingHeader("Branches", self.branchesExpanded):
                self.buildGitHistoryList(nui, Branches)

            # NUI-GAP: old last-message uses tokenColor("error") vs accentColor with
            # TextWrap/Multiline; new reuses MenuItemHoverText/DefaultText, so the
            # error token is lost (see §24).
            if self.lastMessage.len > 0:
              sectionTitle(if self.lastMessageError: "Last Error" else: "Last Result")
              nui.node:
                discard nui.fillX().fitY().textStyleIndex(int(if self.lastMessageError:
                  UiStyleIndexMenuItemHoverText
                else:
                  UiStyleIndexDefaultText)).text(self.lastMessage)

  proc kind(self: GitUiView): string = "gitui"
  proc desc(self: GitUiView): string = "GitUi"
  proc display(self: GitUiView): string = "GitUi"
  proc copy(self: GitUiView): View = self
  proc saveLayout(self: GitUiView, discardedViews: HashSet[Id]): JsonNode =
    result = newJObject()
    result["kind"] = "gitui".toJson

  proc saveState(self: GitUiView): JsonNode =
    result = newJObject()
    result["kind"] = "gitui".toJson
    result["commitMessage"] = self.commitMessage.toJson


  proc newGitUiView*(): GitUiView =
    result = GitUiView()
    result.uiId = newId()
    result.renderNuiImpl = proc(view: View, nui: var UiBuilder) {.gcsafe, raises: [].} =
      renderGitUiNui(view.GitUiView, nui)

    result.getEventHandlersImpl = proc(self: View, inject: Table[string, EventHandler]): seq[EventHandler] =
      getGitUiViewEventHandlers(self.GitUiView, inject)

    result.getActiveEditorImpl = proc(self: View): Option[DocumentEditor] =
      let gitUiView = self.GitUiView
      if gitUiView.editCommit and gitUiView.commitEditor != nil:
        return gitUiView.commitEditor.some
      return DocumentEditor.none

    result.kindImpl = proc(self: View): string = kind(self.GitUiView)
    result.descImpl = proc(self: View): string = desc(self.GitUiView)
    result.displayImpl = proc(self: View): string = display(self.GitUiView)
    result.copyImpl = proc(self: View): View = copy(self.GitUiView)
    result.saveLayoutImpl = proc(self: View, discardedViews: HashSet[Id]): JsonNode = saveLayout(self.GitUiView, discardedViews)
    result.saveStateImpl = proc(self: View): JsonNode = saveState(self.GitUiView)

  proc delayedInit(view: GitUiView) {.async: (raises: []).} =
    view.commitDoc = view.editors.createDocument("text", ".git-commit-message", load = false, %%*{"createLanguageServer": false})
    view.commitDoc.usage = "git-commit-message"
    view.commitEditor = view.editors.createEditorForDocument(view.commitDoc, %%*{"usage": "git-commit-message"}).get(nil)
    if view.commitEditor != nil:
      if view.commitEditor.getConfigComponent().getSome(config):
        config.set("text.disable-completions", true)
        config.set("ui.line-numbers", "none")
        config.set("ui.whitespace-char", " ")
        config.set("text.cursor-margin", 0)
        config.set("text.disable-scrolling", true)
        config.set("text.default-mode", "vim.insert")
        config.set("text.highlight-matches.enable", false)
      view.commitEditor.renderHeader = false
      discard view.commitEditor.onMarkedDirty.subscribe proc() =
        view.markDirty()
        view.platform.requestRender()

      let text = view.commitDoc.getTextComponent().get
      let range = point(0, 0)...text.content.endPoint
      text.withTransaction:
        discard text.edit([range], [range], [view.savedCommitMessage])
      view.commitEditor.getTextEditorComponent().get.selection = text.content.endPoint.toRange

  template runGitAsync(view: GitUiView, args: seq[string], onComplete: untyped): untyped =
    let root = view.getGitRoot()
    if root.len == 0:
      view.setError("No git repository found")
      return
    proc gitTask() {.async: (raises: []).} =
      try:
        let output = await runProcessAsync("git", args, workingDir = root)
        let msg = output.join("\n").strip()
        if msg != "":
          view.setMessage(msg)
        onComplete
      except CatchableError as e:
        log lvlWarn, "Failed to run git command: " & $e.msg
    asyncSpawn gitTask()

  proc gitUiToggle(view: GitUiView) =
    let layout = getServiceChecked(LayoutService)
    if layout.isViewVisible(view):
      layout.closeView(view, keepHidden = false, restoreHidden = false)
    else:
      layout.addView(view, slot = "#small-left", focus = true)
      view.cursor = UiCursor(panel: Changelists, changelistIndex: 0, fileIndex: 0)
      asyncSpawn view.refreshStatusAsync()
      asyncSpawn view.refreshBranchesAsync()
      asyncSpawn view.refreshCommitsAsync()
      asyncSpawn view.refreshChangelistsAsync()
      view.markDirty()

  proc gitUiCursorDown(view: GitUiView) =
    case view.cursor.panel
    of Changelists:
      let totalFiles = view.changelists.foldl(a + b.changelist.files.len, 0)
      if totalFiles == 0:
        view.cursor = UiCursor(panel: Commits, commitIndex: 0)
      else:
        var clIdx = view.cursor.changelistIndex
        var fIdx = view.cursor.fileIndex
        inc fIdx
        while clIdx < view.changelists.len:
          if fIdx < view.changelists[clIdx].changelist.files.len:
            view.cursor = UiCursor(panel: Changelists, changelistIndex: clIdx, fileIndex: fIdx)
            break
          inc clIdx
          fIdx = 0
        if clIdx >= view.changelists.len:
          view.cursor = UiCursor(panel: Commits, commitIndex: 0)
    of Commits:
      if view.commits.len == 0:
        view.cursor = UiCursor(panel: Branches, branchIndex: 0)
      else:
        var idx = view.cursor.commitIndex
        inc idx
        if idx >= view.commits.len:
          view.cursor = UiCursor(panel: Branches, branchIndex: 0)
        else:
          view.cursor = UiCursor(panel: Commits, commitIndex: idx)
    of Branches:
      var idx = view.cursor.branchIndex
      inc idx
      if idx >= view.branches.len:
        view.cursor = UiCursor(panel: Changelists, changelistIndex: 0, fileIndex: 0)
      else:
        view.cursor = UiCursor(panel: Branches, branchIndex: idx)
    view.markDirty()
    view.platform.requestRender()

  proc gitUiCursorUp(view: GitUiView) =
    case view.cursor.panel
    of Changelists:
      var clIdx = view.cursor.changelistIndex
      var fIdx = view.cursor.fileIndex
      if clIdx == 0 and fIdx == 0:
        if view.branches.len > 0:
          view.cursor = UiCursor(panel: Branches, branchIndex: view.branches.high)
        elif view.commits.len > 0:
          view.cursor = UiCursor(panel: Commits, commitIndex: view.commits.high)
      else:
        dec fIdx
        while clIdx >= 0:
          if fIdx >= 0 and fIdx < view.changelists[clIdx].changelist.files.len:
            view.cursor = UiCursor(panel: Changelists, changelistIndex: clIdx, fileIndex: fIdx)
            break
          dec clIdx
          if clIdx >= 0:
            fIdx = view.changelists[clIdx].changelist.files.len - 1
        if clIdx < 0:
          if view.commits.len > 0:
            view.cursor = UiCursor(panel: Commits, commitIndex: view.commits.high)
          else:
            view.cursor = UiCursor(panel: Branches, branchIndex: view.branches.high)
    of Commits:
      var idx = view.cursor.commitIndex
      if idx == 0:
        if view.changelists.len > 0:
          var clIdx = view.changelists.high
          var fIdx = view.changelists[clIdx].changelist.files.len - 1
          view.cursor = UiCursor(panel: Changelists, changelistIndex: clIdx, fileIndex: fIdx)
        else:
          view.cursor = UiCursor(panel: Changelists, changelistIndex: 0, fileIndex: 0)
      else:
        dec idx
        view.cursor = UiCursor(panel: Commits, commitIndex: idx)
    of Branches:
      var idx = view.cursor.branchIndex
      if idx == 0:
        if view.commits.len > 0:
          view.cursor = UiCursor(panel: Commits, commitIndex: view.commits.high)
        elif view.changelists.len > 0:
          var clIdx = view.changelists.high
          var fIdx = view.changelists[clIdx].changelist.files.len - 1
          view.cursor = UiCursor(panel: Changelists, changelistIndex: clIdx, fileIndex: fIdx)
        else:
          view.cursor = UiCursor(panel: Changelists, changelistIndex: 0, fileIndex: 0)
      else:
        dec idx
        view.cursor = UiCursor(panel: Branches, branchIndex: idx)
    view.markDirty()
    view.platform.requestRender()

  proc gitUiPush(view: GitUiView) =
    if view.editCommit:
      view.setError("Finish editing first")
      return
    view.runGitAsync(@["push"]):
      view.setMessage("Pushed")
      asyncSpawn view.refreshStatusAsync()

  proc gitUiPull(view: GitUiView) =
    if view.editCommit:
      view.setError("Finish editing first")
      return
    view.runGitAsync(@["pull"]):
      view.setMessage("Pulled")
      asyncSpawn view.refreshStatusAsync()
      asyncSpawn view.refreshBranchesAsync()
      asyncSpawn view.refreshCommitsAsync()
      asyncSpawn view.refreshChangelistsAsync()

  proc gitUiStash(view: GitUiView) =
    if view.editCommit:
      view.setError("Finish editing first")
      return
    view.runGitAsync(@["stash"]):
      asyncSpawn view.refreshStatusAsync()
      asyncSpawn view.refreshChangelistsAsync()

  proc gitUiStashPop(view: GitUiView) =
    if view.editCommit:
      view.setError("Finish editing first")
      return
    view.runGitAsync(@["stash", "pop"]):
      asyncSpawn view.refreshStatusAsync()
      asyncSpawn view.refreshChangelistsAsync()

  proc gitUiCommit(view: GitUiView) =
    if view.editCommit:
      view.setError("Finish editing first")
      return
    let msg = view.commitMessage
    if msg.strip().len == 0:
      view.savedCommitMessage = view.commitMessage
      view.commitOnMessageSave = true
      if view.commitEditor != nil:
        view.editCommit = true
        view.commitEditor.getCommandComponent().get.executeCommand("""set-mode "vim.insert" true true""")
        view.markDirty()
      else:
        view.setError("No commit message specified")
      return
    view.runGitAsync(@["commit", "-m", msg.strip()]):
      view.commitMessage = ""
      asyncSpawn view.refreshStatusAsync()
      asyncSpawn view.refreshCommitsAsync()
      asyncSpawn view.refreshChangelistsAsync()

  proc gitUiCommitAmend(view: GitUiView) =
    if view.editCommit:
      view.setError("Finish editing first")
      return
    let msg = view.commitMessage
    view.runGitAsync(@["commit", "--amend", "-m", msg.strip()]):
      view.commitMessage = ""
      asyncSpawn view.refreshStatusAsync()
      asyncSpawn view.refreshCommitsAsync()
      asyncSpawn view.refreshChangelistsAsync()

  proc gitUiCommitEditStart(view: GitUiView) =
    if view.editCommit:
      return
    view.commitOnMessageSave = false
    view.savedCommitMessage = view.commitMessage
    if view.commitEditor != nil:
      view.editCommit = true
      view.commitEditor.getCommandComponent().get.executeCommand("""set-mode "vim.insert" true true""")
      view.markDirty()

  proc gitUiCommitEditCancel(view: GitUiView) =
    view.commitMessage = view.savedCommitMessage
    view.savedCommitMessage = ""
    view.editCommit = false
    view.setMessage("Edit cancelled")

  proc gitUiCommitEditConfirm(view: GitUiView) =
    view.savedCommitMessage = ""
    view.editCommit = false
    view.setMessage("Message updated")
    if view.commitOnMessageSave:
      let msg = view.commitMessage
      view.runGitAsync(@["commit", "-m", msg.strip()]):
        view.commitMessage = ""
        asyncSpawn view.refreshStatusAsync()
        asyncSpawn view.refreshCommitsAsync()
        asyncSpawn view.refreshChangelistsAsync()

  proc gitUiSwitchBranch(view: GitUiView) =
    if view.editCommit:
      view.setError("Finish editing first")
      return
    case view.cursor.panel
    of Commits:
      let commitIndex = view.cursor.commitIndex
      if commitIndex >= view.commits.len:
        view.setError("Invalid selection")
        return
      let commit = view.commits[commitIndex]
      view.runGitAsync(@["checkout", commit.id]):
        asyncSpawn view.refreshStatusAsync()
    of Branches:
      let branchIndex = view.cursor.branchIndex
      if branchIndex >= view.branches.len:
        view.setError("Invalid selection")
        return
      let branch = view.branches[branchIndex]
      view.runGitAsync(@["checkout", branch]):
        asyncSpawn view.refreshStatusAsync()
    else:
      view.setError("Select a commit or branch first")

  proc gitUiFetch(view: GitUiView) =
    if view.editCommit:
      view.setError("Finish editing first")
      return
    view.runGitAsync(@["fetch", "--all"]):
      asyncSpawn view.refreshStatusAsync()

  proc gitUiResetSoft(view: GitUiView) =
    if view.editCommit:
      view.setError("Finish editing first")
      return
    view.runGitAsync(@["reset", "--soft", "HEAD~1"]):
      discard

  proc gitUiStageAll(view: GitUiView) =
    if view.editCommit:
      view.setError("Finish editing first")
      return
    view.runGitAsync(@["add", "-A"]):
      asyncSpawn view.refreshStatusAsync()
      asyncSpawn view.refreshChangelistsAsync()

  proc gitUiStageSelected(view: GitUiView) =
    if view.cursor.panel != Changelists:
      view.setError("Select a file first")
      return
    let clIdx = view.cursor.changelistIndex
    let fIdx = view.cursor.fileIndex
    if clIdx >= view.changelists.len or fIdx >= view.changelists[clIdx].changelist.files.len:
      view.setError("Invalid selection")
      return
    let file = view.changelists[clIdx].changelist.files[fIdx]
    if file.stagedStatus != None:
      view.setError("Already staged")
      return
    asyncSpawn view.stageGitFile(view.changelists[clIdx].vcs, file)

  proc gitUiUnstageSelected(view: GitUiView) =
    if view.cursor.panel != Changelists:
      view.setError("Select a file first")
      return
    let clIdx = view.cursor.changelistIndex
    let fIdx = view.cursor.fileIndex
    if clIdx >= view.changelists.len or fIdx >= view.changelists[clIdx].changelist.files.len:
      view.setError("Invalid selection")
      return
    let vcs = view.changelists[clIdx].vcs
    let file = view.changelists[clIdx].changelist.files[fIdx]
    if file.stagedStatus == None:
      view.setError("Not staged")
      return
    asyncSpawn view.stageGitFile(vcs, file)

  proc gitUiRevertSelected(view: GitUiView) =
    if view.cursor.panel != Changelists:
      view.setError("Select a file first")
      return
    let clIdx = view.cursor.changelistIndex
    let fIdx = view.cursor.fileIndex
    if clIdx >= view.changelists.len or fIdx >= view.changelists[clIdx].changelist.files.len:
      view.setError("Invalid selection")
      return
    let vcs = view.changelists[clIdx].vcs
    let file = view.changelists[clIdx].changelist.files[fIdx]
    asyncSpawn view.revertGitFile(vcs, file, confirm = false)

  proc gitUiDiffSelected(view: GitUiView) {.raises: [], gcsafe.} =
    let layout = getServiceChecked(LayoutService)
    let commands = getServiceChecked(CommandService)
    case view.cursor.panel
    of Changelists:
      let clIdx = view.cursor.changelistIndex
      let fIdx = view.cursor.fileIndex
      if clIdx >= view.changelists.len or fIdx >= view.changelists[clIdx].changelist.files.len:
        view.setError("Invalid selection")
        return
      let file = view.changelists[clIdx].changelist.files[fIdx]
      let relPath = file.path
      if file.stagedStatus == None:
        if layout.openFile(file.path).getSome(editor):
          editor.getCommandComponent().get.executeCommand(&"""start-diff "git://@/staged/{relPath}" true""")
      else:
        if layout.openFile("git://@/staged/" & relPath).getSome(editor):
          editor.getCommandComponent().get.executeCommand(&"""start-diff "git://@/HEAD/{relPath}" true""")
    of Commits:
      let commitIndex = view.cursor.commitIndex
      if commitIndex >= view.commits.len:
        view.setError("Invalid selection")
        return
      let commit = view.commits[commitIndex]
      discard commands.executeCommand(&"""explore-files "git://@/{commit.id}" false true true 0.8""")
    else:
      view.setError("Select a file first")

  proc gitUiRefresh(view: GitUiView) =
    asyncSpawn view.refreshStatusAsync()
    asyncSpawn view.refreshBranchesAsync()
    asyncSpawn view.refreshCommitsAsync()
    asyncSpawn view.refreshChangelistsAsync()

  proc refreshRepositoryChanges(view: GitUiView) {.async: (raises: []).} =
    view.refreshing = true
    defer:
      view.refreshing = false
    while view.refreshPending:
      view.refreshPending = false
      await view.refreshStatusAsync()
      await view.refreshBranchesAsync()
      await view.refreshCommitsAsync()
      await view.refreshChangelistsAsync()
      view.markDirty()
      view.platform.requestRender()

  proc scheduleRepositoryRefresh(view: GitUiView) =
    view.refreshPending = true
    if not view.refreshing:
      view.refreshTask.reschedule()

  proc checkIgnoredPaths(args: tuple[root: string, paths: seq[string], directories: bool]):
      tuple[output: string, exitCode: int, error: string] {.gcsafe, raises: [].} =
    try:
      var commandArgs = @["check-ignore", "-z", "--stdin"]
      if args.directories:
        commandArgs.add "--no-index"
      let process = startProcess("git", workingDir = args.root,
        args = commandArgs,
        options = {poUsePath, poStdErrToStdOut})
      defer: process.close()
      process.inputStream.write(args.paths.join("\0") & "\0")
      process.inputStream.close()
      var buffer = newString(4096)
      while true:
        let count = process.outputStream.readData(buffer[0].addr, buffer.len)
        if count == 0:
          break
        result.output.add buffer[0 ..< count]
      result.exitCode = process.waitForExit()
    except CatchableError as e:
      result.error = e.msg

  proc watchablePaths(view: GitUiView, paths: seq[string],
      root: string, directories: bool = false): Future[seq[string]] {.async: (raises: []).} =
    let vfs = view.vcsService.vfs
    var candidates: seq[string]
    for path in paths:
      let path = vfs.normalize(path)
      if path.split('/').anyIt(it.toLowerAscii == ".git") or
          (directories and symlinkExists(vfs.localize(path))):
        continue
      candidates.add path
    if root.len == 0:
      return candidates
    # Bound pipe traffic, and use NUL delimiters for unusual folder names.
    for start in countup(0, candidates.high, 32):
      let batch = candidates[start .. min(start + 31, candidates.high)]
      var localPaths: seq[string]
      for path in batch:
        let kind = if directories: FileKind.Directory.some else: await vfs.getFileKind(path)
        localPaths.add vfs.localize(path) & (if kind == FileKind.Directory.some: "/" else: "")
      try:
        let checked = await spawnAsync(checkIgnoredPaths,
          (root: vfs.localize(root), paths: localPaths, directories: directories))
        if checked.error.len > 0 or checked.exitCode notin {0, 1}:
          log lvlError, &"Failed to check Git ignore rules in '{root}': {checked.error} {checked.output}"
          continue
        let ignored = checked.output.split('\0').toHashSet
        for i, path in batch:
          if localPaths[i] notin ignored:
            result.add path
      except CancelledError as e:
        log lvlWarn, &"Cancelled Git ignore check in '{root}': {e.msg}"
        return

  proc watchRepositoryDirectory(view: GitUiView, path: string,
    rescan: bool = false, root: string = "") {.async: (raises: []).}

  proc watchCreatedDirectories(view: GitUiView, path: string,
      events: seq[PathEvent], root: string = "") {.async: (raises: []).} =
    # Registering watches inside a VFS callback would mutate its active iterator.
    try:
      await sleepAsync(chronos.milliseconds(1))
    except CancelledError as e:
      log lvlWarn, &"Cancelled Git repository watch update: {e.msg}"
      return
    for event in events:
      let changedPath = case event.action
        of FileEventAction.Create: path // event.name
        of FileEventAction.Rename: path // event.newName
        of FileEventAction.CreateSelf: path
        else: ""
      if changedPath.len > 0:
        let kind = await view.vcsService.vfs.getFileKind(changedPath)
        if kind == FileKind.Directory.some:
          let paths = await view.watchablePaths(@[changedPath], root, directories = true)
          for directory in paths:
            await view.watchRepositoryDirectory(directory, rescan = true, root = root)

  proc handleRepositoryChanges(view: GitUiView, path: string,
      events: seq[PathEvent], root: string = "") {.async: (raises: []).} =
    if events.len == 0:
      return
    await view.watchCreatedDirectories(path, events, root)
    var changedPaths: seq[string]
    for event in events:
      case event.action
      of FileEventAction.NonAction:
        discard
      of FileEventAction.Rename:
        changedPaths.add path // event.name
        changedPaths.add path // event.newName
      of FileEventAction.Modify:
        let changedPath = path // event.name
        # Windows reports parent directory writes too; child watches handle the actual files.
        let kind = await view.vcsService.vfs.getFileKind(changedPath)
        if kind != FileKind.Directory.some:
          changedPaths.add changedPath
      else:
        changedPaths.add path // event.name
    let relevantPaths = await view.watchablePaths(changedPaths.deduplicate(), root)
    if relevantPaths.len > 0:
      view.scheduleRepositoryRefresh()

  proc watchRepositoryDirectory(view: GitUiView, path: string,
      rescan: bool = false, root: string = "") {.async: (raises: []).} =
    let path = view.vcsService.vfs.normalize(path)
    let vfs = view.vcsService.vfs
    # Git roots are local; do not follow directory links outside the repository or into cycles.
    if path.extractFilename.toLowerAscii == ".git" or symlinkExists(vfs.localize(path)):
      return
    if path in view.repositoryWatches:
      if not rescan:
        return
    else:
      var handle = vfs.watch(path, proc(events: seq[PathEvent]) =
        asyncSpawn view.handleRepositoryChanges(path, events, root)
      )
      if not handle.isBound:
        log lvlError, &"Failed to watch Git repository directory '{path}'"
        return
      view.repositoryWatches[path] = handle
    let listing = await vfs.getDirectoryListing(path)
    let directories = await view.watchablePaths(
      listing.folders.mapIt(path // it), root, directories = true)
    for directory in directories:
      await view.watchRepositoryDirectory(directory, rescan, root)

  proc watchRepository(view: GitUiView, vcs: VersionControlSystem) =
    if vcs.name != "Git" or vcs.root.len == 0:
      return
    asyncSpawn view.watchRepositoryDirectory(vcs.root, root = vcs.root)
    view.scheduleRepositoryRefresh()

  include generated/git_ui_commands

  proc init_module_git_ui*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, "Failed to initialize init_module_git_ui: no services found"
      return

    let layout = services.getServiceChecked(LayoutService)
    let vcsService = services.getService(VCSService).getOr:
      log lvlWarn, "Failed to get VCSService for git_ui"
      return

    let events = getServiceChecked(EventHandlerService)
    let platform = services.getServiceChecked(PlatformService).platform

    gitUiViewInstance = newGitUiView()
    let view = gitUiViewInstance
    view.vcsService = vcsService
    view.themes = services.getServiceChecked(ThemeService)
    view.events = events
    view.editors = services.getServiceChecked(DocumentEditorService)
    view.platform = platform
    let session = services.getServiceChecked(SessionService)
    session.addSaveHandler "git-ui",
      proc(): JsonNode = view.saveGitUiSession(),
      proc(data: JsonNode) = view.loadGitUiSession(data)
    view.refreshTask = newDelayedTask(250, false, false,
      proc(): Future[void] {.async: (raises: []).} =
        await view.refreshRepositoryChanges()
    )
    discard vcsService.onVcsRegistered.subscribe proc(vcs: VersionControlSystem) =
      view.watchRepository(vcs)
    for vcs in vcsService.versionControlSystems:
      view.watchRepository(vcs)

    let eventService = getServiceChecked(EventService)
    eventService.listen(newId(), "app/initialized"):
      proc(event, payload: string) =
        asyncSpawn delayedInit(view)

    layout.addViewFactory "gitui", proc(config: JsonNode): View {.raises: [].} =
      try:
        if config.kind == JObject and config.hasKey("commitMessage"):
          view.savedCommitMessage = config["commitMessage"].jsonTo(string)
          if view.commitEditor != nil:
            let text = view.commitDoc.getTextComponent().get
            let range = point(0, 0)...text.content.endPoint
            text.withTransaction:
              discard text.edit([range], [range], [view.savedCommitMessage])
            view.commitEditor.getTextEditorComponent().get.selection = text.content.endPoint.toRange
      except CatchableError:
        discard
      return view

    registerCommands(getServiceChecked(CommandService))
