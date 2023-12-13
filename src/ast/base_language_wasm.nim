import std/[macros, genasts, strformat]
import std/[options, tables]
import fusion/matching
import model, ast_ids, custom_logger, util, base_language
import generator_wasm
import scripting/[wasm_builder]

logCategory "base-language-wasm"

let conversionOps = toTable {
  (IdInt32, IdInt64): I32WrapI64,
  (IdInt32, IdUInt64): I32WrapI64,
  (IdInt32, IdFloat32): I32TruncF32S,
  (IdInt32, IdFloat64): I32TruncF64S,

  (IdUInt32, IdInt64): I32WrapI64,
  (IdUInt32, IdUInt64): I32WrapI64,
  (IdUInt32, IdFloat32): I32TruncF32U,
  (IdUInt32, IdFloat64): I32TruncF64U,
  # (IdInt32, IdInt32): I32TruncSatF32S,
  # (IdInt32, IdInt32): I32TruncSatF32U,
  # (IdInt32, IdInt32): I32TruncSatF64S,
  # (IdInt32, IdInt32): I32TruncSatF64U,
  (IdInt64, IdInt32): I64ExtendI32S,
  (IdInt64, IdUInt32): I64ExtendI32U,
  (IdInt64, IdFloat32): I64TruncF32S,
  (IdInt64, IdFloat64): I64TruncF64S,

  (IdUInt64, IdInt32): I64ExtendI32S,
  (IdUInt64, IdUInt32): I64ExtendI32U,
  (IdUInt64, IdFloat32): I64TruncF32U,
  (IdUInt64, IdFloat64): I64TruncF64U,
  # (IdInt64, IdFloat32): I64TruncSatF32S,
  # (IdUInt64, IdFloat32): I64TruncSatF32U,
  # (IdInt64, IdFloat64): I64TruncSatF64S,
  # (IdUInt64, IdFloat64): I64TruncSatF64U,
  (IdFloat32, IdInt32): F32ConvertI32S,
  (IdFloat32, IdUInt32): F32ConvertI32U,
  (IdFloat32, IdInt64): F32ConvertI64S,
  (IdFloat32, IdUInt64): F32ConvertI64U,
  (IdFloat32, IdFloat64): F32DemoteF64,
  (IdFloat64, IdInt32): F64ConvertI32S,
  (IdFloat64, IdUInt32): F64ConvertI32U,
  (IdFloat64, IdInt64): F64ConvertI64S,
  (IdFloat64, IdUInt64): F64ConvertI64U,
  (IdFloat64, IdFloat32): F64PromoteF32,
  # (IdInt32, IdInt32): I32Extend8S,
  # (IdInt32, IdInt32): I32Extend16S,
  # (IdInt64, IdInt32): I64Extend8S,
  # (IdInt64, IdInt32): I64Extend16S,
  # (IdInt64, IdInt32): I64Extend32S,
}

let reinterpretOps = toTable {
  (IdInt32, IdFloat32): I32ReinterpretF32,
  (IdUInt32, IdFloat32): I32ReinterpretF32,
  (IdInt64, IdFloat64): I64ReinterpretF64,
  (IdUInt64, IdFloat64): I64ReinterpretF64,
  (IdFloat32, IdInt32): F32ReinterpretI32,
  (IdFloat32, IdUInt32): F32ReinterpretI32,
  (IdFloat64, IdInt64): F64ReinterpretI64,
  (IdFloat64, IdUInt64): F64ReinterpretI64,
}

proc genNodeBlock(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typ = self.ctx.computeType(node)
  let wasmValueType = self.toWasmValueType(typ)
  let (size, _, _) = self.getTypeAttributes(typ)

  # debugf"genNodeBlock: {node}, {dest}, {typ}, {wasmValueType}, {size}"

  let tempIdx = if dest.kind == Memory and size > 0: # store result pointer in local, and load again in block
    let tempIdx = self.getTempLocal(int32TypeInstance)
    self.instr(LocalSet, localIdx: tempIdx)
    tempIdx.some
  else:
    WasmLocalIdx.none

  let blockType = if dest.kind == Discard:
    WasmBlockType(kind: ValType, typ: WasmValueType.none)
  else:
    WasmBlockType(kind: ValType, typ: wasmValueType)

  self.genBlock(blockType):
    if tempIdx.getSome(tempIdx):
      self.instr(LocalGet, localIdx: tempIdx)

    self.genNodeChildren(node, IdBlockChildren, dest)

proc genNodeBinaryExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination, op32S: WasmInstrKind, op32U: WasmInstrKind, op64S: WasmInstrKind, op64U: WasmInstrKind, op32F: WasmInstrKind, op64F: WasmInstrKind) =
  let left = node.firstChild(IdBinaryExpressionLeft).getOr:
    return
  let right = node.firstChild(IdBinaryExpressionRight).getOr:
    return

  let leftType = self.ctx.computeType(left)
  let rightType = self.ctx.computeType(right)

  let commonType = self.ctx.getBiggerIntType(left, right)

  # debugf"genNodeBinaryExpression: {node}, {dest}, {leftType}, {rightType}, {commonType}, {op32S}"
  self.genNode(left, dest)
  if leftType.class != commonType.class and conversionOps.contains((commonType.class, leftType.class)):
    let op = conversionOps[(commonType.class, leftType.class)]
    self.currentExpr.instr.add WasmInstr(kind: op)

  self.genNode(right, dest)
  if rightType.class != commonType.class and conversionOps.contains((commonType.class, rightType.class)):
    let op = conversionOps[(commonType.class, rightType.class)]
    self.currentExpr.instr.add WasmInstr(kind: op)

  if commonType.class == IdInt32 or commonType.class == IdChar or commonType.class == IdPointerType:
    self.currentExpr.instr.add WasmInstr(kind: op32S)
  elif commonType.class == IdUInt32:
    self.currentExpr.instr.add WasmInstr(kind: op32U)
  elif commonType.class == IdInt64:
    self.currentExpr.instr.add WasmInstr(kind: op64S)
  elif commonType.class == IdUInt64:
    self.currentExpr.instr.add WasmInstr(kind: op64U)
  elif commonType.class == IdFloat32:
    self.currentExpr.instr.add WasmInstr(kind: op32F)
  elif commonType.class == IdFloat64:
    self.currentExpr.instr.add WasmInstr(kind: op64F)
  else:
    log lvlError, fmt"genNodeBinaryExpression: Type not implemented: {`$`(commonType, true)}"

proc genNodeBinaryAddExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32Add, I32Add, I64Add, I64Add, F32Add, F64Add)
  self.genStoreDestination(node, dest)

proc genNodeBinarySubExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32Sub, I32Sub, I64Sub, I64Sub, F32Sub, F64Sub)
  self.genStoreDestination(node, dest)

proc genNodeBinaryMulExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32Mul, I32Mul, I64Mul, I64Mul, F32Mul, F64Mul)
  self.genStoreDestination(node, dest)

proc genNodeBinaryDivExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32DivS, I32DivU, I64DivS, I64DivU, F32Div, F64Div)
  self.genStoreDestination(node, dest)

proc genNodeBinaryModExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32RemS, I32RemU, I64RemS, I64RemU, F32Div, F64Div)
  self.genStoreDestination(node, dest)

proc genNodeBinaryLessExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32LtS, I32LtU, I64LtS, I64LtU, F32Lt, F64Lt)
  self.genStoreDestination(node, dest)

proc genNodeBinaryLessEqualExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32LeS, I32LeU, I64LeS, I64LeU, F32Le, F64Le)
  self.genStoreDestination(node, dest)

proc genNodeBinaryGreaterExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32GtS, I32GtU, I64GtS, I64GtU, F32Gt, F64Gt)
  self.genStoreDestination(node, dest)

proc genNodeBinaryGreaterEqualExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32GeS, I32GeU, I64GeS, I64GeU, F32Ge, F64Ge)
  self.genStoreDestination(node, dest)

proc genNodeBinaryEqualExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32Eq, I32Eq, I64Eq, I64Eq, F32Eq, F64Eq)
  self.genStoreDestination(node, dest)

proc genNodeBinaryNotEqualExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32Ne, I32Ne, I64Ne, I64Ne, F32Ne, F64Ne)
  self.genStoreDestination(node, dest)

proc genNodeBinaryAndExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32And, I32And, I64And, I64And, F32Mul, F64Mul)
  self.genStoreDestination(node, dest)

proc genNodeBinaryOrExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32Or, I32Or, I64Or, I64Or, F32Add, F64Add)
  self.genStoreDestination(node, dest)

proc genNodeUnaryNegateExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typ = self.ctx.computeType(node)
  let (iConst, iSub) = if typ.class == IdInt32 or typ.class == IdUInt32:
    (WasmInstr(kind: I32Const, i32Const: 0), I32Sub)
  elif typ.class == IdInt64 or typ.class == IdUInt64:
    (WasmInstr(kind: I64Const, i64Const: 0), I64Sub)
  else:
    log lvlError, fmt"genNodeUnaryNegateExpression: Type not implemented: {`$`(typ, true)}"
    return

  self.currentExpr.instr.add iConst
  self.genNodeChildren(node, IdUnaryExpressionChild, Destination(kind: Stack))
  self.instr(iSub)
  self.genStoreDestination(node, dest)

proc genNodeUnaryNotExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typ = self.ctx.computeType(node)
  let (iConst, iSub) = if typ.class == IdInt32 or typ.class == IdUInt32:
    (WasmInstr(kind: I32Const, i32Const: 1), I32Sub)
  elif typ.class == IdInt64 or typ.class == IdUInt64:
    (WasmInstr(kind: I64Const, i64Const: 1), I64Sub)
  else:
    log lvlError, fmt"genNodeUnaryNegateExpression: Type not implemented: {`$`(typ, true)}"
    return

  self.currentExpr.instr.add iConst
  self.genNodeChildren(node, IdUnaryExpressionChild, Destination(kind: Stack))
  self.instr(iSub)
  self.genStoreDestination(node, dest)

proc genNodeIntegerLiteral(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let value = node.property(IdIntegerLiteralValue).get
  let typ = self.ctx.computeType(node)
  if typ.class == IdInt32 or typ.class == IdUInt32:
    self.instr(I32Const, i32Const: value.intValue.int32)
  elif typ.class == IdInt64 or typ.class == IdUInt64:
    self.instr(I64Const, i64Const: value.intValue.int64)
  else:
    log lvlError, fmt"genNodeIntegerLiteral: Type not implemented: {`$`(typ, true)}"

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
  let wasmType = self.toWasmValueType(typ)

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
    self.genNode(c, dest)
    # if wasmType.isNone:
      # log lvlError, fmt"drop {typ} -> {wasmType}"
      # self.genDrop(c)

  for i in countdown(ifStack.high, 0):
    let elseCase = self.currentExpr
    self.currentExpr = self.exprStack.pop
    self.instr(If, ifType: WasmBlockType(kind: ValType, typ: wasmType), ifThenInstr: move ifStack[i].instr, ifElseInstr: move elseCase.instr)

proc genNodeWhileExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typ = WasmValueType.none

  self.loopBranchIndices[node.id] = (breakIndex: 0, continueIndex: 1)

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

proc genNodeForLoop(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typ = WasmValueType.none

  let loopVariableNode = node.firstChild(IdForLoopVariable).getOr:
    log lvlError, fmt"No loop variable: {node}"
    return

  let loopStartNode = node.firstChild(IdForLoopStart).getOr:
    log lvlError, fmt"No loop start: {node}"
    return

  let loopEndNode = node.firstChild(IdForLoopEnd)

  let varType = self.ctx.computeType(loopVariableNode)
  let varTypeSize = self.getTypeAttributes(varType).size

  let offset = self.createStackLocal(loopVariableNode.id, varType)
  let loopEndLocalIndex = loopEndNode.mapIt(self.createLocal(it.id, varType, "loop_end"))

  self.loopBranchIndices[node.id] = (breakIndex: 0, continueIndex: 2)

  self.instr(LocalGet, localIdx: self.currentBasePointer)
  if offset > 0:
    self.instr(I32Const, i32Const: offset.int32)
    self.instr(I32Add)
  self.genNode(loopStartNode, Destination(kind: Memory, offset: 0, align: 0))

  if loopEndLocalIndex.getSome(localIndex):
    self.genNode(loopEndNode.get, Destination(kind: Stack))
    self.instr(LocalSet, localIdx: localIndex)

  # outer block for break
  self.genBlock WasmBlockType(kind: ValType, typ: typ):
    self.labelIndices[node.id] = self.exprStack.high

    # generate body in loop block
    self.genLoop WasmBlockType(kind: ValType, typ: typ):
      # condition if we have an end
      if loopEndLocalIndex.getSome(localIndex):
        self.instr(LocalGet, localIdx: self.currentBasePointer)

        if varTypeSize == 4:
          self.instr(I32Load, memArg: WasmMemArg(offset: offset.uint32, align: 0))
          self.instr(LocalGet, localIdx: localIndex)
          self.instr(I32GeS)
        elif varTypeSize == 8:
          self.instr(I64Load, memArg: WasmMemArg(offset: offset.uint32, align: 0))
          self.instr(LocalGet, localIdx: localIndex)
          self.instr(I64GeS)
        else:
          log lvlError, fmt"genNodeForLoop: Type not implemented: {`$`(varType, true)}"

        self.instr(BrIf, brLabelIdx: 1.WasmLabelIdx)

      self.genBlock WasmBlockType(kind: ValType, typ: typ):
        self.genNodeChildren(node, IdForLoopBody, Destination(kind: Discard))

      # increment counter
      self.instr(LocalGet, localIdx: self.currentBasePointer)
      self.instr(LocalGet, localIdx: self.currentBasePointer)

      if varTypeSize == 4:
        self.instr(I32Load, memArg: WasmMemArg(offset: offset.uint32, align: 0))
        self.instr(I32Const, i32Const: 1)
        self.instr(I32Add)
        self.instr(I32Store, memArg: WasmMemArg(offset: offset.uint32, align: 0))
      elif varTypeSize == 8:
        self.instr(I64Load, memArg: WasmMemArg(offset: offset.uint32, align: 0))
        self.instr(I64Const, i64Const: 1)
        self.instr(I64Add)
        self.instr(I64Store, memArg: WasmMemArg(offset: offset.uint32, align: 0))
      else:
        log lvlError, fmt"genNodeForLoop: Type not implemented: {`$`(varType, true)}"

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
    if offset > 0:
      self.instr(I32Const, i32Const: offset.int32)
      self.instr(I32Add)
    self.genNode(value, Destination(kind: Memory, offset: 0, align: 0))

  # self.instr(LocalTee, localIdx: index)

  assert dest.kind == Discard

proc genNodeVarDecl(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typ = self.ctx.computeType(node)
  let offset = self.createStackLocal(node.id, typ)
  # let index = self.createLocal(node.id, nil)

  if node.firstChild(IdVarDeclValue).getSome(value):
    self.instr(LocalGet, localIdx: self.currentBasePointer)
    if offset > 0:
      self.instr(I32Const, i32Const: offset.int32)
      self.instr(I32Add)
    self.genNode(value, Destination(kind: Memory, offset: 0, align: 0))

  # self.instr(LocalTee, localIdx: index)

  assert dest.kind == Discard

proc genNodeBreakExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  var parent = node.parent
  while parent.isNotNil and not parent.nodeClass.isSubclassOf(IdILoop):
    parent = parent.parent

  if parent.isNil:
    log lvlError, fmt"Break outside of loop"
    return

  let branchIndex = self.loopBranchIndices[parent.id].breakIndex
  self.genBranchLabel(parent, branchIndex)

proc genNodeContinueExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  var parent = node.parent
  while parent.isNotNil and not parent.nodeClass.isSubclassOf(IdILoop):
    parent = parent.parent

  if parent.isNil:
    log lvlError, fmt"Break outside of loop"
    return

  let branchIndex = self.loopBranchIndices[parent.id].continueIndex
  self.genBranchLabel(parent, branchIndex)

proc genNodeReturnExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  if self.passReturnAsOutParam:
    self.instr(LocalGet, localIdx: 0.WasmLocalIdx) # load return value address from first parameter
  self.genNodeChildren(node, IdReturnExpressionValue, self.returnValueDestination)
  let actualIndex = WasmLabelIdx(self.exprStack.high)
  self.instr(Br, brLabelIdx: actualIndex)

proc genNodeStringGetPointer(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeChildren(node, IdStringGetPointerValue, Destination(kind: Stack))
  self.instr(I32WrapI64)
  self.genStoreDestination(node, dest)

proc genNodeStringGetLength(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  self.genNodeChildren(node, IdStringGetLengthValue, Destination(kind: Stack))
  self.instr(I64Const, i64Const: 32)
  self.instr(I64ShrU)
  self.instr(I32WrapI64)
  self.genStoreDestination(node, dest)

proc genNodeCast(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let sourceType = self.ctx.computeType node.firstChild(IdCastValue).getOr do:
    return
  let targetType = self.ctx.getValue node.firstChild(IdCastType).getOr do:
    return

  self.genNodeChildren(node, IdCastValue, Destination(kind: Stack))

  if conversionOps.contains((targetType.class, sourceType.class)):
    let op = conversionOps[(targetType.class, sourceType.class)]
    self.currentExpr.instr.add WasmInstr(kind: op)

  self.genStoreDestination(node, dest)

proc genNodeEmptyLine(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  discard

proc genNodeNodeReference(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let id = node.reference(IdNodeReferenceTarget)
  if node.resolveReference(IdNodeReferenceTarget).getSome(target) and target.class == IdConstDecl:
    if target.firstChild(IdConstDeclValue).getSome(value) and value.class == IdFunctionDefinition:
      var name = target.property(IdINamedName).get.stringValue
      let (tableIdx, elemIndex) = self.getOrCreateFuncRef(value, name.some)
      self.instr(I32Const, i32Const: elemIndex)
      self.genStoreDestination(node, dest)
    else:
      self.genNodeChildren(target, IdConstDeclValue, dest)

    return

  if not self.localIndices.contains(id):
    log lvlError, fmt"Variable not found found in locals: {id}, from here {node}"
    return

  let typ = self.ctx.computeType(node)
  let (size, _, _) = self.getTypeAttributes(typ)

  case dest
  of Stack():
    case self.localIndices[id]:
    of Local(localIdx: @index):
      self.instr(LocalGet, localIdx: index)

    of LocalStackPointer(localIdx: @index):
      self.instr(LocalGet, localIdx: index)
      let memInstr = self.getTypeMemInstructions(typ)
      self.loadInstr(memInstr.load, 0, 0)

    of Stack(stackOffset: @offset):
      self.instr(LocalGet, localIdx: self.currentBasePointer)
      let memInstr = self.getTypeMemInstructions(typ)
      # debugf"load node ref {node} from satck with offset {offset}"
      self.loadInstr(memInstr.load, offset.uint32, 0)

  of Memory(offset: @offset, align: @align):
    case self.localIndices[id]:
    of Local(localIdx: @index):
      self.instr(LocalGet, localIdx: index)
      let memInstr = self.getTypeMemInstructions(typ)
      self.storeInstr(memInstr.store, offset, align)

    of LocalStackPointer(localIdx: @index):
      self.instr(LocalGet, localIdx: index)
      self.instr(I32Const, i32Const: size)
      self.instr(MemoryCopy)

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
    of LocalStackPointer(localIdx: @index):
      self.instr(LocalGet, localIdx: index)
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

    of LocalStackPointer(localIdx: @index):
      self.instr(LocalGet, localIdx: index)
      valueDest = Destination(kind: Memory, offset: 0, align: 0)

    of Stack(stackOffset: @offset):
      self.instr(LocalGet, localIdx: self.currentBasePointer)
      if offset > 0:
        self.instr(I32Const, i32Const: offset.int32)
        self.instr(I32Add)
      valueDest = Destination(kind: Memory, offset: 0, align: 0)

  else:
    self.genNode(targetNode, Destination(kind: LValue))
    valueDest = Destination(kind: Memory, offset: 0, align: 0)

  self.genNodeChildren(node, IdAssignmentValue, valueDest)

  if id.isSome:
    case self.localIndices[id.get]
    of Local(localIdx: @index):
      self.instr(LocalSet, localIdx: index)
    of LocalStackPointer():
      discard
    of Stack():
      discard

  assert dest.kind == Discard

proc genNodePrintExpression(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  for i, c in node.children(IdPrintArguments):
    self.genNode(c, Destination(kind: Stack))

    let typ = self.ctx.computeType(c)
    if typ.class == IdInt32:
      self.instr(Call, callFuncIdx: self.printI32)
    elif typ.class == IdUInt32:
      self.instr(Call, callFuncIdx: self.printU32)
    elif typ.class == IdInt64:
      self.instr(Call, callFuncIdx: self.printI64)
    elif typ.class == IdUInt64:
      self.instr(Call, callFuncIdx: self.printU64)
    elif typ.class == IdFloat32:
      self.instr(Call, callFuncIdx: self.printF32)
    elif typ.class == IdFloat64:
      self.instr(Call, callFuncIdx: self.printF64)
    elif typ.class == IdChar:
      self.instr(Call, callFuncIdx: self.printChar)
    elif typ.class == IdPointerType:
      self.instr(Call, callFuncIdx: self.printU32)
    elif typ.class == IdString:
      let tempIdx = self.getTempLocal(stringTypeInstance)
      self.instr(LocalTee, localIdx: tempIdx)
      self.instr(I32WrapI64) # pointer

      # length
      self.instr(LocalGet, localIdx: tempIdx)
      self.instr(I64Const, i64Const: 32)
      self.instr(I64ShrU)
      self.instr(I32WrapI64)

      self.instr(Call, callFuncIdx: self.printString)
    else:
      log lvlError, fmt"genNodePrintExpression: Type not implemented: {`$`(typ, true)}"

  self.instr(Call, callFuncIdx: self.printLine)

proc genToString(self: BaseLanguageWasmCompiler, typ: AstNode) =
  if typ.class == IdInt32:
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
        log lvlError, fmt"test: apply offset for return value (not really an error)"
        self.instr(I32Const, i32Const: offset.int32)
        self.instr(I32Add)
    of Discard(): discard
    of LValue(): return # todo error

  for i, c in node.children(IdCallArguments):
    let argType = self.ctx.computeType(c)
    if argType.class == IdType:
      continue

    let passByReference = self.shouldPassAsOutParamater(argType)
    let argDest = if passByReference:
      Destination(kind: LValue)
    else:
      Destination(kind: Stack)

    self.genNode(c, argDest)

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
      let functionType = self.ctx.computeType(funcExprNode)
      let typeIdx = self.getFunctionTypeIdx(functionType)
      self.instr(CallIndirect, callIndirectTableIdx: self.functionRefTableIdx, callIndirectTypeIdx: typeIdx)

  else: # not a node reference
    self.genNode(funcExprNode, Destination(kind: Stack))
    let functionType = self.ctx.computeType(funcExprNode)
    let typeIdx = self.getFunctionTypeIdx(functionType)
    self.instr(CallIndirect, callIndirectTableIdx: self.functionRefTableIdx, callIndirectTypeIdx: typeIdx)

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
  let structType = if typ.class == IdPointerType:
    typ.resolveReference(IdPointerTypeTarget).getOr:
      log lvlError, fmt"No target: {typ}"
      return
  else:
    typ

  # debugf"genNodeStructMemberAccessExpression {node}, {member}: {structType.dump(recurse=true)}"

  var offset = 0.int32
  var size = 0.int32
  var align = 0.int32

  var memberType: AstNode

  for k, memberDefinition in structType.children(IdStructDefinitionMembers):
    let currentMemberType = self.ctx.computeType(memberDefinition)
    let (memberSize, memberAlign, _) = self.getTypeAttributes(currentMemberType)

    offset = align(offset, memberAlign)

    let originalMember = memberDefinition.resolveOriginal(recurse=true).getOr:
      log lvlError, fmt"Original member not found: {memberDefinition}"
      return

    # echo &"calc member offset of {member}, {k}th member {memberDefinition}, prevOffset {prevOffset}, offset {offset}, size {memberSize}, align {memberAlign}\noriginal: {originalMember}"

    let originalMemberId = if originalMember.hasReference(IdStructTypeGenericMember):
      originalMember.reference(IdStructTypeGenericMember)
    else:
      originalMember.id

    if member.id == originalMemberId:
      size = memberSize
      align = memberAlign
      memberType = currentMemberType
      break
    offset += memberSize

  case dest
  of Memory(offset: @offset, align: @align):
    if offset > 0:
      self.instr(I32Const, i32Const: offset.int32)
      self.instr(I32Add)

  if typ.class == IdPointerType:
    self.genNode(valueNode, Destination(kind: Stack))
  else:
    self.genNode(valueNode, Destination(kind: LValue))

  case dest
  of Stack():
    # debugf"load member {member} from {valueNode}, offset {offset}"
    # debugf"{memberType}"
    let instr = self.getTypeMemInstructions(memberType).load
    self.loadInstr(instr, offset.uint32, 0)

  of Memory():
    if offset > 0: # todo: is this offset correct? Do we need that/is adding it after generating the value correct? We already add the offset above before generating the value
      log lvlWarn, "does this happen?"
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
    # debugf"copy {node} to stack destination, type {typ}, instr {instr}, offset 0"
    self.loadInstr(instr, 0, 0)

  of Memory():
    let typ = self.ctx.computeType(node)
    let (sourceSize, _, _) = self.getTypeAttributes(typ)
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
  let (size, _, _) = self.getTypeAttributes(typ)

  self.genNode(valueNode, Destination(kind: Stack))
  self.genNode(indexNode, Destination(kind: Stack))

  if size != 1:
    self.instr(I32Const, i32Const: size)
    self.instr(I32Mul)

  self.instr(I32Add)

  self.genCopyToDestination(node, dest)

proc genNodeAllocate(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  let typeNode = node.firstChild(IdAllocateType).getOr:
    log lvlError, fmt"No type: {node}"
    return

  let typ = self.ctx.getValue(typeNode)
  let (size, _, _) = self.getTypeAttributes(typ)

  self.instr(I32Const, i32Const: size)

  if node.firstChild(IdAllocateCount).getSome(countNode):
    self.genNode(countNode, Destination(kind: Stack))
    self.instr(I32Mul)

  self.instr(Call, callFuncIdx: self.allocFunc)
  self.genStoreDestination(node, dest)

proc computeStructTypeAttributes(self: BaseLanguageWasmCompiler, typ: AstNode): TypeAttributes =
  result.passReturnAsOutParam = true
  for _, memberNode in typ.children(IdStructDefinitionMembers):
    let memberType = self.ctx.computeType(memberNode)
    let (memberSize, memberAlign, _) = self.getTypeAttributes(memberType)
    result.size = align(result.size, memberAlign)
    result.size += memberSize
    result.align = max(result.align, memberAlign)
  return

proc genNodeFunctionDefinition(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  # let isGeneric = node.isGeneric(self.ctx)
  # debugf"gen function {node.dump(recurse=true)}, generic: {isGeneric}"

  let body = node.children(IdFunctionDefinitionBody)
  if body.len != 1:
    return

  # todo: should these resets be here?
  self.localIndices.clear
  self.currentLocals.setLen 0
  self.currentStackLocalsSize = 0

  let returnType = node.firstChild(IdFunctionDefinitionReturnType).mapIt(self.ctx.getValue(it)).get(voidTypeInstance)
  let passReturnAsOutParam = self.shouldPassAsOutParamater(returnType)

  if passReturnAsOutParam:
    self.localIndices[IdFunctionDefinitionReturnType.NodeId] = LocalVariable(kind: Local, localIdx: self.currentParamCount.WasmLocalIdx)
    inc self.currentParamCount

  for i, param in node.children(IdFunctionDefinitionParameters):
    let paramType = self.ctx.computeType(param)
    if paramType.class == IdType:
      continue

    let passByReference = self.shouldPassAsOutParamater(paramType)
    if passByReference:
      self.localIndices[param.id] = LocalVariable(kind: LocalStackPointer, localIdx: self.currentParamCount.WasmLocalIdx)
    else:
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

  self.returnValueDestination = destination
  self.passReturnAsOutParam = passReturnAsOutParam

  self.genNode(body[0], destination)

  let requiredStackSize: int32 = self.currentStackLocalsSize
  self.currentExpr.instr[stackSizeInstrIndex].i32Const = requiredStackSize

  # epilogue
  self.instr(LocalGet, localIdx: self.currentBasePointer)
  self.instr(I32Const, i32Const: requiredStackSize)
  self.instr(I32Add)
  self.instr(GlobalSet, globalIdx: self.stackPointer)

proc getFunctionInputOutput(self: BaseLanguageWasmCompiler, node: AstNode): tuple[inputs: seq[WasmValueType], outputs: seq[WasmValueType]] =
  for _, c in node.children(IdFunctionDefinitionReturnType):
    let typ = self.ctx.getValue(c)
    if self.shouldPassAsOutParamater(typ):
      result.inputs.add WasmValueType.I32
    elif typ.class != IdVoid:
      result.outputs.add self.toWasmValueType(typ).get

  for _, c in node.children(IdFunctionDefinitionParameters):
    let typ = self.ctx.computeType(c)
    if typ.class == IdType:
      continue
    if self.shouldPassAsOutParamater(typ):
      result.inputs.add WasmValueType.I32
    else:
      result.inputs.add self.toWasmValueType(typ).get

proc getFunctionTypeInputOutput(self: BaseLanguageWasmCompiler, node: AstNode): tuple[inputs: seq[WasmValueType], outputs: seq[WasmValueType]] =
  for _, typ in node.children(IdFunctionTypeReturnType):
    if self.shouldPassAsOutParamater(typ):
      result.inputs.add WasmValueType.I32
    elif typ.class != IdVoid:
      result.outputs.add self.toWasmValueType(typ).get

  for _, typ in node.children(IdFunctionTypeParameterTypes):
    if typ.class == IdType:
      continue
    if self.shouldPassAsOutParamater(typ):
      result.inputs.add WasmValueType.I32
    else:
      result.inputs.add self.toWasmValueType(typ).get

proc addBaseLanguage*(self: BaseLanguageWasmCompiler) =
  self.functionInputOutputComputer[IdFunctionDefinition] = getFunctionInputOutput
  self.functionInputOutputComputer[IdFunctionType] = getFunctionTypeInputOutput

  self.generators[IdFunctionDefinition] = genNodeFunctionDefinition
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
  self.generators[IdAnd] = genNodeBinaryAndExpression
  self.generators[IdOr] = genNodeBinaryOrExpression
  self.generators[IdNegate] = genNodeUnaryNegateExpression
  self.generators[IdNot] = genNodeUnaryNotExpression
  self.generators[IdIntegerLiteral] = genNodeIntegerLiteral
  self.generators[IdBoolLiteral] = genNodeBoolLiteral
  self.generators[IdStringLiteral] = genNodeStringLiteral
  self.generators[IdIfExpression] = genNodeIfExpression
  self.generators[IdWhileExpression] = genNodeWhileExpression
  self.generators[IdForLoop] = genNodeForLoop
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
  self.generators[IdReturnExpression] = genNodeReturnExpression
  self.generators[IdStringGetPointer] = genNodeStringGetPointer
  self.generators[IdStringGetLength] = genNodeStringGetLength
  self.generators[IdCast] = genNodeCast
  self.generators[IdEmptyLine] = genNodeEmptyLine

  self.wasmValueTypes[IdInt32] = (WasmValueType.I32, I32Load, I32Store) # int32
  self.wasmValueTypes[IdUInt32] = (WasmValueType.I32, I32Load, I32Store) # uint32
  self.wasmValueTypes[IdInt64] = (WasmValueType.I64, I64Load, I64Store) # int64
  self.wasmValueTypes[IdUInt64] = (WasmValueType.I64, I64Load, I64Store) # uint64
  self.wasmValueTypes[IdFloat32] = (WasmValueType.F32, F32Load, F32Store) # int64
  self.wasmValueTypes[IdFloat64] = (WasmValueType.F64, F64Load, F64Store) # uint64
  self.wasmValueTypes[IdChar] = (WasmValueType.I32, I32Load8U, I32Store8) # int32
  self.wasmValueTypes[IdPointerType] = (WasmValueType.I32, I32Load, I32Store) # pointer
  self.wasmValueTypes[IdString] = (WasmValueType.I64, I64Load, I64Store) # (len << 32) | ptr
  self.wasmValueTypes[IdFunctionType] = (WasmValueType.I32, I32Load, I32Store) # table index
  self.wasmValueTypes[IdFunctionDefinition] = (WasmValueType.I32, I32Load, I32Store) # table index

  self.typeAttributes[IdInt32] = (4'i32, 4'i32, false)
  self.typeAttributes[IdUInt32] = (4'i32, 4'i32, false)
  self.typeAttributes[IdInt64] = (8'i32, 4'i32, false)
  self.typeAttributes[IdUInt64] = (8'i32, 4'i32, false)
  self.typeAttributes[IdFloat32] = (4'i32, 4'i32, false)
  self.typeAttributes[IdFloat64] = (8'i32, 4'i32, false)
  self.typeAttributes[IdChar] = (1'i32, 1'i32, false)
  self.typeAttributes[IdPointerType] = (4'i32, 4'i32, false)
  self.typeAttributes[IdString] = (8'i32, 4'i32, false)
  self.typeAttributes[IdFunctionType] = (4'i32, 4'i32, false)
  self.typeAttributes[IdFunctionDefinition] = (4'i32, 4'i32, false)
  self.typeAttributes[IdVoid] = (0'i32, 1'i32, false)
  self.typeAttributeComputers[IdStructDefinition] = proc(typ: AstNode): TypeAttributes = self.computeStructTypeAttributes(typ)
