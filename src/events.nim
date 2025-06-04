import std/[tables, sequtils, strutils, sugar, unicode]
import misc/[custom_logger, util, custom_async]
import scripting/expose
import input, service, dispatch_tables

logCategory "events"

var debugEventHandlers = false

type
  EventResponse* = enum
    Failed,
    Ignored,
    Canceled,
    Handled,
    Progress,

  CommandSource* = tuple[filename: string, line: int, column: int]

  Command* = object
    command*: string
    source*: CommandSource

  EventHandlerConfig* = ref object
    parent*: EventHandlerConfig
    context*: string
    commands: Table[string, Table[string, Command]]
    handleActions*: bool
    handleInputs*: bool
    handleKeys*: bool
    consumeAllActions*: bool
    consumeAllInput*: bool
    revision: int
    leaders: seq[string]
    descriptions*: Table[string, string]
    stateToDescription*: Table[int, string]

  EventHandler* = ref object
    states: seq[CommandState]
    config: EventHandlerConfig
    revision: int
    dfaInternal: CommandDFA
    handleAction*: proc(action: string, arg: string): EventResponse {.gcsafe, raises: [].}
    handleInput*: proc(input: string): EventResponse {.gcsafe, raises: [].}
    handleProgress*: proc(input: int64) {.gcsafe, raises: [].}
    handleCanceled*: proc(input: int64) {.gcsafe, raises: [].}
    handleKey*: proc(input: int64, mods: Modifiers): EventResponse {.gcsafe, raises: [].}

  CommandKeyInfo* = object
    keys*: string
    command*: string
    context*: string
    source*: CommandSource

  CommandInfos* = ref object
    built: bool = false
    commandToKeys*: Table[string, seq[CommandKeyInfo]]

  EventHandlerService* = ref object of Service
    eventHandlerConfigs*: Table[string, EventHandlerConfig]
    leaders*: seq[string]
    commandInfos*: CommandInfos
    commandDescriptions*: Table[string, string]

func serviceName*(_: typedesc[EventHandlerService]): string = "EventHandlerService"
addBuiltinService(EventHandlerService)

method init*(self: EventHandlerService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  self.commandInfos = CommandInfos()
  return ok()

func newEventHandlerConfig*(context: string, parent: EventHandlerConfig = nil): EventHandlerConfig =
  new result
  result.parent = parent
  result.handleActions = true
  result.handleInputs = false
  result.handleKeys = false
  result.context = context

proc combineCommands(config: EventHandlerConfig, commands: var Table[string, Table[string, string]]) =
  if config.parent.isNotNil:
    config.parent.combineCommands(commands)

  for (subGraphName, bindings) in config.commands.mpairs:
    if subGraphName == "":
      var temp = initTable[string, string]()
      for (keys, commandInfo) in bindings.mpairs:
        temp[keys] = commandInfo.command
      commands[subGraphName] = temp
    else:
      if not commands.contains(subGraphName):
        commands[subGraphName] = initTable[string, string]()

      commands.withValue(subGraphName, val):
        for (keys, commandInfo) in bindings.mpairs:
          val[][keys] = commandInfo.command

proc buildDFA*(config: EventHandlerConfig): CommandDFA {.gcsafe, raises: [].} =
  var commands = initTable[string, Table[string, string]]()
  config.combineCommands(commands)
  result = buildDFA(commands, config.leaders)

  let leaders = collect(newSeq):
    for leader in config.leaders:
      let (keys, _, _, _, _) = parseNextInput(leader.toRunes, 0)
      for key in keys:
        (key.inputCodes.a, key.mods)

  config.stateToDescription.clear()
  for leader in leaders:
    for (keys, desc) in config.descriptions.pairs:
      var states: seq[CommandState]
      for (inputCode, mods, _) in parseInputs(keys, [leader]):
        states = result.stepAll(states, inputCode.a, mods)

      for s in states:
        config.stateToDescription[s.current] = desc

proc maxRevision*(config: EventHandlerConfig): int =
  result = config.revision
  if config.parent.isNotNil:
    result = max(result, config.parent.maxRevision)

proc dfa*(handler: EventHandler): CommandDFA =
  let configRevision = handler.config.maxRevision
  if handler.revision < configRevision:
    handler.dfaInternal = handler.config.buildDFA()
    # fs.saveApplicationFile(handler.config.context & ".dot", handler.dfaInternal.dumpGraphViz)
    handler.revision = configRevision
  return handler.dfaInternal

proc setHandleInputs*(config: EventHandlerConfig, value: bool) =
  config.handleInputs = value
  config.revision += 1

proc setHandleKeys*(config: EventHandlerConfig, value: bool) =
  config.handleKeys = value
  config.revision += 1

proc setHandleActions*(config: EventHandlerConfig, value: bool) =
  config.handleActions = value
  config.revision += 1

proc setConsumeAllActions*(config: EventHandlerConfig, value: bool) =
  config.consumeAllActions = value
  config.revision += 1

proc setConsumeAllInput*(config: EventHandlerConfig, value: bool) =
  config.consumeAllInput = value
  config.revision += 1

proc addCommand*(config: EventHandlerConfig, context: string, keys: string, action: string, source: CommandSource = CommandSource.default) =
  if not config.commands.contains(context):
    config.commands[context] = initTable[string, Command]()
  config.commands[context][keys] = Command(command: action, source: source)
  config.revision += 1

proc addCommandDescription*(config: EventHandlerConfig, keys: string, description: string) =
  config.descriptions[keys] = description
  config.revision += 1

proc removeCommand*(config: EventHandlerConfig, keys: string) =
  config.commands.del(keys)
  config.revision += 1

proc clearCommands*(config: EventHandlerConfig) =
  config.commands.clear
  config.revision += 1

proc addLeader*(config: EventHandlerConfig, leader: string) =
  config.leaders.add leader
  config.revision += 1

proc setLeader*(config: EventHandlerConfig, leader: string) =
  config.leaders = @[leader]
  config.revision += 1

proc setLeaders*(config: EventHandlerConfig, leaders: openArray[string]) =
  config.leaders = @leaders
  config.revision += 1

proc getNextPossibleInputs*(handler: EventHandler): auto =
  handler.dfa.getNextPossibleInputs(handler.states)

template eventHandler*(inConfig: EventHandlerConfig, handlerBody: untyped): untyped =
  block:
    var handler = EventHandler()
    handler.states = @[]
    handler.config = inConfig
    handler.dfaInternal = inConfig.buildDFA()
    # fs.saveApplicationFile(handler.config.context & ".dot", handler.dfaInternal.dumpGraphViz)

    template onAction(actionBody: untyped): untyped {.used.} =
      handler.handleAction = proc(action: string, arg: string): EventResponse {.gcsafe, raises: [].} =
        if handler.config.handleActions:
          let action {.inject, used.} = action
          let arg {.inject, used.} = arg
          let response = actionBody
          if handler.config.consumeAllActions:
            return Handled
          return response
        elif handler.config.consumeAllActions:
          return Handled
        else:
          return Ignored

    template onInput(inputBody: untyped): untyped {.used.} =
      handler.handleInput = proc(input: string): EventResponse {.gcsafe, raises: [].} =
        if handler.config.handleInputs:
          let input {.inject, used.} = input
          return inputBody
        else:
          return Ignored

    template onProgress(progressBody: untyped): untyped {.used.} =
      handler.handleProgress = proc(i: int64) {.gcsafe, raises: [].} =
        let input {.inject, used.} = i
        progressBody

    template onCanceled(canceledBody: untyped): untyped {.used.} =
      handler.handleCanceled = proc(i: int64) {.gcsafe, raises: [].} =
        let input {.inject, used.} = i
        canceledBody

    template onKey(onKeyBody: untyped): untyped {.used.} =
      handler.handleKey = proc(i: int64, m: Modifiers): EventResponse {.gcsafe, raises: [].} =
        if handler.config.handleKeys:
          let input {.inject, used.} = i
          let mods {.inject, used.} = m
          return onKeyBody
        else:
          return Ignored

    handlerBody
    handler

template assignEventHandler*(target: untyped, inConfig: EventHandlerConfig, handlerBody: untyped): untyped =
  block:
    var handler = EventHandler()
    handler.states = @[]
    handler.config = inConfig
    handler.dfaInternal = inConfig.buildDFA()
    # fs.saveApplicationFile(handler.config.context & ".dot", handler.dfaInternal.dumpGraphViz)

    template onAction(actionBody: untyped): untyped {.used.} =
      handler.handleAction = proc(action: string, arg: string): EventResponse {.gcsafe, raises: [].} =
        if handler.config.handleActions:
          let action {.inject, used.} = action
          let arg {.inject, used.} = arg
          let response = actionBody
          if handler.config.consumeAllActions:
            return Handled
          return response
        elif handler.config.consumeAllActions:
          return Handled
        else:
          return Ignored

    template onInput(inputBody: untyped): untyped {.used.} =
      handler.handleInput = proc(input: string): EventResponse {.gcsafe, raises: [].} =
        if handler.config.handleInputs:
          let input {.inject, used.} = input
          return inputBody
        else:
          return Ignored

    template onProgress(progressBody: untyped): untyped {.used.} =
      handler.handleProgress = proc(i: int64) {.gcsafe, raises: [].} =
        let input {.inject, used.} = i
        progressBody

    template onCanceled(canceledBody: untyped): untyped {.used.} =
      handler.handleCanceled = proc(i: int64) {.gcsafe, raises: [].} =
        let input {.inject, used.} = i
        canceledBody

    template onKey(onKeyBody: untyped): untyped {.used.} =
      handler.handleKey = proc(i: int64, m: Modifiers): EventResponse {.gcsafe, raises: [].} =
        if handler.config.handleKeys:
          let input {.inject, used.} = i
          let mods {.inject, used.} = m
          return onKeyBody
        else:
          return Ignored

    handlerBody
    target = handler

proc resetHandler*(handler: EventHandler) =
  handler.states = @[]

proc resetHandlers*(handlers: seq[EventHandler]) =
  for handler in handlers:
    handler.resetHandler()

proc inProgress*(states: openArray[CommandState]): bool =
  for s in states:
    if s.current != 0:
      return true
  return false

proc inProgress*(handler: EventHandler): bool = handler.states.inProgress
proc states*(handler: EventHandler): auto = handler.states

proc anyInProgress*(handlers: openArray[EventHandler]): bool =
  for h in handlers:
    if h.states.inProgress:
      return true
  return false

proc handleEvent*(handler: var EventHandler, input: int64, modifiers: Modifiers, handleUnknownAsInput: bool, allowHandlingEvent: bool, delayedInputs: var seq[tuple[handle: EventHandler, input: int64, modifiers: Modifiers]]): EventResponse {.gcsafe.} =
  if input != 0:
    # debug &"{handler.config.context}: handleEvent {(inputToString(input, modifiers))}, handleInput: {handleUnknownAsInput}"

    # only handle if no modifier or only shift is pressed, because if any other modifiers are pressed
    # (ctrl, alt, win) then it doesn't produce input
    let prevStates = handler.states
    handler.states = handler.dfa.stepAll(handler.states, input, modifiers)

    if debugEventHandlers:
      debug &"{handler.config.context}: handleEvent {(inputToString(input, modifiers))}, {handleUnknownAsInput}, {allowHandlingEvent}\n  {prevStates}\n  -> {handler.states}, inProgress: {handler.inProgress}, anyTerminal: {handler.states.anyIt(handler.dfa.isTerminal(it.current))}"
      # debugf"handleEvent {handler.config.context} {(inputToString(input, modifiers))}"

    if not handler.inProgress:
      if input > 0 and modifiers + {Shift} == {Shift} and handler.handleInput != nil and allowHandlingEvent:
        # if we have delayed inputs we're allowed to handle the current event as input
        if delayedInputs.len > 0:
          if debugEventHandlers:
            debugf"flush delayed inputs"
          for (handler, input, modifiers) in delayedInputs:
            discard handler.handleInput(inputToString(input, {}))
          delayedInputs.setLen(0)

          if handler.handleInput(inputToString(input, {})) == Handled:
            return Handled

        elif handleUnknownAsInput:
          if handler.handleInput(inputToString(input, {})) == Handled:
            return Handled

      elif handler.handleKey != nil:
        if handler.handleKey(input, modifiers) == Handled:
          return Handled

      handler.resetHandler()
      if not prevStates.inProgress:
        return Ignored
      else:
        # undefined input in state n
        if not handler.handleCanceled.isNil:
          handler.handleCanceled(input)
        return Canceled

    elif handler.states.anyIt(handler.dfa.isTerminal(it.current)):
      if handler.states.len != 1:
        return Failed

      let (action, arg) = handler.dfa.getAction(handler.states[0])
      let currentState = handler.states[0].current
      let nextState = handler.dfa.getDefaultState(currentState)

      if nextState != 0:
        handler.states = @[CommandState(
          current: nextState,
          functionIndices: handler.dfa.getFunctionIndices(nextState),
          captures: handler.states[0].captures, # todo
        )]
      else:
        handler.resetHandler()

      if allowHandlingEvent:
        let res = handler.handleAction(action, arg)
        case res
        of Failed: return Failed
        of Ignored: return Ignored
        of Canceled: return Canceled
        of Progress: return Progress
        of Handled:
          if handler.inProgress:
            return Progress
          else:
            return Handled
      else:
        handler.resetHandler()
        return Canceled

    else:
      if handleUnknownAsInput and input > 0 and modifiers + {Shift} == {Shift} and handler.handleInput != nil and handler.config.handleInputs:
        if debugEventHandlers:
          debugf"delay input {inputToString(input, modifiers)}"
        delayedInputs.add (handler, input, modifiers)

      if not handler.handleProgress.isNil:
        handler.handleProgress(input)
      return Progress

  else:
    return Failed

proc handleEvent*(handlers: seq[EventHandler], input: int64, modifiers: Modifiers, delayedInputs: var seq[tuple[handle: EventHandler, input: int64, modifiers: Modifiers]]): EventResponse {.gcsafe.} =
  let anyInProgress = handlers.anyInProgress

  if debugEventHandlers:
    debugf"handleEvent {inputToString(input, modifiers)}: {handlers.mapIt(it.config.context)}"

  var anyProgressed = false
  var anyFailed = false
  var allowHandlingUnknownAsInput = not anyInProgress
  var anyInProgressAbove = false
  # Go through handlers in reverse
  for i in 0..<handlers.len:
    let handlerIndex = handlers.len - i - 1
    var handler = handlers[handlerIndex]
    let response = if (anyInProgress and handler.inProgress) or (not anyInProgress and not handler.inProgress):
      handler.handleEvent(input, modifiers, allowHandlingUnknownAsInput, not anyInProgressAbove, delayedInputs)
    else:
      Ignored

    if debugEventHandlers:
      debugf"-> {response}"

    case response
    of Handled:
      allowHandlingUnknownAsInput = false
      for k, h in handlers:
        # Don't reset the current handler
        if k != handlerIndex:
          var h = h
          h.resetHandler()

      return Handled
    of Progress:
      allowHandlingUnknownAsInput = false
      anyProgressed = true
      anyInProgressAbove = true

    of Failed, Canceled:
      # Process remaining handlers
      anyFailed = true
      discard

    of Ignored:
      # Process remaining handlers
      discard

    if handler.config.consumeAllInput:
      # Don't process remaining handlers
      break

  if anyProgressed:
    result = Progress
  elif anyFailed:
    result = Failed
  else:
    result = Ignored

proc commands*(config {.byref.}: EventHandlerConfig): lent Table[string, Table[string, Command]] =
  config.commands

proc config*(handler: EventHandler): EventHandlerConfig = handler.config

proc invalidate*(self: CommandInfos) =
  self.built = false
  self.commandToKeys.clear()

proc rebuild*(self: CommandInfos, eventHandlerConfigs {.byref.}: Table[string, EventHandlerConfig]) =
  if self.built:
    return

  self.built = true
  self.commandToKeys.clear()
  for (context, c) in eventHandlerConfigs.pairs:
    if not c.commands.contains(""):
      continue
    for (keys, commandInfo) in c.commands[""].pairs:
      let (action, _) = commandInfo.command.parseAction
      self.commandToKeys.mgetOrPut(action, @[]).add(CommandKeyInfo(
        keys: keys,
        command: commandInfo.command,
        context: context,
        source: commandInfo.source,
      ))

proc getInfos*(self: CommandInfos, command: string): Option[seq[CommandKeyInfo]] =
  if self.commandToKeys.contains(command):
    return self.commandToKeys[command].some

proc wasBuilt*(self: CommandInfos): bool = self.built

proc getEventHandlerConfig*(self: EventHandlerService, context: string): EventHandlerConfig =
  if not self.eventHandlerConfigs.contains(context):
    let parentConfig = if context != "":
      let index = context.rfind(".")
      if index >= 0:
        self.getEventHandlerConfig(context[0..<index])
      else:
        self.getEventHandlerConfig("")
    else:
      nil

    self.eventHandlerConfigs[context] = newEventHandlerConfig(context, parentConfig)
    self.eventHandlerConfigs[context].setLeaders(self.leaders)

  return self.eventHandlerConfigs[context].catch(EventHandlerConfig())

proc invalidateCommandToKeysMap*(self: EventHandlerService) =
  self.commandInfos.invalidate()

proc rebuildCommandToKeysMap*(self: EventHandlerService) =
  self.commandInfos.rebuild(self.eventHandlerConfigs)

###########################################################################

proc getEventHandlerService(): Option[EventHandlerService] =
  {.gcsafe.}:
    if gServices.isNil: return EventHandlerService.none
    return gServices.getService(EventHandlerService)

static:
  addInjector(EventHandlerService, getEventHandlerService)

proc setLeader*(self: EventHandlerService, leader: string) {.expose("events").} =
  self.leaders = @[leader]
  for config in self.eventHandlerConfigs.values:
    config.setLeaders self.leaders

proc setLeaders*(self: EventHandlerService, leaders: seq[string]) {.expose("events").} =
  self.leaders = leaders
  for config in self.eventHandlerConfigs.values:
    config.setLeaders self.leaders

proc addLeader*(self: EventHandlerService, leader: string) {.expose("events").} =
  self.leaders.add leader
  for config in self.eventHandlerConfigs.values:
    config.setLeaders self.leaders

proc clearCommands*(self: EventHandlerService, context: string) {.expose("events").} =
  log(lvlInfo, fmt"Clearing keybindings for {context}")
  self.getEventHandlerConfig(context).clearCommands()
  self.invalidateCommandToKeysMap()

proc removeCommand*(self: EventHandlerService, context: string, keys: string) {.expose("events").} =
  # log(lvlInfo, fmt"Removing command from '{context}': '{keys}'")
  self.getEventHandlerConfig(context).removeCommand(keys)
  self.invalidateCommandToKeysMap()

proc addCommandDescription*(self: EventHandlerService, context: string, keys: string, description: string = "") {.expose("events").} =
  let context = if context.endsWith("."):
    context[0..^2]
  else:
    context

  log lvlWarn, fmt"Adding command description to '{context}': '{keys}' -> '{description}'"

  self.getEventHandlerConfig(context).addCommandDescription(keys, description)

addGlobalDispatchTable "events", genDispatchTable("events")
