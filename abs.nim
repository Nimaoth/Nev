# import std/logging

proc addCommand*(context: string, keys: string, action: string, arg: string = "") =
  scriptAddCommand(context, keys, action, arg)

proc removeCommand*(context: string, keys: string) =
  scriptRemoveCommand(context, keys)

proc runAction*(action: string, arg: string = "") =
  scriptRunAction(action, arg)

proc log*(args: varargs[string, `$`]) =
  var msgLen = 0
  for arg in args:
    msgLen += arg.len
  var result = newStringOfCap(msgLen + 5)
  for arg in args:
    result.add(arg)
  scriptLog(result)