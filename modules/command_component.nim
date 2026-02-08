import std/[tables, options]
import component

export component

const currentSourcePath2 = currentSourcePath()
include module_base

type
  CommandHandler* = proc(handler: RootRef, args: string): string {.gcsafe, raises: [].}
  CommandComponent* = ref object of Component
    commands*: Table[string, tuple[handler: RootRef, cb: CommandHandler]]

# DLL API
{.push rtl, gcsafe, raises: [].}
proc getCommandComponent*(self: ComponentOwner): Option[CommandComponent]
proc newCommandComponent*(): CommandComponent

proc commandComponentRegisterCommand(self: CommandComponent, name: string, handler: RootRef, cb: CommandHandler)

{.pop.}

# Nice wrappers
{.push inline.}
proc registerCommand*(self: CommandComponent, name: string, handler: RootRef, cb: CommandHandler) = commandComponentRegisterCommand(self, name, handler, cb)
{.pop.}

# Implementation
when implModule:
  import misc/util

  var CommandComponentId: ComponentTypeId = componentGenerateTypeId()

  proc getCommandComponent*(self: ComponentOwner): Option[CommandComponent] {.gcsafe, raises: [].} =
    return self.getComponent(CommandComponentId).mapIt(it.CommandComponent)

  proc newCommandComponent*(): CommandComponent =
    return CommandComponent(
      typeId: CommandComponentId,
      initializeImpl: (proc(self: Component, owner: ComponentOwner) =
        let self = self.CommandComponent
      ),
      deinitializeImpl: (proc(self: Component) =
        let self = self.CommandComponent
      ),
    )

  proc commandComponentRegisterCommand(self: CommandComponent, name: string, handler: RootRef, cb: CommandHandler) =
    self.commands[name] = (handler, cb)

  proc init_module_command_component*() {.cdecl, exportc, dynlib.} =
    discard
