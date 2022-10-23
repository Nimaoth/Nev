import std/[tables, sequtils]
import input

type EventResponse* = enum
  Failed,
  Ignored,
  Canceled,
  Handled,
  Progress,

type EventHandlerConfig* = ref object
  commands: Table[string, string]
  revision: int

type EventHandler* = ref object
  state*: int
  config: EventHandlerConfig
  revision: int
  dfa: CommandDFA
  handleAction*: proc(action: string, arg: string): EventResponse
  handleInput*: proc(input: string): EventResponse

proc buildDFA*(config: EventHandlerConfig): CommandDFA =
  return buildDFA(config.commands.pairs.toSeq)

proc dfa*(handler: EventHandler): CommandDFA =
  if handler.revision < handler.config.revision:
    handler.dfa = handler.config.buildDFA()
    handler.revision = handler.config.revision
  return handler.dfa

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
        let action {.inject, used.} = action
        let arg {.inject, used.} = arg
        return actionBody

    template onInput(inputBody: untyped): untyped =
      handler.handleInput = proc(input: string): EventResponse =
        let input {.inject, used.} = input
        return inputBody

    handlerBody
    handler
