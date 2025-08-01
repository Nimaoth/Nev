import std/[strformat]
import misc/[custom_logger, util, delayed_task]
import view
import ui/render_command

{.push gcsafe, raises: [].}

type
  RenderView* = ref object of View
    commands*: RenderCommands
    size*: Vec2
    interval: int = -1
    render*: proc(view: RenderView) {.gcsafe, raises: [].}
    renderTask: DelayedTask

proc setRenderInterval*(self: RenderView, ms: int)

method desc*(self: RenderView): string =
  &"RenderView(interval = {self.interval})"

method kind*(self: RenderView): string = "render"

method display*(self: RenderView): string = self.desc()

method activate*(view: RenderView) =
  view.active = true
  view.setRenderInterval(view.interval)

method deactivate*(view: RenderView) =
  view.active = false
  if view.renderTask != nil:
    view.renderTask.pause()

proc setRenderCommands*(self: RenderView, commands: RenderCommands) =
  self.commands = commands
  self.markDirty()

method checkDirty*(self: RenderView) =
  if self.interval == 0:
    self.markDirty()

proc setRenderInterval*(self: RenderView, ms: int) =
  self.interval = ms
  if ms <= 0:
    if self.renderTask != nil:
      self.renderTask.pause()
    return

  if self.renderTask == nil:
    self.renderTask = startDelayed(ms, repeat = true):
      self.markDirty()
  else:
    self.renderTask.interval = ms
    self.renderTask.reschedule()
