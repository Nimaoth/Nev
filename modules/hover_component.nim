#use command_component
import std/[options]
import nimsumtree/[rope]
import misc/[event, custom_async, delayed_task, jsonex]
import component, view, config_provider, input_api

export component

const currentSourcePath2 = currentSourcePath()
include module_base

declareSettings HoverSettings, "hover":
  ## How many milliseconds after hovering a word the lsp hover request is sent.
  declare delay, int, 200

  ## Command to run when hovering something.
  declare command, JsonNodeEx, nil

type
  HoverComponent* = ref object of Component
    settings*: HoverSettings
    hoverView*: View
    showHoverTask: DelayedTask    # for showing hover info after a delay
    hideHoverTask: DelayedTask    # for hiding hover info after a delay
    currentHoverLocation: Point   # the location of the mouse hover
    showHover*: bool              # whether to show hover info in ui
    hoverText*: string            # the text to show in the hover info
    hoverLocation*: Point         # where to show the hover info
    hoverScrollOffset*: float     # the scroll offset inside the hover window
    onHoverViewMarkedDirtyHandle: Id
    hoverViewCallbackHandles: Id
    overlayViews*: seq[View]
    mouseHoverLocation*: Point
    mouseHoverMods*: Modifiers
    onModsChangedHandle: Id
    isHovered*: bool


{.push gcsafe, raises: [].}

# DLL API
{.push rtl.}
proc getHoverComponent*(self: ComponentOwner): Option[HoverComponent]
proc newHoverComponent*(settings: HoverSettings): HoverComponent

proc hoverComponentClearOverlayViews(self: HoverComponent)
proc hoverComponentClearHoverView(self: HoverComponent)
proc hoverComponentShowHoverForAsync(self: HoverComponent, cursor: Point): Future[void] {.async.}
proc hoverComponentHideHover(self: HoverComponent)
proc hoverComponentShowHoverDelayed(self: HoverComponent)
proc hoverComponentCancelHover(self: HoverComponent)
proc hoverComponentShowHoverView(self: HoverComponent, view: View, location: Point)
{.pop.}

# Nice wrappers
{.push inline.}
proc clearHoverView*(self: HoverComponent) = hoverComponentClearHoverView(self)
proc clearOverlayViews*(self: HoverComponent) = hoverComponentClearOverlayViews(self)
proc showHoverForAsync*(self: HoverComponent, cursor: Point): Future[void] {.async.} = hoverComponentShowHoverForAsync(self, cursor).await
proc hideHover*(self: HoverComponent) = hoverComponentHideHover(self)
proc showHoverDelayed*(self: HoverComponent) = hoverComponentShowHoverDelayed(self)
proc cancelHover*(self: HoverComponent) = hoverComponentCancelHover(self)
proc showHoverView*(self: HoverComponent, view: View, location: Point) = hoverComponentShowHoverView(self, view, location)
{.pop.}

# Implementation
when implModule:
  import std/[strformat]
  import misc/[util, custom_logger, rope_utils]
  import nimsumtree/[rope]
  import document, document_editor, text_component, language_server_component, command_component, text_editor_component
  import command_service, service, platform_service, platform/platform

  logCategory "hover-component"

  proc handleModsChanged(self: HoverComponent, oldMods: Modifiers, newMods: Modifiers)
  proc toggleHover(self: HoverComponent)
  proc showHoverMouseAtMouse(self: HoverComponent)

  var HoverComponentId: ComponentTypeId = componentGenerateTypeId()

  proc markDirty(self: HoverComponent) =
    self.owner.DocumentEditor.markDirty()

  proc getHoverComponent*(self: ComponentOwner): Option[HoverComponent] =
    return self.getComponent(HoverComponentId).mapIt(it.HoverComponent)

  proc newHoverComponent*(settings: HoverSettings): HoverComponent =
    return HoverComponent(
      typeId: HoverComponentId,
      settings: settings,
      initializeImpl: (proc(self: Component, owner: ComponentOwner) =
        let self = self.HoverComponent
        let platform = getServices().getService(PlatformService).get.platform
        self.onModsChangedHandle = platform.onModifiersChanged.subscribe proc(change: tuple[old: Modifiers, new: Modifiers]) {.gcsafe.} =
          self.handleModsChanged(change.old, change.new)

        let commands = owner.getCommandComponent().get
        commands.registerCommand "hover.toggle", self, proc(handler: RootRef, args: string): string {.gcsafe, raises: [].} =
          let self = handler.HoverComponent
          self.toggleHover()

        commands.registerCommand "hover.show-at-mouse", self, proc(handler: RootRef, args: string): string {.gcsafe, raises: [].} =
          let self = handler.HoverComponent
          self.showHoverMouseAtMouse()

        commands.registerCommand "hover.hide", self, proc(handler: RootRef, args: string): string {.gcsafe, raises: [].} =
          let self = handler.HoverComponent
          self.hideHover()
      ),
      deinitializeImpl: (proc(self: Component) =
        let self = self.HoverComponent
        if self.showHoverTask.isNotNil:
          self.showHoverTask.pause()
        if self.hideHoverTask.isNotNil:
          self.hideHoverTask.pause()
        let platform = getServices().getService(PlatformService).get.platform
        platform.onModifiersChanged.unsubscribe self.onModsChangedHandle
      ),
    )

  proc handleModsChanged(self: HoverComponent, oldMods: Modifiers, newMods: Modifiers) =
    if not self.isHovered:
      return
    self.mouseHoverMods = newMods
    if self.showHover:
      self.showHoverDelayed()

  proc hoverComponentClearOverlayViews(self: HoverComponent) =
    for overlay in self.overlayViews:
      overlay.onMarkedDirty.unsubscribe(self.onHoverViewMarkedDirtyHandle)
      overlay.onDetached.unsubscribe(self.hoverViewCallbackHandles)
    self.overlayViews.setLen(0)

  proc hoverComponentClearHoverView(self: HoverComponent) =
    if self.hoverView != nil:
      self.hoverView.onMarkedDirty.unsubscribe(self.onHoverViewMarkedDirtyHandle)
      self.hoverView.onDetached.unsubscribe(self.hoverViewCallbackHandles)
      self.hoverView = nil

  proc detachHoverView(self: HoverComponent) =
    if self.hoverView != nil:
      self.overlayViews.add(self.hoverView)
      self.hoverView = nil
      self.showHover = false

  proc toggleHover(self: HoverComponent) =
    ## Shows lsp hover information for the current selection.
    ## Does nothing if no language server is available or the language server doesn't return any info.
    if self.showHover:
      self.clearHoverView()
      self.showHover = false
      self.markDirty()
    else:
      let te = self.owner.getTextEditorComponent().getOr:
        return
      self.mouseHoverLocation = te.selection.b
      asyncSpawn self.showHoverForAsync(self.mouseHoverLocation)

  proc showHoverMouseAtMouse(self: HoverComponent) =
    ## Shows lsp hover information for the current selection.
    ## Does nothing if no language server is available or the language server doesn't return any info.
    asyncSpawn self.showHoverForAsync(self.mouseHoverLocation)

  proc hoverComponentShowHoverForAsync(self: HoverComponent, cursor: Point): Future[void] {.async.} =
    if self.hideHoverTask.isNotNil:
      self.hideHoverTask.pause()

    let document = self.owner.DocumentEditor.currentDocument

    let ls = document.getLanguageServerComponent().getOr:
      log lvlWarn, &"Failed to show hover for '{cursor}': No language server"
      return

    let hoverInfo = await ls.getHover(document.filename, cursor.toCursor)
    if self.owner.isNil:
      return

    if hoverInfo.getSome(hoverInfo):
      self.showHover = true
      # self.showSignatureHelp = false # todo
      self.hoverScrollOffset = 0
      self.hoverText = hoverInfo
      self.clearHoverView()
      self.hoverLocation = cursor
    else:
      self.clearHoverView()
      self.showHover = false

    self.markDirty()

  # proc showHover*(self: HoverComponent, message: string, location: Cursor) =
  #   if self.hideHoverTask.isNotNil:
  #     self.hideHoverTask.pause()

  #   self.showHover = true
  #   # self.showSignatureHelp = false # todo
  #   self.hoverScrollOffset = 0
  #   self.hoverText = message
  #   self.clearHoverView()
  #   self.hoverLocation = location

  #   self.markDirty()

  proc hoverComponentShowHoverView(self: HoverComponent, view: View, location: Point) =
    if self.hideHoverTask.isNotNil:
      self.hideHoverTask.pause()

    self.clearHoverView()
    self.showHover = true
    self.hoverScrollOffset = 0
    self.hoverView = view
    self.hoverLocation = location
    self.onHoverViewMarkedDirtyHandle = view.onMarkedDirty.subscribe proc() = self.markDirty()
    view.onDetached.subscribe self.hoverViewCallbackHandles, proc() = self.detachHoverView()

    self.markDirty()

  proc hoverComponentCancelHover(self: HoverComponent) =
    if self.showHoverTask.isNotNil:
      self.showHoverTask.pause()

  proc hoverComponentHideHover(self: HoverComponent) =
    ## Hides the hover information.
    self.clearHoverView()
    self.showHover = false
    self.markDirty()

  proc hideHoverDelayed*(self: HoverComponent) =
    ## Hides the hover information after a delay.
    if self.showHoverTask.isNotNil:
      self.showHoverTask.pause()

    let hoverDelayMs = self.settings.delay.get()
    if self.hideHoverTask.isNil:
      self.hideHoverTask = startDelayed(hoverDelayMs, repeat=false):
        self.hideHover()
    else:
      self.hideHoverTask.interval = hoverDelayMs
      self.hideHoverTask.reschedule()

  proc runHoverCommand*(self: HoverComponent) =
    try:
      let commands = getServices().getService(CommandService).get
      var command = ".hover.show-at-mouse "
      var configCommand = self.settings.command.get()
      if configCommand != nil and configCommand.kind != JNull:
        let modsKey = $self.mouseHoverMods
        if configCommand.kind == jsonex.JObject and configCommand.hasKey(modsKey):
          configCommand = configCommand[modsKey]

        let (name, args, ok) = configCommand.parseCommand()
        if name == "":
          return
        if ok:
          discard commands.executeCommand(name & " " & args, record = false)
          return

      discard commands.executeCommand(command, record = false)
    except CatchableError as e:
      log lvlError, &"Failed to execute hover command: {e.msg}"

  proc hoverComponentShowHoverDelayed(self: HoverComponent) =
    ## Show hover information after a delay.

    if self.hideHoverTask.isNotNil:
      self.hideHoverTask.pause()

    let hoverDelayMs = self.settings.delay.get()
    if self.showHoverTask.isNil:
      self.showHoverTask = startDelayed(hoverDelayMs, repeat=false):
        self.runHoverCommand()
    else:
      self.showHoverTask.interval = hoverDelayMs
      self.showHoverTask.reschedule()

  proc init_module_hover_component*() {.cdecl, exportc, dynlib.} =
    discard

{.pop.}
