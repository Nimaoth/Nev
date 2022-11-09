import std/[tables, sequtils]
import input

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
  revision: int

type EventHandler* = ref object
  state*: int
  config: EventHandlerConfig
  revision: int
  dfa: CommandDFA
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
    handler.dfa = handler.config.buildDFA()
    handler.revision = handler.config.revision
  return handler.dfa

proc setHandleInputs*(config: EventHandlerConfig, value: bool) =
  config.handleInputs = value
  config.revision += 1

proc setHandleActions*(config: EventHandlerConfig, value: bool) =
  config.handleActions = value
  config.revision += 1

proc addCommand*(config: EventHandlerConfig, keys: string, action: string) =
  config.commands[keys] = action
  config.revision += 1

proc removeCommand*(config: EventHandlerConfig, keys: string) =
  config.commands.del(keys)
  config.revision += 1

template eventHandler*(inConfig: EventHandlerConfig, handlerBody: untyped): untyped =
  block:
    var handler = EventHandler()
    handler.config = inConfig
    handler.dfa = inConfig.buildDFA()

    template onAction(actionBody: untyped): untyped =
      handler.handleAction = proc(action: string, arg: string): EventResponse =
        if handler.config.handleActions:
          let action {.inject, used.} = action
          let arg {.inject, used.} = arg
          return actionBody
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
