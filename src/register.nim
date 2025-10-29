import std/[strutils, tables, options]
import nimsumtree/rope
import scripting/[expose]
import misc/[custom_logger, custom_async, util, rope_utils, array_set]
import clipboard, service, dispatch_tables

{.push gcsafe.}
{.push raises: [].}

logCategory "register"

type
  RegisterKind* {.pure.} = enum Text, Rope
  Register* = object
    case kind*: RegisterKind
    of RegisterKind.Text:
      text*: string
    of RegisterKind.Rope:
      rope*: Rope

func clone*(register: Register): Register =
  case register.kind
  of RegisterKind.Text: Register(kind: RegisterKind.Text, text: register.text)
  of RegisterKind.Rope: Register(kind: RegisterKind.Rope, rope: register.rope.clone())

proc getText*(register: Register): string =
  case register.kind
  of RegisterKind.Text:
    return register.text
  of RegisterKind.Rope:
    return $register.rope

proc numLines*(register: Register): int =
  case register.kind
  of RegisterKind.Text:
    return register.text.count('\n') + 1
  of RegisterKind.Rope:
    return register.rope.lines

type
  Registers* = ref object of Service
    registers*: Table[string, Register]
    recordingKeys*: seq[string]
    recordingCommands*: seq[string]
    bIsReplayingKeys*: bool = false
    bIsReplayingCommands*: bool = false


func serviceName*(_: typedesc[Registers]): string = "Registers"

addBuiltinService(Registers)

method init*(self: Registers): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  self.registers = initTable[string, Register]()
  return ok()

proc setRegisterTextAsync*(self: Registers, text: string, register: string = ""): Future[void] {.async.} =
  self.registers[register] = Register(kind: RegisterKind.Text, text: text)
  if register.len == 0:
    setSystemClipboardText(text)

proc getRegisterTextAsync*(self: Registers, register: string = ""): Future[string] {.async.} =
  if register.len == 0:
    let text = getSystemClipboardText().await
    if text.isSome:
      return text.get

  if self.registers.contains(register):
    return self.registers[register].getText()

  return ""

proc setRegisterAsync*(self: Registers, register: string, value: sink Register): Future[void] {.async.} =
  if register.len == 0:
    setSystemClipboardText(value.getText())
  self.registers[register] = value.move

proc getRegisterAsync*(self: Registers, register: string, res: ptr Register): Future[bool] {.async.} =
  if register.len == 0:
    var text = getSystemClipboardText().await
    if text.isSome:
      if text.get.len > 1024:
        var rope: Rope
        if createRopeAsync(text.get.addr, rope.addr).await.getSome(errorIndex):
          log lvlWarn, &"Large clipboard contains invalid utf8 at index {errorIndex}, can't use rope"
          res[] = Register(kind: RegisterKind.Text, text: text.get.move)
        else:
          res[] = Register(kind: RegisterKind.Rope, rope: rope.move)

      else:
        res[] = Register(kind: RegisterKind.Text, text: text.get.move)
      return true

  if self.registers.contains(register):
    res[] = self.registers[register].clone()
    return true

  return false

proc recordCommand*(self: Registers, command: string, registers: openArray[string] = []) =
  if self.bIsReplayingCommands:
    return

  template iterate(commands: untyped) =
    for register in commands:
      if not self.registers.contains(register) or self.registers[register].kind != RegisterKind.Text:
        self.registers[register] = Register(kind: RegisterKind.Text, text: "")
      if self.registers[register].text.len > 0:
        self.registers[register].text.add "\n"
      self.registers[register].text.add command

  if registers.len > 0:
    iterate(registers)
  else:
    iterate(self.recordingCommands)

###########################################################################

proc getRegisters(): Option[Registers] =
  {.gcsafe.}:
    if gServices.isNil: return Registers.none
    return gServices.getService(Registers)

static:
  addInjector(Registers, getRegisters)

proc setRegisterText*(self: Registers, text: string, register: string = "") {.expose("registers").} =
  self.registers[register] = Register(kind: RegisterKind.Text, text: text)

proc getRegisterText*(self: Registers, register: string): string {.expose("registers").} =
  if register.len == 0:
    log lvlError, fmt"getRegisterText: Register name must not be empty. Use getRegisterTextAsync() instead."
    return ""

  if self.registers.contains(register):
    return self.registers[register].getText()

  return ""

proc startRecordingKeys*(self: Registers, register: string) {.expose("registers").} =
  log lvlInfo, &"Start recording keys into '{register}'"
  self.recordingKeys.incl register

proc stopRecordingKeys*(self: Registers, register: string) {.expose("registers").} =
  log lvlInfo, &"Stop recording keys into '{register}'"
  self.recordingKeys.excl register

proc startRecordingCommands*(self: Registers, register: string) {.expose("registers").} =
  log lvlInfo, &"Start recording commands into '{register}'"
  self.recordingCommands.incl register

proc stopRecordingCommands*(self: Registers, register: string) {.expose("registers").} =
  log lvlInfo, &"Stop recording commands into '{register}'"
  self.recordingCommands.excl register

proc isReplayingCommands*(self: Registers): bool {.expose("registers").} =
  self.bIsReplayingCommands

proc isReplayingKeys*(self: Registers): bool {.expose("registers").} =
  self.bIsReplayingKeys

proc isRecordingCommands*(self: Registers, registry: string): bool {.expose("registers").} =
  self.recordingCommands.contains(registry)

addGlobalDispatchTable "registers", genDispatchTable("registers")
