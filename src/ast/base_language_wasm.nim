
import std/[options, tables]
import id, model, ast_ids
import scripting/[wasm_builder]
import custom_logger, util

import print

logCategory "bl-wasm"

type
  BaseLanguageWasmCompiler* = ref object
    builder: WasmBuilder

    wasmFuncs: Table[Id, WasmFuncIdx]

    functionsToCompile: seq[(AstNode, WasmFuncIdx)]
    localIndices: Table[Id, WasmLocalIdx]
    globalIndices: Table[Id, WasmGlobalIdx]
    labelIndices: Table[Id, int] # Not the actual index

    exprStack: seq[WasmExpr]
    currentExpr: WasmExpr
    currentLocals: seq[WasmValueType]

    generators: Table[Id, proc(self: BaseLanguageWasmCompiler, node: AstNode)]

    printI32: WasmFuncIdx
    printLine: WasmFuncIdx

proc setupGenerators(self: BaseLanguageWasmCompiler)

proc newBaseLanguageWasmCompiler*(): BaseLanguageWasmCompiler =
  new result
  result.setupGenerators()
  result.builder = newWasmBuilder()

  result.builder.mems.add(WasmMem(typ: WasmMemoryType(limits: WasmLimits(min: 255))))

  discard result.builder.addFunction([I32], [I32], [], exportName="my_alloc".some, body=WasmExpr(instr: @[
    WasmInstr(kind: I32Const, i32Const: 0),
  ]))

  discard result.builder.addFunction([I32], [], [], exportName="my_dealloc".some, body=WasmExpr(instr: @[
      WasmInstr(kind: Nop),
  ]))

  result.printI32 = result.builder.addImport("env", "print_i32", result.builder.addType([I32], []))
  result.printLine = result.builder.addImport("env", "print_line", result.builder.addType([], []))

proc genNode*(self: BaseLanguageWasmCompiler, node: AstNode) =
  if self.generators.contains(node.class):
    let generator = self.generators[node.class]
    generator(self, node)
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

    for c in node.children(IdFunctionDefinitionParameters):
      let typ = c.children(IdParameterDeclType)[0]
      inputs.add typ.toWasmValueType

    for c in node.children(IdFunctionDefinitionReturnType):
      outputs.add c.toWasmValueType

    let funcIdx = self.builder.addFunction(inputs, outputs, exportName=exportName)
    self.wasmFuncs[node.id] = funcIdx
    self.functionsToCompile.add (node, funcIdx)

  return self.wasmFuncs[node.id]

proc compileFunction(self: BaseLanguageWasmCompiler, node: AstNode, funcIdx: WasmFuncIdx) =
  let body = node.children(IdFunctionDefinitionBody)
  if body.len != 1:
    return

  assert self.exprStack.len == 0
  self.currentExpr = WasmExpr()
  self.currentLocals.setLen 0

  self.genNode(body[0])

  self.builder.setBody(funcIdx, self.currentLocals, self.currentExpr)

proc compileRemainingFunctions(self: BaseLanguageWasmCompiler) =
  while self.functionsToCompile.len > 0:
    let function = self.functionsToCompile.pop
    self.compileFunction(function[0], function[1])

proc compileToBinary*(self: BaseLanguageWasmCompiler, node: AstNode): seq[uint8] =
  let functionName = $node.id
  discard self.getOrCreateWasmFunc(node, exportName=functionName.some)
  self.compileRemainingFunctions()

  print self.builder

  let binary = self.builder.generateBinary()
  return binary

import std/[macros, genasts]

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

proc genDrop(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.instr(Drop)
  # todo: size of node, stack

###################### Node Generators ##############################

proc genNodeBlock(self: BaseLanguageWasmCompiler, node: AstNode) =
  # self.exprStack.add self.currentExpr
  # self.currentExpr = WasmExpr()

  for i, c in node.children(IdBlockChildren):
    if i > 0:
      self.genDrop(c)
    self.genNode(c)

  # self.currentExpr = self.exprStack.pop

proc genNodeBinaryExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  for i, c in node.children(IdBinaryExpressionLeft):
    if i > 0:
      self.genDrop(c)
    self.genNode(c)

  for i, c in node.children(IdBinaryExpressionRight):
    if i > 0:
      self.genDrop(c)
    self.genNode(c)

proc genNodeBinaryAddExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.genNodeBinaryExpression(node)
  self.instr(I32Add)

proc genNodeBinarySubExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.genNodeBinaryExpression(node)
  self.instr(I32Sub)

proc genNodeBinaryMulExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.genNodeBinaryExpression(node)
  self.instr(I32Mul)

proc genNodeBinaryDivExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.genNodeBinaryExpression(node)
  self.instr(I32DivS)

proc genNodeBinaryModExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.genNodeBinaryExpression(node)
  self.instr(I32RemS)

proc genNodeBinaryLessExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.genNodeBinaryExpression(node)
  self.instr(I32LtS)

proc genNodeBinaryLessEqualExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.genNodeBinaryExpression(node)
  self.instr(I32LeS)

proc genNodeBinaryGreaterExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.genNodeBinaryExpression(node)
  self.instr(I32GtS)

proc genNodeBinaryGreaterEqualExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.genNodeBinaryExpression(node)
  self.instr(I32GeS)

proc genNodeBinaryEqualExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.genNodeBinaryExpression(node)
  self.instr(I32Eq)

proc genNodeBinaryNotEqualExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.genNodeBinaryExpression(node)
  self.instr(I32Ne)

proc genNodeIntegerLiteral(self: BaseLanguageWasmCompiler, node: AstNode) =
  let value = node.property(IdIntegerLiteralValue).get
  self.instr(I32Const, i32Const: value.intValue.int32)

proc genNodeBoolLiteral(self: BaseLanguageWasmCompiler, node: AstNode) =
  let value = node.property(IdBoolLiteralValue).get
  self.instr(I32Const, i32Const: value.boolValue.int32)

proc genNodeIfExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  var ifStack: seq[WasmExpr]

  let thenCases = node.children(IdIfExpressionThenCase)
  let elseCase = node.children(IdIfExpressionElseCase)

  let typ = if elseCase.len > 0:
    WasmValueType.I32.some
  else:
    WasmValueType.none

  for k, c in thenCases:
    # condition
    for i, c in c.children(IdThenCaseCondition):
      if i > 0: self.genDrop(c)
      self.genNode(c)

    # then case
    self.exprStack.add self.currentExpr
    self.currentExpr = WasmExpr()
    for i, c in c.children(IdThenCaseBody):
      if i > 0 and typ.isSome: self.genDrop(c)
      self.genNode(c)
      if typ.isNone: self.genDrop(c)

    ifStack.add self.currentExpr
    self.currentExpr = WasmExpr()

  self.instr(Nop)
  for i, c in elseCase:
    if i > 0 and typ.isSome: self.genDrop(c)
    self.genNode(c)
    if typ.isNone: self.genDrop(c)

  for i in countdown(ifStack.high, 0):
    let elseCase = self.currentExpr
    self.currentExpr = self.exprStack.pop
    self.instr(If, ifType: WasmBlockType(kind: ValType, typ: typ), ifThenInstr: move ifStack[i].instr, ifElseInstr: move elseCase.instr)

  if typ.isNone:
    self.instr(I32Const, i32Const: 0)

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

proc genNodeWhileExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  let condition = node.children(IdWhileExpressionCondition)
  let body = node.children(IdWhileExpressionBody)

  let typ = WasmValueType.none

  # outer block for break
  self.genBlock WasmBlockType(kind: ValType, typ: typ):
    self.labelIndices[node.id] = self.exprStack.high

    # generate body in loop block
    self.genLoop WasmBlockType(kind: ValType, typ: typ):

      # generate condition
      for i, c in condition:
        if i > 0: self.genDrop(c)
        self.genNode(c)

      # break block if condition is false
      self.instr(I32Eqz)
      self.instr(BrIf, brLabelIdx: 1.WasmLabelIdx)

      for i, c in body:
        self.genNode(c)
        self.genDrop(c)

      # continue loop
      self.instr(Br, brLabelIdx: 0.WasmLabelIdx)

  # Loop doesn't generate a value, but right now every node needs to produce an int32
  self.instr(I32Const, i32Const: 0)

proc createLocal(self: BaseLanguageWasmCompiler, id: Id, typ: RootRef): WasmLocalIdx =
  self.currentLocals.add(I32)
  result = self.currentLocals.high.WasmLocalIdx
  self.localIndices[id] = result

proc genNodeConstDecl(self: BaseLanguageWasmCompiler, node: AstNode) =
  let index = self.createLocal(node.id, nil)

  let values = node.children(IdConstDeclValue)
  assert values.len > 0
  self.genNode(values[0])

  self.instr(LocalTee, localIdx: index)

proc genNodeLetDecl(self: BaseLanguageWasmCompiler, node: AstNode) =
  let index = self.createLocal(node.id, nil)

  let values = node.children(IdLetDeclValue)
  assert values.len > 0
  self.genNode(values[0])

  self.instr(LocalTee, localIdx: index)

proc genNodeVarDecl(self: BaseLanguageWasmCompiler, node: AstNode) =
  let index = self.createLocal(node.id, nil)

  let values = node.children(IdVarDeclValue)
  assert values.len > 0
  self.genNode(values[0])

  self.instr(LocalTee, localIdx: index)

proc genNodeBreakExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  var parent = node.parent
  while parent.isNotNil and parent.class != IdWhileExpression:
    parent = parent.parent

  if parent.isNil:
    log lvlError, fmt"Break outside of loop"
    return

  self.genBranchLabel(parent, 0)

proc genNodeContinueExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  var parent = node.parent
  while parent.isNotNil and parent.class != IdWhileExpression:
    parent = parent.parent

  if parent.isNil:
    log lvlError, fmt"Break outside of loop"
    return

  self.genBranchLabel(parent, 1)

proc genNodeReturnExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  discard

proc genNodeNodeReference(self: BaseLanguageWasmCompiler, node: AstNode) =
  let id = node.reference(IdNodeReferenceTarget)
  if node.resolveReference(IdNodeReferenceTarget).getSome(target) and target.class == IdConstDecl:
    echo "const"
    for i, c in target.children(IdConstDeclValue):
      if i > 0: self.genDrop(c)
      self.genNode(c)

  else:
    if not self.localIndices.contains(id):
      log lvlError, fmt"Variable not found found in locals: {id}"
      return

    let index = self.localIndices[id]
    self.instr(LocalGet, localIdx: index)

proc genAssignmentExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  let targetNodes = node.children(IdAssignmentTarget)

  let id = if targetNodes[0].class == IdNodeReference:
    targetNodes[0].reference(IdNodeReferenceTarget)
  else:
    log lvlError, fmt"Assignment target not found: {targetNodes[0].class}"
    return

  if not self.localIndices.contains(id):
    log lvlError, fmt"Variable not found found in locals: {id}"
    return

  for i, c in node.children(IdAssignmentValue):
    if i > 0: self.genDrop(c)
    self.genNode(c)

  let index = self.localIndices[id]
  self.instr(LocalTee, localIdx: index)

proc genPrintExpression(self: BaseLanguageWasmCompiler, node: AstNode) =
  for i, c in node.children(IdPrintArguments):
    self.genNode(c)
    self.instr(Call, callFuncIdx: self.printI32)

  self.instr(Call, callFuncIdx: self.printLine)
  self.instr(I32Const, i32Const: 0)

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
  self.generators[IdIfExpression] = genNodeIfExpression
  self.generators[IdWhileExpression] = genNodeWhileExpression
  self.generators[IdConstDecl] = genNodeConstDecl
  self.generators[IdLetDecl] = genNodeLetDecl
  self.generators[IdVarDecl] = genNodeVarDecl
  self.generators[IdNodeReference] = genNodeNodeReference
  self.generators[IdAssignment] = genAssignmentExpression
  self.generators[IdBreakExpression] = genNodeBreakExpression
  self.generators[IdContinueExpression] = genNodeContinueExpression
  self.generators[IdPrint] = genPrintExpression