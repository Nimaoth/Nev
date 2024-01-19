import std/[tables, sequtils]
import misc/custom_logger
import platform/[filesystem]
import input

logCategory "events"

type EventResponse* = enum
  Failed,
  Ignored,
  Canceled,
  Handled,
  Progress,

type EventHandlerConfig* = ref object
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

func newEventHandlerConfig*(context: string): EventHandlerConfig =
  new result
  result.handleActions = true
  result.handleInputs = false
  result.context = context

proc buildDFA*(config: EventHandlerConfig): CommandDFA =
  return buildDFA(config.commands, config.leaders)

proc dfa*(handler: EventHandler): CommandDFA =
  if handler.revision < handler.config.revision:
    handler.dfaInternal = handler.config.buildDFA()
    fs.saveApplicationFile(handler.config.context & ".dot", handler.dfaInternal.dumpGraphViz)
    handler.revision = handler.config.revision
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
  echo config.commands
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
    handler.states = @[default(CommandState)]
    handler.config = inConfig
    handler.dfaInternal = inConfig.buildDFA()
    fs.saveApplicationFile(handler.config.context & ".dot", handler.dfaInternal.dumpGraphViz)

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

    handlerBody
    handler

proc reset*(handler: var EventHandler) =
  handler.states = @[default(CommandState)]

proc parseAction*(action: string): tuple[action: string, arg: string] =
  let spaceIndex = action.find(' ')
  if spaceIndex == -1:
    return (action, "")
  else:
    return (action[0..<spaceIndex], action[spaceIndex + 1..^1])

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
    let prevStates = handler.states
    handler.states = handler.dfa.stepAll(handler.states, input, modifiers)
    # debug &"{handler.config.context}: handleEvent {(inputToString(input, modifiers))}\n  {prevStates}\n  -> {handler.states}"
    # debugf"handleEvent {handler.config.context} {(inputToString(input, modifiers))}"
    if not handler.inProgress:
      handler.reset()
      if not prevStates.inProgress:
        # undefined input in state 0
        # only handle if no modifier or only shift is pressed, because if any other modifiers are pressed
        # (ctrl, alt, win) then it doesn't produce input
        if handleUnknownAsInput and input > 0 and modifiers + {Shift} == {Shift} and handler.handleInput != nil:
          return handler.handleInput(inputToString(input, {}))
        return Ignored
      else:
        # undefined input in state n
        return Canceled

    elif handler.states.anyIt(handler.dfa.isTerminal(it.current)):
      if handler.states.len != 1:
        return Failed
      let (action, arg) = handler.dfa.getAction(handler.states[0]).parseAction
      handler.reset()
      # handler.state.current = handler.dfa.getDefaultState(handler.state.current) # todo
      return handler.handleAction(action, arg)
    else:
      if not handler.handleProgress.isNil:
        handler.handleProgress(input)
      return Progress
  else:
    return Failed

proc handleEvent*(handlers: seq[EventHandler], input: int64, modifiers: Modifiers): bool =
  let anyInProgress = handlers.anyInProgress

  var allowHandlingUnknownAsInput = true
  # Go through handlers in reverse
  for i in 0..<handlers.len:
    let handlerIndex = handlers.len - i - 1
    var handler = handlers[handlerIndex]
    let response = if (anyInProgress and handler.inProgress) or (not anyInProgress and not handler.inProgress):
      handler.handleEvent(input, modifiers, allowHandlingUnknownAsInput)
    else:
      Ignored

    if response != Ignored:
      result = true

    case response
    of Handled:
      allowHandlingUnknownAsInput = false
      for k, h in handlers:
        # Don't reset the current handler
        if k != handlerIndex:
          var h = h
          h.reset()

      break
    of Progress:
      allowHandlingUnknownAsInput = false
    of Failed, Canceled, Ignored:
      # Process remaining handlers
      discard

    if handler.config.consumeAllInput:
      # Don't process remaining handlers
      break
