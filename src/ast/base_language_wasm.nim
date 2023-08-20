
import std/[options, tables]
import id, types, ast_ids
import scripting/[wasm_builder]
import custom_logger

logCategory "bl-wasm"

type
  BaseLanguageWasmCompiler* = ref object
    builder: WasmBuilder

    wasmFuncs: Table[Id, WasmFuncIdx]

    functionsToCompile: seq[(AstNode, WasmFuncIdx)]
    localIndices: Table[Id, WasmLocalIdx]
    globalIndices: Table[Id, WasmGlobalIdx]

    exprStack: seq[WasmExpr]
    currentExpr: WasmExpr
    currentLocals: seq[WasmValueType]

    generators: Table[Id, proc(self: BaseLanguageWasmCompiler, node: AstNode)]

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

  result.builder.imports.add(WasmImport(
    module: "env",
    name: "test",
    desc: WasmImportDesc(kind: Func, funcTypeIdx: 1.WasmTypeIdx)
  ))

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
  let funcIdx = self.getOrCreateWasmFunc(node, exportName="test".some)
  self.compileRemainingFunctions()

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

###################### Node Generators ##############################

proc genDrop(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.instr(Drop)
  # todo: size of node, stack

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

proc genNodeIntegerLiteral(self: BaseLanguageWasmCompiler, node: AstNode) =
  let value = node.property(IdIntegerLiteralValue).get
  self.instr(I32Const, i32Const: value.intValue.int32)

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

proc setupGenerators(self: BaseLanguageWasmCompiler) =
  self.generators[IdBlock] = genNodeBlock
  self.generators[IdAdd] = genNodeBinaryAddExpression
  self.generators[IdSub] = genNodeBinarySubExpression
  self.generators[IdMul] = genNodeBinaryMulExpression
  self.generators[IdDiv] = genNodeBinaryDivExpression
  self.generators[IdMod] = genNodeBinaryModExpression
  self.generators[IdIntegerLiteral] = genNodeIntegerLiteral
  self.generators[IdIfExpression] = genNodeIfExpression