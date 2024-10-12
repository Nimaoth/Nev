import std/[macros, genasts, strformat]
import std/[options, tables]
import fusion/matching
import misc/[custom_logger, util]
import scripting/[wasm_builder]
import model, ast_ids, base_language, generator_wasm

{.push gcsafe.}

logCategory "base-language-wasm"

const conversionOps = toTable {
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

# let reinterpretOps = toTable {
#   (IdInt32, IdFloat32): I32ReinterpretF32,
#   (IdUInt32, IdFloat32): I32ReinterpretF32,
#   (IdInt64, IdFloat64): I64ReinterpretF64,
#   (IdUInt64, IdFloat64): I64ReinterpretF64,
#   (IdFloat32, IdInt32): F32ReinterpretI32,
#   (IdFloat32, IdUInt32): F32ReinterpretI32,
#   (IdFloat64, IdInt64): F64ReinterpretI64,
#   (IdFloat64, IdUInt64): F64ReinterpretI64,
# }

type BaseLanguageExtension = ref object of LanguageWasmCompilerExtension
  voidTypeInstance: AstNode
  int32TypeInstance: AstNode
  stringTypeInstance: AstNode
  nodeReferenceClass: NodeClass

proc genNodeBlock(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let typ = self.compiler.ctx.computeType(node)
  let wasmValueType = self.compiler.toWasmValueType(typ)
  let (size, _, _) = self.compiler.getTypeAttributes(typ)

  # debugf"genNodeBlock: {node}, {dest}, {typ}, {wasmValueType}, {size}"

  let tempIdx = if dest.kind == Memory and size > 0: # store result pointer in local, and load again in block
    let tempIdx = self.compiler.getTempLocal(self.int32TypeInstance)
    self.compiler.instr(LocalSet, localIdx: tempIdx)
    tempIdx.some
  else:
    WasmLocalIdx.none

  let blockType = if dest.kind == Discard:
    WasmBlockType(kind: ValType, typ: WasmValueType.none)
  else:
    WasmBlockType(kind: ValType, typ: wasmValueType)

  self.compiler.genBlock(blockType):
    if tempIdx.getSome(tempIdx):
      self.compiler.instr(LocalGet, localIdx: tempIdx)

    self.compiler.genNodeChildren(node, IdBlockChildren, dest)

proc genNodeBinaryExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination, op32S: WasmInstrKind, op32U: WasmInstrKind, op64S: WasmInstrKind, op64U: WasmInstrKind, op32F: WasmInstrKind, op64F: WasmInstrKind) =
  let left = node.firstChild(IdBinaryExpressionLeft).getOr:
    return
  let right = node.firstChild(IdBinaryExpressionRight).getOr:
    return

  let leftType = self.compiler.ctx.computeType(left)
  let rightType = self.compiler.ctx.computeType(right)

  let commonType = self.compiler.ctx.getBiggerIntType(left, right)

  # debugf"genNodeBinaryExpression: {node}, {dest}, {leftType}, {rightType}, {commonType}, {op32S}"
  self.compiler.genNode(left, dest)
  if leftType.class != commonType.class and conversionOps.contains((commonType.class, leftType.class)):
    let op = conversionOps[(commonType.class, leftType.class)]
    self.compiler.currentExpr.instr.add WasmInstr(kind: op)

  self.compiler.genNode(right, dest)
  if rightType.class != commonType.class and conversionOps.contains((commonType.class, rightType.class)):
    let op = conversionOps[(commonType.class, rightType.class)]
    self.compiler.currentExpr.instr.add WasmInstr(kind: op)

  if commonType.class == IdInt32 or commonType.class == IdChar or commonType.class == IdPointerType:
    self.compiler.currentExpr.instr.add WasmInstr(kind: op32S)
  elif commonType.class == IdUInt32:
    self.compiler.currentExpr.instr.add WasmInstr(kind: op32U)
  elif commonType.class == IdInt64:
    self.compiler.currentExpr.instr.add WasmInstr(kind: op64S)
  elif commonType.class == IdUInt64:
    self.compiler.currentExpr.instr.add WasmInstr(kind: op64U)
  elif commonType.class == IdFloat32:
    self.compiler.currentExpr.instr.add WasmInstr(kind: op32F)
  elif commonType.class == IdFloat64:
    self.compiler.currentExpr.instr.add WasmInstr(kind: op64F)
  else:
    log lvlError, fmt"genNodeBinaryExpression: Type not implemented: {`$`(commonType, true)}"

proc genNodeBinaryAddExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32Add, I32Add, I64Add, I64Add, F32Add, F64Add)
  self.compiler.genStoreDestination(node, dest)

proc genNodeBinarySubExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32Sub, I32Sub, I64Sub, I64Sub, F32Sub, F64Sub)
  self.compiler.genStoreDestination(node, dest)

proc genNodeBinaryMulExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32Mul, I32Mul, I64Mul, I64Mul, F32Mul, F64Mul)
  self.compiler.genStoreDestination(node, dest)

proc genNodeBinaryDivExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32DivS, I32DivU, I64DivS, I64DivU, F32Div, F64Div)
  self.compiler.genStoreDestination(node, dest)

proc genNodeBinaryModExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32RemS, I32RemU, I64RemS, I64RemU, F32Div, F64Div)
  self.compiler.genStoreDestination(node, dest)

proc genNodeBinaryLessExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32LtS, I32LtU, I64LtS, I64LtU, F32Lt, F64Lt)
  self.compiler.genStoreDestination(node, dest)

proc genNodeBinaryLessEqualExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32LeS, I32LeU, I64LeS, I64LeU, F32Le, F64Le)
  self.compiler.genStoreDestination(node, dest)

proc genNodeBinaryGreaterExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32GtS, I32GtU, I64GtS, I64GtU, F32Gt, F64Gt)
  self.compiler.genStoreDestination(node, dest)

proc genNodeBinaryGreaterEqualExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32GeS, I32GeU, I64GeS, I64GeU, F32Ge, F64Ge)
  self.compiler.genStoreDestination(node, dest)

proc genNodeBinaryEqualExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32Eq, I32Eq, I64Eq, I64Eq, F32Eq, F64Eq)
  self.compiler.genStoreDestination(node, dest)

proc genNodeBinaryNotEqualExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32Ne, I32Ne, I64Ne, I64Ne, F32Ne, F64Ne)
  self.compiler.genStoreDestination(node, dest)

proc genNodeBinaryAndExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32And, I32And, I64And, I64And, F32Mul, F64Mul)
  self.compiler.genStoreDestination(node, dest)

proc genNodeBinaryOrExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.genNodeBinaryExpression(node, Destination(kind: Stack), I32Or, I32Or, I64Or, I64Or, F32Add, F64Add)
  self.compiler.genStoreDestination(node, dest)

proc genNodeUnaryNegateExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let typ = self.compiler.ctx.computeType(node)
  let (iConst, iSub) = if typ.class == IdInt32 or typ.class == IdUInt32:
    (WasmInstr(kind: I32Const, i32Const: 0), I32Sub)
  elif typ.class == IdInt64 or typ.class == IdUInt64:
    (WasmInstr(kind: I64Const, i64Const: 0), I64Sub)
  else:
    log lvlError, fmt"genNodeUnaryNegateExpression: Type not implemented: {`$`(typ, true)}"
    return

  self.compiler.currentExpr.instr.add iConst
  self.compiler.genNodeChildren(node, IdUnaryExpressionChild, Destination(kind: Stack))
  self.compiler.instr(iSub)
  self.compiler.genStoreDestination(node, dest)

proc genNodeUnaryNotExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let typ = self.compiler.ctx.computeType(node)
  let (iConst, iSub) = if typ.class == IdInt32 or typ.class == IdUInt32:
    (WasmInstr(kind: I32Const, i32Const: 1), I32Sub)
  elif typ.class == IdInt64 or typ.class == IdUInt64:
    (WasmInstr(kind: I64Const, i64Const: 1), I64Sub)
  else:
    log lvlError, fmt"genNodeUnaryNegateExpression: Type not implemented: {`$`(typ, true)}"
    return

  self.compiler.currentExpr.instr.add iConst
  self.compiler.genNodeChildren(node, IdUnaryExpressionChild, Destination(kind: Stack))
  self.compiler.instr(iSub)
  self.compiler.genStoreDestination(node, dest)

proc genNodeIntegerLiteral(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let value = node.property(IdIntegerLiteralValue).get
  let typ = self.compiler.ctx.computeType(node)
  if typ.class == IdInt32 or typ.class == IdUInt32:
    self.compiler.instr(I32Const, i32Const: value.intValue.int32)
  elif typ.class == IdInt64 or typ.class == IdUInt64:
    self.compiler.instr(I64Const, i64Const: value.intValue.int64)
  else:
    log lvlError, fmt"genNodeIntegerLiteral: Type not implemented: {`$`(typ, true)}"

  self.compiler.genStoreDestination(node, dest)

proc genNodeBoolLiteral(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let value = node.property(IdBoolLiteralValue).get
  self.compiler.instr(I32Const, i32Const: value.boolValue.int32)
  self.compiler.genStoreDestination(node, dest)

proc genNodeStringLiteral(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let value = node.property(IdStringLiteralValue).get
  let address = self.compiler.addStringData(value.stringValue)
  self.compiler.instr(I32Const, i32Const: address)
  self.compiler.instr(I64ExtendI32U)
  self.compiler.instr(I64Const, i64Const: value.stringValue.len.int64 shl 32)
  self.compiler.instr(I64Or)
  self.compiler.genStoreDestination(node, dest)

proc genNodeIfExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  var ifStack: seq[WasmExpr]

  let thenCases = node.children(IdIfExpressionThenCase)
  let elseCase = node.children(IdIfExpressionElseCase)

  let typ = self.compiler.ctx.computeType(node)
  let wasmType = self.compiler.toWasmValueType(typ)

  for k, c in thenCases:
    # condition
    self.compiler.genNodeChildren(c, IdThenCaseCondition, Destination(kind: Stack))

    # then case
    self.compiler.exprStack.add self.compiler.currentExpr
    self.compiler.currentExpr = WasmExpr()

    self.compiler.genNodeChildren(c, IdThenCaseBody, dest)

    ifStack.add self.compiler.currentExpr
    self.compiler.currentExpr = WasmExpr()

  for i, c in elseCase:
    self.compiler.genNode(c, dest)
    # if wasmType.isNone:
      # log lvlError, fmt"drop {typ} -> {wasmType}"
      # self.compiler.genDrop(c)

  for i in countdown(ifStack.high, 0):
    let elseCase = self.compiler.currentExpr
    self.compiler.currentExpr = self.compiler.exprStack.pop
    self.compiler.instr(If, ifType: WasmBlockType(kind: ValType, typ: wasmType), ifThenInstr: move ifStack[i].instr, ifElseInstr: move elseCase.instr)

proc genNodeWhileExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let typ = WasmValueType.none

  self.compiler.loopBranchIndices[node.id] = (breakIndex: 0, continueIndex: 1)

  # outer block for break
  self.compiler.genBlock WasmBlockType(kind: ValType, typ: typ):
    self.compiler.labelIndices[node.id] = self.compiler.exprStack.high

    # generate body in loop block
    self.compiler.genLoop WasmBlockType(kind: ValType, typ: typ):

      # generate condition
      self.compiler.genNodeChildren(node, IdWhileExpressionCondition, Destination(kind: Stack))

      # break block if condition is false
      self.compiler.instr(I32Eqz)
      self.compiler.instr(BrIf, brLabelIdx: 1.WasmLabelIdx)

      self.compiler.genNodeChildren(node, IdWhileExpressionBody, Destination(kind: Discard))

      # continue loop
      self.compiler.instr(Br, brLabelIdx: 0.WasmLabelIdx)

proc genNodeForLoop(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let typ = WasmValueType.none

  let loopVariableNode = node.firstChild(IdForLoopVariable).getOr:
    log lvlError, fmt"No loop variable: {node}"
    return

  let loopStartNode = node.firstChild(IdForLoopStart).getOr:
    log lvlError, fmt"No loop start: {node}"
    return

  let loopEndNode = node.firstChild(IdForLoopEnd)

  let varType = self.compiler.ctx.computeType(loopVariableNode)
  let varTypeSize = self.compiler.getTypeAttributes(varType).size

  let offset = self.compiler.createStackLocal(loopVariableNode.id, varType)
  let loopEndLocalIndex = loopEndNode.mapIt(self.compiler.createLocal(it.id, varType, "loop_end"))

  self.compiler.loopBranchIndices[node.id] = (breakIndex: 0, continueIndex: 2)

  self.compiler.instr(LocalGet, localIdx: self.compiler.currentBasePointer)
  if offset > 0:
    self.compiler.instr(I32Const, i32Const: offset.int32)
    self.compiler.instr(I32Add)
  self.compiler.genNode(loopStartNode, Destination(kind: Memory, offset: 0, align: 0))

  if loopEndLocalIndex.getSome(localIndex):
    self.compiler.genNode(loopEndNode.get, Destination(kind: Stack))
    self.compiler.instr(LocalSet, localIdx: localIndex)

  # outer block for break
  self.compiler.genBlock WasmBlockType(kind: ValType, typ: typ):
    self.compiler.labelIndices[node.id] = self.compiler.exprStack.high

    # generate body in loop block
    self.compiler.genLoop WasmBlockType(kind: ValType, typ: typ):
      # condition if we have an end
      if loopEndLocalIndex.getSome(localIndex):
        self.compiler.instr(LocalGet, localIdx: self.compiler.currentBasePointer)

        if varTypeSize == 4:
          self.compiler.instr(I32Load, memArg: WasmMemArg(offset: offset.uint32, align: 0))
          self.compiler.instr(LocalGet, localIdx: localIndex)
          self.compiler.instr(I32GeS)
        elif varTypeSize == 8:
          self.compiler.instr(I64Load, memArg: WasmMemArg(offset: offset.uint32, align: 0))
          self.compiler.instr(LocalGet, localIdx: localIndex)
          self.compiler.instr(I64GeS)
        else:
          log lvlError, fmt"genNodeForLoop: Type not implemented: {`$`(varType, true)}"

        self.compiler.instr(BrIf, brLabelIdx: 1.WasmLabelIdx)

      self.compiler.genBlock WasmBlockType(kind: ValType, typ: typ):
        self.compiler.genNodeChildren(node, IdForLoopBody, Destination(kind: Discard))

      # increment counter
      self.compiler.instr(LocalGet, localIdx: self.compiler.currentBasePointer)
      self.compiler.instr(LocalGet, localIdx: self.compiler.currentBasePointer)

      if varTypeSize == 4:
        self.compiler.instr(I32Load, memArg: WasmMemArg(offset: offset.uint32, align: 0))
        self.compiler.instr(I32Const, i32Const: 1)
        self.compiler.instr(I32Add)
        self.compiler.instr(I32Store, memArg: WasmMemArg(offset: offset.uint32, align: 0))
      elif varTypeSize == 8:
        self.compiler.instr(I64Load, memArg: WasmMemArg(offset: offset.uint32, align: 0))
        self.compiler.instr(I64Const, i64Const: 1)
        self.compiler.instr(I64Add)
        self.compiler.instr(I64Store, memArg: WasmMemArg(offset: offset.uint32, align: 0))
      else:
        log lvlError, fmt"genNodeForLoop: Type not implemented: {`$`(varType, true)}"

      # continue loop
      self.compiler.instr(Br, brLabelIdx: 0.WasmLabelIdx)

proc genNodeConstDecl(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  # let index = self.compiler.createLocal(node.id, nil)

  # let values = node.children(IdConstDeclValue)
  # assert values.len > 0
  # self.compiler.genNode(values[0], dest)

  # self.compiler.instr(LocalTee, localIdx: index)

  assert dest.kind == Discard

proc genNodeLetDecl(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let typ = self.compiler.ctx.computeType(node)
  let offset = self.compiler.createStackLocal(node.id, typ)

  if node.firstChild(IdLetDeclValue).getSome(value):
    self.compiler.instr(LocalGet, localIdx: self.compiler.currentBasePointer)
    if offset > 0:
      self.compiler.instr(I32Const, i32Const: offset.int32)
      self.compiler.instr(I32Add)
    self.compiler.genNode(value, Destination(kind: Memory, offset: 0, align: 0))

  # self.compiler.instr(LocalTee, localIdx: index)

  assert dest.kind == Discard

proc genNodeVarDecl(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let typ = self.compiler.ctx.computeType(node)
  let offset = self.compiler.createStackLocal(node.id, typ)
  # let index = self.compiler.createLocal(node.id, nil)

  if node.firstChild(IdVarDeclValue).getSome(value):
    self.compiler.instr(LocalGet, localIdx: self.compiler.currentBasePointer)
    if offset > 0:
      self.compiler.instr(I32Const, i32Const: offset.int32)
      self.compiler.instr(I32Add)
    self.compiler.genNode(value, Destination(kind: Memory, offset: 0, align: 0))

  # self.compiler.instr(LocalTee, localIdx: index)

  assert dest.kind == Discard

proc genNodeBreakExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  var parent = node.parent
  while parent.isNotNil and not parent.nodeClass.isSubclassOf(IdILoop):
    parent = parent.parent

  if parent.isNil:
    log lvlError, fmt"Break outside of loop"
    return

  let branchIndex = self.compiler.loopBranchIndices[parent.id].breakIndex
  self.compiler.genBranchLabel(parent, branchIndex)

proc genNodeContinueExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  var parent = node.parent
  while parent.isNotNil and not parent.nodeClass.isSubclassOf(IdILoop):
    parent = parent.parent

  if parent.isNil:
    log lvlError, fmt"Break outside of loop"
    return

  let branchIndex = self.compiler.loopBranchIndices[parent.id].continueIndex
  self.compiler.genBranchLabel(parent, branchIndex)

proc genNodeReturnExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  if self.compiler.passReturnAsOutParam:
    self.compiler.instr(LocalGet, localIdx: 0.WasmLocalIdx) # load return value address from first parameter
  self.compiler.genNodeChildren(node, IdReturnExpressionValue, self.compiler.returnValueDestination)
  let actualIndex = WasmLabelIdx(self.compiler.exprStack.high)
  self.compiler.instr(Br, brLabelIdx: actualIndex)

proc genNodeStringGetPointer(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.compiler.genNodeChildren(node, IdStringGetPointerValue, Destination(kind: Stack))
  self.compiler.instr(I32WrapI64)
  self.compiler.genStoreDestination(node, dest)

proc genNodeStringGetLength(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  self.compiler.genNodeChildren(node, IdStringGetLengthValue, Destination(kind: Stack))
  self.compiler.instr(I64Const, i64Const: 32)
  self.compiler.instr(I64ShrU)
  self.compiler.instr(I32WrapI64)
  self.compiler.genStoreDestination(node, dest)

proc genNodeCast(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let sourceType = self.compiler.ctx.computeType node.firstChild(IdCastValue).getOr do:
    return
  let targetType = self.compiler.ctx.getValue node.firstChild(IdCastType).getOr do:
    return

  self.compiler.genNodeChildren(node, IdCastValue, Destination(kind: Stack))

  if conversionOps.contains((targetType.class, sourceType.class)):
    let op = conversionOps[(targetType.class, sourceType.class)]
    self.compiler.currentExpr.instr.add WasmInstr(kind: op)

  self.compiler.genStoreDestination(node, dest)

proc genNodeEmptyLine(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  discard

proc genNodeNodeReference(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let id = node.reference(IdNodeReferenceTarget)
  if node.resolveReference(IdNodeReferenceTarget).getSome(target) and target.class == IdConstDecl:
    if target.firstChild(IdConstDeclValue).getSome(value) and value.class == IdFunctionDefinition:
      var name = target.property(IdINamedName).get.stringValue
      let (_, elemIndex) = self.compiler.getOrCreateFuncRef(value, name.some)
      self.compiler.instr(I32Const, i32Const: elemIndex)
      self.compiler.genStoreDestination(node, dest)
    else:
      self.compiler.genNodeChildren(target, IdConstDeclValue, dest)

    return

  if not self.compiler.localIndices.contains(id):
    log lvlError, fmt"Variable not found found in locals: {id}, from here {node}"
    return

  let typ = self.compiler.ctx.computeType(node)
  let (size, _, _) = self.compiler.getTypeAttributes(typ)

  case dest
  of Stack():
    case self.compiler.localIndices[id]:
    of Local(localIdx: @index):
      self.compiler.instr(LocalGet, localIdx: index)

    of LocalStackPointer(localIdx: @index):
      self.compiler.instr(LocalGet, localIdx: index)
      let memInstr = self.compiler.getTypeMemInstructions(typ)
      self.compiler.loadInstr(memInstr.load, 0, 0)

    of Stack(stackOffset: @offset):
      self.compiler.instr(LocalGet, localIdx: self.compiler.currentBasePointer)
      let memInstr = self.compiler.getTypeMemInstructions(typ)
      # debugf"load node ref {node} from satck with offset {offset}"
      self.compiler.loadInstr(memInstr.load, offset.uint32, 0)

  of Memory(offset: @offset, align: @align):
    case self.compiler.localIndices[id]:
    of Local(localIdx: @index):
      self.compiler.instr(LocalGet, localIdx: index)
      let memInstr = self.compiler.getTypeMemInstructions(typ)
      self.compiler.storeInstr(memInstr.store, offset, align)

    of LocalStackPointer(localIdx: @index):
      self.compiler.instr(LocalGet, localIdx: index)
      self.compiler.instr(I32Const, i32Const: size)
      self.compiler.instr(MemoryCopy)

    of Stack(stackOffset: @offset):
      self.compiler.instr(LocalGet, localIdx: self.compiler.currentBasePointer)
      if offset > 0:
        self.compiler.instr(I32Const, i32Const: offset)
        self.compiler.instr(I32Add)
      self.compiler.instr(I32Const, i32Const: size)
      self.compiler.instr(MemoryCopy)

  of Discard():
    discard

  of LValue():
    case self.compiler.localIndices[id]:
    of Local(localIdx: @index):
      log lvlError, fmt"Can't get lvalue of local: {id}, from here {node}"
    of LocalStackPointer(localIdx: @index):
      self.compiler.instr(LocalGet, localIdx: index)
    of Stack(stackOffset: @offset):
      self.compiler.instr(LocalGet, localIdx: self.compiler.currentBasePointer)
      if offset > 0:
        self.compiler.instr(I32Const, i32Const: offset)
        self.compiler.instr(I32Add)

proc genAssignmentExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let targetNode = node.firstChild(IdAssignmentTarget).getOr:
    log lvlError, fmt"No assignment target for: {node}"
    return

  let id = if targetNode.class == IdNodeReference:
    targetNode.reference(IdNodeReferenceTarget).some
  else:
    NodeId.none

  var valueDest = Destination(kind: Stack)

  if id.isSome:
    if not self.compiler.localIndices.contains(id.get):
      log lvlError, fmt"Variable not found found in locals: {id.get}"
      return

    case self.compiler.localIndices[id.get]
    of Local(localIdx: @index):
      discard

    of LocalStackPointer(localIdx: @index):
      self.compiler.instr(LocalGet, localIdx: index)
      valueDest = Destination(kind: Memory, offset: 0, align: 0)

    of Stack(stackOffset: @offset):
      self.compiler.instr(LocalGet, localIdx: self.compiler.currentBasePointer)
      if offset > 0:
        self.compiler.instr(I32Const, i32Const: offset.int32)
        self.compiler.instr(I32Add)
      valueDest = Destination(kind: Memory, offset: 0, align: 0)

  else:
    self.compiler.genNode(targetNode, Destination(kind: LValue))
    valueDest = Destination(kind: Memory, offset: 0, align: 0)

  self.compiler.genNodeChildren(node, IdAssignmentValue, valueDest)

  if id.isSome:
    case self.compiler.localIndices[id.get]
    of Local(localIdx: @index):
      self.compiler.instr(LocalSet, localIdx: index)
    of LocalStackPointer():
      discard
    of Stack():
      discard

  assert dest.kind == Discard

proc genNodePrintExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  for i, c in node.children(IdPrintArguments):
    self.compiler.genNode(c, Destination(kind: Stack))

    let typ = self.compiler.ctx.computeType(c)
    if typ.class == IdInt32:
      self.compiler.instr(Call, callFuncIdx: self.compiler.printI32)
    elif typ.class == IdUInt32:
      self.compiler.instr(Call, callFuncIdx: self.compiler.printU32)
    elif typ.class == IdInt64:
      self.compiler.instr(Call, callFuncIdx: self.compiler.printI64)
    elif typ.class == IdUInt64:
      self.compiler.instr(Call, callFuncIdx: self.compiler.printU64)
    elif typ.class == IdFloat32:
      self.compiler.instr(Call, callFuncIdx: self.compiler.printF32)
    elif typ.class == IdFloat64:
      self.compiler.instr(Call, callFuncIdx: self.compiler.printF64)
    elif typ.class == IdChar:
      self.compiler.instr(Call, callFuncIdx: self.compiler.printChar)
    elif typ.class == IdPointerType:
      self.compiler.instr(Call, callFuncIdx: self.compiler.printU32)
    elif typ.class == IdString:
      let tempIdx = self.compiler.getTempLocal(self.stringTypeInstance)
      self.compiler.instr(LocalTee, localIdx: tempIdx)
      self.compiler.instr(I32WrapI64) # pointer

      # length
      self.compiler.instr(LocalGet, localIdx: tempIdx)
      self.compiler.instr(I64Const, i64Const: 32)
      self.compiler.instr(I64ShrU)
      self.compiler.instr(I32WrapI64)

      self.compiler.instr(Call, callFuncIdx: self.compiler.printString)
    else:
      log lvlError, fmt"genNodePrintExpression: Type not implemented: {`$`(typ, true)}"

  self.compiler.instr(Call, callFuncIdx: self.compiler.printLine)

proc genToString(self: BaseLanguageExtension, typ: AstNode) =
  if typ.class == IdInt32:
    let tempIdx = self.compiler.getTempLocal(typ)
    self.compiler.instr(Call, callFuncIdx: self.compiler.intToString)
    self.compiler.instr(LocalTee, localIdx: tempIdx)
    self.compiler.instr(I64ExtendI32U)
    self.compiler.instr(LocalGet, localIdx: tempIdx)
    self.compiler.instr(Call, callFuncIdx: self.compiler.strlen)
    self.compiler.instr(I64ExtendI32U)
    self.compiler.instr(I64Const, i64Const: 32)
    self.compiler.instr(I64Shl)
    self.compiler.instr(I64Or)
  else:
    self.compiler.instr(Drop)
    self.compiler.instr(I64Const, i64Const: 0)

proc genNodeBuildExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  for i, c in node.children(IdBuildArguments):
    self.compiler.genNode(c, Destination(kind: Stack))

    let typ = self.compiler.ctx.computeType(c)
    if typ.class != IdString:
      self.genToString(typ)

    if i > 0:
      self.compiler.instr(Call, callFuncIdx: self.compiler.buildString)

  self.compiler.genStoreDestination(node, dest)

proc genNodeCallExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =

  let funcExprNode = node.firstChild(IdCallFunction).getOr:
    log lvlError, fmt"No function specified for call {node}"
    return

  let returnType = self.compiler.ctx.computeType(node)
  let passReturnAsOutParam = self.compiler.shouldPassAsOutParamater(returnType)

  if passReturnAsOutParam:
    case dest
    of Stack(): return # todo error
    of Memory(offset: @offset):
      if offset > 0:
        log lvlError, fmt"test: apply offset for return value (not really an error)"
        self.compiler.instr(I32Const, i32Const: offset.int32)
        self.compiler.instr(I32Add)
    of Discard(): discard
    of LValue(): return # todo error

  for i, c in node.children(IdCallArguments):
    let argType = self.compiler.ctx.computeType(c)
    if argType.class == IdType:
      continue

    let passByReference = self.compiler.shouldPassAsOutParamater(argType)
    let argDest = if passByReference:
      Destination(kind: LValue)
    else:
      Destination(kind: Stack)

    self.compiler.genNode(c, argDest)

  if funcExprNode.class == IdNodeReference:
    let funcDeclNode = funcExprNode.resolveReference(IdNodeReferenceTarget).getOr:
      log lvlError, fmt"Function not found: {funcExprNode}"
      return

    if funcDeclNode.class == IdConstDecl:
      let funcDefNode = funcDeclNode.firstChild(IdConstDeclValue).getOr:
        log lvlError, fmt"No value: {funcDeclNode} in call {node}"
        return

      var name = funcDeclNode.property(IdINamedName).get.stringValue
      if funcDefNode.isGeneric(self.compiler.ctx):
        # generic call
        let concreteFunction = self.compiler.ctx.instantiateFunction(funcDefNode, node.children(IdCallArguments), self.nodeReferenceClass)
        let funcIdx = self.compiler.getOrCreateWasmFunc(concreteFunction, (name & $concreteFunction.id).some)
        self.compiler.instr(Call, callFuncIdx: funcIdx)

      else:
        # static call
        let funcIdx = self.compiler.getOrCreateWasmFunc(funcDefNode, name.some)
        self.compiler.instr(Call, callFuncIdx: funcIdx)

    else: # not a const decl, so call indirect
      self.compiler.genNode(funcExprNode, Destination(kind: Stack))
      let functionType = self.compiler.ctx.computeType(funcExprNode)
      let typeIdx = self.compiler.getFunctionTypeIdx(functionType)
      self.compiler.instr(CallIndirect, callIndirectTableIdx: self.compiler.functionRefTableIdx, callIndirectTypeIdx: typeIdx)

  else: # not a node reference
    self.compiler.genNode(funcExprNode, Destination(kind: Stack))
    let functionType = self.compiler.ctx.computeType(funcExprNode)
    let typeIdx = self.compiler.getFunctionTypeIdx(functionType)
    self.compiler.instr(CallIndirect, callIndirectTableIdx: self.compiler.functionRefTableIdx, callIndirectTypeIdx: typeIdx)

  let typ = self.compiler.ctx.computeType(node)
  if typ.class != IdVoid and not passReturnAsOutParam: # todo: should handlediscard here aswell even if passReturnAsOutParam
    self.compiler.genStoreDestination(node, dest)

proc genNodeStructMemberAccessExpression(self: BaseLanguageExtension, node: AstNode, dest: Destination) =

  let member = node.resolveReference(IdStructMemberAccessMember).getOr:
    log lvlError, fmt"Member not found: {node}"
    return

  let valueNode = node.firstChild(IdStructMemberAccessValue).getOr:
    log lvlError, fmt"No value: {node}"
    return

  let typ = self.compiler.ctx.computeType(valueNode)
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
    let currentMemberType = self.compiler.ctx.computeType(memberDefinition)
    let (memberSize, memberAlign, _) = self.compiler.getTypeAttributes(currentMemberType)

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
      self.compiler.instr(I32Const, i32Const: offset.int32)
      self.compiler.instr(I32Add)

  if typ.class == IdPointerType:
    self.compiler.genNode(valueNode, Destination(kind: Stack))
  else:
    self.compiler.genNode(valueNode, Destination(kind: LValue))

  case dest
  of Stack():
    # debugf"load member {member} from {valueNode}, offset {offset}"
    # debugf"{memberType}"
    let instr = self.compiler.getTypeMemInstructions(memberType).load
    self.compiler.loadInstr(instr, offset.uint32, 0)

  of Memory():
    if offset > 0: # todo: is this offset correct? Do we need that/is adding it after generating the value correct? We already add the offset above before generating the value
      log lvlWarn, "does this happen?"
      self.compiler.instr(I32Const, i32Const: offset.int32)
      self.compiler.instr(I32Add)
    self.compiler.instr(I32Const, i32Const: size)
    self.compiler.instr(MemoryCopy)

  of Discard():
    self.compiler.instr(Drop)

  of LValue():
    if offset > 0:
      self.compiler.instr(I32Const, i32Const: offset)
      self.compiler.instr(I32Add)

proc genNodeAddressOf(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let valueNode = node.firstChild(IdAddressOfValue).getOr:
    log lvlError, fmt"No value: {node}"
    return

  self.compiler.genNode(valueNode, Destination(kind: LValue))
  self.compiler.genStoreDestination(node, dest)

proc genNodeDeref(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let valueNode = node.firstChild(IdDerefValue).getOr:
    log lvlError, fmt"No value: {node}"
    return

  self.compiler.genNode(valueNode, Destination(kind: Stack))
  self.compiler.genCopyToDestination(node, dest)

proc genNodeArrayAccess(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let valueNode = node.firstChild(IdArrayAccessValue).getOr:
    log lvlError, fmt"No value: {node}"
    return

  let indexNode = node.firstChild(IdArrayAccessIndex).getOr:
    log lvlError, fmt"No index: {node}"
    return

  let typ = self.compiler.ctx.computeType(node)
  let (size, _, _) = self.compiler.getTypeAttributes(typ)

  self.compiler.genNode(valueNode, Destination(kind: Stack))
  self.compiler.genNode(indexNode, Destination(kind: Stack))

  if size != 1:
    self.compiler.instr(I32Const, i32Const: size)
    self.compiler.instr(I32Mul)

  self.compiler.instr(I32Add)

  self.compiler.genCopyToDestination(node, dest)

proc genNodeAllocate(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  let typeNode = node.firstChild(IdAllocateType).getOr:
    log lvlError, fmt"No type: {node}"
    return

  let typ = self.compiler.ctx.getValue(typeNode)
  let (size, _, _) = self.compiler.getTypeAttributes(typ)

  self.compiler.instr(I32Const, i32Const: size)

  if node.firstChild(IdAllocateCount).getSome(countNode):
    self.compiler.genNode(countNode, Destination(kind: Stack))
    self.compiler.instr(I32Mul)

  self.compiler.instr(Call, callFuncIdx: self.compiler.allocFunc)
  self.compiler.genStoreDestination(node, dest)

proc computeStructTypeAttributes(self: BaseLanguageExtension, typ: AstNode): TypeAttributes =
  result.passReturnAsOutParam = true
  for _, memberNode in typ.children(IdStructDefinitionMembers):
    let memberType = self.compiler.ctx.computeType(memberNode)
    let (memberSize, memberAlign, _) = self.compiler.getTypeAttributes(memberType)
    result.size = align(result.size, memberAlign)
    result.size += memberSize
    result.align = max(result.align, memberAlign)
  return

proc genNodeFunctionDefinition(self: BaseLanguageExtension, node: AstNode, dest: Destination) =
  # let isGeneric = node.isGeneric(self.compiler.ctx)
  # debugf"gen function {node.dump(recurse=true)}, generic: {isGeneric}"

  let body = node.children(IdFunctionDefinitionBody)
  if body.len != 1:
    return

  # todo: should these resets be here?
  self.compiler.localIndices.clear
  self.compiler.currentLocals.setLen 0
  self.compiler.currentStackLocalsSize = 0

  let returnType = node.firstChild(IdFunctionDefinitionReturnType).mapIt(self.compiler.ctx.getValue(it)).get(self.voidTypeInstance)
  let passReturnAsOutParam = self.compiler.shouldPassAsOutParamater(returnType)

  if passReturnAsOutParam:
    self.compiler.localIndices[IdFunctionDefinitionReturnType.NodeId] = LocalVariable(kind: Local, localIdx: self.compiler.currentParamCount.WasmLocalIdx)
    inc self.compiler.currentParamCount

  for i, param in node.children(IdFunctionDefinitionParameters):
    let paramType = self.compiler.ctx.computeType(param)
    if paramType.class == IdType:
      continue

    let passByReference = self.compiler.shouldPassAsOutParamater(paramType)
    if passByReference:
      self.compiler.localIndices[param.id] = LocalVariable(kind: LocalStackPointer, localIdx: self.compiler.currentParamCount.WasmLocalIdx)
    else:
      self.compiler.localIndices[param.id] = LocalVariable(kind: Local, localIdx: self.compiler.currentParamCount.WasmLocalIdx)
    inc self.compiler.currentParamCount

  self.compiler.currentBasePointer = (self.compiler.currentLocals.len + self.compiler.currentParamCount).WasmLocalIdx
  self.compiler.currentLocals.add((I32, "__base_pointer")) # base pointer

  let stackSizeInstrIndex = block: # prologue
    self.compiler.instr(GlobalGet, globalIdx: self.compiler.stackPointer)
    self.compiler.instr(I32Const, i32Const: 0) # size, patched at end when we know the size of locals
    let i = self.compiler.currentExpr.instr.high
    self.compiler.instr(I32Sub)
    self.compiler.instr(LocalTee, localIdx: self.compiler.currentBasePointer)
    self.compiler.instr(GlobalSet, globalIdx: self.compiler.stackPointer)
    i

  # check stack pointer
  self.compiler.instr(GlobalGet, globalIdx: self.compiler.stackPointer)
  self.compiler.instr(I32Const, i32Const: 0)
  self.compiler.instr(I32LeS)
  self.compiler.instr(If, ifType: WasmBlockType(kind: ValType, typ: WasmValueType.none),
    ifThenInstr: @[WasmInstr(kind: Unreachable)],
    ifElseInstr: @[])

  let destination = if returnType.class == IdVoid:
    Destination(kind: Discard)
  elif passReturnAsOutParam:
    self.compiler.instr(LocalGet, localIdx: 0.WasmLocalIdx) # load return value address from first parameter
    Destination(kind: Memory, offset: 0, align: 0)
  else:
    Destination(kind: Stack)

  self.compiler.returnValueDestination = destination
  self.compiler.passReturnAsOutParam = passReturnAsOutParam

  self.compiler.genNode(body[0], destination)

  let requiredStackSize: int32 = self.compiler.currentStackLocalsSize
  self.compiler.currentExpr.instr[stackSizeInstrIndex].i32Const = requiredStackSize

  # epilogue
  self.compiler.instr(LocalGet, localIdx: self.compiler.currentBasePointer)
  self.compiler.instr(I32Const, i32Const: requiredStackSize)
  self.compiler.instr(I32Add)
  self.compiler.instr(GlobalSet, globalIdx: self.compiler.stackPointer)

proc getFunctionInputOutput(self: BaseLanguageExtension, node: AstNode): tuple[inputs: seq[WasmValueType], outputs: seq[WasmValueType]] =
  for _, c in node.children(IdFunctionDefinitionReturnType):
    let typ = self.compiler.ctx.getValue(c)
    if self.compiler.shouldPassAsOutParamater(typ):
      result.inputs.add WasmValueType.I32
    elif typ.class != IdVoid:
      result.outputs.add self.compiler.toWasmValueType(typ).get

  for _, c in node.children(IdFunctionDefinitionParameters):
    let typ = self.compiler.ctx.computeType(c)
    if typ.class == IdType:
      continue
    if self.compiler.shouldPassAsOutParamater(typ):
      result.inputs.add WasmValueType.I32
    else:
      result.inputs.add self.compiler.toWasmValueType(typ).get

proc getFunctionTypeInputOutput(self: BaseLanguageExtension, node: AstNode): tuple[inputs: seq[WasmValueType], outputs: seq[WasmValueType]] =
  for _, typ in node.children(IdFunctionTypeReturnType):
    if self.compiler.shouldPassAsOutParamater(typ):
      result.inputs.add WasmValueType.I32
    elif typ.class != IdVoid:
      result.outputs.add self.compiler.toWasmValueType(typ).get

  for _, typ in node.children(IdFunctionTypeParameterTypes):
    if typ.class == IdType:
      continue
    if self.compiler.shouldPassAsOutParamater(typ):
      result.inputs.add WasmValueType.I32
    else:
      result.inputs.add self.compiler.toWasmValueType(typ).get

proc getFunctionImportInputOutput(self: BaseLanguageExtension, node: AstNode): tuple[inputs: seq[WasmValueType], outputs: seq[WasmValueType]] =
  if node.firstChild(IdFunctionImportType).getSome(typeNode):
    let typ = self.compiler.ctx.getValue(typeNode)
    return self.getFunctionTypeInputOutput(typ)

proc getFunctionDefinitionIndex(self: BaseLanguageExtension, node: AstNode, exportName: Option[string], inputs: seq[WasmValueType], outputs: seq[WasmValueType]): WasmFuncIdx =
  let funcIdx = self.compiler.builder.addFunction(inputs, outputs, exportName=exportName)
  self.compiler.functionsToCompile.add (node, funcIdx)
  return funcIdx

proc getFunctionImportIndex(self: BaseLanguageExtension, node: AstNode, exportName: Option[string], inputs: seq[WasmValueType], outputs: seq[WasmValueType]): WasmFuncIdx =
  let name = node.property(IdFunctionImportName).get.stringValue
  return self.compiler.builder.addImport("base", name, self.compiler.builder.addType(inputs, outputs))

proc addBaseLanguage*(self: BaseLanguageWasmCompiler) {.raises: [].} =
  let ext = BaseLanguageExtension()
  ext.voidTypeInstance = self.repository.getNode(IdVoidTypeInstance).get
  ext.int32TypeInstance = self.repository.getNode(IdInt32TypeInstance).get
  ext.stringTypeInstance = self.repository.getNode(IdStringTypeInstance).get
  ext.nodeReferenceClass = self.repository.resolveClass(IdNodeReference)

  self.addExtension(ext)

  ext.addFunctionInputOutput(IdFunctionDefinition, getFunctionInputOutput)
  ext.addFunctionInputOutput(IdFunctionType, getFunctionTypeInputOutput)
  ext.addFunctionInputOutput(IdFunctionImport, getFunctionImportInputOutput)

  ext.addFunctionConstructor(IdFunctionDefinition, getFunctionDefinitionIndex)
  ext.addFunctionConstructor(IdFunctionImport, getFunctionImportIndex)

  ext.addGenerator(IdFunctionDefinition, genNodeFunctionDefinition)
  ext.addGenerator(IdBlock, genNodeBlock)
  ext.addGenerator(IdAdd, genNodeBinaryAddExpression)
  ext.addGenerator(IdSub, genNodeBinarySubExpression)
  ext.addGenerator(IdMul, genNodeBinaryMulExpression)
  ext.addGenerator(IdDiv, genNodeBinaryDivExpression)
  ext.addGenerator(IdMod, genNodeBinaryModExpression)
  ext.addGenerator(IdLess, genNodeBinaryLessExpression)
  ext.addGenerator(IdLessEqual, genNodeBinaryLessEqualExpression)
  ext.addGenerator(IdGreater, genNodeBinaryGreaterExpression)
  ext.addGenerator(IdGreaterEqual, genNodeBinaryGreaterEqualExpression)
  ext.addGenerator(IdEqual, genNodeBinaryEqualExpression)
  ext.addGenerator(IdNotEqual, genNodeBinaryNotEqualExpression)
  ext.addGenerator(IdAnd, genNodeBinaryAndExpression)
  ext.addGenerator(IdOr, genNodeBinaryOrExpression)
  ext.addGenerator(IdNegate, genNodeUnaryNegateExpression)
  ext.addGenerator(IdNot, genNodeUnaryNotExpression)
  ext.addGenerator(IdIntegerLiteral, genNodeIntegerLiteral)
  ext.addGenerator(IdBoolLiteral, genNodeBoolLiteral)
  ext.addGenerator(IdStringLiteral, genNodeStringLiteral)
  ext.addGenerator(IdIfExpression, genNodeIfExpression)
  ext.addGenerator(IdWhileExpression, genNodeWhileExpression)
  ext.addGenerator(IdForLoop, genNodeForLoop)
  ext.addGenerator(IdConstDecl, genNodeConstDecl)
  ext.addGenerator(IdLetDecl, genNodeLetDecl)
  ext.addGenerator(IdVarDecl, genNodeVarDecl)
  ext.addGenerator(IdNodeReference, genNodeNodeReference)
  ext.addGenerator(IdAssignment, genAssignmentExpression)
  ext.addGenerator(IdBreakExpression, genNodeBreakExpression)
  ext.addGenerator(IdContinueExpression, genNodeContinueExpression)
  ext.addGenerator(IdPrint, genNodePrintExpression)
  ext.addGenerator(IdBuildString, genNodeBuildExpression)
  ext.addGenerator(IdCall, genNodeCallExpression)
  ext.addGenerator(IdStructMemberAccess, genNodeStructMemberAccessExpression)
  ext.addGenerator(IdAddressOf, genNodeAddressOf)
  ext.addGenerator(IdDeref, genNodeDeref)
  ext.addGenerator(IdArrayAccess, genNodeArrayAccess)
  ext.addGenerator(IdAllocate, genNodeAllocate)
  ext.addGenerator(IdReturnExpression, genNodeReturnExpression)
  ext.addGenerator(IdStringGetPointer, genNodeStringGetPointer)
  ext.addGenerator(IdStringGetLength, genNodeStringGetLength)
  ext.addGenerator(IdCast, genNodeCast)
  ext.addGenerator(IdEmptyLine, genNodeEmptyLine)

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

  ext.addTypeAttributes(IdInt32, 4'i32, 4'i32)
  ext.addTypeAttributes(IdUInt32, 4'i32, 4'i32)
  ext.addTypeAttributes(IdInt64, 8'i32, 4'i32)
  ext.addTypeAttributes(IdUInt64, 8'i32, 4'i32)
  ext.addTypeAttributes(IdFloat32, 4'i32, 4'i32)
  ext.addTypeAttributes(IdFloat64, 8'i32, 4'i32)
  ext.addTypeAttributes(IdChar, 1'i32, 1'i32)
  ext.addTypeAttributes(IdPointerType, 4'i32, 4'i32)
  ext.addTypeAttributes(IdString, 8'i32, 4'i32)
  ext.addTypeAttributes(IdFunctionType, 4'i32, 4'i32)
  ext.addTypeAttributes(IdFunctionDefinition, 4'i32, 4'i32)
  ext.addTypeAttributes(IdVoid, 0'i32, 1'i32)
  ext.addTypeAttributeComputer(IdStructDefinition, computeStructTypeAttributes)
