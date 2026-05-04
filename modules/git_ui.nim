#use command_component layout text_editor_component command_service event_service
import std/[options, algorithm, strutils, times, tables, json]
import service
import component
import vcs/vcs

export component

const currentSourcePath2 = currentSourcePath()
include module_base

# Implementation
when implModule:
  import std/[sets, math, sequtils]
  import misc/[custom_logger, util, id, myjsonutils, jsonex, rope_utils, async_process, custom_async]
  import text_component, event_service, document_editor, document, dynamic_view, view, layout/layout, command_component, platform_service
  import nimsumtree/[buffer, clock, rope]
  import ui/node
  import command_service, workspaces/workspace, config_component, text_editor_component
  import vmath, chroma
  import theme
  import misc/[render_command]
  import events
  import document_editor_render, toast

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

    GitUiView* = ref object of DynamicView
      eventHandlers*: Table[string, EventHandler]
      events*: EventHandlerService
      editors*: DocumentEditorService
      platform*: Platform
      vcsService*: VCSService
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

      lastUpdate: int = 0

  proc commitMessage(view: GitUiView): string =
    $view.commitDoc.getTextComponent().get.content

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
    var branchesSeq: seq[string] = @[]
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

  type
    GitUiCommand* = tuple[command: string, label: string]

  proc getGitUiCommands(): seq[GitUiCommand] =
    @[
      ("gitui.push", "Push"),
      ("gitui.pull", "Pull"),
      ("gitui.fetch", "Fetch"),
      ("gitui.stash", "Stash"),
      ("gitui.stash-pop", "Stash Pop"),
      ("gitui.reset-soft", "Reset Soft"),
    ]

  proc renderGitUiCommands*(self: GitUiView, builder: UINodeBuilder) =
    let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
    let accentColor = builder.theme.color("editorLineNumber.foreground", color(120/255, 120/255, 160/255))
    let keyColor = builder.theme.tokenColor("keyword", accentColor)
    let sepColor = builder.theme.tokenColor("comment", accentColor)
    let lineColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255)).lighten(0.01)

    var commandToKeys: Table[string, seq[string]]
    if self.events != nil and self.events.commandInfos != nil:
      if self.events.commandInfos.commandToKeys.len == 0:
        self.events.rebuildCommandToKeysMap()
      let commands = getGitUiCommands()
      for (cmd, _) in commands:
        if self.events.commandInfos.getInfos(cmd).getSome(infos):
          for info in infos:
            if info.context == "gitui":
              commandToKeys.mgetOrPut(cmd, @[]).add info.keys

    for keys in commandToKeys.mvalues:
      keys.sort(proc(a, b: string): int = cmp(a.len, b.len))

    let cx = builder.charWidth
    let cy = builder.textHeight
    let availableWidth = builder.currentParent.bounds.w

    builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
      builder.panel(&{SizeToContentY, FillX, DrawText}, text = "Commands", textColor = accentColor)

      let commands = getGitUiCommands()
      for (cmd, label) in commands:
        let hasKey = cmd in commandToKeys
        let keys = if hasKey: commandToKeys[cmd] else: @[]
        let totalKeyLen = if keys.len > 0: keys.mapIt(it.len).foldl(a + b) + (keys.len - 1) * 3 else: 0
        let keyX = availableWidth - totalKeyLen.float * cx - cx * 3
        let labelWidth = label.len.float * cx

        builder.panel(&{SizeToContentY, FillX}):
          builder.panel(&{SizeToContentY, FillX, DrawText}, text = label, textColor = textColor)
          if hasKey:
            let lineX = labelWidth + cx
            let lineW = keyX - lineX - cx
            if lineW > 0 and builder.textHeight > 1:
              builder.panel(&{DrawBorder}, x = lineX, y = floor(cy * 0.5) - 1, w = lineW, h = 1, border = border(0, 0, 1, 0), borderColor = lineColor)
            var xOff = keyX
            for ki, key in keys:
              if ki > 0:
                builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, x = xOff, text = " | ", textColor = sepColor)
                xOff += 3.0 * cx
              builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, x = xOff, text = key, textColor = keyColor)
              xOff += key.len.float * cx

  proc renderGitUiCommand*(self: GitUiView, builder: UINodeBuilder, cmd: string, label: string, context: string = "gitui") =
    let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
    let accentColor = builder.theme.color("editorLineNumber.foreground", color(120/255, 120/255, 160/255))
    let keyColor = builder.theme.tokenColor("keyword", accentColor)
    let sepColor = builder.theme.tokenColor("comment", accentColor)
    let lineColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255)).lighten(0.01)

    var keys: seq[string] = @[]
    if self.events != nil and self.events.commandInfos != nil:
      if self.events.commandInfos.commandToKeys.len == 0:
        self.events.rebuildCommandToKeysMap()
      if self.events.commandInfos.getInfos(cmd).getSome(infos):
        for info in infos:
          if info.context == context:
            keys.add info.keys
    keys.sort(proc(a, b: string): int = cmp(a.len, b.len))

    let cx = builder.charWidth
    let cy = builder.textHeight
    let availableWidth = builder.currentParent.bounds.w

    let hasKey = keys.len > 0
    let totalKeyLen = if hasKey: keys.mapIt(it.len).foldl(a + b) + (keys.len - 1) * 3 else: 0
    let keyX = availableWidth - totalKeyLen.float * cx - cx * 3
    let labelWidth = label.len.float * cx

    builder.panel(&{SizeToContentY, FillX}):
      builder.panel(&{SizeToContentY, FillX, DrawText}, text = label, textColor = textColor)
      if hasKey:
        let lineX = labelWidth + cx
        let lineW = keyX - lineX - cx
        if lineW > 0 and builder.textHeight > 1:
          builder.panel(&{DrawBorder}, x = lineX, y = floor(cy * 0.5) - 1, w = lineW, h = 1, border = border(0, 0, 1, 0), borderColor = lineColor)
        var xOff = keyX
        for ki, key in keys:
          if ki > 0:
            builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, x = xOff, text = " | ", textColor = sepColor)
            xOff += 3.0 * cx
          builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, x = xOff, text = key, textColor = keyColor)
          xOff += key.len.float * cx

  proc renderGitUi*(self: GitUiView, builder: UINodeBuilder) =
    let dirty = self.dirty
    self.resetDirty()

    var backgroundColor = if self.active: builder.theme.color("editor.background", color(25/255, 25/255, 40/255)) else: builder.theme.color("editor.background", color(25/255, 25/255, 25/255)).lighten(-0.025)

    let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
    let accentColor = builder.theme.color("editorLineNumber.foreground", color(120/255, 120/255, 160/255))
    let keyColor = builder.theme.tokenColor("keyword", accentColor)
    let selectionColor = builder.theme.color("editor.selectionBackground", color(60/255, 60/255, 80/255))
    let errorColor = builder.theme.tokenColor("error", color(200/255, 25/255, 25/255))

    if self.lastUpdate == 0:
      self.lastUpdate += 1
      asyncSpawn self.refreshStatusAsync()
      asyncSpawn self.refreshBranchesAsync()
      asyncSpawn self.refreshCommitsAsync()
      asyncSpawn self.refreshChangelistsAsync()

    builder.panel(&{FillBackground, FillX, FillY, MaskContent}, backgroundColor = backgroundColor, userId = self.uiId.newPrimaryId, tag = "gitui"):
      onScroll:
        self.scrollOffset -= delta.y * builder.textHeight * 2
        self.markDirty()

      onClickAny btn:
        getServiceChecked(LayoutService).tryActivateView(self)

      if dirty or not builder.retain():
        currentNode.renderCommands.clear()
        currentNode.markDirty(builder)

        proc separator() =
          if builder.textHeight > 1:
            builder.panel(&{}, h = floor(builder.textHeight * 0.5))
          builder.panel(&{DrawBorder, DrawBorderTerminal, FillX, SizeToContentY, FillBackground}, border = border(0, 0, 1, 0), borderColor = accentColor, backgroundColor = backgroundColor)
          if builder.textHeight > 1:
            builder.panel(&{}, h = floor(builder.textHeight * 0.5))

        builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
          builder.panel(&{SizeToContentY, FillX, DrawText}, text = "GitUi", textColor = textColor)

          for vcs in self.vcsService.versionControlSystems:
            separator()
            builder.panel(&{SizeToContentY, FillX, LayoutHorizontal}):
              builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = "Status: ", textColor = textColor)
              builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = vcs.status, textColor = accentColor)
            break

          separator()
          self.renderGitUiCommands(builder)

          separator()
          builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
            self.renderGitUiCommand(builder, "gitui.commit", "Commit")
            self.renderGitUiCommand(builder, "gitui.commit-amend", "Amend Commit")
            self.renderGitUiCommand(builder, "gitui.commit-edit-start", "Edit Message")
            separator()
            if self.editCommit:
              if self.commitEditor != nil:
                discard documentEditorRender(self.commitEditor, builder)
              separator()
              self.renderGitUiCommand(builder, "gitui.commit-edit-cancel", "Cancel", "gitui.message")
              self.renderGitUiCommand(builder, "gitui.commit-edit-confirm", "Confirm", "gitui.message")
            else:
              let commitMessage = self.commitMessage
              builder.panel(&{SizeToContentY, FillX, DrawText, TextWrap, TextMultiline}, text = if commitMessage.len == 0: "(empty)" else: commitMessage, textColor = textColor)

          if self.changelists.len > 0:
            separator()
            builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
              self.renderGitUiCommand(builder, "gitui.stage-all", "Stage All")
              self.renderGitUiCommand(builder, "gitui.stage-selected", "Stage")
              self.renderGitUiCommand(builder, "gitui.unstage-selected", "Unstage")
              self.renderGitUiCommand(builder, "gitui.revert-selected", "Revert")
              for clIdx, changelist in self.changelists:
                builder.panel(&{SizeToContentY, FillX, DrawText}, text = changelist.changelist.description, textColor = accentColor)
                for fileIdx, file in changelist.changelist.files:
                  let isSelected = self.cursor.panel == Changelists and self.cursor.changelistIndex == clIdx and self.cursor.fileIndex == fileIdx
                  let highlightBg = if isSelected: selectionColor else: color(0, 0, 0, 0)
                  let backgroundFlag = if isSelected: &{FillBackground} else: 0.UINodeFlags
                  let (_, name) = file.path.splitPath
                  let stagedStr = if file.stagedStatus != None: $file.stagedStatus else: " "
                  let unstagedStr = if file.unstagedStatus != None: $file.unstagedStatus else: " "
                  builder.panel(&{SizeToContentY, FillX, LayoutHorizontal} + backgroundFlag, backgroundColor = highlightBg):
                    builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = stagedStr & unstagedStr & " ", textColor = keyColor)
                    builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = name, textColor = textColor)

          if not self.commitsFetched:
            asyncSpawn self.refreshCommitsAsync()

          if self.commits.len > 0:
            separator()
            builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
              builder.panel(&{SizeToContentY, FillX, DrawText}, text = "Recent Commits", textColor = accentColor)
              for commitIdx, commit in self.commits:
                let isSelected = self.cursor.panel == Commits and self.cursor.commitIndex == commitIdx
                let highlightBg = if isSelected: selectionColor else: color(0, 0, 0, 0)
                let backgroundFlag = if isSelected: &{FillBackground} else: 0.UINodeFlags
                builder.panel(&{SizeToContentY, FillX, LayoutHorizontal} + backgroundFlag, backgroundColor = highlightBg):
                  builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = commit.id, textColor = keyColor)
                  builder.panel(&{}, w = builder.charWidth)
                  builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = commit.description[0..min(commit.description.high, 40)], textColor = textColor)

          if self.branches.len > 0:
            separator()
            builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
              builder.panel(&{SizeToContentY, FillX, DrawText}, text = "Branches", textColor = accentColor)
              for branchIdx, branch in self.branches:
                if branch.len > 0:
                  let isSelected = self.cursor.panel == Branches and self.cursor.branchIndex == branchIdx
                  let highlightBg = if isSelected: selectionColor else: color(0, 0, 0, 0)
                  let backgroundFlag = if isSelected: &{FillBackground} else: 0.UINodeFlags
                  builder.panel(&{SizeToContentY, FillX, DrawText} + backgroundFlag, text = "  " & branch, textColor = textColor, backgroundColor = highlightBg)

          if self.lastMessage.len > 0:
            separator()
            let color = if self.lastMessageError:
              errorColor
            else:
              accentColor
            builder.panel(&{SizeToContentY, FillX, DrawText, TextWrap, TextMultiline}, text = "Last: " & self.lastMessage, textColor = color)

        let size = builder.currentChild.bounds.wh
        let scrollableAmount = max(size.y - builder.currentParent.bounds.h, 0)
        self.scrollOffset = self.scrollOffset.clamp(0, scrollableAmount)

        builder.currentChild.rawY = -self.scrollOffset

        # Scroll bar
        buildCommands(currentNode.renderCommands):
          let scrollBarColor = builder.theme.color(@["scrollBar", "scrollbarSlider.background"], backgroundColor.lighten(0.1))
          let w = ceil(builder.charWidth * 0.5)
          let thumbHeightRatio = currentNode.bounds.h / max(size.y, 1.0)
          let thumbHeight = clamp(thumbHeightRatio * currentNode.bounds.h.float, builder.textHeight, max(currentNode.bounds.h - builder.textHeight, currentNode.bounds.h * 0.9))
          let scrollableHeight = currentNode.bounds.h.float - thumbHeight
          let thumbY = (self.scrollOffset / scrollableAmount) * scrollableHeight
          fillRect(rect(currentNode.bounds.w - w, floor(thumbY), w, ceil(thumbHeight)), scrollBarColor)

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
    result.renderImpl = proc(view: View, builder: UINodeBuilder): seq[dynamic_view.OverlayRenderFunc] =
      let gitUiView = view.GitUiView
      renderGitUi(gitUiView, builder)

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

  proc init_module_git_ui*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, "Failed to initialize init_module_git_ui: no services found"
      return

    let layout = services.getService(LayoutService).get
    let commands = services.getService(CommandService).get
    let vcsService = services.getService(VCSService).getOr:
      log lvlWarn, "Failed to get VCSService for git_ui"
      return

    let events = getServiceChecked(EventHandlerService)
    let platform = services.getService(PlatformService).get.platform

    var view: GitUiView = newGitUiView()
    view.vcsService = vcsService
    view.events = events
    view.editors = services.getService(DocumentEditorService).get
    view.platform = platform

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

    template runGitAsync(args: seq[string], onComplete: untyped): untyped =
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

    template defineCommand(inName: string, desc: string, body: untyped): untyped =
      discard commands.registerCommand(command_service.Command(
        namespace: "",
        name: "gitui." & inName,
        description: desc,
        parameters: @[],
        returnType: "void",
        execute: proc(args {.inject.}: string): string {.gcsafe, raises: [].} =
          try:
            body
            return ""
          except CatchableError:
            return ""
      ))

    defineCommand("toggle", "Toggle git ui"):
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

    defineCommand("cursor-down", "Move cursor down"):
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

    defineCommand("cursor-up", "Move cursor up"):
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

    defineCommand("push", "Push"):
      if view.editCommit:
        view.setError("Finish editing first")
        return
      runGitAsync(@["push"]):
        view.setMessage("Pushed")
        asyncSpawn view.refreshStatusAsync()

    defineCommand("pull", "Pull"):
      if view.editCommit:
        view.setError("Finish editing first")
        return
      runGitAsync(@["pull"]):
        view.setMessage("Pulled")
        asyncSpawn view.refreshStatusAsync()
        asyncSpawn view.refreshBranchesAsync()
        asyncSpawn view.refreshCommitsAsync()
        asyncSpawn view.refreshChangelistsAsync()

    defineCommand("stash", "Stash changes"):
      if view.editCommit:
        view.setError("Finish editing first")
        return
      runGitAsync(@["stash"]):
        asyncSpawn view.refreshStatusAsync()
        asyncSpawn view.refreshChangelistsAsync()

    defineCommand("stash-pop", "Pop latest stash"):
      if view.editCommit:
        view.setError("Finish editing first")
        return
      runGitAsync(@["stash", "pop"]):
        asyncSpawn view.refreshStatusAsync()
        asyncSpawn view.refreshChangelistsAsync()

    defineCommand("commit", "Commit"):
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
      runGitAsync(@["commit", "-m", msg.strip()]):
        view.commitMessage = ""
        asyncSpawn view.refreshStatusAsync()
        asyncSpawn view.refreshCommitsAsync()
        asyncSpawn view.refreshChangelistsAsync()

    defineCommand("commit-amend", "Amend latest commit"):
      if view.editCommit:
        view.setError("Finish editing first")
        return
      let msg = view.commitMessage
      if msg.strip().len == 0:
        view.setError("No commit message")
        return
      runGitAsync(@["commit", "--amend", "-m", msg.strip()]):
        view.commitMessage = ""
        asyncSpawn view.refreshStatusAsync()
        asyncSpawn view.refreshCommitsAsync()
        asyncSpawn view.refreshChangelistsAsync()

    defineCommand("commit-edit-start", "Start editing commit message"):
      if view.editCommit:
        return
      view.commitOnMessageSave = false
      view.savedCommitMessage = view.commitMessage
      if view.commitEditor != nil:
        view.editCommit = true
        view.commitEditor.getCommandComponent().get.executeCommand("""set-mode "vim.insert" true true""")
        view.markDirty()

    defineCommand("commit-edit-cancel", "Cancel editing commit message"):
      view.commitMessage = view.savedCommitMessage
      view.savedCommitMessage = ""
      view.editCommit = false
      view.setMessage("Edit cancelled")

    defineCommand("commit-edit-confirm", "Confirm commit message"):
      view.savedCommitMessage = ""
      view.editCommit = false
      view.setMessage("Message updated")
      if view.commitOnMessageSave:
        let msg = view.commitMessage
        runGitAsync(@["commit", "-m", msg.strip()]):
          view.commitMessage = ""
          asyncSpawn view.refreshStatusAsync()
          asyncSpawn view.refreshCommitsAsync()
          asyncSpawn view.refreshChangelistsAsync()

    defineCommand("switch-branch", "Switch branch"):
      if view.editCommit:
        view.setError("Finish editing first")
        return
      let branch = args.strip()
      if branch.len == 0:
        view.setError("No branch specified")
        return
      runGitAsync(@["checkout", branch]):
        asyncSpawn view.refreshStatusAsync()
        asyncSpawn view.refreshBranchesAsync()

    defineCommand("fetch", "Fetch"):
      if view.editCommit:
        view.setError("Finish editing first")
        return
      runGitAsync(@["fetch", "--all"]):
        asyncSpawn view.refreshStatusAsync()

    defineCommand("reset-soft", "Soft reset"):
      if view.editCommit:
        view.setError("Finish editing first")
        return
      runGitAsync(@["reset", "--soft", "HEAD~1"]):
        discard

    defineCommand("stage-all", "Stage all files"):
      if view.editCommit:
        view.setError("Finish editing first")
        return
      runGitAsync(@["add", "-A"]):
        asyncSpawn view.refreshStatusAsync()
        asyncSpawn view.refreshChangelistsAsync()

    defineCommand("stage-selected", "Stage selected file"):
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
      let localizedPath = file.path
      for vcs in view.vcsService.versionControlSystems:
        let vcs = vcs
        proc stageTask() {.async: (raises: []).} =
          let res = await vcs.stageFile(localizedPath)
          view.setMessage(res)
          asyncSpawn view.refreshChangelistsAsync()
        asyncSpawn stageTask()
        break

    defineCommand("unstage-selected", "Unstage selected file"):
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
      let localizedPath = file.path
      proc unstageTask() {.async: (raises: []).} =
        let res = await vcs.unstageFile(localizedPath)
        view.setMessage(res)
        asyncSpawn view.refreshChangelistsAsync()
      asyncSpawn unstageTask()

    defineCommand("revert-selected", "Revert selected file"):
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
      let localizedPath = file.path
      proc revertTask() {.async: (raises: []).} =
        let res = await vcs.revertFile(localizedPath)
        view.setMessage(res)
        asyncSpawn view.refreshChangelistsAsync()
      asyncSpawn revertTask()

    defineCommand("diff-selected", "Diff selected file, commit or stash"):
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
        if view.cursor.panel != Commits:
          view.setError("Select a commit or stash first")
          return
        let commitIndex = view.cursor.commitIndex
        if commitIndex >= view.commits.len:
          view.setError("Invalid selection")
          return
        let commit = view.commits[commitIndex]
        discard commands.executeCommand(&"""explore-files "git://@/{commit.id}" false true true 0.8""")
      else:
        view.setError("Select a file first")
        return

    defineCommand("refresh", "Refresh UI"):
      asyncSpawn view.refreshStatusAsync()
      asyncSpawn view.refreshBranchesAsync()
      asyncSpawn view.refreshCommitsAsync()
      asyncSpawn view.refreshChangelistsAsync()
