import std/[strformat, tables, sets]
import misc/[custom_logger, util, delayed_task, timer, render_command]
import view, service
import dynamic_view

include misc/dynlib_export

{.push apprtl, gcsafe, raises: [].}
proc newRenderView*(services: Services): DynamicView
proc rvSetRenderWhenInactive(self: DynamicView, enabled: bool)
proc rvSetRenderInterval(self: DynamicView, ms: int)
{.pop.}

proc setRenderWhenInactive(self: DynamicView, enabled: bool) = rvSetRenderWhenInactive(self, enabled)
proc setRenderInterval(self: DynamicView, ms: int) = rvSetRenderInterval(self, ms)

when implModule:
  import platform
  import layout/layout, input_handler/input_handler, command_service
  import ui/node

  type
    RenderView* = ref object of DynamicView
      services: Services
      commandService: CommandService
      events: EventHandlerService
      layout*: LayoutService
      platform: Platform

      commands*: RenderCommands
      userId*: string

      bounds*: Rect
      interval: int = -1
      onRender*: proc(view: RenderView) {.gcsafe, raises: [].}
      renderTask: DelayedTask
      renderWhenInactive*: bool = false
      preventThrottling*: bool = false

      eventHandlers: Table[string, EventHandler]

      modes*: seq[string]

      keyStates*: HashSet[int64]
      mouseStates*: HashSet[int64]
      mousePos*: Vec2
      scrollDelta*: Vec2

  {.push gcsafe, raises: [].}

  logCategory "custom-view"

  proc handleAction(self: RenderView, action: string, arg: string): Option[string]
  proc handleInput(self: RenderView, text: string)

  proc handleKeyPress*(self: RenderView, input: int64, modifiers: Modifiers) =
    self.keyStates.incl(input)

  proc handleKeyRelease*(self: RenderView, input: int64, modifiers: Modifiers) =
    self.keyStates.excl(input)

  proc handleRune*(self: RenderView, input: int64, modifiers: Modifiers) =
    self.keyStates.incl(input)

  proc handleMousePress(self: RenderView, button: MouseButton, modifiers: Modifiers, pos: Vec2) =
    self.mouseStates.incl(button.int64)

  proc handleMouseRelease(self: RenderView, button: MouseButton, modifiers: Modifiers, pos: Vec2) =
    self.mouseStates.excl(button.int64)

  proc handleMouseMove(self: RenderView, pos: Vec2, delta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
    self.mousePos = pos - self.bounds.xy

  proc handleScroll(self: RenderView, pos: Vec2, scroll: Vec2, modifiers: Modifiers) =
    self.scrollDelta = scroll

  proc bindPlatformEvents(self: RenderView) =
    discard self.platform.onKeyPress.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleKeyPress(event.input, event.modifiers)
    discard self.platform.onKeyRelease.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleKeyRelease(event.input, event.modifiers)
    discard self.platform.onRune.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleRune(event.input, event.modifiers)
    discard self.platform.onMousePress.subscribe proc(event: tuple[button: MouseButton, modifiers: Modifiers, pos: Vec2]): void {.gcsafe, raises: [].} = self.handleMousePress(event.button, event.modifiers, event.pos)
    discard self.platform.onMouseRelease.subscribe proc(event: tuple[button: MouseButton, modifiers: Modifiers, pos: Vec2]): void {.gcsafe, raises: [].} = self.handleMouseRelease(event.button, event.modifiers, event.pos)
    discard self.platform.onMouseMove.subscribe proc(event: tuple[pos: Vec2, delta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]]): void {.gcsafe, raises: [].} = self.handleMouseMove(event.pos, event.delta, event.modifiers, event.buttons)
    discard self.platform.onScroll.subscribe proc(event: tuple[pos: Vec2, scroll: Vec2, modifiers: Modifiers]): void {.gcsafe, raises: [].} = self.handleScroll(event.pos, event.scroll, event.modifiers)

  proc desc*(self: RenderView): string =
    &"RenderView({self.id2}, interval = {self.interval}, renderWhenInactive = {self.renderWhenInactive}, preventThrottling = {self.preventThrottling})"

  proc kind*(self: RenderView): string = "custom"

  proc display*(self: RenderView): string = self.desc()

  proc renderViewFromUserId*(layout: LayoutService, id: string): Option[RenderView] =
    for v in layout.allViews:
      if v of RenderView and v.RenderView.userId == id:
        return v.RenderView.some
    return RenderView.none

  proc activate(self: RenderView) =
    self.active = true
    self.setRenderInterval(self.interval)

  proc deactivate(self: RenderView) =
    self.active = false
    if not self.renderWhenInactive and self.renderTask != nil:
      self.renderTask.pause()

  proc setRenderCommands*(self: RenderView, commands: RenderCommands) =
    self.commands = commands
    self.markDirty()

  proc checkDirty(self: RenderView) =
    ## checkDirty is called for every visible view every frame
    if self.interval == 0 and (self.active or self.renderWhenInactive):
      self.markDirty()

  proc rvSetRenderWhenInactive(self: DynamicView, enabled: bool) =
    let self = self.RenderView
    self.renderWhenInactive = enabled
    if not self.active and enabled:
      self.setRenderInterval(self.interval)

  proc rvSetRenderInterval(self: DynamicView, ms: int) =
    let self = self.RenderView
    self.interval = ms
    if ms <= 0:
      if self.renderTask != nil:
        self.renderTask.pause()
      return

    if self.active or self.renderWhenInactive:
      if self.renderTask == nil:
        self.renderTask = startDelayed(ms, repeat = true):
          if self.active or self.renderWhenInactive:
            self.markDirty()
          else:
            self.renderTask.pause()
      else:
        self.renderTask.interval = ms
        self.renderTask.reschedule()

  proc getEventHandler(self: RenderView, context: string): EventHandler =
    if context notin self.eventHandlers:
      var eventHandler: EventHandler
      assignEventHandler(eventHandler, self.events.getEventHandlerConfig(context)):
        onAction:
            if self.handleAction(action, arg).isSome:
              Handled
            else:
              Ignored

        onInput:
          self.handleInput(input)
          Handled

      self.eventHandlers[context] = eventHandler
      return eventHandler

    return self.eventHandlers[context]

  proc getEventHandlers*(self: RenderView, inject: Table[string, EventHandler]): seq[EventHandler] =
    for mode in self.modes:
      result.add self.getEventHandler(mode)

  proc render(self: RenderView, builder: UINodeBuilder): seq[OverlayFunction] =
    builder.panel(&{FillX, FillY, FillBackground, MaskContent}, backgroundColor = color(0, 0, 0)):
      onClickAny btn:
        self.layout.tryActivateView(self)
        self.mouseStates.incl(btn.int64)

      self.bounds = currentNode.boundsAbsolute
      if self.preventThrottling:
        self.platform.lastEventTime = startTimer()

      if self.dirty and self.onRender != nil:
        try:
          self.onRender(self)
        except Exception:
          discard

      self.scrollDelta = vec2(0, 0)
      currentNode.renderCommands = self.commands
      currentNode.markDirty(builder)

    self.resetDirty()

  proc handleAction(self: RenderView, action: string, arg: string): Option[string] =
    return self.commandService.executeCommand(action & " " & arg)

  proc handleInput(self: RenderView, text: string) =
    discard

  proc newRenderView*(services: Services): DynamicView =
    let view = RenderView(services: services)
    view.platform = services.getServiceChecked(PlatformService).platform
    view.commandService = services.getServiceChecked(CommandService)
    view.events = services.getServiceChecked(EventHandlerService)
    view.layout = services.getServiceChecked(LayoutService)
    view.bindPlatformEvents()


    view.renderImpl = proc(self: View, builder: UINodeBuilder): seq[OverlayRenderFunc] =
      render(self.RenderView, builder)
    view.getEventHandlersImpl = proc(self: View, inject: Table[string, EventHandler]): seq[EventHandler] =
      getEventHandlers(self.RenderView, inject)
    view.descImpl = proc(self: View): string = desc(self.RenderView)
    view.kindImpl = proc(self: View): string = kind(self.RenderView)
    view.displayImpl = proc(self: View): string = display(self.RenderView)
    view.activateImpl = proc(self: View) = activate(self.RenderView)
    view.deactivateImpl = proc(self: View) = deactivate(self.RenderView)
    view.checkDirtyImpl = proc(self: View) = checkDirty(self.RenderView)
    return view
