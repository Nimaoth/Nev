#use stats layout command_service
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
  import std/[tables, options, strformat, sequtils, random, json, algorithm, math]
  import vmath, chroma
  import misc/[custom_logger, util, custom_async, custom_unicode, jsonex, myjsonutils, timer]
  import ui/node
  import view, dynamic_view, layout/layout, service, events, command_service
  import theme
  import vcs/vcs
  import platform_service, stats
  import session
  import config_provider
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor

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
    SectionRenderFunc* = proc(self: DashboardView, builder: UINodeBuilder, section: var SectionInfo) {.gcsafe, raises: [].}

    DashboardView* = ref object of DynamicView
      events*: EventHandlerService
      commandService*: CommandService
      eventHandlers*: Table[string, EventHandler]
      sections*: seq[SectionInfo]
      sectionRenderers*: Table[string, SectionRenderFunc]
      uptimeTimer: Timer

  proc drawSection(self: DashboardView, builder: UINodeBuilder, section: var SectionInfo, sectionRenderers: Table[string, SectionRenderFunc], x, y, w: float, textColor, sectionColor: Color) =
    let cx = builder.charWidth
    builder.panel(&{SizeToContentY, MaskContent}, x = x, y = y, w = w, backgroundColor = sectionColor):
      builder.panel(&{LayoutVertical, SizeToContentY, FillX}, border = border(ceil(cx / 2))):
        if section.title != "":
          builder.panel(&{SizeToContentY, FillX, DrawText}, text = section.title, textColor = textColor)
        if section.renderer in sectionRenderers:
          sectionRenderers[section.renderer](self, builder, section)
      if section.border:
        builder.panel(&{FillX, FillY, DrawBorder, DrawBorderTerminal}, border = border(1), borderColor = textColor, backgroundColor = sectionColor)

  proc renderDashboard(self: DashboardView, builder: UINodeBuilder): seq[OverlayRenderFunc] =
    self.resetDirty()

    let services = getServices()
    let configService = services.getService(ConfigService).get
    let configStore = configService.runtime

    let minTwoColChars = configStore.get("dashboard.min-two-col-chars", 160)
    let padXPercent = configStore.get("dashboard.pad-x", 0.1)
    let padYPercent = configStore.get("dashboard.pad-y", 0.02)
    let sectionGapPercent = configStore.get("dashboard.section-gap", 0.02)
    let colGapPercent = configStore.get("dashboard.col-gap", 0.05)

    let inactiveBrightnessChange = -0.025
    var backgroundColor = if self.active:
      builder.theme.color("editor.background", color(25/255, 25/255, 40/255))
    else:
      builder.theme.color("editor.background", color(25/255, 25/255, 25/255)).lighten(inactiveBrightnessChange)
    backgroundColor.a = 1

    let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))

    let parentBounds = builder.currentParent.bounds
    let pw = parentBounds.w
    let ph = parentBounds.h

    let padX = padXPercent * pw
    let padY = padYPercent * ph
    let gapY = sectionGapPercent * ph
    let colGapX = colGapPercent * pw

    builder.panel(&{FillBackground, FillX, FillY}, backgroundColor = backgroundColor):
      if pw < minTwoColChars.float * builder.charWidth:
        # Single column layout
        let colX = padX
        let colW = pw - padX * 2

        var y = padY
        for section in self.sections.mitems:
          if y > ph - padY:
            continue
          drawSection(self, builder, section, self.sectionRenderers, colX, y, colW, textColor, backgroundColor)
          y += builder.currentChild.bounds.h + gapY
      else:
        # Two column layout
        let totalContentW = pw - padX * 2 - colGapX
        let leftColW = totalContentW * 0.5
        let rightColW = totalContentW - leftColW
        let leftColX = padX
        let rightColX = padX + leftColW + colGapX

        var ly = padY
        var ry = padY
        for section in self.sections.mitems:
          let (colX, colW) = if section.side == -1:
            (leftColX, rightColX + rightColW - leftColX)
          elif section.side == 0:
            (leftColX, leftColW)
          else:
            (rightColX, rightColW)
          var y = if section.side == -1:
            max(ly, ry)
          elif section.side == 0:
            ly
          else:
            ry
          if y > ph - padY:
            continue
          drawSection(self, builder, section, self.sectionRenderers, colX, y, colW, textColor, backgroundColor)
          let sectionH = builder.currentChild.bounds.h
          if section.side == -1:
            let yh = y + sectionH + gapY
            ly = yh
            ry = yh
          elif section.side == 0:
            ly += sectionH + gapY
          else:
            ry += sectionH + gapY

    return @[]

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

  proc renderLogo(self: DashboardView, builder: UINodeBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    let cx = builder.charWidth
    let cy = builder.textHeight
    let foregroundColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))

    if section.state == nil:
      let state = LogoState()
      section.state = state

    let sectionLogos = section.getLogos()
    var state = section.state.LogoState
    if state.index < 0 or state.index > sectionLogos.high:
      state.index = rand(sectionLogos.high)
    if state.colorName.len == 0:
      let colorNames = ["Red", "Green", "Yellow", "Blue", "Magenta", "Cyan"]
      state.colorName = colorNames[rand(colorNames.high)]

    let ansiColor = builder.theme.color("terminal.ansi" & state.colorName, foregroundColor).darken(0.1)
    let ansiBrightColor = builder.theme.color("terminal.ansiBright" & state.colorName, foregroundColor).lighten(0.1)
    let lines {.cursor.} = sectionLogos[state.index]

    var maxLineWidth = 0
    for l in lines:
      maxLineWidth = max(maxLineWidth, l.runeLen.int)

    let availableWidth = builder.currentParent.bounds.w
    let logoWidth = maxLineWidth.float * cx
    let logoX = max(0.0, (availableWidth - logoWidth) / 2)

    builder.panel(0.UINodeFlags, x = logoX, w = logoWidth, h = lines.len.float * cy):
      currentNode.renderCommands.clear()
      buildCommands(currentNode.renderCommands):
        let brightnessSteps = lines.len.max(1)
        for i, line in lines:
          let y = i.float * cy
          let t = i.float / (brightnessSteps - 1).float.max(1)
          let lineColor = mix(ansiBrightColor, ansiColor, t)
          drawText(line, rect(0, y, line.runeLen.float * cx, cy), lineColor, 0.UINodeFlags)

  proc shouldRenderLines(): bool =
    let services = getServices()
    let platformService = services.getService(PlatformService).getOr:
      return false
    return platformService.platform.backend == Backend.Gui

  proc maxItems(section: SectionInfo, default: int = 10): int =
    if section.config != nil:
      section.config{"maxItems"}.getInt(default)
    else:
      default

  proc renderKeymaps(self: DashboardView, builder: UINodeBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
    let accentColor = builder.theme.color("editorLineNumber.foreground", color(120/255, 120/255, 160/255))
    let keyColor = builder.theme.tokenColor("keyword", accentColor)
    let sepColor = builder.theme.tokenColor("comment", accentColor)

    var commands: seq[(string, string)] = @[]
    if section.config != nil and section.config.hasKey("commands"):
      for cmdNode in section.config["commands"].getElems:
        let cmd = cmdNode.getStr
        let label = cmd.split('-').mapIt(it.capitalizeAscii).join(" ")
        commands.add (cmd, label)

    var activeModes: seq[string] = @["editor"]
    let services = getServices()
    if services != nil:
      let configService = services.getService(ConfigService).get
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

    let renderLines = shouldRenderLines()
    let cx = builder.charWidth
    let cy = builder.textHeight
    let availableWidth = builder.currentParent.bounds.w
    let lineColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255)).lighten(0.01)
    builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
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
            if lineW > 0 and renderLines:
              builder.panel(&{DrawBorder}, x = lineX, y = floor(cy * 0.5) - 1, w = lineW, h = 1, border = border(0, 0, 1, 0), borderColor = lineColor)
            var xOff = keyX
            for ki, key in keys:
              if ki > 0:
                builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, x = xOff, text = " | ", textColor = sepColor)
                xOff += 3.0 * cx
              builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, x = xOff, text = key, textColor = keyColor)
              xOff += key.len.float * cx

  proc renderRecentFiles(self: DashboardView, builder: UINodeBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
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

  proc renderSessions(self: DashboardView, builder: UINodeBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
    let accentColor = builder.theme.color("editorLineNumber.foreground", color(120/255, 120/255, 160/255))
    let keyColor = builder.theme.tokenColor("keyword", accentColor)
    let lineColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255)).lighten(0.01)
    let renderLines = shouldRenderLines()

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

    builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
      if not state.hasFetched:
        builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = "Loading...", textColor = accentColor)
      elif state.sessions.len == 0:
        builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = "No recent sessions", textColor = accentColor)
      else:
        let cx = builder.charWidth
        let cy = builder.textHeight
        let availableWidth = builder.currentParent.bounds.w
        let count = min(section.maxItems(9), state.sessions.len)
        for vi in 0 ..< count:
          let session = state.sessions[state.sessions.len - 1 - vi]
          let hasKey = vi in indexToKey
          let keyText = if hasKey: indexToKey[vi] else: ""
          let keyX = availableWidth - keyText.len.float * cx - cx * 2
          let sessionWidth = session.len.float * cx
          builder.panel(&{SizeToContentY, FillX}):
            builder.panel(&{SizeToContentY, FillX, DrawText}, text = session, textColor = textColor)
            if hasKey:
              let lineX = sessionWidth + cx
              let lineW = keyX - lineX - cx
              if lineW > 0 and renderLines:
                builder.panel(&{DrawBorder}, x = lineX, y = floor(cy * 0.5) - 1, w = lineW, h = 1, border = border(0, 0, 1, 0), borderColor = lineColor)
              builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, x = keyX, text = keyText, textColor = keyColor)

  proc renderCurrentSession(self: DashboardView, builder: UINodeBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
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

  proc renderGitStatus(self: DashboardView, builder: UINodeBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
    let accentColor = builder.theme.color("editorLineNumber.foreground", color(120/255, 120/255, 160/255))

    var state = GitStatusState(section.state)
    if state == nil:
      state = GitStatusState()
      section.state = state
      asyncSpawn refreshGitStatus(self, state)

    builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
      if not state.hasFetched:
        builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = "Loading...", textColor = accentColor)
      elif state.entries.len == 0:
        builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = "No changes", textColor = accentColor)
      else:
        let maxEntries = section.maxItems(25)
        for i, entry in state.entries:
          if i >= maxEntries: break
          builder.panel(&{SizeToContentY, FillX, LayoutHorizontal}):
            let statusStr = entry.stagedStatus & entry.unstagedStatus & "  "
            builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = statusStr, textColor = accentColor)
            builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = entry.path, textColor = textColor)

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

  proc renderCommitHistory(self: DashboardView, builder: UINodeBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
    let accentColor = builder.theme.color("editorLineNumber.foreground", color(120/255, 120/255, 160/255))
    let commitIdColor = builder.theme.tokenColor("keyword", accentColor)
    let descriptionColor = builder.theme.tokenColor("string", textColor)
    let authorColor = builder.theme.tokenColor("comment", accentColor)
    let dateColor = builder.theme.tokenColor("type", textColor)

    var state = CommitHistoryState(section.state)
    if state == nil:
      state = CommitHistoryState()
      section.state = state
      asyncSpawn refreshCommitHistory(self, state)

    builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
      if not state.hasFetched:
        builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = "Loading...", textColor = accentColor)
      elif state.commits.len == 0:
        builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = "No commits", textColor = accentColor)
      else:
        let maxCommits = section.maxItems(20)
        let displayCommits = state.commits[0 ..< min(maxCommits, state.commits.len)]

        var maxIdLen = 0
        var maxDateLen = 0
        var maxAuthorLen = 0
        for commit in displayCommits:
          maxIdLen = max(maxIdLen, commit.id.runeLen.int)
          maxDateLen = max(maxDateLen, commit.date.runeLen.int)
          maxAuthorLen = max(maxAuthorLen, commit.author.runeLen.int)

        let colPad = 2
        let cx = builder.charWidth
        let availableWidth = builder.currentParent.bounds.w
        let fixedWidth = (maxIdLen + maxDateLen + maxAuthorLen + colPad * 4).float * cx
        let maxDescLen = max(10, int((availableWidth - fixedWidth) / cx))

        let idX = 0.0
        let descX = (maxIdLen + colPad).float * cx
        let dateX = descX + (maxDescLen + colPad).float * cx
        let authorX = dateX + (maxDateLen + colPad).float * cx

        for commit in displayCommits:
          var descText = commit.description
          if descText.runeLen.int > maxDescLen:
            descText = descText[0.RuneIndex ..< (maxDescLen - 1).RuneIndex] & "…"
          builder.panel(&{SizeToContentY, FillX, LayoutHorizontal}):
            builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, x = idX, text = commit.id, textColor = commitIdColor)
            builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, x = descX, text = descText, textColor = descriptionColor)
            builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, x = dateX, text = commit.date, textColor = dateColor)
            builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, x = authorX, text = commit.author, textColor = authorColor)

  proc renderStats(self: DashboardView, builder: UINodeBuilder, section: var SectionInfo) {.gcsafe, raises: [].} =
    let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
    let accentColor = builder.theme.color("editorLineNumber.foreground", color(120/255, 120/255, 160/255))
    let valueColor = builder.theme.tokenColor("keyword", accentColor)
    let lineColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255)).lighten(0.01)
    let renderLines = shouldRenderLines()

    var state = StatsState(section.state)
    if state == nil:
      let stats = getServices().getService(StatsService).getOr:
        return
      state = StatsState(stats: stats)
      section.state = state

    let cx = builder.charWidth
    let cy = builder.textHeight
    let availableWidth = builder.currentParent.bounds.w

    builder.panel(&{SizeToContentY, FillX, LayoutVertical}):
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
        let valueX = availableWidth - valueText.len.float * cx - cx * 2
        let labelWidth = name.len.float * cx
        builder.panel(&{SizeToContentY, FillX}):
          builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, text = name, textColor = textColor)
          let lineX = labelWidth + cx
          let lineW = valueX - lineX - cx
          if lineW > 0 and renderLines:
            builder.panel(&{DrawBorder}, x = lineX, y = floor(cy * 0.5) - 1, w = lineW, h = 1, border = border(0, 0, 1, 0), borderColor = lineColor)
          builder.panel(&{SizeToContentY, SizeToContentX, DrawText}, x = valueX, text = valueText, textColor = valueColor)

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
    let configService = services.getService(ConfigService).get
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

    view.renderImpl = proc(self: View, builder: UINodeBuilder): seq[OverlayRenderFunc] =
      renderDashboard(self.DashboardView, builder)
    view.getEventHandlersImpl = proc(self: View, inject: Table[string, EventHandler]): seq[EventHandler] =
      getEventHandlers(self.DashboardView, inject)
    view.descImpl = proc(self: View): string = desc(self.DashboardView)
    view.kindImpl = proc(self: View): string = kind(self.DashboardView)
    view.displayImpl = proc(self: View): string = display(self.DashboardView)

    let platformService = services.getService(PlatformService).get
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

    let layout = services.getService(LayoutService).get
    let view = createDashboardView(events, commandService)
    layout.fallbackView = view
