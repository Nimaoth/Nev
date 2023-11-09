import std/[macros, genasts]
import std/[options, tables]
import fusion/matching
import id, model, ast_ids, custom_logger, util, model_state
import scripting/[wasm_builder]

logCategory "base-language-wasm"

type
  LocalVariableStorage = enum Local, Stack
  LocalVariable = object
    case kind: LocalVariableStorage
    of Local: localIdx: WasmLocalIdx
    of Stack: stackOffset: int32

  DestinationStorage = enum Stack, Memory, Discard
  Destination = object
    case kind: DestinationStorage
    of Stack: discard
    of Memory:
      offset: uint32
      align: uint32
    of Discard: discard

  BaseLanguageWasmCompiler* = ref object
    builder: WasmBuilder

    ctx: ModelComputationContextBase

    wasmFuncs: Table[Id, WasmFuncIdx]

    functionsToCompile: seq[(AstNode, WasmFuncIdx)]
    localIndices: Table[Id, LocalVariable]
    globalIndices: Table[Id, WasmGlobalIdx]
    labelIndices: Table[Id, int] # Not the actual index

    exprStack: seq[WasmExpr]
    currentExpr: WasmExpr
    currentLocals: seq[tuple[typ: WasmValueType, id: string]]
    currentParamCount: int32
    currentStackLocals: seq[int32]
    currentStackLocalsSize: int32

    generators: Table[Id, proc(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination)]

    printI32: WasmFuncIdx
    printString: WasmFuncIdx
    printLine: WasmFuncIdx

    stackBase: WasmGlobalIdx
    stackEnd: WasmGlobalIdx
    stackPointer: WasmGlobalIdx

    currentBasePointer: WasmLocalIdx

    memoryBase: WasmGlobalIdx
    tableBase: WasmGlobalIdx

    globalData: seq[uint8]

proc setupGenerators(self: BaseLanguageWasmCompiler)

proc newBaseLanguageWasmCompiler*(ctx: ModelComputationContextBase): BaseLanguageWasmCompiler =
  new result
  result.setupGenerators()
  result.builder = newWasmBuilder()
  result.ctx = ctx

  result.builder.mems.add(WasmMem(typ: WasmMemoryType(limits: WasmLimits(min: 255))))

  discard result.builder.addFunction([I32], [I32], [], exportName="my_alloc".some, body=WasmExpr(instr: @[
    WasmInstr(kind: I32Const, i32Const: 0),
  ]))

  discard result.builder.addFunction([I32], [], [], exportName="my_dealloc".some, body=WasmExpr(instr: @[
      WasmInstr(kind: Nop),
  ]))

  result.builder.addExport("memory", 0.WasmMemIdx)

  result.printI32 = result.builder.addImport("env", "print_i32", result.builder.addType([I32], []))
  result.printString = result.builder.addImport("env", "print_string", result.builder.addType([I32], []))
  result.printLine = result.builder.addImport("env", "print_line", result.builder.addType([], []))
  result.stackBase = result.builder.addGlobal(I32, mut=true, 0, id="__stack_base")
  result.stackEnd = result.builder.addGlobal(I32, mut=true, 0, id="__stack_end")
  result.stackPointer = result.builder.addGlobal(I32, mut=true, 65536, id="__stack_pointer")
  result.memoryBase = result.builder.addGlobal(I32, mut=false, 0, id="__memory_base")
  result.tableBase = result.builder.addGlobal(I32, mut=false, 0, id="__table_base")

proc genNode*(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  if self.generators.contains(node.class):
    let generator = self.generators[node.class]
    generator(self, node, dest)
  else:
    let class = node.nodeClass
    log(lvlWarn, fmt"genNode: Node class not implemented: {class.name}")

proc toWasmValueType(typ: AstNode): WasmValueType =
  if typ.class == IdInt:
    return WasmValueType.I32
  if typ.class == IdString:
    return WasmValueType.I32
  if typ.class == IdFunctionType:
    return WasmValueType.FuncRef
  return WasmValueType.I32

proc getOrCreateWasmFunc(self: BaseLanguageWasmCompiler, node: AstNode, exportName: Option[string] = string.none): WasmFuncIdx =
  if not self.wasmFuncs.contains(node.id):
    var inputs, outputs: seq[WasmValueType]

    for _, c in node.children(IdFunctionDefinitionParameters):
      let typ = c.children(IdParameterDeclType)[0]
      inputs.add typ.toWasmValueType

    for _, c in node.children(IdFunctionDefinitionReturnType):
      outputs.add c.toWasmValueType

    let funcIdx = self.builder.addFunction(inputs, outputs, exportName=exportName)
    self.wasmFuncs[node.id] = funcIdx
    self.functionsToCompile.add (node, funcIdx)

  return self.wasmFuncs[node.id]

proc getTypeAttributes(self: BaseLanguageWasmCompiler, typ: AstNode): tuple[size: int32, align: int32] =
  if typ.class == IdInt:
    return (4, 4)
  if typ.class == IdString:
    return (8, 4)
  if typ.class == IdFunctionType:
    return (0, 1)
  if typ.class == IdVoid:
    return (0, 1)
  return (0, 1)

proc getTypeMemInstructions(self: BaseLanguageWasmCompiler, typ: AstNode): tuple[load: WasmInstrKind, store: WasmInstrKind] =
  if typ.class == IdInt:
    return (I32Load, I32Store)
  if typ.class == IdString:
    return (I64Load, I64Store)
  log lvlError, fmt"getTypeMemInstructions: Type not implemented: {`$`(typ, true)}"
  return (Nop, Nop)

proc createLocal(self: BaseLanguageWasmCompiler, id: Id, typ: AstNode, name: string): WasmLocalIdx =
  result = (self.currentLocals.len + self.currentParamCount).WasmLocalIdx
  self.currentLocals.add((I32, name))
  self.localIndices[id] = LocalVariable(kind: Local, localIdx: result)

proc align(address, alignment: int32): int32 =
  if alignment == 0: # Actually, this is illegal. This branch exists to actively
                     # hide problems.
    result = address
  else:
    result = (address + (alignment - 1)) and not (alignment - 1)

proc createStackLocal(self: BaseLanguageWasmCompiler, id: Id, typ: AstNode): int32 =
  let (size, alignment) = self.getTypeAttributes(typ)

  self.currentStackLocalsSize = self.currentStackLocalsSize.align(alignment)
  result = self.currentStackLocalsSize

  self.currentStackLocals.add(self.currentStackLocalsSize)
  debugf"createStackLocal size {size}, alignment {alignment}, offset {self.currentStackLocalsSize}"

  self.localIndices[id] = LocalVariable(kind: Stack, stackOffset: self.currentStackLocalsSize)

  self.currentStackLocalsSize += size

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

proc storeInstr(self: BaseLanguageWasmCompiler, op: WasmInstrKind, offset: uint32, align: uint32) =
  debugf"storeInstr {op}, offset {offset}, align {align}"
  assert op in {I32Store, I64Store, F32Store, F64Store, I32Store8, I64Store8, I32Store16, I64Store16, I64Store32}
  var instr = WasmInstr(kind: op)
  instr.memArg = WasmMemArg(offset: offset, align: align)
  self.currentExpr.instr.add instr

proc loadInstr(self: BaseLanguageWasmCompiler, op: WasmInstrKind, offset: uint32, align: uint32) =
  debugf"loadInstr {op}, offset {offset}, align {align}"
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
  for i, arg in node.children(IdFunctionDefinitionParameters):
    # self.createLocal(arg.id, nil)
    self.localIndices[arg.id] = LocalVariable(kind: Local, localIdx: self.currentParamCount.WasmLocalIdx)
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

  self.genNode(body[0], Destination(kind: Stack))

  let requiredStackSize: int32 = self.currentStackLocalsSize
  self.currentExpr.instr[stackSizeInstrIndex].i32Const = requiredStackSize

  self.generateEpiloque()

  self.builder.setBody(funcIdx, self.currentLocals, self.currentExpr)

proc compileRemainingFunctions(self: BaseLanguageWasmCompiler) =
  while self.functionsToCompile.len > 0:
    let function = self.functionsToCompile.pop
    self.compileFunction(function[0], function[1])

proc compileToBinary*(self: BaseLanguageWasmCompiler, node: AstNode): seq[uint8] =
  let functionName = $node.id
  discard self.getOrCreateWasmFunc(node, exportName=functionName.some)
  self.compileRemainingFunctions()

  discard self.builder.addActiveData(0.WasmMemIdx, wasmPageSize, self.globalData)

  debugf"{self.builder}"

  let binary = self.builder.generateBinary()
  return binary

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

proc genNodeChildren(self: BaseLanguageWasmCompiler, node: AstNode, role: Id, dest: Destination) =
  let count = node.childCount(role)
  for i, c in node.children(role):
    let childDest = if i == count - 1:
      dest
    else:
      Destination(kind: Discard)

    self.genNode(c, childDest)

###################### Node Generators ##############################

proc genNodeBlock(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  # self.exprStack.add self.currentExpr
  # self.currentExpr = WasmExpr()

  self.genNodeChildren(node, IdBlockChildren, dest)

  # self.currentExpr = self.exprStack.pop

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

  let typ = if elseCase.len > 0:
    WasmValueType.I32.some
  else:
    WasmValueType.none

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
    if i > 0 and typ.isSome: self.genDrop(c)
    self.genNode(c, dest)
    if typ.isNone: self.genDrop(c)

  for i in countdown(ifStack.high, 0):
    let elseCase = self.currentExpr
    self.currentExpr = self.exprStack.pop
    self.instr(If, ifType: WasmBlockType(kind: ValType, typ: typ), ifThenInstr: move ifStack[i].instr, ifElseInstr: move elseCase.instr)

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

  # Loop doesn't generate a value, but right now every node needs to produce an int32
  self.instr(I32Const, i32Const: 0)

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

  let values = node.children(IdLetDeclValue)
  assert values.len > 0

  self.instr(LocalGet, localIdx: self.currentBasePointer)
  self.genNode(values[0], Destination(kind: Memory, offset: offset.uint32, align: 0))

  # self.instr(LocalTee, localIdx: index)

  assert dest.kind == Discard

proc genNodeVarDecl(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typ = self.ctx.computeType(node)
  let offset = self.createStackLocal(node.id, typ)
  # let index = self.createLocal(node.id, nil)

  let values = node.children(IdVarDeclValue)
  assert values.len > 0

  self.instr(LocalGet, localIdx: self.currentBasePointer)
  self.genNode(values[0], Destination(kind: Memory, offset: offset.uint32, align: 0))

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

    case self.localIndices[id]:
    of Local(localIdx: @index):
      self.instr(LocalGet, localIdx: index)
    of Stack(stackOffset: @offset):
      self.instr(LocalGet, localIdx: self.currentBasePointer)

      let typ = self.ctx.computeType(node)
      let instr = self.getTypeMemInstructions(typ).load
      self.loadInstr(instr, offset.uint32, 0)

    self.genStoreDestination(node, dest)

proc genAssignmentExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let targetNodes = node.children(IdAssignmentTarget)

  let id = if targetNodes[0].class == IdNodeReference:
    targetNodes[0].reference(IdNodeReferenceTarget)
  else:
    log lvlError, fmt"Assignment target not found: {targetNodes[0].class}"
    return

  if not self.localIndices.contains(id):
    log lvlError, fmt"Variable not found found in locals: {id}"
    return

  var valueDest = Destination(kind: Stack)

  case self.localIndices[id]
  of Local(localIdx: @index):
    discard
  of Stack(stackOffset: @offset):
    self.instr(LocalGet, localIdx: self.currentBasePointer)
    valueDest = Destination(kind: Memory, offset: offset.uint32, align: 0)

  self.genNodeChildren(node, IdAssignmentValue, valueDest)

  case self.localIndices[id]
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
    elif typ.class == IdString:
      self.instr(I32WrapI64)
      self.instr(Call, callFuncIdx: self.printString)
    else:
      log lvlError, fmt"genNodePrintExpression: Type not implemented: {`$`(typ, true)}"

  self.instr(Call, callFuncIdx: self.printLine)
  self.instr(I32Const, i32Const: 0)

proc genNodeBuildExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  for i, c in node.children(IdBuildArguments):
    self.genNode(c, Destination(kind: Stack))

    let typ = self.ctx.computeType(c)
    if typ.class == IdInt:
      self.instr(Call, callFuncIdx: self.printI32)
    elif typ.class == IdString:
      self.instr(I32WrapI64)
      self.instr(Call, callFuncIdx: self.printString)
    else:
      log lvlError, fmt"genNodeBuildExpression: Type not implemented: {`$`(typ, true)}"

  self.instr(Call, callFuncIdx: self.printLine)
  self.instr(I32Const, i32Const: 0)

proc genNodeCallExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  for i, c in node.children(IdCallArguments):
    self.genNode(c, Destination(kind: Stack))

  let funcExprNode = node.firstChild(IdCallFunction).getOr:
    log lvlError, fmt"No function specified for call {node}"
    return

  if funcExprNode.class == IdNodeReference:
    let funcDeclNode = funcExprNode.resolveReference(IdNodeReferenceTarget).getOr:
      log lvlError, fmt"Function not found: {funcExprNode}"
      return

    if funcDeclNode.class == IdConstDecl:
      let funcDefNode = funcDeclNode.firstChild(IdConstDeclValue).getOr:
        log lvlError, fmt"No value: {funcDeclNode} in call {node}"
        return

      # static call
      let name = funcDeclNode.property(IdINamedName).get.stringValue
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
  if typ.id != IdVoid:
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