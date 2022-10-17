import std/[tables, sequtils]
import input

type EventResponse* = enum
  Failed,
  Ignored,
  Canceled,
  Handled,
  Progress,

type EventHandler* = ref object
  state*: int
  commands: Table[string, string]
  dirty: bool
  dfa: CommandDFA
  handleAction*: proc(action: string, arg: string): EventResponse
  handleInput*: proc(input: string): EventResponse

proc dfa*(handler: EventHandler): CommandDFA =
  if handler.dirty:
    handler.dfa = buildDFA(handler.commands.pairs.toSeq)
    handler.dirty = false
  return handler.dfa

proc addCommand*(handler: EventHandler, keys: string, action: string) =
  handler.commands[keys] = action
  handler.dirty = true

proc removeCommand*(handler: EventHandler, keys: string) =
  handler.commands.del(keys)
  handler.dirty = true

template eventHandler*(inCommands: Table[string, string], handlerBody: untyped): untyped =
  block:
    var handler = EventHandler()
    handler.commands = inCommands
    handler.dfa = buildDFA(inCommands.pairs.toSeq)

    template onAction(actionBody: untyped): untyped =
      handler.handleAction = proc(action: string, arg: string): EventResponse =
        let action {.inject.} = action
        let arg {.inject.} = arg
        return actionBody

    template onInput(inputBody: untyped): untyped =
      handler.handleInput = proc(input: string): EventResponse =
        let input {.inject.} = input
        return inputBody

    handlerBody
    # handler.dfa.dump(0, 0, {})
    handler

template eventHandler2*(handlerBody: untyped): untyped =
  block:
    var handler = EventHandler()

    template onAction(actionBody: untyped): untyped =
      handler.handleAction = proc(action: string, arg: string): EventResponse =
        let action {.inject, used.} = action
        let arg {.inject, used.} = arg
        return actionBody

    template onInput(inputBody: untyped): untyped =
      handler.handleInput = proc(input: string): EventResponse =
        let input {.inject, used.} = input
        return inputBody

    var tempCommands = initTable[string, string]()

    template command(cmd: string, a: string): untyped =
      tempCommands[cmd] = a

    handlerBody
    handler.commands = tempCommands
    handler.dfa = buildDFA(handler.commands.pairs.toSeq)
    # handler.dfa.dump(0, 0, {})
    handler