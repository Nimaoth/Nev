import std/[tables, sequtils, strformat]
import input, custom_logger

type EventResponse* = enum
  Failed,
  Ignored,
  Canceled,
  Handled,
  Progress,

type EventHandlerConfig* = ref object
  context*: string
  commands: Table[string, string]
  handleActions*: bool
  handleInputs*: bool
  consumeAllActions*: bool
  consumeAllInput*: bool
  revision: int

type EventHandler* = ref object
  state*: CommandState
  config: EventHandlerConfig
  revision: int
  dfaInternal: CommandDFA
  handleAction*: proc(action: string, arg: string): EventResponse
  handleInput*: proc(input: string): EventResponse

func newEventHandlerConfig*(context: string): EventHandlerConfig =
  new result
  result.handleActions = true
  result.handleInputs = false
  result.context = context

proc buildDFA*(config: EventHandlerConfig): CommandDFA =
  return buildDFA(config.commands.pairs.toSeq)

proc dfa*(handler: EventHandler): CommandDFA =
  if handler.revision < handler.config.revision:
    handler.dfaInternal = handler.config.buildDFA()
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

proc addCommand*(config: EventHandlerConfig, keys: string, action: string) =
  config.commands[keys] = action
  config.revision += 1

proc removeCommand*(config: EventHandlerConfig, keys: string) =
  config.commands.del(keys)
  config.revision += 1

proc clearCommands*(config: EventHandlerConfig) =
  config.commands.clear
  config.revision += 1

template eventHandler*(inConfig: EventHandlerConfig, handlerBody: untyped): untyped =
  block:
    var handler = EventHandler()
    handler.config = inConfig
    handler.dfaInternal = inConfig.buildDFA()

    template onAction(actionBody: untyped): untyped =
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

    template onInput(inputBody: untyped): untyped =
      handler.handleInput = proc(input: string): EventResponse =
        if handler.config.handleInputs:
          let input {.inject, used.} = input
          return inputBody
        else:
          return Ignored

    handlerBody
    handler

proc reset*(handler: var EventHandler) =
  handler.state = default(CommandState)

proc parseAction*(action: string): tuple[action: string, arg: string] =
  let spaceIndex = action.find(' ')
  if spaceIndex == -1:
    return (action, "")
  else:
    return (action[0..<spaceIndex], action[spaceIndex + 1..^1])

proc handleEvent*(handler: var EventHandler, input: int64, modifiers: Modifiers, handleUnknownAsInput: bool): EventResponse =
  if input != 0:
    let prevState = handler.state
    handler.state = handler.dfa.step(handler.state, input, modifiers)
    # debugf"handleEvent {(inputToString(input, modifiers))}, {prevState.current} -> {handler.state.current}, term = {(handler.dfa.isTerminal(handler.state.current))}, default = {(handler.dfa.getDefaultState(handler.state.current))}"
    if handler.state.current == 0:
      if prevState.current == 0:
        # undefined input in state 0
        # only handle if no modifier or only shift is pressed, because if any other modifiers are pressed
        # (ctrl, alt, win) then it doesn't produce input
        if handleUnknownAsInput and input > 0 and modifiers + {Shift} == {Shift} and handler.handleInput != nil:
          return handler.handleInput(inputToString(input, {}))
        return Ignored
      else:
        # undefined input in state n
        return Canceled

    elif handler.dfa.isTerminal(handler.state.current):
      let (action, arg) = handler.dfa.getAction(handler.state.current).parseAction
      handler.state.current = handler.dfa.getDefaultState(handler.state.current)
      return handler.handleAction(action, arg)
    else:
      return Progress
  else:
    return Failed

proc anyInProgress*(handlers: openArray[EventHandler]): bool =
  for h in handlers:
    if h.state.current != 0:
      return true
  return false

proc handleEvent*(handlers: seq[EventHandler], input: int64, modifiers: Modifiers): bool =
  let anyInProgress = handlers.anyInProgress

  var allowHandlingUnknownAsInput = true
  # Go through handlers in reverse
  for i in 0..<handlers.len:
    let handlerIndex = handlers.len - i - 1
    var handler = handlers[handlerIndex]
    let response = if (anyInProgress and handler.state.current != 0) or (not anyInProgress and handler.state.current == 0):
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
