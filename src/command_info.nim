import std/[options, tables]
import events, input_api

type
  CommandKeyInfo* = object
    keys*: string
    command*: string
    context*: string
    source*: CommandSource

  CommandInfos* = ref object
    built: bool = false
    commandToKeys*: Table[string, seq[CommandKeyInfo]]

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
