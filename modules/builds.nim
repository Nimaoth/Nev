#use terminal layout command_service selector_popup finder theme
import std/[options, json, tables]
import service, view

const currentSourcePath2 = currentSourcePath()
include module_base

when implModule:
  import std/[sets, strutils, strformat]
  import misc/[custom_logger, util, id, myjsonutils, jsonex, custom_async, timer]
  import layout/layout, platform, view_panel, config_provider, command_service
  import terminal/terminal
  import selector_popup/builder, finder
  import theme, chroma
  from scripting_api import CreateTerminalOptions
  import nuigi
  import nuigi/widgets
  import nuigi/layout/flex

  {.push gcsafe.}
  {.push raises: [].}

  logCategory "builds"

  type
    BuildStatus = enum
      Idle
      Running
      Stopping
      Succeeded
      Failed
      Cancelled

    BuildConfig = object
      name: string
      description: string
      kind: string
      shell: string
      command: string
      setup: string
      group: string
      slot: string
      mode: Option[string]
      focus: bool

    BuildState = ref object
      name: string
      group: string
      status: BuildStatus
      exitCode: Option[int]
      terminal: View
      timer: Timer
      duration: float64
      runId: int

    BuildsView* = ref object of View
      states: Table[string, BuildState]
      lastBuild: string
      ticking: bool

  var gBuildsView: BuildsView

  const defaultShell = when defined(windows): "powershell" else: "bash"
  const defaultSlot = "#build-run-terminal"

  proc getBuildsView(): BuildsView {.raises: [ValueError].} =
    {.gcsafe.}:
      if gBuildsView.isNil:
        raise newException(ValueError, "Builds view not initialized")
      gBuildsView

  proc getCommandString(node: JsonNodeEx): string =
    ## Commands can be a string or an array of strings, which are joined with `; `.
    if node != nil and node.kind == JsonexNodeKind.JArray:
      var parts: seq[string] = @[]
      for part in node:
        let part = part.getStr("")
        if part.len > 0:
          parts.add part
      return parts.join("; ")
    return node.getStr("")

  proc parseBuildConfig(name: string, value: JsonNodeEx): Option[BuildConfig] =
    if value == nil or value.kind != JsonexNodeKind.JObject:
      return BuildConfig.none
    var config = BuildConfig(name: name)
    config.description = value{"description"}.getStr("")
    config.kind = value{"kind"}.getStr("build")
    config.shell = value{"shell"}.getStr(defaultShell)
    config.command = value{"command"}.getCommandString()
    config.setup = value{"setup"}.getCommandString()
    config.group = value{"group"}.getStr("builds")
    config.slot = value{"slot"}.getStr(defaultSlot)
    config.focus = value{"focus"}.getBool(false)
    let mode = value{"mode"}
    if mode != nil and mode.kind == JsonexNodeKind.JString:
      config.mode = mode.getStr().some
    if config.command.len == 0:
      return BuildConfig.none
    return config.some

  proc getBuildConfigs(): seq[BuildConfig] =
    let config = getServiceChecked(ConfigService)
    let builds = config.runtime.get("builds", newJexObject())
    if builds == nil or builds.kind != JsonexNodeKind.JObject:
      return
    for name, value in builds.fields.pairs:
      if parseBuildConfig(name, value).getSome(build):
        result.add build

  proc getBuildConfig(name: string): Option[BuildConfig] =
    for config in getBuildConfigs():
      if config.name == name:
        return config.some
    return BuildConfig.none

  proc isActive(state: BuildState): bool = state.status in {Running, Stopping}

  proc anyActive(self: BuildsView): bool =
    for state in self.states.values:
      if state.isActive:
        return true
    return false

  proc finishBuild(self: BuildsView, state: BuildState, exitCode: Option[int]) =
    if not state.isActive:
      return
    state.duration = state.timer.elapsed.float64
    state.exitCode = exitCode
    state.status = if state.status == Stopping:
      Cancelled
    elif exitCode == 0.some:
      Succeeded
    else:
      Failed
    log lvlInfo, &"Build '{state.name}' finished: {state.status}, exit code {exitCode}"
    self.markDirty()

  proc updateTerminalStates(self: BuildsView) =
    ## Detects terminals which were closed by the user.
    let terminals = getServiceChecked(TerminalService)
    for state in self.states.values:
      if state.terminal != nil and not terminals.isOpen(state.terminal):
        state.terminal = nil
        if state.isActive:
          state.status = Stopping
          self.finishBuild(state, int.none)

  proc closeTerminal(state: BuildState) =
    if state.terminal == nil:
      return
    let terminal = state.terminal
    state.terminal = nil
    if getServiceChecked(TerminalService).isOpen(terminal):
      getServiceChecked(LayoutService).closeView(terminal, keepHidden = false, restoreHidden = false)

  proc tickWhileActive(self: BuildsView) {.async: (raises: []).} =
    ## Redraws the view every second while builds are running so the elapsed time updates.
    defer:
      self.ticking = false
    while true:
      try:
        await sleepAsync(1000.milliseconds)
      except CatchableError:
        discard
      self.updateTerminalStates()
      self.markDirty()
      if not self.anyActive():
        break

  proc runBuild(self: BuildsView, config: BuildConfig) =
    let terminals = getServiceChecked(TerminalService)
    let layout = getServiceChecked(LayoutService)
    let configs = getServiceChecked(ConfigService)

    let shellCommand = configs.runtime.get("editor.shells." & config.shell & ".command", "")
    if shellCommand == "":
      log lvlError, &"Failed to run build '{config.name}': Unknown shell '{config.shell}', configure it in 'editor.shells.{config.shell}'"
      return

    var args: seq[string] = @[]
    let shellArgs = configs.runtime.get("editor.shells." & config.shell & ".args", newJexArray())
    if shellArgs != nil and shellArgs.kind == JsonexNodeKind.JArray:
      for arg in shellArgs:
        args.add arg.getStr("")
    if config.setup.len > 0:
      args.add config.setup & "; " & config.command
    else:
      args.add config.command

    self.updateTerminalStates()

    var state = self.states.getOrDefault(config.name, nil)
    if state == nil:
      state = BuildState(name: config.name)
      self.states[config.name] = state

    # Close the previous terminal of this build and all finished terminals in the same group.
    if state.isActive:
      state.status = Stopping
      self.finishBuild(state, int.none)
    state.closeTerminal()
    for other in self.states.values:
      if other != state and other.group == config.group and not other.isActive:
        other.closeTerminal()

    inc state.runId
    let runId = state.runId
    state.group = config.group
    state.exitCode = int.none
    state.duration = 0

    log lvlInfo, &"Run build '{config.name}': {shellCommand} {args}"
    let view = terminals.createTerminalView(shellCommand, CreateTerminalOptions(
      args: args,
      group: config.group,
      mode: config.mode,
      closeOnTerminate: false,
      slot: config.slot,
      focus: config.focus,
      createPty: true,
    ))
    if view == nil:
      log lvlError, &"Failed to create terminal for build '{config.name}'"
      state.status = Failed
      self.markDirty()
      return

    # Restoring the terminal from a session would run the build again.
    view.saveStateImpl = proc(self: View): JsonNode = nil

    state.terminal = view
    state.status = Running
    state.timer = startTimer()
    self.lastBuild = config.name

    let self = self
    discard terminals.onTerminated(view, proc(exitCode: Option[int]) {.gcsafe, raises: [].} =
      if state.runId == runId:
        self.finishBuild(state, exitCode)
    )

    layout.addView(view, slot = config.slot, focus = config.focus)
    self.markDirty()

    if not self.ticking:
      self.ticking = true
      asyncSpawn self.tickWhileActive()

  proc stopBuild(self: BuildsView, state: BuildState) =
    if not state.isActive:
      return
    if state.status == Running and state.terminal != nil:
      log lvlInfo, &"Interrupt build '{state.name}'"
      state.status = Stopping
      getServiceChecked(TerminalService).interrupt(state.terminal)
    else:
      log lvlInfo, &"Kill build '{state.name}'"
      state.status = Stopping
      self.finishBuild(state, int.none)
      state.closeTerminal()
    self.markDirty()

  proc showTerminal(self: BuildsView, state: BuildState) =
    if state.terminal == nil:
      return
    let slot = if getBuildConfig(state.name).getSome(config): config.slot else: defaultSlot
    getServiceChecked(LayoutService).showView(state.terminal, slot = slot, focus = true)

  proc buildsToggle(view: BuildsView) =
    let layout = getServiceChecked(LayoutService)
    if layout.isViewVisible(view):
      layout.closeView(view, keepHidden = false, restoreHidden = false)
    else:
      layout.addView(view, slot = "#small-left", focus = false)

  proc buildsRun(view: BuildsView, name: string = "") =
    if getBuildConfig(name).getSome(config):
      view.runBuild(config)
    else:
      log lvlError, &"Unknown build '{name}', configure it in 'builds.{name}'"

  proc buildsStop(view: BuildsView, name: string = "") =
    if name == "":
      for state in view.states.values:
        view.stopBuild(state)
    elif view.states.contains(name):
      view.stopBuild(view.states.getOrDefault(name, nil))

  proc buildsRerunLast(view: BuildsView) =
    if view.lastBuild == "":
      log lvlWarn, "No build was run yet"
      return
    view.buildsRun(view.lastBuild)

  proc buildsShowTerminal(view: BuildsView, name: string = "") =
    let name = if name == "": view.lastBuild else: name
    view.updateTerminalStates()
    if view.states.contains(name):
      view.showTerminal(view.states.getOrDefault(name, nil))

  proc buildsChoose(view: BuildsView) =
    var builder = SelectorPopupBuilder()
    builder.scope = "choose-build".some
    builder.scaleX = 0.5
    builder.scaleY = 0.5

    var items = newSeq[FinderItem]()
    for config in getBuildConfigs():
      items.add FinderItem(
        displayName: config.name,
        details: @[config.kind, config.description, config.command],
        filterText: config.name & " " & config.description,
      )

    builder.finder = newFinder(newStaticDataSource(items), filterAndSort = true).some
    builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
      view.buildsRun(item.displayName)
      true

    discard getServiceChecked(LayoutService).pushSelectorPopup(builder)

  proc formatDuration(seconds: float64): string =
    let total = max(0, seconds.int)
    if total < 60:
      return &"{total}s"
    return &"{total div 60}m {total mod 60:02}s"

  proc statusText(state: BuildState): string =
    case state.status
    of Idle: ""
    of Running: "Running " & formatDuration(state.timer.elapsed.float64)
    of Stopping: "Stopping " & formatDuration(state.timer.elapsed.float64)
    of Succeeded: "Succeeded in " & formatDuration(state.duration)
    of Failed:
      if state.exitCode.getSome(code):
        &"Failed (exit code {code}) after {formatDuration(state.duration)}"
      else:
        "Failed after " & formatDuration(state.duration)
    of Cancelled: "Cancelled after " & formatDuration(state.duration)

  proc statusTextStyle(status: BuildStatus): int =
    case status
    of Idle: int(UiStyleIndexMutedText)
    of Running, Stopping: int(UiStyleIndexInfoText)
    of Succeeded: int(UiStyleIndexHintText)
    of Failed: int(UiStyleIndexErrorText)
    of Cancelled: int(UiStyleIndexWarningText)

  proc sectionTitle(kind: string): string =
    case kind
    of "build": "Build"
    of "run": "Run"
    of "debug": "Debug"
    else: kind.capitalizeAscii

  proc toUiColor(c: chroma.Color): UiColor =
    rgba(c.r.float32, c.g.float32, c.b.float32, c.a.float32)

  proc toChromaColor(c: UiColor): chroma.Color =
    color(c.r, c.g, c.b, c.a)

  proc renderBuildRow(self: BuildsView, nui: var UiBuilder, config: BuildConfig, commandColor: UiColor) =
    let state = self.states.getOrDefault(config.name, nil)
    let status = if state != nil: state.status else: Idle
    let title = if config.description.len > 0: config.description else: config.name
    let subtitle = if status == Idle: config.command else: state.statusText()

    nui.node("build:" & config.name):
      discard nui.fillX().fitY().flexLayout().flexDirection(FlexDirectionRow)
        .columnGap(nui.backendSpacing(2)).alignItems(FlexAlignCenter)
      nui.layoutVertical:
        discard nui.fitY().flex(1.0'f32, 1.0'f32, 0.0'f32).maskChildren()
        nui.node:
          discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(title)
        nui.node:
          if status == Idle:
            discard nui.fit().textStyleIndex(int(UiStyleIndexMutedText)).textColor(commandColor).text(subtitle)
          else:
            discard nui.fit().textStyleIndex(status.statusTextStyle()).text(subtitle)

      if status in {Running, Stopping}:
        # Stop sends Ctrl+C, pressing it again while stopping kills the build.
        if nui.button(if status == Stopping: "✖" else: "■"):
          nui.enqueueNextFrame(proc() {.closure, gcsafe, raises: [].} = self.stopBuild(state))
      else:
        if nui.button(if status == Idle: "▶" else: "↻"):
          nui.enqueueNextFrame(proc() {.closure, gcsafe, raises: [].} = self.runBuild(config))
      if state != nil and state.terminal != nil:
        if nui.button("❐"):
          nui.enqueueNextFrame(proc() {.closure, gcsafe, raises: [].} = self.showTerminal(state))

  proc renderBuildsNui(self: BuildsView, nui: var UiBuilder) =
    {.cast(gcsafe).}:
      self.resetDirty()
      try:
        self.updateTerminalStates()
        let layout = getServiceChecked(LayoutService)
        let configs = getBuildConfigs()

        var kinds: seq[string] = @[]
        for config in configs:
          if config.kind notin kinds:
            kinds.add config.kind

        var activeCount = 0
        for state in self.states.values:
          if state.isActive:
            inc activeCount

        nui.viewPanel("builds", self.active, true,
            getServiceChecked(ConfigService).runtime,
            ViewPanelOptions().withViewActions(layout, self)):
          nui.node:
            discard nui.fit().textStyleIndex(int(UiStyleIndexHeaderText))
              .text(if activeCount > 0: &"Builds ({activeCount} running)" else: "Builds")
        do:
          if nui.wasClicked(includeChildren = true):
            layout.tryActivateView(self)

          nui.scrollBox:
            discard nui.fillX().fillY()
            nui.layoutVertical("builds-content"):
              # The scrollbar is drawn over the content, so keep the buttons out from under it.
              let scrollbarWidth = if nui.backendType == UiBackendType.Terminal: 0.0'f32 else: 10.0'f32
              discard nui.anchorsX(0, 1).offsetsX(0, -scrollbarWidth).finishAnchors()
                .fitY().backendGap(4)
              if configs.len == 0:
                nui.node:
                  discard nui.fit().textStyleIndex(int(UiStyleIndexMutedText))
                    .text("No builds configured. Add them to the 'builds' setting.")
              let themes = getServiceChecked(ThemeService)
              let mutedColor = nui.themeTextStyle(UiStyleIndexMutedText)[].textColor.toChromaColor
              let commandColor = themes.theme.tokenColor("string", mutedColor).toUiColor
              var separatorColor = nui.themeTextStyle(UiStyleIndexMutedText)[].textColor
              separatorColor.a *= 0.5
              for i, kind in kinds:
                if i > 0:
                  nui.layoutVertical("separator:" & kind):
                    if nui.backendType == UiBackendType.Terminal:
                      discard nui.fillX().height(1)
                    else:
                      discard nui.fillX().fitY().paddingY(4)
                      nui.node:
                        discard nui.fillX().height(1).backgroundColor(separatorColor).fillBackground()
                nui.node:
                  discard nui.fit().textStyleIndex(int(UiStyleIndexLabelText)).text(kind.sectionTitle)
                for config in configs:
                  if config.kind == kind:
                    self.renderBuildRow(nui, config, commandColor)
      except Exception as e:
        log lvlError, &"Failed to render builds view: {e.msg}"

  proc newBuildsView(): BuildsView =
    result = BuildsView()
    result.renderNuiImpl = proc(view: View, nui: var UiBuilder) {.gcsafe, raises: [].} =
      renderBuildsNui(view.BuildsView, nui)
    result.kindImpl = proc(self: View): string = "builds"
    result.descImpl = proc(self: View): string = "Builds"
    result.displayImpl = proc(self: View): string = "Builds"
    result.copyImpl = proc(self: View): View = self
    result.saveLayoutImpl = proc(self: View, discardedViews: HashSet[Id]): JsonNode =
      result = newJObject()
      result["kind"] = "builds".toJson
    result.saveStateImpl = proc(self: View): JsonNode =
      result = newJObject()
      result["kind"] = "builds".toJson

  include generated/builds_commands

  proc init_module_builds*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, "Failed to initialize init_module_builds: no services found"
      return

    let layout = services.getServiceChecked(LayoutService)

    let view = newBuildsView()
    {.gcsafe.}:
      gBuildsView = view

    layout.addViewFactory "builds", proc(config: JsonNode): View {.raises: [].} =
      return view

    registerCommands(getServiceChecked(CommandService))
