import std/[strformat]
import misc/[custom_logger, util, delayed_task, timer]
import view, service
import ui/render_command
import platform/platform
import platform_service, layout

{.push gcsafe, raises: [].}

logCategory "custom-view"

type
  RenderView* = ref object of View
    services: Services
    layout*: LayoutService
    platform: Platform

    commands*: RenderCommands
    userId*: string

    size*: Vec2
    interval: int = -1
    onRender*: proc(view: RenderView) {.gcsafe, raises: [].}
    renderTask: DelayedTask
    renderWhenInactive*: bool = false
    preventThrottling*: bool = false

proc newRenderView*(services: Services): RenderView =
  result = RenderView(services: services)
  result.platform = services.getService(PlatformService).get.platform
  result.layout = services.getService(LayoutService).get

proc setRenderInterval*(self: RenderView, ms: int)

method desc*(self: RenderView): string =
  &"RenderView({self.id2}, interval = {self.interval}, renderWhenInactive = {self.renderWhenInactive}, preventThrottling = {self.preventThrottling})"

method kind*(self: RenderView): string = "render"

method display*(self: RenderView): string = self.desc()

proc renderViewFromUserId*(layout: LayoutService, id: string): Option[RenderView] =
  for v in layout.allViews:
    if v of RenderView and v.RenderView.userId == id:
      return v.RenderView.some
  return RenderView.none

proc render*(self: RenderView) =
  if self.preventThrottling:
    self.platform.lastEventTime = startTimer()

  if self.dirty and self.onRender != nil:
    try:
      self.onRender(self)
    except Exception:
      discard

method activate*(self: RenderView) =
  self.active = true
  self.setRenderInterval(self.interval)

method deactivate*(self: RenderView) =
  self.active = false
  if not self.renderWhenInactive and self.renderTask != nil:
    self.renderTask.pause()

proc setRenderCommands*(self: RenderView, commands: RenderCommands) =
  self.commands = commands
  self.markDirty()

method checkDirty*(self: RenderView) =
  ## checkDirty is called for every visible view every frame
  if self.interval == 0 and (self.active or self.renderWhenInactive):
    self.markDirty()

proc setRenderWhenInactive*(self: RenderView, enabled: bool) =
  self.renderWhenInactive = enabled
  if not self.active and enabled:
    self.setRenderInterval(self.interval)

proc setRenderInterval*(self: RenderView, ms: int) =
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
