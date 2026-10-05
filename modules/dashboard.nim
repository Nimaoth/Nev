#use stats layout command_service session input_handler
const currentSourcePath2 = currentSourcePath()
include module_base

const logos = @[
  @[
    """░▒▓███████▓▒░░▒▓████████▓▒░▒▓█▓▒░░▒▓█▓▒░""",
    """░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░""",
    """░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░       ░▒▓█▓▒▒▓█▓▒░""",
    """░▒▓█▓▒░░▒▓█▓▒░▒▓██████▓▒░  ░▒▓█▓▒▒▓█▓▒░""",
    """░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░        ░▒▓█▓▓█▓▒░""",
    """░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░        ░▒▓█▓▓█▓▒░""",
    """░▒▓█▓▒░░▒▓█▓▒░▒▓████████▓▒░  ░▒▓██▓▒░""",
  ],

  @[
    """░███    ░██""",
    """░████   ░██""",
    """░██░██  ░██  ░███████  ░██    ░██""",
    """░██ ░██ ░██ ░██    ░██ ░██    ░██""",
    """░██  ░██░██ ░█████████  ░██  ░██""",
    """░██   ░████ ░██          ░██░██""",
    """░██    ░███  ░███████     ░███""",
  ],

  @[
    """ ███▄    █ ▓█████ ██▒   █▓""",
    """ ██ ▀█   █ ▓█   ▀▓██░   █▒""",
    """▓██  ▀█ ██▒▒███   ▓██  █▒░""",
    """▓██▒  ▐▌██▒▒▓█  ▄  ▒██ █░░""",
    """▒██░   ▓██░░▒████▒  ▒▀█░""",
    """░ ▒░   ▒ ▒ ░░ ▒░ ░  ░ ▐░""",
    """░ ░░   ░ ▒░ ░ ░  ░  ░ ░░""",
    """   ░   ░ ░    ░       ░░""",
    """         ░    ░  ░     ░""",
    """                      ░""",
  ],

  @[
    """███╗   ██╗███████╗██╗   ██╗""",
    """████╗  ██║██╔════╝██║   ██║""",
    """██╔██╗ ██║█████╗  ██║   ██║""",
    """██║╚██╗██║██╔══╝  ╚██╗ ██╔╝""",
    """██║ ╚████║███████╗ ╚████╔╝""",
    """╚═╝  ╚═══╝╚══════╝  ╚═══╝""",
  ],

  @[
    """   ▄▄     ▄▄▄""",
    """   ██▄   ██▀""",
    """   ███▄  ██""",
    """   ██ ▀█▄██ ▄█▀█▄▀█▄ ██▀""",
    """   ██   ▀██ ██▄█▀ ██▄██""",
    """ ▀██▀    ██▄▀█▄▄▄  ▀█▀""",
  ],
]

when implModule:
  import std/[tables, options, strformat, sequtils, random, json, algorithm]
  import misc/[custom_logger, util, custom_async, jsonex, myjsonutils, timer]
  import nuigi
  import nuigi/layout/flex
  import nuigi/widgets
  import view, layout/layout, service, input_handler/input_handler, command_service
  import vcs
  import platform, stats
  import session
  import config_provider

  logCategory "dashboard"

  from std/times import getTime, toUnix, nanosecond
  let now = getTime()
  randomize(now.toUnix * 1_000_000_000 + now.nanosecond)

  type
    GitFileEntry* = object
      stagedStatus*: string
      unstagedStatus*: string
      path*: string

    GitStatusState* = ref object of RootObj
      entries*: seq[GitFileEntry]
      hasFetched*: bool

    SessionsState* = ref object of RootObj
      sessions*: seq[string]
      hasFetched*: bool

    CommitHistoryState* = ref object of RootObj
      commits*: seq[VCSCommitInfo]
      hasFetched*: bool

    StatEntry* = object
      label*: string
      value*: string

    StatsState* = ref object of RootObj
      stats: StatsService

    LogoState = ref object of RootObj
      index: int = -1
      colorName: string
      cachedLogos: seq[seq[string]]

    SectionInfo* = object
      title*: string
      side*: int
      renderer*: string
      state*: RootRef
      border*: bool = false
      config*: JsonNodeEx

  proc getLogos(section: var SectionInfo): seq[seq[string]] =
    var state = section.state.LogoState
    if state == nil:
      state = LogoState()
      section.state = state
    if state.cachedLogos.len == 0:
      if section.config != nil and section.config.hasKey("logos"):
        for logoNode in section.config["logos"].getElems:
          var lines: seq[string] = @[]
          for line in logoNode.getElems:
            lines.add line.getStr
          state.cachedLogos.add lines
      else:
        state.cachedLogos = logos
    return state.cachedLogos

  type
    SectionRenderFunc* = proc(self: DashboardView, nui: var UiBuilder, section: var SectionInfo) {.gcsafe, raises: [].}

    DashboardView* = ref object of View
      events*: EventHandlerService
      commandService*: CommandService
      eventHandlers*: Table[string, EventHandler]
      sections*: seq[SectionInfo]
      sectionRenderers*: Table[string, SectionRenderFunc]
      uptimeTimer: Timer

  proc drawSection(self: DashboardView, nui: var UiBuilder, section: var SectionInfo) =
    nui.layoutVertical:
      discard nui.fillX().fitY().backendPadding(4).backendGap(2).maskChildren()
      if section.border:
        discard nui.styleIndex(UiStyleIndexPanel).fillBackground()
          .backendBorderWidth(1).backendPadding(8, 1)
          .borderColor(nui.themeStyle(UiStyleIndexPanel)[].borderColor)
      if section.title.len > 0:
        nui.node:
          discard nui.fillX().fitY().styleIndex(UiStyleIndexHeader)
            .fillBackground().backendPadding(2)
            .textStyleIndex(int(UiStyleIndexHeaderText)).text(section.title)
      if section.renderer in self.sectionRenderers:
        self.sectionRenderers[section.renderer](self, nui, section)

  proc renderDashboardNui(self: DashboardView, nui: var UiBuilder) =
    {.cast(gcsafe).}:
      self.resetDirty()

      let configStore = getServices().getServiceChecked(ConfigService).runtime
      let minTwoColChars = configStore.get("dashboard.min-two-col-chars", 160)
      let padXPercent = configStore.get("dashboard.pad-x", 0.1).float32
      let padYPercent = configStore.get("dashboard.pad-y", 0.02).float32
      let sectionGapPercent = configStore.get("dashboard.section-gap", 0.02).float32
      let colGapPercent = configStore.get("dashboard.col-gap", 0.05).float32
      let parentWidth = nui.currentNode.size.x
      let parentHeight = nui.currentNode.size.y
      let monoSize = nui.themeTextStyle(UiStyleIndexDefaultMono)[].fontSize
      let charWidth = if nui.backendType == UiBackendType.Terminal:
        1.0'f32
      else:
        monoSize * 0.6'f32
      let twoColumns = parentWidth >= minTwoColChars.float32 * charWidth
      let padX = max(0.0'f32, parentWidth * padXPercent)
      let padY = max(0.0'f32, parentHeight * padYPercent)
      let sectionGap = max(if nui.backendType == UiBackendType.Terminal: 1.0'f32 else: 4.0'f32,
        parentHeight * sectionGapPercent)
      let columnGap = if nui.backendType == UiBackendType.Terminal:
        0.0'f32
      else:
        max(8.0'f32, parentWidth * colGapPercent)
      let panelBase = nui.themeStyle(UiStyleIndexPanel)[].fillColor
      let panelColor = if self.active:
        accentVariation(panelBase, 0.06'f32, 1.08'f32)
      else:
        panelBase

      nui.layoutVertical("dashboard"):
        discard nui.fillX().fillY().styleIndex(UiStyleIndexPanel)
          .fillBackground().backgroundColor(panelColor)
        if nui.wasClicked(includeChildren = true):
          getServiceChecked(LayoutService).tryActivateView(self)

        nui.scrollBox:
          discard nui.fillX().fillY()
          nui.layoutVertical("dashboard-content"):
            discard nui.fillX().fitY().backendPaddingX(padX)
              .backendPaddingY(padY).backendGap(sectionGap)

            for section in self.sections.mitems:
              if section.side == -1:
                self.drawSection(nui, section)

            if twoColumns:
              nui.node("dashboard-columns"):
                discard nui.fillX().fitY().flexLayout()
                  .flexDirection(FlexDirectionRow).columnGap(columnGap)
                nui.layoutVertical("dashboard-left"):
                  discard nui.fitY().flex(1.0'f32, 1.0'f32, 0.0'f32)
                    .backendGap(sectionGap)
                  for section in self.sections.mitems:
                    if section.side == 0:
                      self.drawSection(nui, section)
                nui.layoutVertical("dashboard-right"):
                  discard nui.fitY().flex(1.0'f32, 1.0'f32, 0.0'f32)
                    .backendGap(sectionGap)
                  for section in self.sections.mitems:
                    if section.side > 0:
                      self.drawSection(nui, section)
            else:
              for section in self.sections.mitems:
                if section.side != -1:
                  self.drawSection(nui, section)

  proc desc(self: DashboardView): string = "Dashboard"
  proc kind(self: DashboardView): string = "dashboard"
  proc display(self: DashboardView): string = "Dashboard"

  proc handleAction(self: DashboardView, action: string, arg: string): Option[string] =
    if action == "dashboard.logo.randomize":
      let colorNames = ["Red", "Green", "Yellow", "Blue", "Magenta", "Cyan"]
      for section in self.sections.mitems:
        if section.state of LogoState:
          let sectionLogos = section.getLogos()
          let current = section.state.LogoState.index
          while section.state.LogoState.index == current:
            section.state.LogoState.index = rand(sectionLogos.high)
          section.state.LogoState.colorName = colorNames[rand(colorNames.high)]
      self.markDirty()
      return "".some
    if action == "dashboard.session.open":
      try:
        let idx = arg.parseInt
        for section in self.sections:
          if section.state of SessionsState:
            let state = section.state.SessionsState
            if idx >= 0 and idx < state.sessions.len:
              let path = state.sessions[state.sessions.len - 1 - idx]
              return self.commandService.executeCommand("load-session " & $path.toJson)
            break
      except: discard
      return "".some
    return self.commandService.executeCommand(action & " " & arg)

  proc getEventHandler(self: DashboardView, context: string): EventHandler =
    if context notin self.eventHandlers:
      var eventHandler: EventHandler
      assignEventHandler(eventHandler, self.events.getEventHandlerConfig(context)):
        onAction:
          if self.handleAction(action, arg).isSome:
            Handled
          else:
            Ignored

        onInput:
          log lvlInfo, &"dashboard handleInput: {input}"
          Handled

      self.eventHandlers[context] = eventHandler
      return eventHandler

    return self.eventHandlers[context]

  proc getEventHandlers(self: DashboardView, inject: Table[string, EventHandler]): seq[EventHandler] =
    result.add self.getEventHandler("dashboard")

  proc renderLogo(self: DashboardView, nui: var UiBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    if section.state == nil:
      let state = LogoState()
      section.state = state

    let sectionLogos = section.getLogos()
    if sectionLogos.len == 0:
      return
    var state = section.state.LogoState
    if state.index < 0 or state.index > sectionLogos.high:
      state.index = rand(sectionLogos.high)
    if state.colorName.len == 0:
      let colorNames = ["Red", "Green", "Yellow", "Blue", "Magenta", "Cyan"]
      state.colorName = colorNames[rand(colorNames.high)]

    let lines {.cursor.} = sectionLogos[state.index]
    let hueShift = case state.colorName
      of "Red": -0.46'f32
      of "Green": -0.28'f32
      of "Yellow": -0.18'f32
      of "Blue": 0.04'f32
      of "Magenta": 0.18'f32
      of "Cyan": -0.08'f32
      else: 0.0'f32
    let accent = nui.themeStyle(UiStyleIndexAccent)[].fillColor
    nui.node("dashboard-logo"):
      discard nui.fillX().fitY().flexLayout()
        .flexDirection(FlexDirectionRow).justifyContent(FlexJustifyCenter)
      nui.layoutVertical:
        discard nui.fitX().fitY()
        let brightnessSteps = max(1, lines.len - 1)
        for lineIndex, line in lines:
          nui.node:
            let brightness = 1.15'f32 -
              lineIndex.float32 / brightnessSteps.float32 * 0.35'f32
            discard nui.fit().copyTextStyleIndex(UiStyleIndexDefaultMono)
              .textColor(accentVariation(accent, hueShift, brightness)).text(line)

  proc maxItems(section: SectionInfo, default: int = 10): int =
    if section.config != nil:
      section.config{"maxItems"}.getInt(default)
    else:
      default

  proc renderKeymaps(self: DashboardView, nui: var UiBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    var commands: seq[(string, string)] = @[]
    if section.config != nil and section.config.hasKey("commands"):
      for cmdNode in section.config["commands"].getElems:
        let cmd = cmdNode.getStr
        let label = cmd.split('-').mapIt(it.capitalizeAscii).join(" ")
        commands.add (cmd, label)

    var activeModes: seq[string] = @["editor"]
    let services = getServices()
    if services != nil:
      let configService = services.getServiceChecked(ConfigService)
      activeModes = configService.runtime.get("editor.base-modes", seq[string], @["editor"])

    var commandToKeys: Table[string, seq[string]]
    let events = self.events
    if events != nil and events.commandInfos != nil:
      for (cmd, _) in commands:
        if events.commandInfos.getInfos(cmd).getSome(infos):
          for info in infos:
            if info.context in activeModes:
              commandToKeys.mgetOrPut(cmd, @[]).add info.keys

    for keys in commandToKeys.mvalues:
      keys.sort(proc(a, b: string): int = cmp(a.len, b.len))

    nui.layoutVertical("dashboard-keymaps"):
      discard nui.fillX().fitY().backendGap(1)
      for (cmd, label) in commands:
        let hasKey = cmd in commandToKeys
        let keys = if hasKey: commandToKeys[cmd] else: @[]
        nui.node:
          discard nui.fillX().fitY().flexLayout()
            .flexDirection(FlexDirectionRow).columnGap(nui.backendSpacing(2))
          nui.node:
            discard nui.fitY().flex(1.0'f32, 1.0'f32, 0.0'f32)
              .textStyleIndex(int(UiStyleIndexDefaultText)).text(label)
          if hasKey:
            for ki, key in keys:
              if ki > 0:
                nui.node:
                  discard nui.fit().textStyleIndex(int(UiStyleIndexMutedText)).text("|")
              nui.node:
                discard nui.fit().textStyleIndex(int(UiStyleIndexLabelText)).text(key)

  proc renderRecentFiles(self: DashboardView, nui: var UiBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    discard

  proc refreshSessions(view: DashboardView, state: SessionsState) {.async.} =
    let services = getServices()
    if services == nil: return
    let sessionService = services.getService(SessionService).getOr: return

    try:
      let sessions = await sessionService.getRecentSessions()
      state.sessions = sessions
      state.hasFetched = true
      view.markDirty()
      view.events.rebuildCommandToKeysMap()
    except CatchableError as e:
      log lvlError, &"Failed to get recent sessions: {e.msg}"
      state.hasFetched = true
      view.markDirty()

  proc renderSessions(self: DashboardView, nui: var UiBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    var state = SessionsState(section.state)
    if state == nil:
      state = SessionsState()
      section.state = state
      asyncSpawn refreshSessions(self, state)

    var indexToKey: Table[int, string]
    let events = self.events
    if events != nil and events.commandInfos != nil:
      if events.commandInfos.getInfos("dashboard.session.open").getSome(infos):
        for info in infos:
          let spaceIdx = info.command.find(' ')
          if spaceIdx != -1:
            try:
              let idx = info.command[spaceIdx + 1 .. ^1].parseInt
              if idx notin indexToKey:
                indexToKey[idx] = info.keys
            except: discard

    nui.layoutVertical("dashboard-sessions"):
      discard nui.fillX().fitY().backendGap(1)
      if not state.hasFetched:
        nui.node:
          discard nui.fit().textStyleIndex(int(UiStyleIndexMutedText)).text("Loading...")
      elif state.sessions.len == 0:
        nui.node:
          discard nui.fit().textStyleIndex(int(UiStyleIndexMutedText)).text("No recent sessions")
      else:
        let count = min(section.maxItems(9), state.sessions.len)
        for vi in 0 ..< count:
          let session = state.sessions[state.sessions.len - 1 - vi]
          let hasKey = vi in indexToKey
          let keyText = if hasKey: indexToKey[vi] else: ""
          nui.node:
            discard nui.fillX().fitY().flexLayout()
              .flexDirection(FlexDirectionRow).columnGap(nui.backendSpacing(2))
            nui.node:
              discard nui.fitY().flex(1.0'f32, 1.0'f32, 0.0'f32)
                .maskChildren()
                .textStyleIndex(int(UiStyleIndexDefaultText)).text(session)
            if hasKey:
              nui.node:
                discard nui.fit().textStyleIndex(int(UiStyleIndexLabelText)).text(keyText)

  proc renderCurrentSession(self: DashboardView, nui: var UiBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    discard

  proc refreshGitStatus(view: DashboardView, state: GitStatusState) {.async.} =
    let services = getServices()
    if services == nil: return
    let vcsService = services.getService(VCSService).getOr: return

    var entries: seq[GitFileEntry] = @[]
    for vcs in vcsService.versionControlSystems:
      try:
        let changelists = await vcs.getChangedFiles()
        for changelist in changelists:
          for info in changelist.files:
            let (_, name) = info.path.splitPath
            entries.add GitFileEntry(
              stagedStatus: $info.stagedStatus,
              unstagedStatus: $info.unstagedStatus,
              path: name,
            )
      except CatchableError as e:
        log lvlError, &"Failed to get git status: {e.msg}"

    state.entries = entries
    state.hasFetched = true
    view.markDirty()

  proc renderGitStatus(self: DashboardView, nui: var UiBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    var state = GitStatusState(section.state)
    if state == nil:
      state = GitStatusState()
      section.state = state
      asyncSpawn refreshGitStatus(self, state)

    nui.layoutVertical("dashboard-git-status"):
      discard nui.fillX().fitY().backendGap(1)
      if not state.hasFetched:
        nui.node:
          discard nui.fit().textStyleIndex(int(UiStyleIndexMutedText)).text("Loading...")
      elif state.entries.len == 0:
        nui.node:
          discard nui.fit().textStyleIndex(int(UiStyleIndexMutedText)).text("No changes")
      else:
        let maxEntries = section.maxItems(25)
        for i, entry in state.entries:
          if i >= maxEntries: break
          nui.node:
            discard nui.fillX().fitY().flexLayout()
              .flexDirection(FlexDirectionRow).columnGap(nui.backendSpacing(2))
            let statusStr = entry.stagedStatus & entry.unstagedStatus & "  "
            nui.node:
              discard nui.fit().textStyleIndex(int(UiStyleIndexSmallText)).text(statusStr)
            nui.node:
              discard nui.fitY().flex(1.0'f32, 1.0'f32, 0.0'f32)
                .maskChildren()
                .textStyleIndex(int(UiStyleIndexDefaultText)).text(entry.path)

  proc refreshCommitHistory(view: DashboardView, state: CommitHistoryState) {.async.} =
    let services = getServices()
    if services == nil: return
    let vcsService = services.getService(VCSService).getOr: return

    var commits: seq[VCSCommitInfo] = @[]
    for vcs in vcsService.versionControlSystems:
      try:
        let history = await vcs.getCommitHistory(50)
        commits.add history
      except CatchableError as e:
        log lvlError, &"Failed to get commit history: {e.msg}"

    state.commits = commits
    state.hasFetched = true
    view.markDirty()

  proc renderCommitHistory(self: DashboardView, nui: var UiBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    var state = CommitHistoryState(section.state)
    if state == nil:
      state = CommitHistoryState()
      section.state = state
      asyncSpawn refreshCommitHistory(self, state)

    nui.layoutVertical("dashboard-commit-history"):
      discard nui.fillX().fitY().backendGap(1)
      if not state.hasFetched:
        nui.node:
          discard nui.fit().textStyleIndex(int(UiStyleIndexMutedText)).text("Loading...")
      elif state.commits.len == 0:
        nui.node:
          discard nui.fit().textStyleIndex(int(UiStyleIndexMutedText)).text("No commits")
      else:
        let maxCommits = section.maxItems(20)
        let displayCommits = state.commits[0 ..< min(maxCommits, state.commits.len)]
        for commit in displayCommits:
          nui.node:
            discard nui.fillX().fitY().flexLayout()
              .flexDirection(FlexDirectionRow).columnGap(nui.backendSpacing(4))
            nui.node:
              discard nui.fit().textStyleIndex(int(UiStyleIndexSmallText)).text(commit.id)
            nui.node:
              discard nui.fitY().flex(1.0'f32, 1.0'f32, 0.0'f32)
                .maskChildren()
                .textStyleIndex(int(UiStyleIndexDefaultText)).text(commit.description)
            nui.node:
              discard nui.fit().textStyleIndex(int(UiStyleIndexMutedText)).text(commit.date)
            nui.node:
              discard nui.fit().textStyleIndex(int(UiStyleIndexSmallText)).text(commit.author)

  proc renderStats(self: DashboardView, nui: var UiBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    var state = StatsState(section.state)
    if state == nil:
      let stats = getServices().getService(StatsService).getOr:
        return
      state = StatsState(stats: stats)
      section.state = state

    nui.layoutVertical("dashboard-stats"):
      discard nui.fillX().fitY().backendGap(1)
      var uptime = self.uptimeTimer.elapsed.ms.int div 1000
      var uptimeUnit = "s"
      if uptime >= 60:
        uptime = uptime div 60
        uptimeUnit = "min"
      if uptime >= 60:
        uptime = uptime div 60
        uptimeUnit = "h"
      state.stats.set("Uptime", uptime, uptimeUnit)

      for (name, stat) in state.stats.stats.pairs:
        let valueText = $stat.value & stat.unit
        nui.node:
          discard nui.fillX().fitY().flexLayout()
            .flexDirection(FlexDirectionRow).columnGap(nui.backendSpacing(2))
          nui.node:
            discard nui.fitY().flex(1.0'f32, 1.0'f32, 0.0'f32)
              .textStyleIndex(int(UiStyleIndexDefaultText)).text(name)
          nui.node:
            discard nui.fit().textStyleIndex(int(UiStyleIndexLabelText)).text(valueText)

  proc buildSectionsFromConfig(config: JsonNodeEx): seq[SectionInfo] =
    if config == nil or config.kind != JObject:
      log lvlWarn, "dashboard: sections config is not an object, using defaults"
      return @[]

    var sections: seq[SectionInfo] = @[]
    for key, entry in config.getFields:
      if entry == nil or entry.kind != JObject:
        log lvlWarn, &"dashboard: section '{key}' is not an object, ignoring"
        continue

      let name = entry{"name"}.getStr(key)
      if name.len == 0:
        log lvlWarn, &"dashboard: section '{key}' has empty name, ignoring"
        continue

      let title = entry{"title"}.getStr(name)
      let side = clamp(entry{"side"}.getInt(0), -1, 1)
      let border = entry{"border"}.getBool(false)
      sections.add SectionInfo(
        title: title,
        side: side,
        renderer: name,
        border: border,
        config: entry,
      )
    return sections

  proc createDashboardView(events: EventHandlerService, commandService: CommandService): DashboardView =
    let defaultSectionsConfig = %%*{
      "logo": {
        "name": "logo",
        "title": "",
        "side": -1,
      },
      "commands": {
        "name": "commands",
        "title": "Commands",
        "side": 0,
        "commands": ["command-line", "explore-help", "choose-file", "choose-open",
          "explore-workspace", "explore-files",
          "browse-keybinds", "explore-user-config", "quit"]
      },
      "sessions": {
        "name": "sessions",
        "title": "Sessions",
        "side": 0,
        "maxItems": 9
      },
      "gitStatus": {
        "name": "gitStatus",
        "title": "Git Status",
        "side": 1,
        "maxItems": 20
      },
      "commitHistory": {
        "name": "commitHistory",
        "title": "Commit History",
        "side": 1,
        "maxItems": 20
      },
      "stats": {
        "name": "stats",
        "title": "Stats",
        "side": 0
      }
    }

    let services = getServices()
    let configService = services.getServiceChecked(ConfigService)
    let sectionsConfig = configService.runtime.get("dashboard.sections", JsonNodeEx, defaultSectionsConfig)

    var sections = buildSectionsFromConfig(sectionsConfig)
    if sections.len == 0:
      log lvlWarn, "dashboard: no valid sections found, falling back to defaults"
      sections = buildSectionsFromConfig(defaultSectionsConfig)

    let view = DashboardView(
      events: events,
      commandService: commandService,
      sections: sections,
      uptimeTimer: startTimer(),
    )

    view.sectionRenderers["logo"] = renderLogo
    view.sectionRenderers["commands"] = renderKeymaps
    view.sectionRenderers["recentFiles"] = renderRecentFiles
    view.sectionRenderers["sessions"] = renderSessions
    view.sectionRenderers["currentSession"] = renderCurrentSession
    view.sectionRenderers["gitStatus"] = renderGitStatus
    view.sectionRenderers["commitHistory"] = renderCommitHistory
    view.sectionRenderers["stats"] = renderStats

    view.renderNuiImpl = proc(self: View, nui: var UiBuilder) =
      renderDashboardNui(self.DashboardView, nui)
    view.getEventHandlersImpl = proc(self: View, inject: Table[string, EventHandler]): seq[EventHandler] =
      getEventHandlers(self.DashboardView, inject)
    view.descImpl = proc(self: View): string = desc(self.DashboardView)
    view.kindImpl = proc(self: View): string = kind(self.DashboardView)
    view.displayImpl = proc(self: View): string = display(self.DashboardView)

    let platformService = services.getServiceChecked(PlatformService)
    discard view.onMarkedDirty.subscribe proc() =
      platformService.platform.requestedRender = true

    discard configService.runtime.onConfigChanged.subscribe proc(key: string) =
      if key == "" or key.startsWith("dashboard."):
        let sectionsConfig = configService.runtime.get("dashboard.sections", JsonNodeEx, defaultSectionsConfig)
        var newSections = buildSectionsFromConfig(sectionsConfig)
        if newSections.len == 0:
          log lvlWarn, "dashboard: no valid sections after config change, keeping current"
          return
        # Preserve state from matching sections, clear logo cache on config change
        var merged: seq[SectionInfo] = @[]
        for newSection in newSections:
          var section = newSection
          for oldSection in view.sections:
            if oldSection.title == newSection.title and oldSection.renderer == newSection.renderer:
              section.state = oldSection.state
              if section.renderer == "logo" and section.state of LogoState:
                section.state.LogoState.cachedLogos = @[]
              break
          merged.add section
        view.sections = merged
        view.markDirty()

    return view

  proc init_module_dashboard*() {.cdecl, exportc, dynlib.} =
    log lvlInfo, "init_module_dashboard"
    let services = getServices()
    if services == nil:
      log lvlWarn, "Failed to initialize dashboard: no services found"
      return

    let events = services.getService(EventHandlerService).getOr:
      log lvlWarn, "Failed to get EventHandlerService for dashboard"
      return

    let commandService = services.getService(CommandService).getOr:
      log lvlWarn, "Failed to get CommandService for dashboard"
      return

    let layout = services.getServiceChecked(LayoutService)
    let view = createDashboardView(events, commandService)
    layout.fallbackView = view
