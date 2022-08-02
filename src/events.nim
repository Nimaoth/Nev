import input

type EventResponse* = enum
  Failed,
  Ignored,
  Canceled,
  Handled,
  Progress,

type EventHandler* = ref object
  state*: int
  dfa*: CommandDFA
  handleAction*: proc(action: string, arg: string): EventResponse
  handleInput*: proc(input: string): EventResponse

template eventHandler*(commandDFA: CommandDFA, handlerBody: untyped): untyped =
  block:
    var handler = EventHandler()
    handler.dfa = commandDFA
    
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
        let action {.inject.} = action
        let arg {.inject.} = arg
        return actionBody

    template onInput(inputBody: untyped): untyped =
      handler.handleInput = proc(input: string): EventResponse =
        let input {.inject.} = input
        return inputBody

    var commands: seq[(string, string)] = @[]

    template command(cmd: string, a: string): untyped =
      commands.add (cmd, a)

    handlerBody
    handler.dfa = buildDFA(commands)
    # handler.dfa.dump(0, 0, {})
    handler