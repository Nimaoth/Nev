import std/[macros, genasts]
import std/[options, tables]
import fusion/matching
import misc/[id, custom_logger, util]
import scripting/[wasm_builder]
import model

{.push gcsafe.}
{.push raises: [].}
{.push hint[XCannotRaiseY]:off.}

logCategory "generator-wasm"

type
  LocalVariableStorage* = enum Local, Stack, LocalStackPointer
  LocalVariable* = object
    case kind*: LocalVariableStorage
    of Local, LocalStackPointer: localIdx*: WasmLocalIdx
    of Stack: stackOffset*: int32

  DestinationStorage* = enum Stack, Memory, Discard, LValue
  Destination* = object
    case kind*: DestinationStorage
    of Stack: discard
    of Memory:
      offset*: uint32 # todo: remove?
      align*: uint32
    of Discard: discard
    of LValue: discard

  TypeAttributes* = tuple[size: int32, align: int32, passReturnAsOutParam: bool]
  WasmTypeAttributes* = tuple[typ: WasmValueType, load: WasmInstrKind, store: WasmInstrKind]

  TypeAttributeComputer* = proc(self: LanguageWasmCompilerExtension, typ: AstNode): TypeAttributes {.gcsafe, raises: [CatchableError].}
  GeneratorFunc* = proc(self: LanguageWasmCompilerExtension, node: AstNode, dest: Destination) {.gcsafe, raises: [CatchableError].}
  FunctionInputOutputComputer* = proc(self: LanguageWasmCompilerExtension, node: AstNode): tuple[inputs: seq[WasmValueType], outputs: seq[WasmValueType]] {.gcsafe, raises: [CatchableError].}
  FunctionConstructorComputer* = proc(self: LanguageWasmCompilerExtension, node: AstNode, exportName: Option[string], inputs: seq[WasmValueType], outputs: seq[WasmValueType]): WasmFuncIdx {.gcsafe, raises: [CatchableError].}

  BaseLanguageWasmCompiler* = ref object
    builder*: WasmBuilder

    ctx*: ModelComputationContextBase
    repository*: Repository

    wasmFuncs: Table[NodeId, WasmFuncIdx]

    functionsToCompile*: seq[(AstNode, WasmFuncIdx)]
    localIndices*: Table[NodeId, LocalVariable]
    globalIndices*: Table[NodeId, WasmGlobalIdx]
    labelIndices*: Table[NodeId, int] # Not the actual index
    wasmValueTypes*: Table[ClassId, WasmTypeAttributes]
    typeAttributes*: Table[ClassId, TypeAttributes]
    typeAttributeComputers*: Table[ClassId, tuple[ext: LanguageWasmCompilerExtension, gen: TypeAttributeComputer]]
    functionInputOutputComputer*: Table[ClassId, tuple[ext: LanguageWasmCompilerExtension, gen: FunctionInputOutputComputer]]
    functionConstructors*: Table[ClassId, tuple[ext: LanguageWasmCompilerExtension, gen: FunctionConstructorComputer]]

    loopBranchIndices*: Table[NodeId, tuple[breakIndex: int, continueIndex: int]]
    functionTableIndices*: Table[NodeId, (WasmTableIdx, int32)]
    functionRefIndices: seq[WasmFuncIdx]
    functionRefTableIdx: WasmTableIdx

    exprStack*: seq[WasmExpr]
    currentExpr*: WasmExpr
    currentLocals*: seq[tuple[typ: WasmValueType, id: string]]
    currentParamCount*: int32
    currentStackLocals*: seq[int32]
    currentStackLocalsSize*: int32

    returnValueDestination*: Destination
    passReturnAsOutParam*: bool

    genDebugCode: bool

    generators*: Table[ClassId, tuple[ext: LanguageWasmCompilerExtension, gen: GeneratorFunc]]
    extensions: seq[LanguageWasmCompilerExtension]

    # imported
    printI32: WasmFuncIdx
    printU32: WasmFuncIdx
    printI64: WasmFuncIdx
    printU64: WasmFuncIdx
    printF32: WasmFuncIdx
    printF64: WasmFuncIdx
    printChar: WasmFuncIdx
    printString: WasmFuncIdx
    printLine: WasmFuncIdx
    intToString: WasmFuncIdx

    # implemented inline
    buildString: WasmFuncIdx
    strlen: WasmFuncIdx
    allocFunc: WasmFuncIdx
    cstrToInternal*: WasmFuncIdx

    stackSize: int32
    activeDataOffset: int32

    stackBase: WasmGlobalIdx
    stackEnd: WasmGlobalIdx
    stackPointer: WasmGlobalIdx

    currentBasePointer*: WasmLocalIdx

    memoryBase: WasmGlobalIdx
    tableBase: WasmGlobalIdx
    heapBase: WasmGlobalIdx
    heapSize: WasmGlobalIdx

    globalData: seq[uint8]

  LanguageWasmCompilerExtension* = ref object of RootObj
    compiler*: BaseLanguageWasmCompiler

method genNode*(self: LanguageWasmCompilerExtension, node: AstNode, dest: Destination) {.raises: [CatchableError].} =
  discard

proc compileFunction*(self: BaseLanguageWasmCompiler, node: AstNode, funcIdx: WasmFuncIdx) {.raises: [CatchableError].}
proc getOrCreateWasmFunc*(self: BaseLanguageWasmCompiler, node: AstNode, exportName: Option[string] = string.none): WasmFuncIdx
proc compileRemainingFunctions*(self: BaseLanguageWasmCompiler) {.raises: [CatchableError].}

proc newBaseLanguageWasmCompiler*(repository: Repository, ctx: ModelComputationContextBase): BaseLanguageWasmCompiler =
  new result
  result.builder = newWasmBuilder()
  result.repository = repository
  result.ctx = ctx

  result.builder.mems.add(WasmMem(typ: WasmMemoryType(limits: WasmLimits(min: 255))))

  result.builder.addExport("memory", 0.WasmMemIdx)
  result.functionRefTableIdx = result.builder.addTable()
  result.builder.addExport("__indirect_function_table", result.functionRefTableIdx)
  result.stackSize = wasmPageSize * 10
  result.activeDataOffset = align(result.stackSize, wasmPageSize)

  result.printI32 = result.builder.addImport("env", "print_i32", result.builder.addType([I32], []))
  result.printU32 = result.builder.addImport("env", "print_u32", result.builder.addType([I32], []))
  result.printI64 = result.builder.addImport("env", "print_i64", result.builder.addType([I64], []))
  result.printU64 = result.builder.addImport("env", "print_u64", result.builder.addType([I64], []))
  result.printF32 = result.builder.addImport("env", "print_f32", result.builder.addType([F32], []))
  result.printF64 = result.builder.addImport("env", "print_f64", result.builder.addType([F64], []))
  result.printChar = result.builder.addImport("env", "print_char", result.builder.addType([I32], []))
  result.printString = result.builder.addImport("env", "print_string", result.builder.addType([I32, I32], []))
  result.printLine = result.builder.addImport("env", "print_line", result.builder.addType([], []))
  result.intToString = result.builder.addImport("env", "intToString", result.builder.addType([I32], [I32]))

  result.stackBase = result.builder.addGlobal(I32, mut=true, 0, id="__stack_base")
  result.stackEnd = result.builder.addGlobal(I32, mut=true, 0, id="__stack_end")
  result.stackPointer = result.builder.addGlobal(I32, mut=true, result.stackSize, id="__stack_pointer")
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

    # check/grow memory size
    WasmInstr(kind: MemorySize),
    WasmInstr(kind: I32Const, i32Const: wasmPageSize),
    WasmInstr(kind: I32Mul),
    WasmInstr(kind: GlobalGet, globalIdx: result.heapBase),
    WasmInstr(kind: GlobalGet, globalIdx: result.heapSize),
    WasmInstr(kind: I32Add),
    WasmInstr(kind: I32LeS),
    WasmInstr(kind: If, ifType: WasmBlockType(kind: ValType, typ: WasmValueType.none),
      ifThenInstr: @[
        WasmInstr(kind: LocalGet, localIdx: 0.WasmLocalIdx),
        WasmInstr(kind: I32Const, i32Const: wasmPageSize),
        WasmInstr(kind: I32DivS),
        WasmInstr(kind: I32Const, i32Const: 1),
        WasmInstr(kind: I32Add),
        WasmInstr(kind: MemoryGrow),
        WasmInstr(kind: I32Const, i32Const: -1),
        WasmInstr(kind: I32Eq),
        WasmInstr(kind: If, ifType: WasmBlockType(kind: ValType, typ: WasmValueType.none),
          ifThenInstr: @[
            WasmInstr(kind: Unreachable),
          ],
          ifElseInstr: @[]),
      ],
      ifElseInstr: @[]),
  ]))

  discard result.builder.addFunction([I32], [], [], exportName="my_dealloc".some, body=WasmExpr(instr: @[
      WasmInstr(kind: Nop),
  ]))

  discard result.builder.addFunction([I32], [I32], [], exportName="stackAlloc".some, body=WasmExpr(instr: @[
      WasmInstr(kind: GlobalGet, globalIdx: result.stackPointer),
      WasmInstr(kind: LocalGet, localIdx: 0.WasmLocalIdx),
      WasmInstr(kind: I32Sub),
      WasmInstr(kind: I32Const, i32Const: -16),
      WasmInstr(kind: I32And),
      WasmInstr(kind: LocalTee, localIdx: 0.WasmLocalIdx),
      WasmInstr(kind: GlobalSet, globalIdx: result.stackPointer),
      WasmInstr(kind: LocalGet, localIdx: 0.WasmLocalIdx),
  ]))

  discard result.builder.addFunction([], [I32], [], exportName="stackSave".some, body=WasmExpr(instr: @[
      WasmInstr(kind: GlobalGet, globalIdx: result.stackPointer),
  ]))

  discard result.builder.addFunction([I32], [], [], exportName="stackRestore".some, body=WasmExpr(instr: @[
      WasmInstr(kind: LocalGet, localIdx: 0.WasmLocalIdx),
      WasmInstr(kind: GlobalSet, globalIdx: result.stackPointer),
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

  # cstrToInternal
  block:
    let param = 0.WasmLocalIdx
    result.cstrToInternal = result.builder.addFunction([I32], [I64], [], body=WasmExpr(instr: @[
      WasmInstr(kind: LocalGet, localIdx: param),
      WasmInstr(kind: I64ExtendI32U),

      WasmInstr(kind: LocalGet, localIdx: param),
      WasmInstr(kind: Call, callFuncIdx: result.strlen),
      WasmInstr(kind: I64ExtendI32U),

      WasmInstr(kind: I64Const, i64Const: 32),
      WasmInstr(kind: I64Shl),
      WasmInstr(kind: I64Or),
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

proc addFunctionToCompile*(self: BaseLanguageWasmCompiler, node: AstNode) =
  let functionName = $node.id
  discard self.getOrCreateWasmFunc(node, exportName=functionName.some)

proc compileToBinary*(self: BaseLanguageWasmCompiler): seq[uint8] {.raises: [CatchableError].} =
  self.compileRemainingFunctions()

  let activeDataSize = self.globalData.len.int32
  discard self.builder.addActiveData(0.WasmMemIdx, self.activeDataOffset, self.globalData)

  let heapBase = align(self.activeDataOffset + activeDataSize, wasmPageSize)
  self.builder.globals[self.heapBase.int].init = WasmInstr(kind: I32Const, i32Const: heapBase)

  self.builder.getTable(self.functionRefTableIdx).typ.limits.min = self.functionRefIndices.len.uint32

  if self.functionRefIndices.len > 0:
    self.builder.addFunctionElements("function pointers", self.functionRefTableIdx, self.functionRefIndices)

  # debugf"{self.builder}"

  try:
    {.gcsafe.}:
      if not self.builder.validate(false):
        log(lvlError, "Wasm validation failed")
        # discard self.builder.validate(true)
  except:
    log lvlError, &"Failed to validate: {getCurrentExceptionMsg()}"

  let binary = self.builder.generateBinary()
  return binary

proc compileRemainingFunctions*(self: BaseLanguageWasmCompiler) {.raises: [CatchableError].} =
  while self.functionsToCompile.len > 0:
    let function = self.functionsToCompile.pop
    self.compileFunction(function[0], function[1])

proc addImport*(self: BaseLanguageWasmCompiler, id: Id, env: string, name: string, inputs: openArray[WasmValueType], outputs: openArray[WasmValueType]) =
  self.wasmFuncs[id.NodeId] = self.builder.addImport(env, name, self.builder.addType(inputs, outputs))

proc addExtension*(self: BaseLanguageWasmCompiler, ext: LanguageWasmCompilerExtension) {.raises: [].} =
  self.extensions.add(ext)
  ext.compiler = self

proc addFunctionInputOutput*[T: LanguageWasmCompilerExtension](self: T, id: ClassId,
    gen: proc(self: T, node: AstNode):
      tuple[inputs: seq[WasmValueType], outputs: seq[WasmValueType]] {.nimcall, gcsafe, raises: [CatchableError].}
    ) {.raises: [].} =
  proc wrapper(self: LanguageWasmCompilerExtension, node: AstNode): tuple[inputs: seq[WasmValueType], outputs: seq[WasmValueType]] {.gcsafe, raises: [CatchableError].} =
    gen(self.T, node)

  self.compiler.functionInputOutputComputer[id] = (self, wrapper)

proc addFunctionConstructor*[T: LanguageWasmCompilerExtension](self: T, id: ClassId,
    gen: proc(self: T, node: AstNode, exportName: Option[string], inputs: seq[WasmValueType],
      outputs: seq[WasmValueType]): WasmFuncIdx {.gcsafe, raises: [CatchableError].}) {.raises: [].} =
  proc wrapper(self: LanguageWasmCompilerExtension, node: AstNode, exportName: Option[string], inputs: seq[WasmValueType],
      outputs: seq[WasmValueType]): WasmFuncIdx {.gcsafe, raises: [CatchableError].} =
    gen(self.T, node, exportName, inputs, outputs)
  self.compiler.functionConstructors[id] = (self, wrapper)

proc addGenerator*[T: LanguageWasmCompilerExtension](self: T, id: ClassId,
    gen: proc(self: T, node: AstNode, dest: Destination) {.gcsafe, raises: [CatchableError].}) {.raises: [].} =
  proc wrapper(self: LanguageWasmCompilerExtension, node: AstNode, dest: Destination) {.gcsafe, raises: [CatchableError].} =
    gen(self.T, node, dest)
  self.compiler.generators[id] = (self, wrapper)

proc addTypeAttributes*(self: LanguageWasmCompilerExtension, id: ClassId,
    size: int32, align: int32, passReturnAsOutParam: bool = false) {.raises: [].} =
  self.compiler.typeAttributes[id] = (size, align, passReturnAsOutParam)

proc addTypeAttributeComputer*[T: LanguageWasmCompilerExtension](self: T, id: ClassId,
    gen: proc(self: T, typ: AstNode): TypeAttributes {.gcsafe, raises: [CatchableError].}) {.raises: [].} =
  proc wrapper(self: LanguageWasmCompilerExtension, node: AstNode): TypeAttributes {.gcsafe, raises: [CatchableError].} =
    gen(self.T, node)
  self.compiler.typeAttributeComputers[id] = (self, wrapper)

proc genNode*(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) {.raises: [CatchableError].} =
  self.generators.withValue(node.class, val):
    val[].gen(val[].ext, node, dest)
  do:
    let class = node.nodeClass
    log(lvlWarn, fmt"genNode: Node class not implemented: {class.name}")

proc toWasmValueType*(self: BaseLanguageWasmCompiler, typ: AstNode): Option[WasmValueType] =
  if self.wasmValueTypes.contains(typ.class):
    return self.wasmValueTypes[typ.class].typ.some
  # log lvlError, fmt"toWasmValueType: Type not implemented: {`$`(typ, true)}"
  return WasmValueType.none

proc getTypeAttributes*(self: BaseLanguageWasmCompiler, typ: AstNode): TypeAttributes {.raises: [CatchableError].} =
  self.typeAttributes.withValue(typ.class, val):
    return val[]
  self.typeAttributeComputers.withValue(typ.class, val):
    return val[].gen(val[].ext, typ)
  return (0, 1, false)

proc shouldPassAsOutParamater*(self: BaseLanguageWasmCompiler, typ: AstNode): bool {.raises: [CatchableError].} =
  let (size, _, passReturnAsOutParam) = self.getTypeAttributes(typ)
  if passReturnAsOutParam:
    return true
  if size > 8:
    return true
  return false

proc getTypeMemInstructions*(self: BaseLanguageWasmCompiler, typ: AstNode): tuple[load: WasmInstrKind, store: WasmInstrKind] =
  if self.wasmValueTypes.contains(typ.class):
    let (_, load, store) = self.wasmValueTypes[typ.class]
    return (load, store)

  log lvlError, fmt"getTypeMemInstructions: Type not implemented: {`$`(typ, true)}"
  assert false
  return (Nop, Nop)

proc getWasmFunc*(self: BaseLanguageWasmCompiler, id: Id): WasmFuncIdx =
  if not self.wasmFuncs.contains(id.NodeId):
    return 0.WasmFuncIdx
  return self.wasmFuncs[id.NodeId]

proc getFunctionTypeIdx*(self: BaseLanguageWasmCompiler, node: AstNode): WasmTypeIdx {.raises: [CatchableError].} =
  self.functionInputOutputComputer.withValue(node.class, val):
    let (inputs, outputs) = val[].gen(val[].ext, node)
    return self.builder.getFunctionTypeIdx(inputs, outputs)

  log lvlError, fmt"getFunctionTypeIdx: Function not implemented: {`$`(node, true)}"
  return 0.WasmTypeIdx

proc getOrCreateWasmFunc*(self: BaseLanguageWasmCompiler, node: AstNode, exportName: Option[string] = string.none): WasmFuncIdx =
  self.wasmFuncs.withValue(node.id, val):
    return val[]

  # debugf"getOrCreateWasmFunc {exportName}: {node}"
  self.functionInputOutputComputer.withValue(node.class, val):
    self.functionConstructors.withValue(node.class, val2):
      try:
        let (inputs, outputs) = val[].gen(val[].ext, node)
        let f: FunctionConstructorComputer = val2[].gen
        let funcIdx = f(val2[].ext, node, exportName, inputs, outputs)
        self.wasmFuncs[node.id] = funcIdx
        return funcIdx
      except CatchableError as e:
        log lvlError, &"getOrCreateWasmFunc: Failed to create wasm function: {e.msg}\n{`$`(node, true)}"
        return 0.WasmFuncIdx

    log lvlError, fmt"getOrCreateWasmFunc: Function constructor not implemented: {`$`(node, true)}"
    return 0.WasmFuncIdx

  log lvlError, fmt"getOrCreateWasmFunc: Function IO not implemented: {`$`(node, true)}"
  return 0.WasmFuncIdx

proc getOrCreateFuncRef*(self: BaseLanguageWasmCompiler, node: AstNode, exportName: Option[string] = string.none): (WasmTableIdx, int32) =
  if not self.functionTableIndices.contains(node.id):
    self.functionTableIndices[node.id] = (self.functionRefTableIdx, self.functionRefIndices.len.int32)
    self.functionRefIndices.add self.getOrCreateWasmFunc(node, exportName=exportName)
  return self.functionTableIndices[node.id]

proc createLocal*(self: BaseLanguageWasmCompiler, id: NodeId, typ: AstNode, name: string): WasmLocalIdx =
  if self.toWasmValueType(typ).getSome(wasmType):
    result = (self.currentLocals.len + self.currentParamCount).WasmLocalIdx
    self.currentLocals.add((wasmType, name))
    self.localIndices[id] = LocalVariable(kind: Local, localIdx: result)

proc createStackLocal*(self: BaseLanguageWasmCompiler, id: NodeId, typ: AstNode): int32 {.raises: [CatchableError].} =
  let (size, alignment, _) = self.getTypeAttributes(typ)

  self.currentStackLocalsSize = self.currentStackLocalsSize.align(alignment)
  result = self.currentStackLocalsSize

  self.currentStackLocals.add(self.currentStackLocalsSize)
  # debugf"createStackLocal size {size}, alignment {alignment}, offset {self.currentStackLocalsSize}"

  self.localIndices[id] = LocalVariable(kind: Stack, stackOffset: self.currentStackLocalsSize)

  self.currentStackLocalsSize += size

proc getTempLocal*(self: BaseLanguageWasmCompiler, typ: AstNode): WasmLocalIdx =
  if self.localIndices.contains(typ.id):
    return self.localIndices[typ.id].localIdx

  return self.createLocal(typ.id, typ, fmt"__temp_{typ.id}")

proc addStringData*(self: BaseLanguageWasmCompiler, value: string): int32 =
  let offset = self.globalData.len.int32
  self.globalData.add(value.toOpenArrayByte(0, value.high))
  self.globalData.add(0)

  result = offset + self.activeDataOffset

macro instr*(self: WasmExpr, op: WasmInstrKind, args: varargs[untyped]): untyped =
  result = genAst(self, op):
    self.instr.add WasmInstr(kind: op)
  for arg in args:
    result[1].add arg

macro instr*(self: BaseLanguageWasmCompiler, op: WasmInstrKind, args: varargs[untyped]): untyped =
  result = genAst(self, op):
    self.currentExpr.instr.add WasmInstr(kind: op)
  for arg in args:
    result[1].add arg

proc genDup*(self: BaseLanguageWasmCompiler, typ: AstNode) =
  let tempIdx = self.getTempLocal(typ)
  self.instr(LocalTee, localIdx: tempIdx)
  self.instr(LocalGet, localIdx: tempIdx)

proc storeInstr*(self: BaseLanguageWasmCompiler, op: WasmInstrKind, offset: uint32, align: uint32) =
  # debugf"storeInstr {op}, offset {offset}, align {align}"
  assert op in {I32Store, I64Store, F32Store, F64Store, I32Store8, I64Store8, I32Store16, I64Store16, I64Store32}
  var instr = WasmInstr(kind: op)
  instr.memArg = WasmMemArg(offset: offset, align: align)
  self.currentExpr.instr.add instr

proc loadInstr*(self: BaseLanguageWasmCompiler, op: WasmInstrKind, offset: uint32, align: uint32) =
  # debugf"loadInstr {op}, offset {offset}, align {align}"
  assert op in {I32Load, I64Load, F32Load, F64Load, I32Load8U, I32Load8S, I64Load8U, I64Load8S, I32Load16U, I32Load16S, I64Load16U, I64Load16S, I64Load32U, I64Load32S}
  var instr = WasmInstr(kind: op)
  instr.memArg = WasmMemArg(offset: offset, align: align)
  self.currentExpr.instr.add instr

proc compileFunction*(self: BaseLanguageWasmCompiler, node: AstNode, funcIdx: WasmFuncIdx) {.raises: [CatchableError].} =
  assert self.exprStack.len == 0
  self.currentExpr = WasmExpr()
  self.currentLocals.setLen 0
  self.currentParamCount = 0.int32
  self.genNode(node, Destination(kind: Discard))
  self.builder.setBody(funcIdx, self.currentLocals, self.currentExpr)

proc genDrop*(self: BaseLanguageWasmCompiler, node: AstNode) =
  self.instr(Drop)
  # todo: size of node, stack

proc genStoreDestination*(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) {.raises: [CatchableError].} =
  case dest
  of Stack(): discard
  of Memory(offset: @offset, align: @align):
    let typ = self.ctx.computeType(node)
    let instr = self.getTypeMemInstructions(typ).store
    self.storeInstr(instr, offset, align)
  of Discard():
    self.genDrop(node)

proc genNodeChildren*(self: BaseLanguageWasmCompiler, node: AstNode, role: RoleId, dest: Destination) {.raises: [CatchableError].} =
  let count = node.childCount(role)
  for i, c in node.children(role):
    let childDest = if i == count - 1:
      dest
    else:
      Destination(kind: Discard)

    self.genNode(c, childDest)

###################### Node Generators ##############################

template genNested*(self: BaseLanguageWasmCompiler, body: untyped): untyped =
  self.exprStack.add self.currentExpr
  self.currentExpr = WasmExpr()

  try:
    body
  finally:
    let bodyExpr = self.currentExpr
    self.currentExpr = self.exprStack.pop
    self.instr(Loop, loopType: typ, loopInstr: move bodyExpr.instr)

template genBlock*(self: BaseLanguageWasmCompiler, typ: WasmBlockType, body: untyped): untyped =
  self.exprStack.add self.currentExpr
  self.currentExpr = WasmExpr()

  try:
    body
  finally:
    let bodyExpr = self.currentExpr
    self.currentExpr = self.exprStack.pop
    self.instr(Block, blockType: typ, blockInstr: move bodyExpr.instr)

template genLoop*(self: BaseLanguageWasmCompiler, typ: WasmBlockType, body: untyped): untyped =
  self.exprStack.add self.currentExpr
  self.currentExpr = WasmExpr()

  try:
    body
  finally:
    let bodyExpr = self.currentExpr
    self.currentExpr = self.exprStack.pop
    self.instr(Loop, loopType: typ, loopInstr: move bodyExpr.instr)

proc genBranchLabel*(self: BaseLanguageWasmCompiler, node: AstNode, offset: int) =
  assert self.labelIndices.contains(node.id)
  let index = self.labelIndices[node.id]
  let actualIndex = WasmLabelIdx(self.exprStack.high - index - offset)
  self.instr(Br, brLabelIdx: actualIndex)

proc genCopyToDestination*(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) {.raises: [CatchableError].} =
  case dest
  of Stack():
    let typ = self.ctx.computeType(node)
    let instr = self.getTypeMemInstructions(typ).load
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
