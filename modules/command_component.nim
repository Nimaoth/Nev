import std/[tables, options]
import component

export component

const currentSourcePath2 = currentSourcePath()
include module_base

type
  CommandHandler* = proc(handler: RootRef, args: string): string {.gcsafe, raises: [].}
  CommandComponent* = ref object of Component
    commands*: Table[string, tuple[handler: RootRef, cb: CommandHandler]]
    executeCommandImpl*: proc (command: string) {.gcsafe, raises: [].}
    recordCurrentCommandRegisters*: seq[string] # List of registers the current command should be recorded into.
    bIsRecordingCurrentCommand*: bool = false # True while running a command which is being recorded
    commandCount*: int = 0
    commandCountRestore*: int

# DLL API
{.push rtl, gcsafe, raises: [].}
proc getCommandComponent*(self: ComponentOwner): Option[CommandComponent]
proc newCommandComponent*(): CommandComponent

proc commandComponentRegisterCommand(self: CommandComponent, name: string, handler: RootRef, cb: CommandHandler)
proc commandComponentExecuteCommand(self: CommandComponent, command: string)
proc commandComponentGetCommandCount(self: CommandComponent): int
proc commandComponentSetCommandCount(self: CommandComponent, count: int)
proc commandComponentSetCommandCountRestore(self: CommandComponent, count: int)
proc commandComponentUpdateCommandCount(self: CommandComponent, digit: int)

{.pop.}

# Nice wrappers
{.push inline.}
proc registerCommand*(self: CommandComponent, name: string, handler: RootRef, cb: CommandHandler) = commandComponentRegisterCommand(self, name, handler, cb)
proc executeCommand*(self: CommandComponent, command: string) = commandComponentExecuteCommand(self, command)
proc getCommandCount*(self: CommandComponent): int = commandComponentGetCommandCount(self)
proc setCommandCount*(self: CommandComponent, count: int) = commandComponentSetCommandCount(self, count)
proc setCommandCountRestore*(self: CommandComponent, count: int) = commandComponentSetCommandCountRestore(self, count)
proc updateCommandCount*(self: CommandComponent, digit: int) = commandComponentUpdateCommandCount(self, digit)
{.pop.}

proc recordCurrentCommand*(self: CommandComponent, registers: seq[string] = @[]) =
  self.recordCurrentCommandRegisters = registers

# Implementation
when implModule:
  import misc/util

  var CommandComponentId: ComponentTypeId = componentGenerateTypeId()

  proc getCommandComponent*(self: ComponentOwner): Option[CommandComponent] {.gcsafe, raises: [].} =
    return self.getComponent(CommandComponentId).mapIt(it.CommandComponent)

  proc newCommandComponent*(): CommandComponent =
    return CommandComponent(
      typeId: CommandComponentId,
    )

  proc commandComponentRegisterCommand(self: CommandComponent, name: string, handler: RootRef, cb: CommandHandler) =
    self.commands[name] = (handler, cb)

  proc commandComponentExecuteCommand(self: CommandComponent, command: string) =
    if self.executeCommandImpl != nil:
      self.executeCommandImpl(command)

  proc commandComponentGetCommandCount(self: CommandComponent): int =
    return self.commandCount

  proc commandComponentSetCommandCount(self: CommandComponent, count: int) =
    self.commandCount = count

  proc commandComponentSetCommandCountRestore(self: CommandComponent, count: int) =
    self.commandCountRestore = count

  proc commandComponentUpdateCommandCount(self: CommandComponent, digit: int) =
    self.commandCount = self.commandCount * 10 + digit

  proc init_module_command_component*() {.cdecl, exportc, dynlib.} =
    discard
