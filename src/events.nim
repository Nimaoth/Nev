import std/[tables, sequtils]
import misc/[custom_logger, util]
import platform/[filesystem]
import input

logCategory "events"

var debugEventHandlers = false

type EventResponse* = enum
  Failed,
  Ignored,
  Canceled,
  Handled,
  Progress,

type EventHandlerConfig* = ref object
  parent*: EventHandlerConfig
  context*: string
  commands: Table[string, Table[string, string]]
  handleActions*: bool
  handleInputs*: bool
  consumeAllActions*: bool
  consumeAllInput*: bool
  revision: int
  leaders: seq[string]

type EventHandler* = ref object
  states: seq[CommandState]
  config: EventHandlerConfig
  revision: int
  dfaInternal: CommandDFA
  handleAction*: proc(action: string, arg: string): EventResponse
  handleInput*: proc(input: string): EventResponse
  handleProgress*: proc(input: int64)
  handleCanceled*: proc(input: int64)

func newEventHandlerConfig*(context: string, parent: EventHandlerConfig = nil): EventHandlerConfig =
  new result
  result.parent = parent
  result.handleActions = true
  result.handleInputs = false
  result.context = context

proc combineCommands(config: EventHandlerConfig, commands: var Table[string, Table[string, string]]) =
  if config.parent.isNotNil:
    config.parent.combineCommands(commands)

  for (subGraphName, bindings) in config.commands.mpairs:
    if subGraphName == "":
      commands[subGraphName] = bindings
    else:
      if not commands.contains(subGraphName):
        commands[subGraphName] = initTable[string, string]()

      for (keys, command) in bindings.mpairs:
        commands[subGraphName][keys] = command

proc buildDFA*(config: EventHandlerConfig): CommandDFA =
  var commands = initTable[string, Table[string, string]]()
  config.combineCommands(commands)
  return buildDFA(commands, config.leaders)

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

proc setHandleActions*(config: EventHandlerConfig, value: bool) =
  config.handleActions = value
  config.revision += 1

proc setConsumeAllActions*(config: EventHandlerConfig, value: bool) =
  config.consumeAllActions = value
  config.revision += 1

proc setConsumeAllInput*(config: EventHandlerConfig, value: bool) =
  config.consumeAllInput = value
  config.revision += 1

proc addCommand*(config: EventHandlerConfig, context: string, keys: string, action: string) =
  if not config.commands.contains(context):
    config.commands[context] = initTable[string, string]()
  config.commands[context][keys] = action
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

template eventHandler*(inConfig: EventHandlerConfig, handlerBody: untyped): untyped =
  block:
    var handler = EventHandler()
    handler.states = @[]
    handler.config = inConfig
    handler.dfaInternal = inConfig.buildDFA()
    # fs.saveApplicationFile(handler.config.context & ".dot", handler.dfaInternal.dumpGraphViz)

    template onAction(actionBody: untyped): untyped {.used.} =
      handler.handleAction = proc(action: string, arg: string): EventResponse =
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
      handler.handleInput = proc(input: string): EventResponse =
        if handler.config.handleInputs:
          let input {.inject, used.} = input
          return inputBody
        else:
          return Ignored

    template onProgress(progressBody: untyped): untyped {.used.} =
      handler.handleProgress = proc(i: int64) =
        let input {.inject, used.} = i
        progressBody

    template onCanceled(canceledBody: untyped): untyped {.used.} =
      handler.handleCanceled = proc(i: int64) =
        let input {.inject, used.} = i
        canceledBody

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
      handler.handleAction = proc(action: string, arg: string): EventResponse =
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
      handler.handleInput = proc(input: string): EventResponse =
        if handler.config.handleInputs:
          let input {.inject, used.} = input
          return inputBody
        else:
          return Ignored

    template onProgress(progressBody: untyped): untyped {.used.} =
      handler.handleProgress = proc(i: int64) =
        let input {.inject, used.} = i
        progressBody

    template onCanceled(canceledBody: untyped): untyped {.used.} =
      handler.handleCanceled = proc(i: int64) =
        let input {.inject, used.} = i
        canceledBody

    handlerBody
    target = handler

proc reset*(handler: var EventHandler) =
  handler.states = @[]

proc inProgress*(states: openArray[CommandState]): bool =
  for s in states:
    if s.current != 0:
      return true
  return false

proc inProgress*(handler: EventHandler): bool = handler.states.inProgress

proc anyInProgress*(handlers: openArray[EventHandler]): bool =
  for h in handlers:
    if h.states.inProgress:
      return true
  return false

proc handleEvent*(handler: var EventHandler, input: int64, modifiers: Modifiers, handleUnknownAsInput: bool): EventResponse =
  if input != 0:
    # debug &"{handler.config.context}: handleEvent {(inputToString(input, modifiers))}, handleInput: {handleUnknownAsInput}"

    # only handle if no modifier or only shift is pressed, because if any other modifiers are pressed
    # (ctrl, alt, win) then it doesn't produce input
    if handleUnknownAsInput and input > 0 and modifiers + {Shift} == {Shift} and handler.handleInput != nil:
      if handler.handleInput(inputToString(input, {})) == Handled:
        return Handled

    let prevStates = handler.states
    handler.states = handler.dfa.stepAll(handler.states, input, modifiers)

    if debugEventHandlers:
      debug &"{handler.config.context}: handleEvent {(inputToString(input, modifiers))}\n  {prevStates}\n  -> {handler.states}"
      # debugf"handleEvent {handler.config.context} {(inputToString(input, modifiers))}"

    if not handler.inProgress:
      handler.reset()
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
      handler.reset()
      # handler.state.current = handler.dfa.getDefaultState(handler.state.current) # todo
      return handler.handleAction(action, arg)

    else:
      if not handler.handleProgress.isNil:
        handler.handleProgress(input)
      return Progress

  else:
    return Failed

proc handleEvent*(handlers: seq[EventHandler], input: int64, modifiers: Modifiers): EventResponse =
  let anyInProgress = handlers.anyInProgress

  if debugEventHandlers:
    debugf"handleEvent {inputToString(input, modifiers)}: {handlers.mapIt(it.config.context)}"

  var anyProgressed = false
  var anyFailed = false
  var allowHandlingUnknownAsInput = not anyInProgress
  # Go through handlers in reverse
  for i in 0..<handlers.len:
    let handlerIndex = handlers.len - i - 1
    var handler = handlers[handlerIndex]
    let response = if (anyInProgress and handler.inProgress) or (not anyInProgress and not handler.inProgress):
      handler.handleEvent(input, modifiers, allowHandlingUnknownAsInput)
    else:
      Ignored

    case response
    of Handled:
      allowHandlingUnknownAsInput = false
      for k, h in handlers:
        # Don't reset the current handler
        if k != handlerIndex:
          var h = h
          h.reset()

      return Handled
    of Progress:
      allowHandlingUnknownAsInput = false
      anyProgressed = true

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

proc commands*(config {.byref.}: EventHandlerConfig): lent Table[string, Table[string, string]] =
  config.commands

proc config*(handler: EventHandler): EventHandlerConfig = handler.config
