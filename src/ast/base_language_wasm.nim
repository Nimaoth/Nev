import std/[macros, genasts]
import std/[options, tables]
import fusion/matching
import id, model, ast_ids, custom_logger, util, base_language, model_state
import scripting/[wasm_builder]

logCategory "base-language-wasm"

type
  LocalVariableStorage = enum Local, Stack
  LocalVariable = object
    case kind: LocalVariableStorage
    of Local: localIdx: WasmLocalIdx
    of Stack: stackOffset: int32

  DestinationStorage = enum Stack, Memory, Discard, LValue
  Destination = object
    case kind: DestinationStorage
    of Stack: discard
    of Memory:
      offset: uint32
      align: uint32
    of Discard: discard
    of LValue: discard

  BaseLanguageWasmCompiler* = ref object
    builder: WasmBuilder

    ctx: ModelComputationContextBase

    wasmFuncs: Table[NodeId, WasmFuncIdx]

    functionsToCompile: seq[(AstNode, WasmFuncIdx)]
    localIndices: Table[NodeId, LocalVariable]
    globalIndices: Table[NodeId, WasmGlobalIdx]
    labelIndices: Table[NodeId, int] # Not the actual index

    exprStack: seq[WasmExpr]
    currentExpr: WasmExpr
    currentLocals: seq[tuple[typ: WasmValueType, id: string]]
    currentParamCount: int32
    currentStackLocals: seq[int32]
    currentStackLocalsSize: int32

    generators: Table[ClassId, proc(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination)]

    # imported
    printI32: WasmFuncIdx
    printString: WasmFuncIdx
    printLine: WasmFuncIdx
    intToString: WasmFuncIdx

    # implemented inline
    buildString: WasmFuncIdx
    strlen: WasmFuncIdx
    allocFunc: WasmFuncIdx

    stackBase: WasmGlobalIdx
    stackEnd: WasmGlobalIdx
    stackPointer: WasmGlobalIdx

    currentBasePointer: WasmLocalIdx

    memoryBase: WasmGlobalIdx
    tableBase: WasmGlobalIdx
    heapBase: WasmGlobalIdx
    heapSize: WasmGlobalIdx

    globalData: seq[uint8]

proc setupGenerators(self: BaseLanguageWasmCompiler)
proc compileFunction(self: BaseLanguageWasmCompiler, node: AstNode, funcIdx: WasmFuncIdx)
proc getOrCreateWasmFunc(self: BaseLanguageWasmCompiler, node: AstNode, exportName: Option[string] = string.none): WasmFuncIdx
proc compileRemainingFunctions(self: BaseLanguageWasmCompiler)

proc newBaseLanguageWasmCompiler*(ctx: ModelComputationContextBase): BaseLanguageWasmCompiler =
  new result
  result.setupGenerators()
  result.builder = newWasmBuilder()
  result.ctx = ctx

  result.builder.mems.add(WasmMem(typ: WasmMemoryType(limits: WasmLimits(min: 255))))

  result.builder.addExport("memory", 0.WasmMemIdx)

  result.printI32 = result.builder.addImport("env", "print_i32", result.builder.addType([I32], []))
  result.printString = result.builder.addImport("env", "print_string", result.builder.addType([I32], []))
  result.printLine = result.builder.addImport("env", "print_line", result.builder.addType([], []))
  result.intToString = result.builder.addImport("env", "intToString", result.builder.addType([I32], [I32]))
  result.stackBase = result.builder.addGlobal(I32, mut=true, 0, id="__stack_base")
  result.stackEnd = result.builder.addGlobal(I32, mut=true, 0, id="__stack_end")
  result.stackPointer = result.builder.addGlobal(I32, mut=true, 65536, id="__stack_pointer")
  result.memoryBase = result.builder.addGlobal(I32, mut=false, 0, id="__memory_base")
  result.tableBase = result.builder.addGlobal(I32, mut=false, 0, id="__table_base")
  result.heapBase = result.builder.addGlobal(I32, mut=false, 0, id="__heap_base")
  result.heapSize = result.builder.addGlobal(I32, mut=true, 0, id="__heap_size")

  # todo: add proper allocator. For now just a bump allocator without freeing
  result.allocFunc = result.builder.addFunction([I32], [I32], [], exportName="my_alloc".some, body=WasmExpr(instr: @[
    WasmInstr(kind: GlobalGet, globalIdx: result.heapBase),
    WasmInstr(kind: GlobalGet, globalIdx: result.heapSize),
    WasmInstr(kind: I32Add),
    WasmInstr(kind: GlobalGet, globalIdx: result.heapSize),
    WasmInstr(kind: LocalGet, localIdx: 0.WasmLocalIdx),
    WasmInstr(kind: I32Add),
    WasmInstr(kind: GlobalSet, globalIdx: result.heapSize),
  ]))

  discard result.builder.addFunction([I32], [], [], exportName="my_dealloc".some, body=WasmExpr(instr: @[
      WasmInstr(kind: Nop),
  ]))

  # strlen
  block:
    let param = 0.WasmLocalIdx
    let current = 1.WasmLocalIdx
    result.strlen = result.builder.addFunction([I32], [I32], [
        (I32, "current"),
      ], body=WasmExpr(instr: @[

      # a.length
      WasmInstr(kind: LocalGet, localIdx: param),
      WasmInstr(kind: LocalSet, localIdx: current),

      WasmInstr(kind: Block, blockType: WasmBlockType(kind: ValType), blockInstr: @[
        WasmInstr(kind: Loop, loopType: WasmBlockType(kind: ValType), loopInstr: @[
          WasmInstr(kind: LocalGet, localIdx: current),
          WasmInstr(kind: I32Load8U),
          WasmInstr(kind: I32Eqz),
          WasmInstr(kind: BrIf, brLabelIdx: 1.WasmLabelIdx),

          WasmInstr(kind: LocalGet, localIdx: current),
          WasmInstr(kind: I32Const, i32Const: 1),
          WasmInstr(kind: I32Add),
          WasmInstr(kind: LocalSet, localIdx: current),
          WasmInstr(kind: Br, brLabelIdx: 0.WasmLabelIdx),
        ]),
      ]),

      WasmInstr(kind: LocalGet, localIdx: current),
      WasmInstr(kind: LocalGet, localIdx: param),
      WasmInstr(kind: I32Sub),
    ]))

  # build
  block:
    let paramA = 0.WasmLocalIdx
    let paramB = 1.WasmLocalIdx
    let lengthA = 2.WasmLocalIdx
    let lengthB = 3.WasmLocalIdx
    let resultLength = 4.WasmLocalIdx
    let resultAddress = 5.WasmLocalIdx
    result.buildString = result.builder.addFunction([I64, I64], [I64], [
        (I32, "lengthA"),
        (I32, "lengthB"),
        (I32, "resultLength"),
        (I32, "resultAddress")
      ], body=WasmExpr(instr: @[

      # params: a: string, b: string
      # a.length
      WasmInstr(kind: LocalGet, localIdx: paramA),
      WasmInstr(kind: I64Const, i64Const: 32),
      WasmInstr(kind: I64ShrU),
      WasmInstr(kind: I32WrapI64),
      WasmInstr(kind: LocalTee, localIdx: lengthA),

      # b.length
      WasmInstr(kind: LocalGet, localIdx: paramB),
      WasmInstr(kind: I64Const, i64Const: 32),
      WasmInstr(kind: I64ShrU),
      WasmInstr(kind: I32WrapI64),
      WasmInstr(kind: LocalTee, localIdx: lengthB),

      # resultLength = a.length + b.length
      WasmInstr(kind: I32Add),
      WasmInstr(kind: LocalTee, localIdx: resultLength),

      # result = alloc(resultLength)
      WasmInstr(kind: I32Const, i32Const: 1),
      WasmInstr(kind: I32Add),
      WasmInstr(kind: Call, callFuncIdx: result.allocFunc),
      WasmInstr(kind: LocalTee, localIdx: resultAddress),

      # memcpy(resultAddress, a, a.length)
      WasmInstr(kind: LocalGet, localIdx: paramA),
      WasmInstr(kind: I32WrapI64),
      WasmInstr(kind: LocalGet, localIdx: lengthA),
      WasmInstr(kind: MemoryCopy),

      # memcpy(resultAddress + a.length, b, b.length)
      WasmInstr(kind: LocalGet, localIdx: resultAddress),
      WasmInstr(kind: LocalGet, localIdx: lengthA),
      WasmInstr(kind: I32Add),

      WasmInstr(kind: LocalGet, localIdx: paramB),
      WasmInstr(kind: I32WrapI64),
      WasmInstr(kind: LocalGet, localIdx: lengthB),
      WasmInstr(kind: MemoryCopy),

      # *(resultAddress + resultLength) = 0
      WasmInstr(kind: LocalGet, localIdx: resultAddress),
      WasmInstr(kind: LocalGet, localIdx: resultLength),
      WasmInstr(kind: I32Add),
      WasmInstr(kind: I32Const, i32Const: 0),
      WasmInstr(kind: I32Store),

      # result = ptr or (resultLength << 32)
      WasmInstr(kind: LocalGet, localIdx: resultAddress),
      WasmInstr(kind: I64ExtendI32U),
      WasmINstr(kind: LocalGet, localIdx: resultLength),
      WasmInstr(kind: I64ExtendI32U),
      WasmInstr(kind: I64Const, i64Const: 32),
      WasmInstr(kind: I64Shl),
      WasmInstr(kind: I64Or),
    ]))

proc compileToBinary*(self: BaseLanguageWasmCompiler, node: AstNode): seq[uint8] =
  let functionName = $node.id
  discard self.getOrCreateWasmFunc(node, exportName=functionName.some)
  self.compileRemainingFunctions()

  let activeDataOffset = wasmPageSize # todo: after stack
  let activeDataSize = self.globalData.len.int32
  discard self.builder.addActiveData(0.WasmMemIdx, activeDataOffset, self.globalData)

  let heapBase = align(activeDataOffset + activeDataSize, wasmPageSize)
  self.builder.globals[self.heapBase.int].init = WasmInstr(kind: I32Const, i32Const: heapBase)

  debugf"{self.builder}"

  let binary = self.builder.generateBinary()
  return binary

proc compileRemainingFunctions(self: BaseLanguageWasmCompiler) =
  while self.functionsToCompile.len > 0:
    let function = self.functionsToCompile.pop
    self.compileFunction(function[0], function[1])

proc genNode*(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  if self.generators.contains(node.class):
    let generator = self.generators[node.class]
    generator(self, node, dest)
  else:
    let class = node.nodeClass
    log(lvlWarn, fmt"genNode: Node class not implemented: {class.name}")

proc toWasmValueType(typ: AstNode): Option[WasmValueType] =
  if typ.class == IdInt:
    return WasmValueType.I32.some # int32
  if typ.class == IdPointerType:
    return WasmValueType.I32.some # pointer
  if typ.class == IdString:
    return WasmValueType.I64.some # (len << 32) | ptr
  if typ.class == IdFunctionType:
    return WasmValueType.I32.some # table index
  return WasmValueType.none

proc getTypeAttributes(self: BaseLanguageWasmCompiler, typ: AstNode): tuple[size: int32, align: int32] =
  if typ.class == IdInt:
    return (4, 4)
  if typ.class == IdPointerType:
    return (4, 4)
  if typ.class == IdString:
    return (8, 4)
  if typ.class == IdFunctionType:
    return (0, 1)
  if typ.class == IdVoid:
    return (0, 1)
  if typ.class == IdStructDefinition:
    for _, memberNode in typ.children(IdStructDefinitionMembers):
      let memberType = self.ctx.computeType(memberNode)
      let (memberSize, memberAlign) = self.getTypeAttributes(memberType)
      assert memberAlign <= 4

      result.size = align(result.size, memberAlign)
      result.size += memberSize
      result.align = max(result.align, memberAlign)
    return
  return (0, 1)

proc shouldPassAsOutParamater(self: BaseLanguageWasmCompiler, typ: AstNode): bool =
  let (size, _) = self.getTypeAttributes(typ)
  if size > 8:
    return true
  if typ.class == IdStructDefinition:
    return true
  return false

proc getOrCreateWasmFunc(self: BaseLanguageWasmCompiler, node: AstNode, exportName: Option[string] = string.none): WasmFuncIdx =
  if not self.wasmFuncs.contains(node.id):
    var inputs, outputs: seq[WasmValueType]

    for _, c in node.children(IdFunctionDefinitionReturnType):
      let typ = self.ctx.getValue(c)
      echo "return type: ", typ
      if self.shouldPassAsOutParamater(typ):
        inputs.add WasmValueType.I32
      elif typ.class != IdVoid:
        outputs.add typ.toWasmValueType.get

    for _, c in node.children(IdFunctionDefinitionParameters):
      let typ = self.ctx.computeType(c)
      echo typ
      if typ.class == IdType:
        continue
      echo typ.toWasmValueType.get
      inputs.add typ.toWasmValueType.get

    let funcIdx = self.builder.addFunction(inputs, outputs, exportName=exportName)
    self.wasmFuncs[node.id] = funcIdx
    self.functionsToCompile.add (node, funcIdx)

  return self.wasmFuncs[node.id]

proc getTypeMemInstructions(self: BaseLanguageWasmCompiler, typ: AstNode): tuple[load: WasmInstrKind, store: WasmInstrKind] =
  if typ.class == IdInt:
    return (I32Load, I32Store)
  if typ.class == IdPointerType:
    return (I32Load, I32Store)
  if typ.class == IdString:
    return (I64Load, I64Store)
  log lvlError, fmt"getTypeMemInstructions: Type not implemented: {`$`(typ, true)}"
  return (Nop, Nop)

proc createLocal(self: BaseLanguageWasmCompiler, id: NodeId, typ: AstNode, name: string): WasmLocalIdx =
  if typ.toWasmValueType.getSome(wasmType):
    result = (self.currentLocals.len + self.currentParamCount).WasmLocalIdx
    self.currentLocals.add((wasmType, name))
    self.localIndices[id] = LocalVariable(kind: Local, localIdx: result)

proc createStackLocal(self: BaseLanguageWasmCompiler, id: NodeId, typ: AstNode): int32 =
  let (size, alignment) = self.getTypeAttributes(typ)

  self.currentStackLocalsSize = self.currentStackLocalsSize.align(alignment)
  result = self.currentStackLocalsSize

  self.currentStackLocals.add(self.currentStackLocalsSize)
  # debugf"createStackLocal size {size}, alignment {alignment}, offset {self.currentStackLocalsSize}"

  self.localIndices[id] = LocalVariable(kind: Stack, stackOffset: self.currentStackLocalsSize)

  self.currentStackLocalsSize += size

proc getTempLocal(self: BaseLanguageWasmCompiler, typ: AstNode): WasmLocalIdx =
  if self.localIndices.contains(typ.id):
    return self.localIndices[typ.id].localIdx

  return self.createLocal(typ.id, typ, fmt"__temp_{typ.id}")

proc addStringData(self: BaseLanguageWasmCompiler, value: string): int32 =
  let offset = self.globalData.len.int32
  self.globalData.add(value.toOpenArrayByte(0, value.high))
  self.globalData.add(0)

  result = offset + wasmPageSize

macro instr(self: WasmExpr, op: WasmInstrKind, args: varargs[untyped]): untyped =
  result = genAst(self, op):
    self.instr.add WasmInstr(kind: op)
  for arg in args:
    result[1].add arg

macro instr(self: BaseLanguageWasmCompiler, op: WasmInstrKind, args: varargs[untyped]): untyped =
  result = genAst(self, op):
    self.currentExpr.instr.add WasmInstr(kind: op)
  for arg in args:
    result[1].add arg

proc genDup(self: BaseLanguageWasmCompiler, typ: AstNode) =
  let tempIdx = self.getTempLocal(typ)
  self.instr(LocalTee, localIdx: tempIdx)
  self.instr(LocalGet, localIdx: tempIdx)

proc storeInstr(self: BaseLanguageWasmCompiler, op: WasmInstrKind, offset: uint32, align: uint32) =
  # debugf"storeInstr {op}, offset {offset}, align {align}"
  assert op in {I32Store, I64Store, F32Store, F64Store, I32Store8, I64Store8, I32Store16, I64Store16, I64Store32}
  var instr = WasmInstr(kind: op)
  instr.memArg = WasmMemArg(offset: offset, align: align)
  self.currentExpr.instr.add instr

proc loadInstr(self: BaseLanguageWasmCompiler, op: WasmInstrKind, offset: uint32, align: uint32) =
  # debugf"loadInstr {op}, offset {offset}, align {align}"
  assert op in {I32Load, I64Load, F32Load, F64Load, I32Load8U, I32Load8S, I64Load8U, I64Load8S, I32Load16U, I32Load16S, I64Load16U, I64Load16S, I64Load32U, I64Load32S}
  var instr = WasmInstr(kind: op)
  instr.memArg = WasmMemArg(offset: offset, align: align)
  self.currentExpr.instr.add instr

proc generateEpiloque(self: BaseLanguageWasmCompiler) =
  self.instr(LocalGet, localIdx: self.currentBasePointer)
  self.instr(GlobalSet, globalIdx: self.stackPointer)

proc compileFunction(self: BaseLanguageWasmCompiler, node: AstNode, funcIdx: WasmFuncIdx) =
  let body = node.children(IdFunctionDefinitionBody)
  if body.len != 1:
    return

  assert self.exprStack.len == 0
  self.currentExpr = WasmExpr()
  self.currentLocals.setLen 0
  self.currentParamCount = 0.int32

  let returnType = node.firstChild(IdFunctionDefinitionReturnType).mapIt(self.ctx.getValue(it)).get(voidTypeInstance)
  let passReturnAsOutParam = self.shouldPassAsOutParamater(returnType)

  if passReturnAsOutParam:
    self.localIndices[IdFunctionDefinitionReturnType.NodeId] = LocalVariable(kind: Local, localIdx: self.currentParamCount.WasmLocalIdx)
    inc self.currentParamCount

  for i, param in node.children(IdFunctionDefinitionParameters):
    let paramType = self.ctx.computeType(param)
    if paramType.class == IdType:
      continue

    self.localIndices[param.id] = LocalVariable(kind: Local, localIdx: self.currentParamCount.WasmLocalIdx)
    inc self.currentParamCount

  self.currentBasePointer = (self.currentLocals.len + self.currentParamCount).WasmLocalIdx
  self.currentLocals.add((I32, "__base_pointer")) # base pointer

  let stackSizeInstrIndex = block: # prologue
    self.instr(GlobalGet, globalIdx: self.stackPointer)
    self.instr(I32Const, i32Const: 0) # size, patched at end when we know the size of locals
    let i = self.currentExpr.instr.high
    self.instr(I32Sub)
    self.instr(LocalTee, localIdx: self.currentBasePointer)
    self.instr(GlobalSet, globalIdx: self.stackPointer)
    i

  let destination = if returnType.class == IdVoid:
    Destination(kind: Discard)
  elif passReturnAsOutParam:
    self.instr(LocalGet, localIdx: 0.WasmLocalIdx) # load return value address from first parameter
    Destination(kind: Memory, offset: 0, align: 0)
  else:
    Destination(kind: Stack)

  self.genNode(body[0], destination)

  let requiredStackSize: int32 = self.currentStackLocalsSize
  self.currentExpr.instr[stackSizeInstrIndex].i32Const = requiredStackSize

  self.generateEpiloque()

  self.builder.setBody(funcIdx, self.currentLocals, self.currentExpr)

proc genDrop(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.instr(Drop)
  # todo: size of node, stack

proc genStoreDestination(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  case dest
  of Stack(): discard
  of Memory(offset: @offset, align: @align):
    let typ = self.ctx.computeType(node)
    let instr = self.getTypeMemInstructions(typ).store
    self.storeInstr(instr, offset, align)
  of Discard():
    self.genDrop(node)

proc genNodeChildren(self: BaseLanguageWasmCompiler, node: AstNode, role: RoleId, dest: Destination) =
  let count = node.childCount(role)
  for i, c in node.children(role):
    let childDest = if i == count - 1:
      dest
    else:
      Destination(kind: Discard)

    self.genNode(c, childDest)

###################### Node Generators ##############################

proc genNodeBlock(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typ = self.ctx.computeType(node)
  let tempIdx = if dest.kind == Memory:
    let tempIdx = self.getTempLocal(intTypeInstance)
    self.instr(LocalSet, localIdx: tempIdx)
    tempIdx.some
  else:
    WasmLocalIdx.none

  self.exprStack.add self.currentExpr
  self.currentExpr = WasmExpr()

  if tempIdx.getSome(tempIdx):
    self.instr(LocalGet, localIdx: tempIdx)

  self.genNodeChildren(node, IdBlockChildren, dest)

  let blockExpr = self.currentExpr
  self.currentExpr = self.exprStack.pop

  let wasmType = typ.toWasmValueType
  self.instr(Block, blockType: WasmBlockType(kind: ValType, typ: wasmType), blockInstr: move blockExpr.instr)

proc genNodeBinaryExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeChildren(node, IdBinaryExpressionLeft, dest)
  self.genNodeChildren(node, IdBinaryExpressionRight, dest)

proc genNodeBinaryAddExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack))
  self.instr(I32Add)
  self.genStoreDestination(node, dest)

proc genNodeBinarySubExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack))
  self.instr(I32Sub)
  self.genStoreDestination(node, dest)

proc genNodeBinaryMulExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack))
  self.instr(I32Mul)
  self.genStoreDestination(node, dest)

proc genNodeBinaryDivExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack))
  self.instr(I32DivS)
  self.genStoreDestination(node, dest)

proc genNodeBinaryModExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack))
  self.instr(I32RemS)
  self.genStoreDestination(node, dest)

proc genNodeBinaryLessExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack))
  self.instr(I32LtS)
  self.genStoreDestination(node, dest)

proc genNodeBinaryLessEqualExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack))
  self.instr(I32LeS)
  self.genStoreDestination(node, dest)

proc genNodeBinaryGreaterExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack))
  self.instr(I32GtS)
  self.genStoreDestination(node, dest)

proc genNodeBinaryGreaterEqualExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack))
  self.instr(I32GeS)
  self.genStoreDestination(node, dest)

proc genNodeBinaryEqualExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack))
  self.instr(I32Eq)
  self.genStoreDestination(node, dest)

proc genNodeBinaryNotEqualExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack))
  self.instr(I32Ne)
  self.genStoreDestination(node, dest)

proc genNodeUnaryNegateExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.instr(I32Const, i32Const: 0)
  self.genNodeChildren(node, IdUnaryExpressionChild, Destination(kind: Stack))
  self.instr(I32Sub)
  self.genStoreDestination(node, dest)

proc genNodeUnaryNotExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.instr(I32Const, i32Const: 1)
  self.genNodeChildren(node, IdUnaryExpressionChild, Destination(kind: Stack))
  self.instr(I32Sub)
  self.genStoreDestination(node, dest)

proc genNodeIntegerLiteral(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let value = node.property(IdIntegerLiteralValue).get
  self.instr(I32Const, i32Const: value.intValue.int32)
  self.genStoreDestination(node, dest)

proc genNodeBoolLiteral(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let value = node.property(IdBoolLiteralValue).get
  self.instr(I32Const, i32Const: value.boolValue.int32)
  self.genStoreDestination(node, dest)

proc genNodeStringLiteral(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let value = node.property(IdStringLiteralValue).get
  let address = self.addStringData(value.stringValue)
  self.instr(I32Const, i32Const: address)
  self.instr(I64ExtendI32U)
  self.instr(I64Const, i64Const: value.stringValue.len.int64 shl 32)
  self.instr(I64Or)
  self.genStoreDestination(node, dest)

proc genNodeIfExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  var ifStack: seq[WasmExpr]

  let thenCases = node.children(IdIfExpressionThenCase)
  let elseCase = node.children(IdIfExpressionElseCase)

  let typ = self.ctx.computeType(node)
  let wasmType = typ.toWasmValueType

  for k, c in thenCases:
    # condition
    self.genNodeChildren(c, IdThenCaseCondition, Destination(kind: Stack))

    # then case
    self.exprStack.add self.currentExpr
    self.currentExpr = WasmExpr()

    self.genNodeChildren(c, IdThenCaseBody, dest)

    ifStack.add self.currentExpr
    self.currentExpr = WasmExpr()

  for i, c in elseCase:
    if i > 0 and wasmType.isSome: self.genDrop(c)
    self.genNode(c, dest)
    if wasmType.isNone: self.genDrop(c)

  for i in countdown(ifStack.high, 0):
    let elseCase = self.currentExpr
    self.currentExpr = self.exprStack.pop
    self.instr(If, ifType: WasmBlockType(kind: ValType, typ: wasmType), ifThenInstr: move ifStack[i].instr, ifElseInstr: move elseCase.instr)

template genBlock(self: BaseLanguageWasmCompiler, typ: WasmBlockType, body: untyped): untyped =
  self.exprStack.add self.currentExpr
  self.currentExpr = WasmExpr()

  try:
    body
  finally:
    let bodyExpr = self.currentExpr
    self.currentExpr = self.exprStack.pop
    self.instr(Block, blockType: typ, blockInstr: move bodyExpr.instr)

template genLoop(self: BaseLanguageWasmCompiler, typ: WasmBlockType, body: untyped): untyped =
  self.exprStack.add self.currentExpr
  self.currentExpr = WasmExpr()

  try:
    body
  finally:
    let bodyExpr = self.currentExpr
    self.currentExpr = self.exprStack.pop
    self.instr(Loop, loopType: typ, loopInstr: move bodyExpr.instr)

proc genBranchLabel(self: BaseLanguageWasmCompiler, node: AstNode, offset: int) =
  assert self.labelIndices.contains(node.id)
  let index = self.labelIndices[node.id]
  let actualIndex = WasmLabelIdx(self.exprStack.high - index - offset)
  self.instr(Br, brLabelIdx: actualIndex)

proc genNodeWhileExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typ = WasmValueType.none

  # outer block for break
  self.genBlock WasmBlockType(kind: ValType, typ: typ):
    self.labelIndices[node.id] = self.exprStack.high

    # generate body in loop block
    self.genLoop WasmBlockType(kind: ValType, typ: typ):

      # generate condition
      self.genNodeChildren(node, IdWhileExpressionCondition, Destination(kind: Stack))

      # break block if condition is false
      self.instr(I32Eqz)
      self.instr(BrIf, brLabelIdx: 1.WasmLabelIdx)

      self.genNodeChildren(node, IdWhileExpressionBody, Destination(kind: Discard))

      # continue loop
      self.instr(Br, brLabelIdx: 0.WasmLabelIdx)

proc genNodeConstDecl(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  # let index = self.createLocal(node.id, nil)

  # let values = node.children(IdConstDeclValue)
  # assert values.len > 0
  # self.genNode(values[0], dest)

  # self.instr(LocalTee, localIdx: index)

  assert dest.kind == Discard

proc genNodeLetDecl(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typ = self.ctx.computeType(node)
  let offset = self.createStackLocal(node.id, typ)

  if node.firstChild(IdLetDeclValue).getSome(value):
    self.instr(LocalGet, localIdx: self.currentBasePointer)
    self.genNode(value, Destination(kind: Memory, offset: offset.uint32, align: 0))

  # self.instr(LocalTee, localIdx: index)

  assert dest.kind == Discard

proc genNodeVarDecl(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typ = self.ctx.computeType(node)
  let offset = self.createStackLocal(node.id, typ)
  # let index = self.createLocal(node.id, nil)

  if node.firstChild(IdVarDeclValue).getSome(value):
    self.instr(LocalGet, localIdx: self.currentBasePointer)
    self.genNode(value, Destination(kind: Memory, offset: offset.uint32, align: 0))

  # self.instr(LocalTee, localIdx: index)

  assert dest.kind == Discard

proc genNodeBreakExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  var parent = node.parent
  while parent.isNotNil and parent.class != IdWhileExpression:
    parent = parent.parent

  if parent.isNil:
    log lvlError, fmt"Break outside of loop"
    return

  self.genBranchLabel(parent, 0)

proc genNodeContinueExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  var parent = node.parent
  while parent.isNotNil and parent.class != IdWhileExpression:
    parent = parent.parent

  if parent.isNil:
    log lvlError, fmt"Break outside of loop"
    return

  self.genBranchLabel(parent, 1)

proc genNodeReturnExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  discard

proc genNodeNodeReference(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let id = node.reference(IdNodeReferenceTarget)
  if node.resolveReference(IdNodeReferenceTarget).getSome(target) and target.class == IdConstDecl:
    self.genNodeChildren(target, IdConstDeclValue, dest)

  else:
    if not self.localIndices.contains(id):
      log lvlError, fmt"Variable not found found in locals: {id}, from here {node}"
      return

    let typ = self.ctx.computeType(node)
    let (size, align) = self.getTypeAttributes(typ)

    case dest
    of Stack():
      case self.localIndices[id]:
      of Local(localIdx: @index):
        self.instr(LocalGet, localIdx: index)
      of Stack(stackOffset: @offset):
        self.instr(LocalGet, localIdx: self.currentBasePointer)
        let memInstr = self.getTypeMemInstructions(typ)
        self.loadInstr(memInstr.load, offset.uint32, 0)

    of Memory(offset: @offset, align: @align):
      case self.localIndices[id]:
      of Local(localIdx: @index):
        self.instr(LocalGet, localIdx: index)
        let memInstr = self.getTypeMemInstructions(typ)
        self.storeInstr(memInstr.store, offset, align)

      of Stack(stackOffset: @offset):
        self.instr(LocalGet, localIdx: self.currentBasePointer)
        if offset > 0:
          self.instr(I32Const, i32Const: offset)
          self.instr(I32Add)
        self.instr(I32Const, i32Const: size)
        self.instr(MemoryCopy)

    of Discard():
      discard

    of LValue():
      case self.localIndices[id]:
      of Local(localIdx: @index):
        log lvlError, fmt"Can't get lvalue of local: {id}, from here {node}"
      of Stack(stackOffset: @offset):
        self.instr(LocalGet, localIdx: self.currentBasePointer)
        if offset > 0:
          self.instr(I32Const, i32Const: offset)
          self.instr(I32Add)

proc genAssignmentExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let targetNode = node.firstChild(IdAssignmentTarget).getOr:
    log lvlError, fmt"No assignment target for: {node}"
    return

  let id = if targetNode.class == IdNodeReference:
    targetNode.reference(IdNodeReferenceTarget).some
  else:
    NodeId.none

  var valueDest = Destination(kind: Stack)

  if id.isSome:
    if not self.localIndices.contains(id.get):
      log lvlError, fmt"Variable not found found in locals: {id.get}"
      return

    case self.localIndices[id.get]
    of Local(localIdx: @index):
      discard
    of Stack(stackOffset: @offset):
      self.instr(LocalGet, localIdx: self.currentBasePointer)
      valueDest = Destination(kind: Memory, offset: offset.uint32, align: 0)
  else:
    self.genNode(targetNode, Destination(kind: LValue))
    valueDest = Destination(kind: Memory, offset: 0, align: 0)

  self.genNodeChildren(node, IdAssignmentValue, valueDest)

  if id.isSome:
    case self.localIndices[id.get]
    of Local(localIdx: @index):
      self.instr(LocalSet, localIdx: index)
    of Stack():
      discard

  assert dest.kind == Discard

proc genNodePrintExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  for i, c in node.children(IdPrintArguments):
    self.genNode(c, Destination(kind: Stack))

    let typ = self.ctx.computeType(c)
    if typ.class == IdInt:
      self.instr(Call, callFuncIdx: self.printI32)
    elif typ.class == IdPointerType:
      self.instr(Call, callFuncIdx: self.printI32)
    elif typ.class == IdString:
      self.instr(I32WrapI64)
      self.instr(Call, callFuncIdx: self.printString)
    else:
      log lvlError, fmt"genNodePrintExpression: Type not implemented: {`$`(typ, true)}"

  self.instr(Call, callFuncIdx: self.printLine)

proc genToString(self: BaseLanguageWasmCompiler, typ: AstNode) =
  if typ.class == IdInt:
    let tempIdx = self.getTempLocal(typ)
    self.instr(Call, callFuncIdx: self.intToString)
    self.instr(LocalTee, localIdx: tempIdx)
    self.instr(I64ExtendI32U)
    self.instr(LocalGet, localIdx: tempIdx)
    self.instr(Call, callFuncIdx: self.strlen)
    self.instr(I64ExtendI32U)
    self.instr(I64Const, i64Const: 32)
    self.instr(I64Shl)
    self.instr(I64Or)
  else:
    self.instr(Drop)
    self.instr(I64Const, i64Const: 0)

proc genNodeBuildExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  for i, c in node.children(IdBuildArguments):
    self.genNode(c, Destination(kind: Stack))

    let typ = self.ctx.computeType(c)
    if typ.class != IdString:
      self.genToString(typ)

    if i > 0:
      self.instr(Call, callFuncIdx: self.buildString)

  self.genStoreDestination(node, dest)

proc genNodeCallExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  for i, c in node.children(IdCallArguments):
    self.genNode(c, Destination(kind: Stack))

  let funcExprNode = node.firstChild(IdCallFunction).getOr:
    log lvlError, fmt"No function specified for call {node}"
    return

  let returnType = self.ctx.computeType(node)
  let passReturnAsOutParam = self.shouldPassAsOutParamater(returnType)

  if passReturnAsOutParam:
    case dest
    of Stack(): return # todo error
    of Memory(offset: @offset):
      if offset > 0:
        self.instr(I32Const, i32Const: offset.int32)
    of Discard(): discard
    of LValue(): return # todo error

  if funcExprNode.class == IdNodeReference:
    let funcDeclNode = funcExprNode.resolveReference(IdNodeReferenceTarget).getOr:
      log lvlError, fmt"Function not found: {funcExprNode}"
      return

    if funcDeclNode.class == IdConstDecl:
      let funcDefNode = funcDeclNode.firstChild(IdConstDeclValue).getOr:
        log lvlError, fmt"No value: {funcDeclNode} in call {node}"
        return

      var name = funcDeclNode.property(IdINamedName).get.stringValue
      if funcDefNode.isGeneric(self.ctx):
        # generic call
        let concreteFunction = self.ctx.instantiateFunction(funcDefNode, node.children(IdCallArguments))
        let funcIdx = self.getOrCreateWasmFunc(concreteFunction, (name & $concreteFunction.id).some)
        self.instr(Call, callFuncIdx: funcIdx)

      else:
        # static call
        let funcIdx = self.getOrCreateWasmFunc(funcDefNode, name.some)
        self.instr(Call, callFuncIdx: funcIdx)

    else: # not a const decl, so call indirect
      self.genNode(funcExprNode, Destination(kind: Stack))
      const tableIdx = 0.WasmTableIdx
      let typeIdx = 0.WasmTypeIdx
      self.instr(CallIndirect, callIndirectTableIdx: tableIdx, callIndirectTypeIdx: typeIdx)

  else: # not a node reference
    self.genNode(funcExprNode, Destination(kind: Stack))
    const tableIdx = 0.WasmTableIdx
    let typeIdx = 0.WasmTypeIdx
    self.instr(CallIndirect, callIndirectTableIdx: tableIdx, callIndirectTypeIdx: typeIdx)

  let typ = self.ctx.computeType(node)
  if typ.class != IdVoid and not passReturnAsOutParam: # todo: should handlediscard here aswell even if passReturnAsOutParam
    self.genStoreDestination(node, dest)

proc genNodeStructMemberAccessExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =

  let member = node.resolveReference(IdStructMemberAccessMember).getOr:
    log lvlError, fmt"Member not found: {node}"
    return

  let valueNode = node.firstChild(IdStructMemberAccessValue).getOr:
    log lvlError, fmt"No value: {node}"
    return

  let typ = self.ctx.computeType(valueNode)

  var offset = 0.int32
  var size = 0.int32
  var align = 0.int32

  for _, memberDefinition in typ.children(IdStructDefinitionMembers):
    let memberType = self.ctx.computeType(memberDefinition)
    let (memberSize, memberAlign) = self.getTypeAttributes(memberType)
    offset = align(offset, memberAlign)

    let originalMemberId = if memberDefinition.hasReference(IdStructTypeGenericMember):
      memberDefinition.reference(IdStructTypeGenericMember)
    else:
      memberDefinition.id

    if member.id == originalMemberId:
      size = memberSize
      align = memberAlign
      break
    offset += memberSize

  case dest
  of Memory(offset: @offset, align: @align):
    if offset > 0:
      self.instr(I32Const, i32Const: offset.int32)
      self.instr(I32Add)

  self.genNode(valueNode, Destination(kind: LValue))

  case dest
  of Stack():
    let typ = self.ctx.computeType(member)
    let instr = self.getTypeMemInstructions(typ).load
    self.loadInstr(instr, offset.uint32, 0)

  of Memory():
    if offset > 0:
      self.instr(I32Const, i32Const: offset.int32)
      self.instr(I32Add)
    self.instr(I32Const, i32Const: size)
    self.instr(MemoryCopy)

  of Discard():
    self.instr(Drop)

  of LValue():
    if offset > 0:
      self.instr(I32Const, i32Const: offset)
      self.instr(I32Add)

proc genNodeAddressOf(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let valueNode = node.firstChild(IdAddressOfValue).getOr:
    log lvlError, fmt"No value: {node}"
    return

  self.genNode(valueNode, Destination(kind: LValue))
  self.genStoreDestination(node, dest)

proc genCopyToDestination(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  case dest
  of Stack():
    let typ = self.ctx.computeType(node)
    let instr = self.getTypeMemInstructions(typ).load
    self.loadInstr(instr, 0, 0)

  of Memory():
    let typ = self.ctx.computeType(node)
    let (sourceSize, sourceAlign) = self.getTypeAttributes(typ)
    self.instr(I32Const, i32Const: sourceSize)
    self.instr(MemoryCopy)

  of Discard():
    self.instr(Drop)

  of LValue():
    discard

proc genNodeDeref(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let valueNode = node.firstChild(IdDerefValue).getOr:
    log lvlError, fmt"No value: {node}"
    return

  self.genNode(valueNode, Destination(kind: Stack))
  self.genCopyToDestination(node, dest)

proc genNodeArrayAccess(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let valueNode = node.firstChild(IdArrayAccessValue).getOr:
    log lvlError, fmt"No value: {node}"
    return

  let indexNode = node.firstChild(IdArrayAccessIndex).getOr:
    log lvlError, fmt"No index: {node}"
    return

  let typ = self.ctx.computeType(node)
  let (size, _) = self.getTypeAttributes(typ)

  self.genNode(valueNode, Destination(kind: Stack))
  self.genNode(indexNode, Destination(kind: Stack))
  self.instr(I32Const, i32Const: size)
  self.instr(I32Mul)
  self.instr(I32Add)

  self.genCopyToDestination(node, dest)

proc genNodeAllocate(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typeNode = node.firstChild(IdAllocateType).getOr:
    log lvlError, fmt"No type: {node}"
    return

  let typ = self.ctx.getValue(typeNode)
  let (size, align) = self.getTypeAttributes(typ)

  self.instr(I32Const, i32Const: size)

  if node.firstChild(IdAllocateCount).getSome(countNode):
    self.genNode(countNode, Destination(kind: Stack))
    self.instr(I32Mul)

  self.instr(Call, callFuncIdx: self.allocFunc)
  self.genStoreDestination(node, dest)

proc setupGenerators(self: BaseLanguageWasmCompiler) =
  self.generators[IdBlock] = genNodeBlock
  self.generators[IdAdd] = genNodeBinaryAddExpression
  self.generators[IdSub] = genNodeBinarySubExpression
  self.generators[IdMul] = genNodeBinaryMulExpression
  self.generators[IdDiv] = genNodeBinaryDivExpression
  self.generators[IdMod] = genNodeBinaryModExpression
  self.generators[IdLess] = genNodeBinaryLessExpression
  self.generators[IdLessEqual] = genNodeBinaryLessEqualExpression
  self.generators[IdGreater] = genNodeBinaryGreaterExpression
  self.generators[IdGreaterEqual] = genNodeBinaryGreaterEqualExpression
  self.generators[IdEqual] = genNodeBinaryEqualExpression
  self.generators[IdNotEqual] = genNodeBinaryNotEqualExpression
  self.generators[IdNegate] = genNodeUnaryNegateExpression
  self.generators[IdNot] = genNodeUnaryNotExpression
  self.generators[IdIntegerLiteral] = genNodeIntegerLiteral
  self.generators[IdBoolLiteral] = genNodeBoolLiteral
  self.generators[IdStringLiteral] = genNodeStringLiteral
  self.generators[IdIfExpression] = genNodeIfExpression
  self.generators[IdWhileExpression] = genNodeWhileExpression
  self.generators[IdConstDecl] = genNodeConstDecl
  self.generators[IdLetDecl] = genNodeLetDecl
  self.generators[IdVarDecl] = genNodeVarDecl
  self.generators[IdNodeReference] = genNodeNodeReference
  self.generators[IdAssignment] = genAssignmentExpression
  self.generators[IdBreakExpression] = genNodeBreakExpression
  self.generators[IdContinueExpression] = genNodeContinueExpression
  self.generators[IdPrint] = genNodePrintExpression
  self.generators[IdBuildString] = genNodeBuildExpression
  self.generators[IdCall] = genNodeCallExpression
  self.generators[IdStructMemberAccess] = genNodeStructMemberAccessExpression
  self.generators[IdAddressOf] = genNodeAddressOf
  self.generators[IdDeref] = genNodeDeref
  self.generators[IdArrayAccess] = genNodeArrayAccess
  self.generators[IdAllocate] = genNodeAllocate