#use input_handler layout
import std/[strformat, tables, sets, unicode]
import bumpy, chroma, vmath
import misc/[custom_logger, util, delayed_task, timer, render_command]
import view, service
from nuigi import UiBuilder, UiImageId, UiNodeText, UiRenderCommand,
  UiRenderCommandKind, absoluteNodePos, backgroundColor, customRenderCommands,
  currentNodeIndex, fillX, fillY, maskChildren, node, rgba, uiString, wasClicked
import nuigi/core/[arena, array_view]
import nuigi/core/vecmath as nuiMath

type Vec2 = vmath.Vec2

const currentSourcePath2 = currentSourcePath()
include module_base

type
  RenderView* = ref object of View
    userId*: string
    onRender*: proc(view: RenderView) {.gcsafe, raises: [].}
    bounds*: Rect

    keyStates*: HashSet[int64]
    mouseStates*: HashSet[int64]
    mousePos*: Vec2
    scrollDelta*: Vec2
    renderWhenInactive*: bool = false
    preventThrottling*: bool = false

    modes*: seq[string]

    commands*: RenderCommands

{.push modrtl, gcsafe, raises: [].}
proc newRenderView*(services: Services): RenderView
proc rvSetRenderWhenInactive(self: RenderView, enabled: bool)
proc rvSetRenderInterval(self: RenderView, ms: int)
{.pop.}

proc setRenderWhenInactive*(self: RenderView, enabled: bool) = rvSetRenderWhenInactive(self, enabled)
proc setRenderInterval*(self: RenderView, ms: int) = rvSetRenderInterval(self, ms)

when implModule:
  import platform
  import layout/layout, input_handler/input_handler, command_service

  type
    RenderViewImpl* = ref object of RenderView
      services: Services
      commandService: CommandService
      events: EventHandlerService
      layout*: LayoutService
      platform: Platform

      interval: int = -1
      renderTask: DelayedTask

      eventHandlers: Table[string, EventHandler]

  {.push gcsafe, raises: [].}

  logCategory "custom-view"

  proc handleAction(self: RenderViewImpl, action: string, arg: string): Option[string]
  proc handleInput(self: RenderViewImpl, text: string)

  proc handleKeyPress*(self: RenderViewImpl, input: int64, modifiers: Modifiers) =
    self.keyStates.incl(input)

  proc handleKeyRelease*(self: RenderViewImpl, input: int64, modifiers: Modifiers) =
    self.keyStates.excl(input)

  proc handleRune*(self: RenderViewImpl, input: int64, modifiers: Modifiers) =
    self.keyStates.incl(input)

  proc handleMousePress(self: RenderViewImpl, button: MouseButton, modifiers: Modifiers, pos: Vec2) =
    self.mouseStates.incl(button.int64)

  proc handleMouseRelease(self: RenderViewImpl, button: MouseButton, modifiers: Modifiers, pos: Vec2) =
    self.mouseStates.excl(button.int64)

  proc handleMouseMove(self: RenderViewImpl, pos: Vec2, delta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
    self.mousePos = pos - self.bounds.xy

  proc handleScroll(self: RenderViewImpl, pos: Vec2, scroll: Vec2, modifiers: Modifiers) =
    self.scrollDelta = scroll

  proc bindPlatformEvents(self: RenderViewImpl) =
    discard self.platform.onKeyPress.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleKeyPress(event.input, event.modifiers)
    discard self.platform.onKeyRelease.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleKeyRelease(event.input, event.modifiers)
    discard self.platform.onRune.subscribe proc(event: auto): void {.gcsafe, raises: [].} = self.handleRune(event.input, event.modifiers)
    discard self.platform.onMousePress.subscribe proc(event: tuple[button: MouseButton, modifiers: Modifiers, pos: Vec2]): void {.gcsafe, raises: [].} = self.handleMousePress(event.button, event.modifiers, event.pos)
    discard self.platform.onMouseRelease.subscribe proc(event: tuple[button: MouseButton, modifiers: Modifiers, pos: Vec2]): void {.gcsafe, raises: [].} = self.handleMouseRelease(event.button, event.modifiers, event.pos)
    discard self.platform.onMouseMove.subscribe proc(event: tuple[pos: Vec2, delta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]]): void {.gcsafe, raises: [].} = self.handleMouseMove(event.pos, event.delta, event.modifiers, event.buttons)
    discard self.platform.onScroll.subscribe proc(event: tuple[pos: Vec2, scroll: Vec2, modifiers: Modifiers]): void {.gcsafe, raises: [].} = self.handleScroll(event.pos, event.scroll, event.modifiers)

  proc desc*(self: RenderViewImpl): string =
    &"RenderViewImpl({self.id2}, interval = {self.interval}, renderWhenInactive = {self.renderWhenInactive}, preventThrottling = {self.preventThrottling})"

  proc kind*(self: RenderViewImpl): string = "custom"

  proc display*(self: RenderViewImpl): string = self.desc()

  proc activate(self: RenderViewImpl) =
    self.active = true
    self.setRenderInterval(self.interval)

  proc deactivate(self: RenderViewImpl) =
    self.active = false
    if not self.renderWhenInactive and self.renderTask != nil:
      self.renderTask.pause()

  proc setRenderCommands*(self: RenderViewImpl, commands: RenderCommands) =
    self.commands = commands
    self.markDirty()

  proc checkDirty(self: RenderViewImpl) =
    ## checkDirty is called for every visible view every frame
    if self.interval == 0 and (self.active or self.renderWhenInactive):
      self.markDirty()

  proc rvSetRenderWhenInactive(self: RenderView, enabled: bool) =
    let self = self.RenderViewImpl
    self.renderWhenInactive = enabled
    if not self.active and enabled:
      self.setRenderInterval(self.interval)

  proc rvSetRenderInterval(self: RenderView, ms: int) =
    let self = self.RenderViewImpl
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

  proc getEventHandler(self: RenderViewImpl, context: string): EventHandler =
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

  proc getEventHandlers*(self: RenderViewImpl, inject: Table[string, EventHandler]): seq[EventHandler] =
    for mode in self.modes:
      result.add self.getEventHandler(mode)

  proc toUiColor(color: Color): auto {.inline.} =
    rgba(color.r, color.g, color.b, color.a)

  proc appendRenderCommand(
      command: RenderCommand,
      commands: ptr RenderCommands,
      nui: var UiBuilder,
      output: var ArrayView[UiRenderCommand],
      offsets: var seq[nuiMath.Vec2],
      currentOffset: var nuiMath.Vec2
  ) =
    case command.kind
    of RenderCommandKind.Rect:
      output.add UiRenderCommand(
        kind: CmdRectStroke,
        pos: nuiMath.vec2(command.bounds.x.float32, command.bounds.y.float32) + currentOffset,
        size: nuiMath.vec2(command.bounds.w.float32, command.bounds.h.float32),
        color: toUiColor(command.color),
        thickness: 1)
    of RenderCommandKind.FilledRect:
      output.add UiRenderCommand(
        kind: CmdRectFill,
        pos: nuiMath.vec2(command.bounds.x.float32, command.bounds.y.float32) + currentOffset,
        size: nuiMath.vec2(command.bounds.w.float32, command.bounds.h.float32),
        color: toUiColor(command.color))
    of RenderCommandKind.TextRaw:
      if command.len > 0 and command.data != nil:
        var text = newString(command.len)
        copyMem(text[0].addr, command.data, command.len)
        let textIndex = block:
          let index = nui.frame.texts.len
          nui.frame.texts.add UiNodeText(
            text: text.uiString,
            fontSize: 16,
            textColor: toUiColor(command.color))
          (index + 1).uint16
        output.add UiRenderCommand(
          kind: CmdText,
          pos: nuiMath.vec2(command.bounds.x.float32, command.bounds.y.float32) + currentOffset,
          color: toUiColor(command.color),
          textIndex: textIndex)
    of RenderCommandKind.Text:
      if command.arrangementIndex == uint32.high:
        if command.textLen > 0 and commands != nil:
          let text = commands.strings[
            command.textOffset.int ..< command.textOffset.int + command.textLen.int]
          let textIndex = block:
            let index = nui.frame.texts.len
            nui.frame.texts.add UiNodeText(
              text: text.uiString,
              fontSize: 16 * max(0.1'f32, command.fontScale.float32),
              textColor: toUiColor(command.color))
            (index + 1).uint16
          output.add UiRenderCommand(
            kind: CmdText,
            pos: nuiMath.vec2(command.bounds.x.float32, command.bounds.y.float32) + currentOffset,
            color: toUiColor(command.color),
            textIndex: textIndex)
      elif commands != nil and
          command.arrangementIndex.int < commands.arrangements.len:
        let indices = commands.arrangements[command.arrangementIndex]
        let arrangement = commands.arrangement
        let position = nuiMath.vec2(
          command.bounds.x.float32, command.bounds.y.float32) + currentOffset
        let color = toUiColor(command.color)
        var text = newStringOfCap(
          max(0, indices.runes.b - indices.runes.a + 1) * 4 + 4)
        for index in indices.runes:
          if index < 0 or index >= arrangement.runes.len:
            continue
          var rune = arrangement.runes[index]
          if rune == ' '.Rune and TextDrawSpaces in command.flags:
            rune = commands.space
          if rune.int32 < 32 and rune != ' '.Rune and rune != commands.space:
            continue
          text.add($rune)
        if text.len > 0:
          let textIndex = block:
            let index = nui.frame.texts.len
            nui.frame.texts.add UiNodeText(
              text: text.uiString,
              fontSize: 16 * max(0.1'f32, command.fontScale.float32),
              textColor: color)
            (index + 1).uint16
          output.add UiRenderCommand(
            kind: CmdText,
            pos: position,
            color: color,
            textIndex: textIndex)
        if TextUndercurl in command.flags:
          output.add UiRenderCommand(
            kind: CmdRectFill,
            pos: position + nuiMath.vec2(0, command.bounds.h.float32 - 2),
            size: nuiMath.vec2(command.bounds.w.float32, 2),
            color: toUiColor(command.underlineColor))
    of RenderCommandKind.Image:
      output.add UiRenderCommand(
        kind: CmdImage,
        pos: nuiMath.vec2(command.bounds.x.float32, command.bounds.y.float32) + currentOffset,
        size: nuiMath.vec2(command.bounds.w.float32, command.bounds.h.float32),
        color: toUiColor(command.color),
        imageId: UiImageId(cast[uint64](command.textureId)),
        uv0: nuiMath.vec2(command.uv0.x, command.uv0.y),
        uv1: nuiMath.vec2(command.uv1.x, command.uv1.y))
    of RenderCommandKind.ScissorStart:
      output.add UiRenderCommand(
        kind: CmdClipPush,
        pos: nuiMath.vec2(command.bounds.x.float32, command.bounds.y.float32) + currentOffset,
        size: nuiMath.vec2(command.bounds.w.float32, command.bounds.h.float32))
    of RenderCommandKind.ScissorEnd:
      output.add UiRenderCommand(kind: CmdClipPop)
    of RenderCommandKind.TransformStart:
      offsets.add currentOffset
      let offset = nuiMath.vec2(command.bounds.x.float32, command.bounds.y.float32)
      currentOffset += offset
      output.add UiRenderCommand(kind: CmdTransformPush, offset: offset)
    of RenderCommandKind.TransformEnd:
      if offsets.len > 0:
        currentOffset = offsets.pop()
      output.add UiRenderCommand(kind: CmdTransformPop)

  proc renderNui(self: RenderViewImpl, nui: var UiBuilder) =
    {.cast(gcsafe).}:
      nui.node("render-view"):
        discard nui.fillX().fillY().backgroundColor(rgba(0, 0, 0, 1))
          .maskChildren()

        if nui.wasClicked(includeChildren = true):
          self.layout.tryActivateView(self)

        let position = nui.absoluteNodePos(nui.currentNodeIndex)
        self.bounds = rect(
          position.x, position.y, nui.currentNode.size.x, nui.currentNode.size.y)
        if self.preventThrottling:
          self.platform.lastEventTime = startTimer()

        if self.dirty and self.onRender != nil:
          try:
            self.onRender(self)
          except Exception:
            discard

        self.scrollDelta = vmath.vec2(0, 0)
        try:
          var commandCount = self.commands.commands.len
          for _ in self.commands.decodeRenderCommands:
            inc commandCount
          var output = nui.frame.arena[].allocEmptyArray(
            max(1, commandCount * 2 + 1), UiRenderCommand)
          var offsets: seq[nuiMath.Vec2]
          var currentOffset = nuiMath.vec2(0, 0)
          for command in self.commands.commands:
            appendRenderCommand(command, self.commands.addr, nui, output,
              offsets, currentOffset)
          for command in self.commands.decodeRenderCommands:
            appendRenderCommand(command, self.commands.addr, nui, output,
              offsets, currentOffset)
          if output.len > 0:
            discard nui.customRenderCommands(output)
        except Exception:
          discard

      self.resetDirty()

  proc handleAction(self: RenderViewImpl, action: string, arg: string): Option[string] =
    return self.commandService.executeCommand(action & " " & arg)

  proc handleInput(self: RenderViewImpl, text: string) =
    discard

  proc newRenderView*(services: Services): RenderView =
    let view = RenderViewImpl(services: services)
    view.platform = services.getServiceChecked(PlatformService).platform
    view.commandService = services.getServiceChecked(CommandService)
    view.events = services.getServiceChecked(EventHandlerService)
    view.layout = services.getServiceChecked(LayoutService)
    view.bindPlatformEvents()

    view.renderNuiImpl = proc(self: View, nui: var UiBuilder) =
      renderNui(self.RenderViewImpl, nui)
    view.getEventHandlersImpl = proc(self: View, inject: Table[string, EventHandler]): seq[EventHandler] =
      getEventHandlers(self.RenderViewImpl, inject)
    view.descImpl = proc(self: View): string = desc(self.RenderViewImpl)
    view.kindImpl = proc(self: View): string = kind(self.RenderViewImpl)
    view.displayImpl = proc(self: View): string = display(self.RenderViewImpl)
    view.activateImpl = proc(self: View) = activate(self.RenderViewImpl)
    view.deactivateImpl = proc(self: View) = deactivate(self.RenderViewImpl)
    view.checkDirtyImpl = proc(self: View) = checkDirty(self.RenderViewImpl)
    return view
