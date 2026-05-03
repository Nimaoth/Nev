#use register
import std/[options, strutils, sequtils, strformat, json, streams, tables]
import misc/[jsonex, myjsonutils]
import service, lisp, log

const currentSourcePath2 = currentSourcePath()
include module_base

logCategory "commands"

type
  CommandHandler* = proc(command: Option[string]): Option[string] {.gcsafe, raises: [].}

  CommandId* = distinct int

  Command* = object
    id: CommandId
    namespace*: string
    name*: string
    description*: string
    parameters*: seq[tuple[name: string, `type`: string]]
    returnType*: string
    signature*: string
    active*: bool
    execute*: proc(args: string): string {.gcsafe, raises: [CatchableError].}

  CommandPermissions* = object
    allowAll*: Option[bool]
    disallowAll*: Option[bool]
    allow*: seq[string]
    disallow*: seq[string]

  CommandService* = ref object of DynamicService
    logCommands*: bool = false
    dontRecord*: bool = false
    commands*: Table[string, Command]
    defaultCommandHandler*: CommandHandler

func serviceName*(_: typedesc[CommandService]): string = "CommandService"

# DLL API
{.push rtl, gcsafe, raises: [].}
proc commandServiceRegisterCommand(self: CommandService, command: sink Command, override: bool = false): CommandId
proc commandServiceExecuteCommand(self: CommandService, command: string, record: bool = true, context: JsonNodeEx = nil): Option[string]
proc commandServiceUnregisterCommandByName(self: CommandService, command: string)
proc commandServiceUnregisterCommandById(self: CommandService, id: CommandId)
proc commandServiceAddPrefixCommandHandler(self: CommandService, prefix: string, handler: CommandHandler)
proc commandServiceAddScopedCommandHandler(self: CommandService, prefix: string, handler: CommandHandler)
proc commandServiceCheckPermissions(self: CommandService, command: string, permissions: CommandPermissions): bool
{.pop.}

# Nice wrappers
proc registerCommand*(self: CommandService, command: sink Command, override: bool = false): CommandId {.inline.} = commandServiceRegisterCommand(self, command, override)
proc executeCommand*(self: CommandService, command: string, record: bool = true, context: JsonNodeEx = nil): Option[string] {.inline.} = commandServiceExecuteCommand(self, command, record, context)
proc unregisterCommand*(self: CommandService, command: string) {.inline.} = commandServiceUnregisterCommandByName(self, command)
proc unregisterCommand*(self: CommandService, id: CommandId) {.inline.} = commandServiceUnregisterCommandById(self, id)
proc addPrefixCommandHandler*(self: CommandService, prefix: string, handler: CommandHandler) {.inline.} = commandServiceAddPrefixCommandHandler(self, prefix, handler)
proc addScopedCommandHandler*(self: CommandService, prefix: string, handler: CommandHandler) {.inline.} = commandServiceAddScopedCommandHandler(self, prefix, handler)
proc checkPermissions*(self: CommandService, command: string, permissions: CommandPermissions): bool {.inline.} = commandServiceCheckPermissions(self, command, permissions)

import std/[macros, genasts]

proc getArg*[T](args: JsonNodeEx, namedArgs: JsonNodeEx, index: int, name: string): T {.gcsafe.} =
  if args != nil and index < args.elems.len:
    return args.elems[index].jsonTo(T)
  if namedArgs != nil and name in namedArgs.fields:
    return namedArgs.fields[name].jsonTo(T)
  return T.default

macro registerCommandImpl(self: CommandService, name: string, impl: typed): untyped =
  let typ = impl.getTypeImpl[0]
  var callImpl = nnkCall.newTree(impl)
  let jsonArg = ident "arg"
  for i in countdown(typ.len - 1, 1):
    let originalArgumentName = typ[i][0]
    let originalArgumentType = typ[i][1]
    var mappedArgumentType = originalArgumentType.repr.parseExpr
    let index = newLit(i - 1)
    # todo: default value
    let arg = genAst(jsonArg, index, originalArgumentName = newLit(originalArgumentName.repr), originalArgumentType):
      getArg[originalArgumentType](jsonArg, nil, index, originalArgumentName)
    callImpl.insert(1, arg)

  let returnType = typ[0]
  let call = if returnType.repr == "":
    genAst(callImpl):
      {.gcsafe.}:
        callImpl
      return newJexNull()
  else:
    quote do:
      {.gcsafe.}:
        return `callImpl`.toJsonEx

  result = genAst(call, argName = jsonArg):
    proc(argName: JsonNodeEx): JsonNodeEx {.closure.} =
      call

  return result

proc registerCommand*[T](self: CommandService, name: string, impl: T) =
  let implCl = registerCommandImpl(self, name, impl)
  discard self.registerCommand(Command(
    namespace: "",
    name: name,
    description: "",
    execute: proc(argsString: string): string {.gcsafe, raises: [].} =
      try:
        {.gcsafe.}:
          let args = newJexArray()
          for a in newStringStream(argsString).parseJsonexFragments():
            args.add a
          let res = implCl(args)
          return $res
      except CatchableError:
        log lvlError, &"registerCommand[T]: Failed to execute command '{argsString}'"
  ))

proc registerActiveCommand*[T](self: CommandService, name: string, impl: T) =
  let implCl = registerCommandImpl(self, name, impl)
  discard self.registerCommand(Command(
    namespace: "",
    name: name,
    description: "",
    active: true,
    execute: proc(argsString: string): string {.gcsafe, raises: [].} =
      try:
        {.gcsafe.}:
          let args = newJexArray()
          for a in newStringStream(argsString).parseJsonexFragments():
            args.add a
          let res = implCl(args)
          return $res
      except CatchableError:
        log lvlError, &"registerCommand[T]: Failed to execute command '{argsString}'"
  ))

proc parseCommand*(json: JsonNodeEx): tuple[command: string, args: string, ok: bool] {.raises: [ValueError].} =
  if json.kind == JString:
    let commandStr = json.getStr
    let spaceIndex = commandStr.find(" ")

    if spaceIndex == -1:
      return (commandStr, "", true)
    else:
      return (commandStr[0..<spaceIndex], commandStr[spaceIndex+1..^1], true)

  elif json.kind == JArray:
    if json.elems.len > 0:
      let name = json[0].getStr
      let args = json.elems[1..^1].mapIt($it).join(" ")
      return (name, args, true)
    else:
      raise newException(ValueError, "Missing command name, got empty array")

  elif json.kind == JLispVal:
    return ($json.lval, "", true)

  else:
    return ("", "", false)

# Implementation
when implModule:
  import std/[strformat, sugar, json, streams, hashes]
  import misc/[util, custom_async, custom_unicode, myjsonutils, parsejsonex, timer]
  import config_provider, input_api, register, dispatch_tables

  {.push gcsafe.}
  {.push raises: [].}

  type
    CommandServiceImpl* = ref object of CommandService
      mRegisters*: Registers

      scopedCommandHandlers: Table[string, CommandHandler]
      prefixCommandHandlers: seq[tuple[prefix: string, execute: CommandHandler]]
      commandIdCounter: int = 1
      idToCommand*: Table[CommandId, string]

      commandsThisFrame: int

  proc all*(_: typedesc[CommandPermissions]) = CommandPermissions(allowAll: some(true), disallowAll: some(true))
  proc none*(_: typedesc[CommandPermissions]) = CommandPermissions(allowAll: some(false), disallowAll: some(none))

  func serviceName*(_: typedesc[CommandServiceImpl]): string = "CommandService"

  proc `==`(a, b: CommandId): bool {.borrow.}
  proc hash(a: CommandId): Hash {.borrow.}
  proc `$`(a: CommandId): string {.borrow.}

  proc toStringResult(node: JsonNode): string =
    if node != nil and node.kind != JNull:
        return $node
    return ""

  proc registers*(self: CommandServiceImpl): Registers =
    if self.mRegisters == nil:
      self.mRegisters = getService(Registers).get(nil)
    return self.mRegisters

  proc newCommandService(): CommandServiceImpl =
    log lvlInfo, &"newCommandService"
    let self = CommandServiceImpl()

    {.gcsafe.}:
      for table in globalDispatchTables.mitems:
        for value in table.functions.values:
          capture value:
            discard self.registerCommand(Command(
              name: value.name,
              parameters: value.params.mapIt((it.name, it.typ)),
              description: value.docs,
              returnType: value.returnType,
              execute: (proc(args: string): string =
                try:
                  var argsJson = newJArray()
                  try:
                    for a in newStringStream(args).parseJsonFragments():
                      argsJson.add a
                  except CatchableError as e:
                    log(lvlError, fmt"Failed to parse arguments '{args}': {e.msg}")

                  return value.dispatch(argsJson).toStringResult()
                except CatchableError as e:
                  log lvlError, &"Failed to execute command '{value.name}': {e.msg}"
                  return ""
              )
            ))

    return self

  # todo
  # method tick*(self: CommandServiceImpl) =
  #   self.commandsThisFrame = 0

  proc config(self: CommandServiceImpl): ConfigStore =
    if self.services.getService(ConfigService).getSome(configs):
      return configs.runtime
    return nil

  proc commandServiceUnregisterCommandByName(self: CommandService, command: string) =
    let self = self.CommandServiceImpl
    if self.commands.contains(command):
      let id = self.commands[command].id
      self.commands.del(command)
      self.idToCommand.del(id)

  proc commandServiceUnregisterCommandById(self: CommandService, id: CommandId) =
    let self = self.CommandServiceImpl
    if self.idToCommand.contains(id):
      let name = self.idToCommand[id]
      self.idToCommand.del(id)

      if name in self.commands and self.commands[name].id != id:
        # Command was reassigned, don't delete the new command.
        return
      self.commands.del(name)

  proc commandServiceRegisterCommand(self: CommandService, command: sink Command, override: bool = false): CommandId =
    let self = self.CommandServiceImpl
    if command.name == "":
      log lvlError, &"Trying to register command with no name"
      return

    if not override and self.commands.contains(command.name):
      log lvlError, &"Trying to register command '{command.name}' which already exists"
      return

    let id = self.commandIdCounter.CommandId
    inc self.commandIdCounter

    self.unregisterCommand(command.name)

    command.id = id
    command.signature = "(" & command.parameters.mapIt(it.name & ": " & it.`type`).join(", ") & ") " & command.returnType
    self.idToCommand[id] = command.name
    self.commands[command.name] = command.ensureMove

    return id

  proc commandServiceAddPrefixCommandHandler(self: CommandService, prefix: string, handler: CommandHandler) =
    let self = self.CommandServiceImpl
    self.prefixCommandHandlers.add((prefix, handler))

  proc commandServiceAddScopedCommandHandler(self: CommandService, prefix: string, handler: CommandHandler) =
    let self = self.CommandServiceImpl
    self.scopedCommandHandlers[prefix] = handler

  iterator parseJsonFragmentsAndSubstituteArgs(s: Stream, args: seq[JsonNodeEx], index: var int): JsonNodeEx =
    var p: JsonexParser
    try:
      p.open(s, "")
      discard getTok(p) # read first token
      while p.tok != tkEof:
        if p.tok == tkError and p.buf[p.bufpos - 1] == '@':
          if p.bufpos < p.buf.len and p.buf[p.bufpos] == '@':
            inc p.bufpos
            for arg in args:
              yield arg

          else:
            var numStr = ""
            while p.buf[p.bufpos] in {'0'..'9'}:
              numStr.add p.buf[p.bufpos]
              inc p.bufpos

            if numStr == "":
              while index < args.len:
                yield args[index]
                inc index

            else:
              index = parseInt(numStr)
              if index < args.len:
                yield args[index]
                inc index

          discard getTok(p) # read next token
        else:
          yield p.parseJsonex(false, false)
    except:
      discard
    finally:
      try:
        p.close()
      except:
        discard

  proc handleAlias(self: CommandServiceImpl, action: string, arg: string, alias: JsonNode): Option[string] =
    var args = newSeq[JsonNodeEx]()
    try:
      for a in newStringStream(arg).parseJsonexFragments():
        args.add a

    except CatchableError:
      log(lvlError, fmt"Failed to parse arguments '{arg}': {getCurrentExceptionMsg()}")

    if alias.kind == JString:
      let (action, arg) = alias.getStr.parseAction
      var aliasArgs = newJexArray()
      try:
        var argIndex = 0
        for a in newStringStream(arg).parseJsonFragmentsAndSubstituteArgs(args, argIndex):
          aliasArgs.add a

      except:
        log(lvlError, fmt"Failed to parse arguments '{arg}': {getCurrentExceptionMsg()}")

      return self.executeCommand(action & " " & aliasArgs.mapIt($it).join(" "), record=false)

    elif alias.kind == JArray:
      var argIndex = 0
      for command in alias:
        if command.kind == JString:
          let (action, arg) = command.getStr.parseAction
          var aliasArgs = newJexArray()
          try:
            for a in newStringStream(arg).parseJsonFragmentsAndSubstituteArgs(args, argIndex):
              aliasArgs.add a

          except:
            log(lvlError, fmt"Failed to parse arguments '{arg}': {getCurrentExceptionMsg()}")
          result = self.executeCommand(action & " " & aliasArgs.mapIt($it).join(" "), record=false)

      return

    else:
      log lvlError, &"Failed to run alias '{action}': invalid configuration. Expected string | string[], got '{alias}'"
      return string.none

  proc commandServiceExecuteCommand(self: CommandService, command: string, record: bool = true, context: JsonNodeEx = nil): Option[string] =
    let self = self.CommandServiceImpl

    if command == "toggle-log-commands":
      self.logCommands = not self.logCommands
      return string.none

    var doRecord = record
    if self.dontRecord:
      doRecord = false

    let oldDontRecord = self.dontRecord
    if record:
      self.dontRecord = true
    defer:
      if record:
        self.dontRecord = oldDontRecord

    let t = startTimer()
    if not self.registers.bIsReplayingCommands and self.logCommands:
      log lvlInfo, &"[executeCommand] '{command}'"
    defer:
      if not self.registers.bIsReplayingCommands and self.logCommands:
        let elapsed = t.elapsed
        log lvlInfo, &"[executeCommand] '{command}' took {elapsed.ms} ms -> {result}"

    if not self.registers.bIsReplayingCommands and doRecord:
      self.registers.recordCommand(command)

    # todo
    # if self.commandsThisFrame > self.config.get("max-commands-per-frame", 1000):
    #   log lvlError, &""
    #   return string.none

    self.commandsThisFrame.inc()
    for handler in self.prefixCommandHandlers:
      if command.startsWith(handler.prefix):
        return handler.execute(command.some)

    let i = command.find('.')
    let (prefix, rawCommand) = if i <= 0:
      ("", command)
    else:
      (command[0..<i], command[(i + 1)..^1])

    if prefix in self.scopedCommandHandlers:
      let handler = self.scopedCommandHandlers[prefix]
      return handler(rawCommand.some)

    var (action, arg) = command.parseAction
    if arg.startsWith("\\"):
      arg = $newJString(arg[1..^1])

    let alias = if self.config != nil: self.config.get("alias." & action, newJNull()) else: nil
    if alias != nil and alias.kind != JNull:
      return self.handleAlias(action, arg, alias)

    if self.commands.contains(action):
      try:
        let command = self.commands[action]
        if command.active:
          let contextStr = if context == nil: "null" else: $context
          arg = contextStr & " " & arg
        return command.execute(arg).some
      except Exception as e:
        log lvlError, &"Failed to run command '{command}': {e.msg}"
        return string.none

    try:
      if self.defaultCommandHandler.isNotNil:
        return self.defaultCommandHandler(command.some)
    except Exception as e:
      log lvlError, &"Failed to run command '{command}': {e.msg}"
      return string.none

    return string.none

  proc commandServiceCheckPermissions(self: CommandService, command: string, permissions: CommandPermissions): bool =
    if permissions.disallowAll.get(false) or command in permissions.disallow:
      return false
    if permissions.allowAll.get(false) or command in permissions.allow:
      return true
    return false

  proc init_module_command_service*() {.cdecl, exportc, dynlib.} =
    getServices().addService(newCommandService())
