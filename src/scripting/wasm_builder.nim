import std/[macrocache, json, options, tables, strutils, strformat, sequtils]
import binary_encoder
import util
import custom_logger

logCategory "wasm-builder"

type
  WasmTypeIdx* = distinct uint32
  WasmFuncIdx* = distinct uint32
  WasmTableIdx* = distinct uint32
  WasmMemIdx* = distinct uint32
  WasmGlobalIdx* = distinct uint32
  WasmElemIdx* = distinct uint32
  WasmDataIdx* = distinct uint32
  WasmLocalIdx* = distinct uint32
  WasmLabelIdx* = distinct uint32

  WasmValueType* {.pure.} = enum I32 = "i32", I64 = "i64", F32 = "f32", F64 = "f64", V128 = "v128", FuncRef = "funcref", ExternRef = "externref"
  WasmRefType* = WasmValueType

  WasmResultType* = object
    types*: seq[WasmValueType]

  WasmLimits* = object
    min*: uint32
    max*: Option[uint32]

  WasmFunctionType* = object
    input*: WasmResultType
    output*: WasmResultType

  WasmTableType* = object
    limits*: WasmLimits
    refType*: WasmRefType

  WasmGlobalType* = object
    mut*: bool
    typ*: WasmValueType

  WasmMemoryType* = object
    limits*: WasmLimits

  WasmExternTypeKind* {.pure.} = enum FuncType, TableType, MemType, GlobalType
  WasmExternType* = object
    case kind*: WasmExternTypeKind
    of FuncType:
      funcType*: WasmFunctionType
    of TableType:
      tableType*: WasmTableType
    of MemType:
      memType*: WasmMemoryType
    of GlobalType:
      globalType*: WasmGlobalType

  WasmInstrKind* {.pure.} = enum
    # Control Instructions https://webassembly.github.io/spec/core/syntax/instructions.html
    Unreachable = 0x00, Nop, Block, Loop, If,
    Br = 0x0C, BrIf, BrTable, Return, Call, CallIndirect,
    Drop = 0x1A, Select, # SelectWithArg
    LocalGet = 0x20, LocalSet, LocalTee, GlobalGet, GlobalSet,
    TableGet = 0x25, TableSet,
    I32Load = 0x28, I64Load, F32Load, F64Load,
    I32Load8S = 0x2C, I32Load8U, I32Load16S, I32Load16U, I64Load8S, I64Load8U, I64Load16S, I64Load16U, I64Load32S, I64Load32U,
    I32Store = 0x36, I64Store, F32Store, F64Store,
    I32Store8 = 0x3A, I32Store16, I64Store8, I64Store16, I64Store32,
    MemorySize = 0x3F, MemoryGrow,
    I32Const = 0x41, I64Const, F32Const, F64Const,
    I32Eqz = 0x45,
    I32Eq = 0x46, I32Ne, I32LtS, I32LtU, I32GtS, I32GtU, I32LeS, I32LeU, I32GeS, I32GeU,
    I64Eqz = 0x50,
    I64Eq = 0x51, I64Ne, I64LtS, I64LtU, I64GtS, I64GtU, I64LeS, I64LeU, I64GeS, I64GeU,
    F32Eq = 0x5B, F32Ne, F32Lt, F32Gt, F32Le, F32Ge,
    F64Eq = 0x61, F64Ne, F64Lt, F64Gt, F64Le, F64Ge,
    I32Clz = 0x67, I32Ctz, I32Popcnt,
    I32Add = 0x6A, I32Sub, I32Mul, I32DivS, I32DivU, I32RemS, I32RemU, I32And, I32Or, I32Xor, I32Shl, I32ShrS, I32ShrU, I32Rotl, I32Rotr,
    I64Clz = 0x79, I64Ctz, I64Popcnt,
    I64Add = 0x7C, I64Sub, I64Mul, I64DivS, I64DivU, I64RemS, I64RemU, I64And, I64Or, I64Xor, I64Shl, I64ShrS, I64ShrU, I64Rotl, I64Rotr,
    F32Abs = 0x8B, F32Neg, F32Ceil, F32Floor, F32Trunc, F32Nearest, F32Sqrt,
    F32Add = 0x92, F32Sub, F32Mul, F32Div, F32Min, F32Max, F32Copysign,
    F64Abs = 0x99, F64Neg, F64Ceil, F64Floor, F64Trunc, F64Nearest, F64Sqrt,
    F64Add = 0xA0, F64Sub, F64Mul, F64Div, F64Min, F64Max, F64Copysign,
    I32WrapI64 = 0xA7,
    I32TruncF32S = 0xA8, I32TruncF32U, I32TruncF64S, I32TruncF64U,
    I64ExtendI32S = 0xAC, I64ExtendI32U,
    I64TruncF32S = 0xAE, I64TruncF32U, I64TruncF64S, I64TruncF64U,
    F32ConvertI32S = 0xB2, F32ConvertI32U, F32ConvertI64S, F32ConvertI64U, F32DemoteF64,
    F64ConvertI32S = 0xB7, F64ConvertI32U, F64ConvertI64S, F64ConvertI64U, F64PromoteF32,
    I32ReinterpretF32 = 0xBC, I64ReinterpretF64, F32ReinterpretI32, F64ReinterpretI64,
    I32Extend8S = 0xC0, I32Extend16S, I64Extend8S, I64Extend16S, I64Extend32S,
    RefNull = 0xD0, RefIsNull, RefFunc,

    I32TruncSatF32S = 0xF00, I32TruncSatF32U, I32TruncSatF64S, I32TruncSatF64U, I64TruncSatF32S, I64TruncSatF32U, I64TruncSatF64S, I64TruncSatF64U,
    MemoryInit = 0xF08, DataDrop, MemoryCopy, MemoryFill,
    TableInit = 0xF0C, ElemDrop, TableCopy, TableGrow, TableSize, TableFill,

    # V128Load = , V128Store,

    # V128Load8x8U, V128Load8x8S, V128Load16x4U, V128Load16x4S, V128Load32x2U, V128Load32x2S, V128Load32Zero, V128Load64Zero,
    # V128Load8Splat, V128Load16Splat, V128Load32Splat, V128Load64Splat,

    # V128Load8Lane, V128Load16Lane, V128Load32Lane, V128Load64Lane,
    # V128Store8Lane, V128Store16Lane, V128Store32Lane, V128Store64Lane,

    # 32, 64, I, F

  WasmBlockTypeKind* {.pure.} = enum TypeIdx, ValType
  WasmBlockType* = object
    case kind*: WasmBlockTypeKind
    of TypeIdx: idx*: WasmTypeIdx
    of ValType: typ*: Option[WasmValueType]

  WasmMemArg* = object
    offset*: uint32
    align*: uint32

  WasmInstr* = object
    case kind*: WasmInstrKind
    of I32Const: i32Const*: int32
    of I64Const: i64Const*: int64
    of F32Const: f32Const*: float32
    of F64Const: f64Const*: float64

    # Reference Instructions
    of RefNull: refNullType*: WasmRefType
    of RefFunc: refFuncIdx*: WasmFuncIdx

    # Parametric Instructions
    of Select: selectValType*: Option[WasmValueType] # might be seq in the future

    # Variable Instructions
    of LocalGet, LocalSet, LocalTee: localIdx*: WasmLocalIdx
    of GlobalGet, GlobalSet: globalIdx*: WasmGlobalIdx
    of TableGet, TableSet, TableSize, TableGrow, TableFill: tableOpIdx*: WasmTableIdx
    of TableCopy:
      tableCopyTargetIdx*: WasmTableIdx
      tableCopySourceIdx*: WasmTableIdx
    of TableInit:
      tableInitIdx*: WasmTableIdx
      tableInitElementIdx*: WasmElemIdx
    of ElemDrop: elemDropIdx*: WasmElemIdx

    # Memory Instructions
    of I32Load, I64Load, F32Load, F64Load, I32Store, I64Store, F32Store, F64Store,
      I32Load8U, I32Load8S, I64Load8U, I64Load8S, I32Load16U, I32Load16S, I64Load16U, I64Load16S, I64Load32U, I64Load32S,
      I32Store8, I64Store8, I32Store16, I64Store16, I64Store32
      # V128Load, V128Store,
      # V128Load8x8U, V128Load8x8S, V128Load16x4U, V128Load16x4S, V128Load32x2U, V128Load32x2S, V128Load32Zero, V128Load64Zero,
      # V128Load8Splat, V128Load16Splat, V128Load32Splat, V128Load64Splat:
        :
      memArg*: WasmMemArg
    # of V128Load8Lane, V128Load16Lane, V128Load32Lane, V128Load64Lane, V128Store8Lane, V128Store16Lane, V128Store32Lane, V128Store64Lane:
    #   v128LaneMemArg*: WasmMemArg
    #   v128LaneIdx*: uint8
    of MemoryInit: memoryInitDataIdx*: WasmDataIdx
    of DataDrop: dataDropDataIdx*: WasmDataIdx

    # Control Instructions
    of Block:
      blockType*: WasmBlockType
      blockInstr*: seq[WasmInstr]
    of Loop:
      loopType*: WasmBlockType
      loopInstr*: seq[WasmInstr]
    of If:
      ifType*: WasmBlockType
      ifThenInstr*: seq[WasmInstr]
      ifElseInstr*: seq[WasmInstr]
    of Br, BrIf: brLabelIdx*: WasmLabelIdx
    of BrTable:
      brTableIndices*: seq[WasmLabelIdx]
      brTableDefaultIdx*: WasmLabelIdx
    of Call: callFuncIdx*: WasmFuncIdx
    of CallIndirect:
      callIndirectTableIdx*: WasmTableIdx
      callIndirectTypeIdx*: WasmTypeIdx
    else: discard

  WasmExpr* = ref object
    instr*: seq[WasmInstr]

  WasmFunc* = object
    typeIdx*: WasmTypeIdx
    locals*: seq[tuple[typ: WasmValueType, id: string]]
    body*: WasmExpr
    id*: string

  WasmTable* = object
    typ*: WasmTableType

  WasmMem* = object
    typ*: WasmMemoryType

  WasmGlobal* = object
    id*: string
    typ*: WasmGlobalType
    init*: WasmExpr

  WasmElementModeKind* {.pure.} = enum Passive, Active, Declarative
  WasmElementMode* = object
    case kind*: WasmElementModeKind
    of Active:
      tableIdx*: WasmTableIdx
      offset*: WasmExpr
    else:
      discard

  WasmElem* = object
    typ*: WasmRefType
    init*: seq[WasmExpr]
    mode*: WasmElementMode

  WasmDataModeKind* {.pure.} = enum Passive, Active
  WasmDataMode* = object
    case kind*: WasmDataModeKind
    of Active:
      memIdx*: WasmMemIdx
      offset*: WasmExpr
    else:
      discard

  WasmData* = object
    init*: seq[uint8]
    mode*: WasmDataMode

  WasmStart* = object
    start*: WasmFuncIdx

  WasmImportDescKind* {.pure.} = enum Func, Table, Mem, Global
  WasmImportDesc* = object
    case kind*: WasmImportDescKind
    of Func:
      funcTypeIdx*: WasmTypeIdx
    of Table:
      table*: WasmTableType
    of Mem:
      mem*: WasmMemoryType
    of Global:
      global*: WasmGlobalType

  WasmImport* = object
    module*: string
    name*: string
    desc*: WasmImportDesc

  WasmExportDescKind* {.pure.} = enum Func, Table, Mem, Global
  WasmExportDesc* = object
    case kind*: WasmExportDescKind
    of Func:
      funcIdx*: WasmFuncIdx
    of Table:
      tableIdx*: WasmTableIdx
    of Mem:
      memIdx*: WasmMemIdx
    of Global:
      globalIdx*: WasmGlobalIdx

  WasmExport* = object
    name*: string
    desc*: WasmExportDesc

  WasmBuilder* = ref object
    types*: seq[WasmFunctionType]
    funcs*: seq[WasmFunc]
    tables*: seq[WasmTable]
    mems*: seq[WasmMem]
    globals*: seq[WasmGlobal]
    elems*: seq[WasmElem]
    datas*: seq[WasmData]
    start*: Option[WasmStart]
    functionImports: seq[WasmImport]
    tableImports: seq[WasmImport]
    memImports: seq[WasmImport]
    globalImports: seq[WasmImport]
    exports*: seq[WasmExport]

const wasmPageSize* = 65536.int32

proc `$`*(idx: WasmTypeIdx): string {.borrow.}
proc `$`*(idx: WasmFuncIdx): string {.borrow.}
proc `$`*(idx: WasmTableIdx): string {.borrow.}
proc `$`*(idx: WasmMemIdx): string {.borrow.}
proc `$`*(idx: WasmGlobalIdx): string {.borrow.}
proc `$`*(idx: WasmElemIdx): string {.borrow.}
proc `$`*(idx: WasmDataIdx): string {.borrow.}
proc `$`*(idx: WasmLocalIdx): string {.borrow.}
proc `$`*(idx: WasmLabelIdx): string {.borrow.}

converter toWasmExpr*(self: WasmInstr): WasmExpr = WasmExpr(instr: @[self])

proc newWasmBuilder*(): WasmBuilder =
  new result

proc getEffectiveFunctionIdx(self: WasmBuilder, idx: WasmFuncIdx): int =
  if (idx.uint32 and 0x80000000.uint32) != 0:
    return (not idx.uint32).int
  else:
    return idx.int + self.functionImports.len

proc getEffectiveTableIdx(self: WasmBuilder, idx: WasmTableIdx): int =
  if (idx.uint32 and 0x80000000.uint32) != 0:
    return (not idx.uint32).int
  else:
    return idx.int + self.tableImports.len

proc getEffectiveMemIdx(self: WasmBuilder, idx: WasmMemIdx): int =
  if (idx.uint32 and 0x80000000.uint32) != 0:
    return (not idx.uint32).int
  else:
    return idx.int + self.memImports.len

proc getEffectiveGlobalIdx(self: WasmBuilder, idx: WasmGlobalIdx): int =
  if (idx.uint32 and 0x80000000.uint32) != 0:
    return (not idx.uint32).int
  else:
    return idx.int + self.globalImports.len

proc addType*(self: WasmBuilder, inputs: openArray[WasmValueType], outputs: openArray[WasmValueType]): WasmTypeIdx =
  result = self.types.len.WasmTypeIdx
  self.types.add WasmFunctionType(input: WasmResultType(types: @inputs), output: WasmResultType(types: @outputs))

proc addTable*(self: WasmBuilder): WasmTableIdx =
  result = (-self.tables.len - 1).WasmTableIdx
  self.tables.add(WasmTable(
    typ: WasmTableType(
      limits: WasmLimits(min: 1, max: uint32.none),
      refType: FuncRef)))

proc addFunctionElements*(self: WasmBuilder, name: string, table: WasmTableIdx, funcs: seq[WasmFuncIdx]) =
  self.elems.add WasmElem(
    typ: FuncRef,
    init: funcs.mapIt(WasmExpr(instr: @[WasmInstr(kind: RefFunc, refFuncIdx: it)])),
    mode: WasmElementMode(
      kind: Active,
      tableIdx: table,
      offset: WasmExpr(instr: @[WasmInstr(kind: I32Const, i32Const: 0)])
  ))

proc addImport*(self: WasmBuilder, module: string, name: string, typeIdx: WasmTypeIdx): WasmFuncIdx =
  result = (-self.functionImports.len - 1).WasmFuncIdx

  self.functionImports.add WasmImport(
    module: module,
    name: name,
    desc: WasmImportDesc(kind: Func, funcTypeIdx: typeIdx)
  )

proc addImport*(self: WasmBuilder, module: string, name: string, typ: WasmGlobalType): WasmGlobalIdx =
  result = (-self.globalImports.len - 1).WasmGlobalIdx
  self.globalImports.add WasmImport(
    module: module,
    name: name,
    desc: WasmImportDesc(kind: Global, global: typ)
  )

proc addImport*(self: WasmBuilder, module: string, name: string, typ: WasmValueType, mut: bool): WasmGlobalIdx =
  result = (-self.globalImports.len - 1).WasmGlobalIdx
  self.globalImports.add WasmImport(
    module: module,
    name: name,
    desc: WasmImportDesc(kind: Global, global: WasmGlobalType(typ: typ, mut: mut))
  )

proc addExport*(self: WasmBuilder, name: string, funcIdx: WasmFuncIdx) =
  self.exports.add WasmExport(
    name: name,
    desc: WasmExportDesc(kind: Func, funcIdx: funcIdx)
  )

proc addExport*(self: WasmBuilder, name: string, tableIdx: WasmTableIdx) =
  self.exports.add WasmExport(
    name: name,
    desc: WasmExportDesc(kind: Table, tableIdx: tableIdx)
  )

proc addExport*(self: WasmBuilder, name: string, memIdx: WasmMemIdx) =
  self.exports.add WasmExport(
    name: name,
    desc: WasmExportDesc(kind: Mem, memIdx: memIdx)
  )

proc addExport*(self: WasmBuilder, name: string, globalIdx: WasmGlobalIdx) =
  self.exports.add WasmExport(
    name: name,
    desc: WasmExportDesc(kind: Global, globalIdx: globalIdx)
  )

proc addGlobal*(self: WasmBuilder, typ: WasmValueType, mut: bool, init: WasmExpr, id: string = ""): WasmGlobalIdx =
  result = self.globals.len.WasmGlobalIdx
  self.globals.add WasmGlobal(id: id, typ: WasmGlobalType(typ: typ, mut: mut), init: init)

proc addGlobal*[T](self: WasmBuilder, typ: WasmValueType, mut: bool, init: T, id: string = ""): WasmGlobalIdx =
  let instr = case typ
  of I32: WasmInstr(kind: I32Const, i32Const: init.int32)
  of I64: WasmInstr(kind: I64Const, i64Const: init.int64)
  of F32: WasmInstr(kind: F32Const, f32Const: init.float32)
  of F64: WasmInstr(kind: F64Const, f64Const: init.float64)
  of V128: raise newException(Exception, "V128 not supported")
  of FuncRef: raise newException(Exception, "FuncRef not supported")
  of ExternRef: raise newException(Exception, "ExternRef not supported")

  return self.addGlobal(typ, mut, WasmExpr(instr: @[instr]), id)

proc addActiveData*(self: WasmBuilder, memIdx: WasmMemIdx, offset: WasmExpr, data: openArray[uint8]): WasmDataIdx =
  result = self.datas.len.WasmDataIdx
  self.datas.add WasmData(mode: WasmDataMode(kind: Active, memIdx: memIdx, offset: offset), init: @data)

proc addActiveData*(self: WasmBuilder, memIdx: WasmMemIdx, offset: int32, data: openArray[uint8]): WasmDataIdx =
  return self.addActiveData(memIdx, WasmInstr(kind: I32Const, i32Const: offset), data)

proc addPassiveData*(self: WasmBuilder, offset: int32, data: openArray[uint8]): WasmGlobalIdx =
  result = self.globals.len.WasmGlobalIdx
  self.datas.add WasmData(mode: WasmDataMode(kind: Passive), init: @data)

proc addFunction*(self: WasmBuilder, inputs: openArray[WasmValueType], outputs: openArray[WasmValueType], exportName: Option[string] = string.none): WasmFuncIdx =
  let typeIdx = self.types.len.WasmTypeIdx
  self.types.add WasmFunctionType(input: WasmResultType(types: @inputs), output: WasmResultType(types: @outputs))

  let funcIdx = self.funcs.len.WasmFuncIdx

  self.funcs.add WasmFunc(
    typeIdx: typeIdx,
    id: exportName.get ""
  )

  if exportName.getSome(exportName):
    self.exports.add WasmExport(
      name: exportName,
      desc: WasmExportDesc(kind: Func, funcIdx: funcIdx)
    )

  return funcIdx

proc addFunction*(self: WasmBuilder,
  inputs: openArray[WasmValueType], outputs: openArray[WasmValueType], locals: openArray[tuple[typ: WasmValueType, id: string]], body: WasmExpr, exportName: Option[string] = string.none): WasmFuncIdx =
  let typeIdx = self.types.len.WasmTypeIdx
  self.types.add WasmFunctionType(input: WasmResultType(types: @inputs), output: WasmResultType(types: @outputs))

  let funcIdx = self.funcs.len.WasmFuncIdx

  self.funcs.add WasmFunc(
    typeIdx: typeIdx,
    locals: @locals,
    body: body,
    id: exportName.get ""
  )

  if exportName.getSome(exportName):
    self.exports.add WasmExport(
      name: exportName,
      desc: WasmExportDesc(kind: Func, funcIdx: funcIdx)
    )

  return funcIdx

proc getFunctionTypeIdx*(self: WasmBuilder, funcIdx: WasmFuncIdx): WasmTypeIdx =
  let index = self.getEffectiveFunctionIdx(funcIdx)
  if index < self.functionImports.len:
    return self.functionImports[index].desc.funcTypeIdx
  else:
    return self.funcs[index - self.functionImports.len].typeIdx

proc getFunctionTypeIdx*(self: WasmBuilder, inputs: openArray[WasmValueType], outputs: openArray[WasmValueType]): WasmTypeIdx =
  for i, typ in self.types:
    if typ.input.types == inputs and typ.output.types == outputs:
      return i.WasmTypeIdx

proc setBody*(self: WasmBuilder, funcIdx: WasmFuncIdx, locals: openArray[tuple[typ: WasmValueType, id: string]], body: WasmExpr) =
  assert funcIdx.int < self.funcs.len
  self.funcs[funcIdx.int].locals = @locals
  self.funcs[funcIdx.int].body = body

proc writeLength(encoder: var BinaryEncoder, length: int) =
  encoder.writeLEB128(uint32, length.uint32)

proc writeLimits(encoder: var BinaryEncoder, limits: WasmLimits) =
  if limits.max.isSome:
    encoder.write(byte, 0x01)
    encoder.writeLEB128(uint32, limits.min)
    encoder.writeLEB128(uint32, limits.max.get)
  else:
    encoder.write(byte, 0x00)
    encoder.writeLEB128(uint32, limits.min)

proc writeType(encoder: var BinaryEncoder, typ: WasmValueType) =
  case typ
  of I32: encoder.write(byte, 0x7F)
  of I64: encoder.write(byte, 0x7E)
  of F32: encoder.write(byte, 0x7D)
  of F64: encoder.write(byte, 0x7C)
  of V128: encoder.write(byte, 0x7B)
  of FuncRef: encoder.write(byte, 0x70)
  of ExternRef: encoder.write(byte, 0x6F)

proc writeType(encoder: var BinaryEncoder, typ: WasmResultType) =
  encoder.writeLength(typ.types.len)
  for t in typ.types:
    encoder.writeType(t)

proc writeType(encoder: var BinaryEncoder, typ: WasmFunctionType) =
  encoder.write(byte, 0x60)
  encoder.writeType(typ.input)
  encoder.writeType(typ.output)

proc writeType(encoder: var BinaryEncoder, typ: WasmMemoryType) =
  encoder.writeLimits(typ.limits)

proc writeType(encoder: var BinaryEncoder, typ: WasmTableType) =
  encoder.writeType(typ.refType)
  encoder.writeLimits(typ.limits)

proc writeType(encoder: var BinaryEncoder, typ: WasmGlobalType) =
  encoder.writeType(typ.typ)
  encoder.write(byte, if typ.mut: 1 else: 0)

proc writeBlockType(encoder: var BinaryEncoder, blockType: WasmBlockType) =
  case blockType.kind
  of TypeIdx: encoder.writeLength(blockType.idx.int)
  of ValType:
    if blockType.typ.isSome:
      encoder.writeType(blockType.typ.get)
    else:
      encoder.write(byte, 0x40)

proc writeInstr(self: WasmBuilder, encoder: var BinaryEncoder, instr: WasmInstr) =
  # echo "writeInstr ", instr
  case instr.kind

  of Block:
    encoder.write(byte, instr.kind.byte)
    encoder.writeBlockType(instr.blockType)
    for i in instr.blockInstr:
      self.writeInstr(encoder, i)
    encoder.write(byte, 0x0B)

  of Loop:
    encoder.write(byte, instr.kind.byte)
    encoder.writeBlockType(instr.loopType)
    for i in instr.loopInstr:
      self.writeInstr(encoder, i)
    encoder.write(byte, 0x0B)

  of If:
    encoder.write(byte, instr.kind.byte)
    encoder.writeBlockType(instr.ifType)
    for i in instr.ifThenInstr:
      self.writeInstr(encoder, i)
    if instr.ifElseInstr.len > 0:
      encoder.write(byte, 0x05)
      for i in instr.ifElseInstr:
        self.writeInstr(encoder, i)
    encoder.write(byte, 0x0B)

  of Br, BrIf:
    encoder.write(byte, instr.kind.byte)
    encoder.writeLength(instr.brLabelIdx.int)

  of BrTable:
    encoder.write(byte, instr.kind.byte)
    encoder.writeLength(instr.brTableIndices.len)
    for idx in instr.brTableIndices:
      encoder.writeLength(idx.int)
    encoder.writeLength(instr.brTableDefaultIdx.int)

  of Call:
    encoder.write(byte, instr.kind.byte)
    encoder.writeLength(self.getEffectiveFunctionIdx(instr.callFuncIdx))

  of CallIndirect:
    encoder.write(byte, instr.kind.byte)
    encoder.writeLength(instr.callIndirectTypeIdx.int)
    encoder.writeLength(self.getEffectiveTableIdx(instr.callIndirectTableIdx))

  of RefNull:
    encoder.write(byte, instr.kind.byte)
    encoder.writeType(instr.refNullType)

  of RefFunc:
    encoder.write(byte, instr.kind.byte)
    encoder.writeLength(self.getEffectiveFunctionIdx(instr.refFuncIdx))

  of Select:
    if instr.selectValType.isSome:
      encoder.write(byte, 0x1C)
      encoder.writeLength(1)
      encoder.writeType(instr.selectValType.get)
    else:
      encoder.write(byte, 0x1B)

  of LocalGet, LocalSet, LocalTee:
    encoder.write(byte, instr.kind.byte)
    encoder.writeLength(instr.localIdx.int)

  of GlobalGet, GlobalSet:
    encoder.write(byte, instr.kind.byte)
    encoder.writeLength(self.getEffectiveGlobalIdx(instr.globalIdx))

  of TableGet, TableSet:
    encoder.write(byte, instr.kind.byte)
    encoder.writeLength(self.getEffectiveTableIdx(instr.tableOpIdx))

  of TableInit:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)
    encoder.writeLength(instr.tableInitElementIdx.int)
    encoder.writeLength(self.getEffectiveTableIdx(instr.tableInitIdx))

  of ElemDrop:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)
    encoder.writeLength(instr.elemDropIdx.int)

  of TableCopy:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)
    encoder.writeLength(self.getEffectiveTableIdx(instr.tableCopyTargetIdx))
    encoder.writeLength(self.getEffectiveTableIdx(instr.tableCopySourceIdx))

  of TableGrow, TableSize, TableFill:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)
    encoder.writeLength(self.getEffectiveTableIdx(instr.tableOpIdx))

  of I32Load, I64Load, F32Load, F64Load, I32Store, I64Store, F32Store, F64Store,
    I32Load8U, I32Load8S, I64Load8U, I64Load8S, I32Load16U, I32Load16S, I64Load16U, I64Load16S, I64Load32U, I64Load32S,
    I32Store8, I64Store8, I32Store16, I64Store16, I64Store32
    # V128Load, V128Store,
    # V128Load8x8U, V128Load8x8S, V128Load16x4U, V128Load16x4S, V128Load32x2U, V128Load32x2S, V128Load32Zero, V128Load64Zero,
    # V128Load8Splat, V128Load16Splat, V128Load32Splat, V128Load64Splat:
      :
    encoder.write(byte, instr.kind.byte)
    encoder.writeLength(instr.memArg.align.int)
    encoder.writeLength(instr.memArg.offset.int)

  of MemorySize, MemoryGrow:
    encoder.write(byte, instr.kind.byte)
    encoder.write(byte, 0)

  of MemoryInit:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)
    encoder.writeLength(instr.memoryInitDataIdx.int)
    encoder.write(byte, 0)

  of DataDrop:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)
    encoder.writeLength(instr.dataDropDataIdx.int)

  of MemoryCopy:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)
    encoder.write(byte, 0)
    encoder.write(byte, 0)

  of MemoryFill:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)
    encoder.write(byte, 0)

  of I32Const:
    encoder.write(byte, instr.kind.byte)
    encoder.writeLEB128(int32, instr.i32Const)

  of I64Const:
    encoder.write(byte, instr.kind.byte)
    encoder.writeLEB128(int64, instr.i64Const)

  of F32Const:
    encoder.write(byte, instr.kind.byte)
    encoder.write(float32, instr.f32Const)

  of F64Const:
    encoder.write(byte, instr.kind.byte)
    encoder.write(float64, instr.f64Const)

  of I32TruncSatF32S, I32TruncSatF32U, I32TruncSatF64S, I32TruncSatF64U, I64TruncSatF32S, I64TruncSatF32U, I64TruncSatF64S, I64TruncSatF64U:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)

  else:
    encoder.write(byte, instr.kind.byte)

proc writeExpr(self: WasmBuilder, encoder: var BinaryEncoder, expr: WasmExpr) =
  for instr in expr.instr.mitems:
    self.writeInstr(encoder, instr)
  encoder.write(byte, 0x0B)

template generateSection(self: WasmBuilder, encoder: var BinaryEncoder, id: untyped, body: untyped): untyped =
  # Section id
  encoder.write(byte, id)

  let subEncoder = block:
    var e {.inject.} = BinaryEncoder()
    body
    e

  # Length
  encoder.writeLEB128(uint32, subEncoder.buffer.len.uint32)

  # Content
  encoder.buffer.add subEncoder.buffer

proc generateTypeSection(self: WasmBuilder, encoder: var BinaryEncoder) =
  if self.types.len > 0:
    generateSection(self, encoder, 1):
      e.writeLength(self.types.len)
      for typ in self.types:
        e.writeType(typ)

proc generateImportSection(self: WasmBuilder, encoder: var BinaryEncoder) =
  let totalImports = self.functionImports.len + self.tableImports.len + self.memImports.len + self.globalImports.len
  if totalImports > 0:
    generateSection(self, encoder, 2):
      e.writeLength(totalImports)

      for v in self.functionImports:
        e.writeString(v.module)
        e.writeString(v.name)
        e.write(byte, 0x00)
        e.writeLEB128(uint32, v.desc.funcTypeIdx.uint32)

      for v in self.tableImports:
        e.writeString(v.module)
        e.writeString(v.name)
        e.write(byte, 0x01)
        e.writeType(v.desc.table)

      for v in self.memImports:
        e.writeString(v.module)
        e.writeString(v.name)
        e.write(byte, 0x02)
        e.writeType(v.desc.mem)

      for v in self.globalImports:
        e.writeString(v.module)
        e.writeString(v.name)
        e.write(byte, 0x03)
        e.writeType(v.desc.global)

proc generateFunctionSection(self: WasmBuilder, encoder: var BinaryEncoder) =
  if self.funcs.len > 0:
    generateSection(self, encoder, 3):
      e.writeLength(self.funcs.len)
      for v in self.funcs:
        e.writeLength(v.typeIdx.int)

proc generateTableSection(self: WasmBuilder, encoder: var BinaryEncoder) =
  if self.tables.len > 0:
    generateSection(self, encoder, 4):
      e.writeLength(self.tables.len)
      for v in self.tables:
        e.writeType(v.typ)

proc generateMemorySection(self: WasmBuilder, encoder: var BinaryEncoder) =
  if self.mems.len > 0:
    generateSection(self, encoder, 5):
      e.writeLength(self.mems.len)
      for v in self.mems:
        e.writeType(v.typ)

proc generateGlobalSection(self: WasmBuilder, encoder: var BinaryEncoder) =
  if self.globals.len > 0:
    generateSection(self, encoder, 6):
      e.writeLength(self.globals.len)
      for v in self.globals:
        e.writeType(v.typ)
        self.writeExpr(e, v.init)

proc generateExportSection(self: WasmBuilder, encoder: var BinaryEncoder) =
  if self.exports.len > 0:
    generateSection(self, encoder, 7):
      e.writeLength(self.exports.len)
      for v in self.exports:
        e.writeString(v.name)

        case v.desc.kind
        of Func:
          e.write(byte, 0x00)
          e.writeLength(self.getEffectiveFunctionIdx(v.desc.funcIdx))
        of Table:
          e.write(byte, 0x01)
          e.writeLength(self.getEffectiveTableIdx(v.desc.tableIdx))
        of Mem:
          e.write(byte, 0x02)
          e.writeLength(self.getEffectiveMemIdx(v.desc.memIdx))
        of Global:
          e.write(byte, 0x03)
          e.writeLength(self.getEffectiveGlobalIdx(v.desc.globalIdx))

proc generateStartSection(self: WasmBuilder, encoder: var BinaryEncoder) =
  if self.start.isSome:
    generateSection(self, encoder, 8):
      e.writeLength(self.getEffectiveFunctionIdx(self.start.get.start))

proc generateElementSection(self: WasmBuilder, encoder: var BinaryEncoder) =
  ## https://webassembly.github.io/spec/core/binary/modules.html#element-section
  if self.elems.len > 0:
    generateSection(self, encoder, 9):
      e.writeLength(self.elems.len)

      for v in self.elems.mitems:
        let allInitsFunctionRefs = block:
          var res = true
          for expr in v.init:
            if expr.instr.len != 1 or expr.instr[0].kind != RefFunc:
              res = false
              break
          res

        var idx = 0
        case v.mode.kind
        of WasmElementModeKind.Passive:
          idx = idx or 0b001
        of WasmElementModeKind.Declarative:
          idx = idx or 0b011
        of Active:
          if v.typ != FuncRef and self.getEffectiveTableIdx(v.mode.tableIdx) == 0:
            idx = idx or 0b010

        if not allInitsFunctionRefs:
          idx = idx or 0b100

        e.writeLength(idx)

        case idx
        of 0:
          assert allInitsFunctionRefs
          self.writeExpr(e, v.mode.offset)
          e.writeLength(v.init.len)
          for expr in v.init:
            e.writeLength(self.getEffectiveFunctionIdx(expr.instr[0].refFuncIdx))

        of 1:
          assert allInitsFunctionRefs
          e.writeType(v.typ)
          e.writeLength(v.init.len)
          for expr in v.init:
            e.writeLength(self.getEffectiveFunctionIdx(expr.instr[0].refFuncIdx))

        of 2:
          assert allInitsFunctionRefs
          e.writeLength(self.getEffectiveTableIdx(v.mode.tableIdx))
          self.writeExpr(e, v.mode.offset)
          e.writeType(v.typ)
          e.writeLength(v.init.len)
          for expr in v.init:
            e.writeLength(self.getEffectiveFunctionIdx(expr.instr[0].refFuncIdx))

        of 3:
          assert allInitsFunctionRefs
          e.writeType(v.typ)
          e.writeLength(v.init.len)
          for expr in v.init:
            e.writeLength(self.getEffectiveFunctionIdx(expr.instr[0].refFuncIdx))

        of 4:
          assert not allInitsFunctionRefs
          self.writeExpr(e, v.mode.offset)
          e.writeLength(v.init.len)
          for expr in v.init:
            self.writeExpr(e, expr)

        of 5:
          assert not allInitsFunctionRefs
          e.writeType(v.typ)
          e.writeLength(v.init.len)
          for expr in v.init:
            self.writeExpr(e, expr)

        of 6:
          assert not allInitsFunctionRefs
          e.writeLength(self.getEffectiveTableIdx(v.mode.tableIdx))
          self.writeExpr(e, v.mode.offset)
          e.writeType(v.typ)
          e.writeLength(v.init.len)
          for expr in v.init:
            self.writeExpr(e, expr)

        of 7:
          assert not allInitsFunctionRefs
          e.writeType(v.typ)
          e.writeLength(v.init.len)
          for expr in v.init:
            self.writeExpr(e, expr)

        else: discard

proc generateCodeSection(self: WasmBuilder, encoder: var BinaryEncoder) =
  if self.funcs.len > 0:
    generateSection(self, encoder, 10):
      e.writeLength(self.funcs.len)
      for v in self.funcs.mitems:
        var funcEncoder = BinaryEncoder()

        # Locals
        funcEncoder.writeLength(v.locals.len)
        for l in v.locals.mitems:
          funcEncoder.writeLength(1) # Number of locals with this type
          funcEncoder.writeType(l.typ)

        # Expr
        self.writeExpr(funcEncoder, v.body)

        # Code
        e.writeLength(funcEncoder.buffer.len)
        e.buffer.add funcEncoder.buffer

proc generateDataSection(self: WasmBuilder, encoder: var BinaryEncoder) =
  if self.datas.len > 0:
    generateSection(self, encoder, 11):
      e.writeLength(self.datas.len)
      for v in self.datas.mitems:
        case v.mode.kind
        of Passive:
          e.writeLength(1)
          e.writeLength(v.init.len)
          e.buffer.add v.init
        of Active:
          if v.mode.memIdx.int == 0:
            e.writeLength(0)
          else:
            e.writeLength(2)
            e.writeLength(v.mode.memIdx.int)
          self.writeExpr(e, v.mode.offset)
          e.writeLength(v.init.len)
          e.buffer.add v.init

proc generateDataCountSection(self: WasmBuilder, encoder: var BinaryEncoder) =
  if self.datas.len > 0:
    generateSection(self, encoder, 12):
      e.writeLength(self.datas.len)

proc generateBinary*(self: WasmBuilder): seq[byte] =
  var encoder = BinaryEncoder()
  encoder.write(uint32, 0x6D736100) # magic number
  encoder.write(uint32, 1) # version

  self.generateTypeSection(encoder)
  self.generateImportSection(encoder)
  self.generateFunctionSection(encoder)
  self.generateTableSection(encoder)
  self.generateMemorySection(encoder)
  self.generateGlobalSection(encoder)
  self.generateExportSection(encoder)
  self.generateStartSection(encoder)
  self.generateElementSection(encoder)
  self.generateDataCountSection(encoder)
  self.generateCodeSection(encoder)
  self.generateDataSection(encoder)

  return encoder.buffer

proc `$`(self: WasmLimits): string =
  result = $self.min
  if self.max.getSome(max):
    result.add " "
    result.add $max

proc `$`(self: WasmFunctionType): string =
  result = "(func (param"
  for i, typ in self.input.types:
    result.add " "
    result.add $typ
  result.add ") (result"
  for i, typ in self.output.types:
    result.add " "
    result.add $typ
  result.add "))"

proc `$`(typ: WasmTableType): string = fmt"{typ.limits} {typ.refType}"

proc `$`(typ: WasmMemoryType): string = $typ.limits

proc `$`(typ: WasmGlobalType): string =
  if typ.mut:
    fmt"(mut {typ.typ})"
  else:
    $typ.typ

proc `$`(typ: WasmBlockType): string =
  case typ.kind
  of TypeIdx:
    return fmt"(type {typ.idx})"
  of ValType:
    if typ.typ.getSome(valueType):
      return fmt"(result {valueType})"
    return ""

proc `$`(memArg: WasmMemArg): string =
  if memArg.offset != 0:
    result.add "offset="
    result.add $memArg.offset
  if memArg.align != 0:
    if result.len > 0:
      result.add " "
    result.add "align="
    result.add $memArg.align

proc getResultTypeWat(typ: WasmResultType, name: string): string =
  result.add "("
  result.add name
  for i, typ in typ.types:
    result.add " "
    result.add $typ
  result.add ")"

proc getTypeUseWat(self: WasmBuilder, typ: WasmTypeIdx, inline: bool): string =
  result = fmt"(type {typ})"
  if inline:
    let funcType = self.types[typ.uint32]
    if funcType.input.types.len > 0:
      result.add " "
      result.add getResultTypeWat(funcType.input, "param")
    if funcType.output.types.len > 0:
      result.add " "
      result.add getResultTypeWat(funcType.output, "result")

proc getImportDescWat(self: WasmBuilder, imp: WasmImportDesc): string =
  case imp.kind
  of Func:
    result = "(func "
    result.add self.getTypeUseWat(imp.funcTypeIdx, false)
    result.add ")"
  of Table:
    # (table (;0;) 104 104 funcref)
    result = fmt"(table {imp.table})"
  of Mem:
    # (memory (;0;) 256 256)
    result = fmt"(memory {imp.mem.limits})"
  of Global:
    # (global $a i32 (i32.const 65536))
    # (global $b (mut i32) (i32.const 65536))
    result = fmt"(global {imp.global})"

proc getHeapTypeWat(typ: WasmRefType): string =
  if typ == FuncRef:
    "func"
  else:
    "extern"

proc getInstrWat(self: WasmBuilder, instr: WasmInstr, blockLevel: int = 0): string =
  case instr.kind

  of Block:
    result.add &"block $label{blockLevel} {instr.blockType}"
    for subInstr in instr.blockInstr:
      result.add "\n"
      result.add getInstrWat(self, subInstr, blockLevel + 1).indent(1, "  ")
    result.add &"\nend $label{blockLevel}"

  of Loop:
    result.add &"loop $label{blockLevel} {instr.loopType}"
    for subInstr in instr.loopInstr:
      result.add "\n"
      result.add getInstrWat(self, subInstr, blockLevel + 1).indent(1, "  ")
    result.add &"\nend $label{blockLevel}"

  of If:
    result.add &"if $label{blockLevel} {instr.ifType}"
    for subInstr in instr.ifThenInstr:
      result.add "\n"
      result.add getInstrWat(self, subInstr, blockLevel + 1).indent(1, "  ")
    result.add "\nelse"
    for subInstr in instr.ifElseInstr:
      result.add "\n"
      result.add getInstrWat(self, subInstr, blockLevel + 1).indent(1, "  ")
    result.add &"\nend $label{blockLevel}"

  of Unreachable: result.add "unreachable"
  of Nop: result.add "nop"
  of Drop: result.add "drop"
  of Br: result.add &"br $label{(blockLevel - instr.brLabelIdx.int - 1)}"
  of BrIf: result.add &"br_if $label{(blockLevel - instr.brLabelIdx.int - 1)}"
  of BrTable:
    result.add &"br_table"
    for label in instr.brTableIndices:
      result.add &" {label}"
    result.add &" {instr.brTableDefaultIdx}"
  of Return: result.add "return"
  of Call: result.add &"call {getEffectiveFunctionIdx(self, instr.callFuncIdx)}"
  of CallIndirect: result.add &"call {getEffectiveTableIdx(self, instr.callIndirectTableIdx)} (type {instr.callIndirectTypeIdx})"

  of RefNull: result.add &"ref.null {getHeapTypeWat(instr.refNullType)}"
  of RefIsNull: result.add "ref.is_null"
  of RefFunc: result.add &"ref.func {getEffectiveFunctionIdx(self, instr.refFuncIdx)}"

  of Select:
    result.add "select"
    if instr.selectValType.getSome(valType):
      result.add " (result "
      result.add $valType
      result.add ")"

  of LocalGet: result.add &"local.get $var{instr.localIdx}"
  of LocalSet: result.add &"local.set $var{instr.localIdx}"
  of LocalTee: result.add &"local.tee $var{instr.localIdx}"
  of GlobalGet: result.add &"global.get $var{getEffectiveGlobalIdx(self, instr.globalIdx)}"
  of GlobalSet: result.add &"global.set $var{getEffectiveGlobalIdx(self, instr.globalIdx)}"

  of TableGet: result.add &"table.get {getEffectiveTableIdx(self, instr.tableOpIdx)}"
  of TableSet: result.add &"table.set {getEffectiveTableIdx(self, instr.tableOpIdx)}"
  of TableSize: result.add &"table.size {getEffectiveTableIdx(self, instr.tableOpIdx)}"
  of TableGrow: result.add &"table.grow {getEffectiveTableIdx(self, instr.tableOpIdx)}"
  of TableFill: result.add &"table.fill {getEffectiveTableIdx(self, instr.tableOpIdx)}"
  of TableCopy: result.add &"table.copy {getEffectiveTableIdx(self, instr.tableCopyTargetIdx)} {getEffectiveTableIdx(self, instr.tableCopySourceIdx)}"
  of TableInit: result.add &"table.init {getEffectiveTableIdx(self, instr.tableInitIdx)} {instr.tableInitElementIdx}"
  of ElemDrop: result.add &"elem.drop {instr.elemDropIdx}"

  of I32Load: result.add &"i32.load {instr.memArg}"
  of I64Load: result.add &"i64.load {instr.memArg}"
  of F32Load: result.add &"f32.load {instr.memArg}"
  of F64Load: result.add &"f64.load {instr.memArg}"
  of I32Load8S: result.add &"i32.load8_s {instr.memArg}"
  of I32Load8U: result.add &"i32.load8_u {instr.memArg}"
  of I32Load16S: result.add &"i32.load16_s {instr.memArg}"
  of I32Load16U: result.add &"i32.load16_u {instr.memArg}"
  of I64Load8S: result.add &"i64.load8_s {instr.memArg}"
  of I64Load8U: result.add &"i64.load8_u {instr.memArg}"
  of I64Load16S: result.add &"i64.load16_s {instr.memArg}"
  of I64Load16U: result.add &"i64.load16_u {instr.memArg}"
  of I64Load32S: result.add &"i64.load32_s {instr.memArg}"
  of I64Load32U: result.add &"i64.load32_u {instr.memArg}"

  of I32Store: result.add &"i32.store {instr.memArg}"
  of I64Store: result.add &"i64.store {instr.memArg}"
  of F32Store: result.add &"f32.store {instr.memArg}"
  of F64Store: result.add &"f64.store {instr.memArg}"
  of I32Store8: result.add &"i32.store8 {instr.memArg}"
  of I32Store16: result.add &"i32.store16 {instr.memArg}"
  of I64Store8: result.add &"i64.store8 {instr.memArg}"
  of I64Store16: result.add &"i64.store16 {instr.memArg}"
  of I64Store32: result.add &"i64.store32 {instr.memArg}"

  of MemorySize: result.add "memory.size"
  of MemoryGrow: result.add "memory.grow"
  of MemoryFill: result.add "memory.fill"
  of MemoryCopy: result.add "memory.copy"
  of MemoryInit: result.add &"memory.init {instr.memoryInitDataIdx}"
  of DataDrop: result.add &"data.drop {instr.dataDropDataIdx}"

  of I32Const: result.add &"i32.const {instr.i32Const}"
  of I64Const: result.add &"i64.const {instr.i64Const}"
  of F32Const: result.add &"f32.const {instr.f32Const}"
  of F64Const: result.add &"f64.const {instr.f64Const}"

  of I32Clz: result.add "i32.clz"
  of I32Ctz: result.add "i32.ctz"
  of I32Popcnt: result.add "i32.popcnt"
  of I32Add: result.add "i32.add"
  of I32Sub: result.add "i32.sub"
  of I32Mul: result.add "i32.mul"
  of I32DivS: result.add "i32.div_s"
  of I32DivU: result.add "i32.div_u"
  of I32RemS: result.add "i32.rem_s"
  of I32RemU: result.add "i32.rem_u"
  of I32And: result.add "i32.and"
  of I32Or: result.add "i32.or"
  of I32Xor: result.add "i32.xor"
  of I32Shl: result.add "i32.shl"
  of I32ShrS: result.add "i32.shr_s"
  of I32ShrU: result.add "i32.shr_u"
  of I32Rotl: result.add "i32.rotl"
  of I32Rotr: result.add "i32.rotr"

  of I64Clz: result.add "i64.clz"
  of I64Ctz: result.add "i64.ctz"
  of I64Popcnt: result.add "i64.popcnt"
  of I64Add: result.add "i64.add"
  of I64Sub: result.add "i64.sub"
  of I64Mul: result.add "i64.mul"
  of I64DivS: result.add "i64.div_s"
  of I64DivU: result.add "i64.div_u"
  of I64RemS: result.add "i64.rem_s"
  of I64RemU: result.add "i64.rem_u"
  of I64And: result.add "i64.and"
  of I64Or: result.add "i64.or"
  of I64Xor: result.add "i64.xor"
  of I64Shl: result.add "i64.shl"
  of I64ShrS: result.add "i64.shr_s"
  of I64ShrU: result.add "i64.shr_u"
  of I64Rotl: result.add "i64.rotl"
  of I64Rotr: result.add "i64.rotr"

  of F32Abs: result.add "f32.abs"
  of F32Neg: result.add "f32.neg"
  of F32Ceil: result.add "f32.ceil"
  of F32Floor: result.add "f32.floor"
  of F32Trunc: result.add "f32.trunc"
  of F32Nearest: result.add "f32.nearest"
  of F32Sqrt: result.add "f32.sqrt"
  of F32Add: result.add "f32.add"
  of F32Sub: result.add "f32.sub"
  of F32Mul: result.add "f32.mul"
  of F32Div: result.add "f32.div"
  of F32Min: result.add "f32.min"
  of F32Max: result.add "f32.max"
  of F32Copysign: result.add "f32.copysign"

  of F64Abs: result.add "f64.abs"
  of F64Neg: result.add "f64.neg"
  of F64Ceil: result.add "f64.ceil"
  of F64Floor: result.add "f64.floor"
  of F64Trunc: result.add "f64.trunc"
  of F64Nearest: result.add "f64.nearest"
  of F64Sqrt: result.add "f64.sqrt"
  of F64Add: result.add "f64.add"
  of F64Sub: result.add "f64.sub"
  of F64Mul: result.add "f64.mul"
  of F64Div: result.add "f64.div"
  of F64Min: result.add "f64.min"
  of F64Max: result.add "f64.max"
  of F64Copysign: result.add "f64.copysign"

  of I32Eqz: result.add "i32.eqz"
  of I32Eq: result.add "i32.eq"
  of I32Ne: result.add "i32.ne"
  of I32LtS: result.add "i32.lt_s"
  of I32LtU: result.add "i32.lt_u"
  of I32GtS: result.add "i32.gt_s"
  of I32GtU: result.add "i32.gt_u"
  of I32LeS: result.add "i32.le_s"
  of I32LeU: result.add "i32.le_u"
  of I32GeS: result.add "i32.ge_s"
  of I32GeU: result.add "i32.ge_u"

  of I64Eqz: result.add "i64.eqz"
  of I64Eq: result.add "i64.eq"
  of I64Ne: result.add "i64.ne"
  of I64LtS: result.add "i64.lt_s"
  of I64LtU: result.add "i64.lt_u"
  of I64GtS: result.add "i64.gt_s"
  of I64GtU: result.add "i64.gt_u"
  of I64LeS: result.add "i64.le_s"
  of I64LeU: result.add "i64.le_u"
  of I64GeS: result.add "i64.ge_s"
  of I64GeU: result.add "i64.ge_u"

  of F32Eq: result.add "f32.eq"
  of F32Ne: result.add "f32.ne"
  of F32Lt: result.add "f32.lt"
  of F32Gt: result.add "f32.gt"
  of F32Le: result.add "f32.le"
  of F32Ge: result.add "f32.ge"

  of F64Eq: result.add "f64.eq"
  of F64Ne: result.add "f64.ne"
  of F64Lt: result.add "f64.lt"
  of F64Gt: result.add "f64.gt"
  of F64Le: result.add "f64.le"
  of F64Ge: result.add "f64.ge"

  of I32WrapI64: result.add "i32.wrap_i64"
  of I32TruncF32S: result.add "i32.trunc_f32_s"
  of I32TruncF32U: result.add "i32.trunc_f32_u"
  of I32TruncF64S: result.add "i32.trunc_f64_s"
  of I32TruncF64U: result.add "i32.trunc_f64_u"
  of I32TruncSatF32S: result.add "i32.trunc_sat_f32_s"
  of I32TruncSatF32U: result.add "i32.trunc_sat_f32_u"
  of I32TruncSatF64S: result.add "i32.trunc_sat_f64_s"
  of I32TruncSatF64U: result.add "i32.trunc_sat_f64_u"

  of I64ExtendI32S: result.add "i64.extend_i32_s"
  of I64ExtendI32U: result.add "i64.extend_i32_u"
  of I64TruncF32S: result.add "i64.trunc_f32_s"
  of I64TruncF32U: result.add "i64.trunc_f32_u"
  of I64TruncF64S: result.add "i64.trunc_f64_s"
  of I64TruncF64U: result.add "i64.trunc_f64_u"
  of I64TruncSatF32S: result.add "i64.trunc_sat_f32_s"
  of I64TruncSatF32U: result.add "i64.trunc_sat_f32_u"
  of I64TruncSatF64S: result.add "i64.trunc_sat_f64_s"
  of I64TruncSatF64U: result.add "i64.trunc_sat_f64_u"

  of F32ConvertI32S: result.add "f32.convert_i32_s"
  of F32ConvertI32U: result.add "f32.convert_i32_u"
  of F32ConvertI64S: result.add "f32.convert_i64_s"
  of F32ConvertI64U: result.add "f32.convert_i64_u"
  of F32DemoteF64: result.add "f32.demote_f64"

  of F64ConvertI32S: result.add "f64.convert_i32_s"
  of F64ConvertI32U: result.add "f64.convert_i32_u"
  of F64ConvertI64S: result.add "f64.convert_i64_s"
  of F64ConvertI64U: result.add "f64.convert_i64_u"
  of F64PromoteF32: result.add "f64.promote_f32"

  of I32ReinterpretF32: result.add "i32.reinterpret_f32"
  of I64ReinterpretF64: result.add "i64.reinterpret_f64"
  of F32ReinterpretI32: result.add "f32.reinterpret_i32"
  of F64ReinterpretI64: result.add "f64.reinterpret_i64"

  of I32Extend8S: result.add "i32.extend8_s"
  of I32Extend16S: result.add "i32.extend16_s"
  of I64Extend8S: result.add "i64.extend8_s"
  of I64Extend16S: result.add "i64.extend16_s"
  of I64Extend32S: result.add "i64.extend32_s"

proc getExprWat(self: WasmBuilder, exp: WasmExpr): string =
  for i, instr in exp.instr:
    if i > 0: result.add "\n"
    result.add self.getInstrWat(instr, 0)

proc getTypeSectionWat(self: WasmBuilder): string =
  # (type (;9;) (func (param i32 i32 i32 i32) (result i32)))
  for i, typ in self.types:
    result.add "\n"
    result.add "(type (;"
    result.add $i
    result.add ";) "
    result.add $typ
    result.add ")"

proc getImportSectionWat(self: WasmBuilder): string =
  # (import "wasi_snapshot_preview1" "fd_seek" (func $__wasi_fd_seek (type 28)))

  proc genImport(i: int, imp: WasmImport): string =
    result.add "\n"
    result.add fmt"(import (;{i};) "
    result.add "\""
    result.add imp.module
    result.add "\" \""
    result.add imp.name
    result.add "\" "
    result.add self.getImportDescWat(imp.desc)
    result.add ")"

  for i, imp in self.functionImports:
    result.add genImport(i, imp)

  for i, imp in self.tableImports:
    result.add genImport(i, imp)

  for i, imp in self.memImports:
    result.add genImport(i, imp)

  for i, imp in self.tableImports:
    result.add genImport(i, imp)

proc getFunctionSectionWat(self: WasmBuilder): string =
  # (func $emscripten_stack_get_current (type 7) (result i32)
  #     global.get $__stack_pointer)
  for i, v in self.funcs:
    result.add "\n"
    let funcIdx = getEffectiveFunctionIdx(self, i.WasmFuncIdx)
    let id = if v.id.len > 0: v.id else: fmt"func{funcIdx}"
    result.add fmt"(func (;{funcIdx};) ${id} (type {v.typeIdx}) "
    result.add getResultTypeWat(self.types[v.typeIdx.uint32].input, "param")
    result.add " "
    result.add getResultTypeWat(self.types[v.typeIdx.uint32].output, "result")
    result.add " "

    let funcTyp = self.types[v.typeIdx.int]
    let paramCount = funcTyp.input.types.len
    for k, local in v.locals:
      let id = if local.id.len > 0: local.id else: fmt"var{(paramCount + k)}"
      result.add &"\n (local (;{(paramCount + k)};) ${id} {local.typ})"

    result.add "\n"
    result.add getExprWat(self, v.body).indent(1, "  ")

    result.add ")"

proc getTableSectionWat(self: WasmBuilder): string =
  for i, v in self.tables:
    result.add "\n"
    result.add fmt"(table (;{i};) {v.typ})"

proc getMemorySectionWat(self: WasmBuilder): string =
  for i, v in self.mems:
    result.add "\n"
    result.add fmt"(memory (;{i};) {v.typ})"

proc getGlobalSectionWat(self: WasmBuilder): string =
  for i, v in self.globals:
    result.add "\n"
    let init = self.getExprWat(v.init)
    let id = if v.id.len > 0: v.id else: fmt"global{i}"
    result.add &"(global (;{i};) ${id} {v.typ} {init})"

proc getExportSectionWat(self: WasmBuilder): string =
  for i, v in self.exports:
    result.add "\n"
    result.add "(export "
    result.add v.name
    result.add " "

    case v.desc.kind
    of Func:
      result.add fmt"(func {getEffectiveFunctionIdx(self, v.desc.funcIdx)})"
    of Table:
      result.add fmt"(table {getEffectiveTableIdx(self, v.desc.tableIdx)})"
    of Mem:
      result.add fmt"(memory {getEffectiveMemIdx(self, v.desc.memIdx)})"
    of Global:
      result.add fmt"(global {getEffectiveGlobalIdx(self, v.desc.globalIdx)})"

proc getStartSectionWat(self: WasmBuilder): string =
  if self.start.getSome(start):
    result.add &"\n(start {getEffectiveFunctionIdx(self, start.start)})"

proc getElementListWat(self: WasmBuilder, typ: WasmValueType, exprs: openArray[WasmExpr]): string =
  result.add $typ
  for e in exprs:
    result.add " (item "
    result.add self.getExprWat(e)
    result.add ")"

proc getElementSectionWat(self: WasmBuilder): string =
  for i, v in self.elems:
    result.add "\n"

    case v.mode.kind:
    of Passive:
      result.add fmt"(elem {getElementListWat(self, v.typ, v.init)})"
    of Active:
      result.add fmt"(elem (table {getEffectiveTableIdx(self, v.mode.tableIdx)}) (offset {getExprWat(self, v.mode.offset)}) {getElementListWat(self, v.typ, v.init)})"
    of Declarative:
      result.add fmt"(elem declare {getElementListWat(self, v.typ, v.init)})"

proc getDataSectionWat(self: WasmBuilder): string =
  proc dataStringWat(str: openArray[uint8]): string =
    result = newStringOfCap(str.len * 4)
    const hexChars = "0123456789abcdef"
    for c in str:
      case c.char
      of '\t': result.add "\\t"
      of '\n': result.add "\\n"
      of '\r': result.add "\\r"
      of '\'': result.add "\\'"
      of '"': result.add "\\\""
      else:
        if c >= 0x20 and c < 0x7F:
          result.add chr(c)
        else:
          result.add "\\"
          result.add hexChars[c shr 4]
          result.add hexChars[c and 0xF]

  for i, v in self.datas:
    result.add "\n"
    result.add fmt"(data "

    case v.mode.kind:
    of Passive:
      discard
    of Active:
      result.add fmt"(memory {v.mode.memIdx}) (offset {getExprWat(self, v.mode.offset)}) "

    result.add "\""
    result.add dataStringWat(v.init)
    result.add "\")"

proc generateWat*(self: WasmBuilder): string =
  let indentString = "  "

  result.add "(module"
  result.add self.getTypeSectionWat().indent(1, indentString)
  result.add self.getImportSectionWat().indent(1, indentString)
  result.add self.getTableSectionWat().indent(1, indentString)
  result.add self.getMemorySectionWat().indent(1, indentString)
  result.add self.getGlobalSectionWat().indent(1, indentString)
  result.add self.getExportSectionWat().indent(1, indentString)
  result.add self.getStartSectionWat().indent(1, indentString)
  result.add self.getElementSectionWat().indent(1, indentString)
  result.add self.getDataSectionWat().indent(1, indentString)
  result.add self.getFunctionSectionWat().indent(1, indentString)
  result.add ")"

proc `$`*(self: WasmBuilder): string =
  return self.generateWat()

proc getStackChange*(self: WasmBuilder, instr: WasmInstr): int =
  # echo "writeInstr ", instr
  case instr.kind

  of Nop: return 0
  of Drop: return -1

  of Block:
    case instr.blockType.kind
    of TypeIdx:
      return 1
    of ValType:
      return if instr.blockType.typ.isSome: 1 else: 0

  of Loop:
    case instr.loopType.kind
    of TypeIdx:
      return 1
    of ValType:
      return if instr.loopType.typ.isSome: 1 else: 0

  of If:
    case instr.ifType.kind
    of TypeIdx:
      return 1-1
    of ValType:
      return if instr.ifType.typ.isSome: 1-1 else: 0-1

  of Br: return 0
  of BrIf: return -1

  of BrTable:
    # todo
    return 0

  of Call:
    let index = self.getEffectiveFunctionIdx(instr.callFuncIdx)
    let typIndex = if index < self.functionImports.len:
      self.functionImports[index].desc.funcTypeIdx
    else:
      self.funcs[index - self.functionImports.len].typeIdx
    let typ = self.types[typIndex.int]
    return typ.output.types.len - typ.input.types.len

  of CallIndirect:
    let typIndex = instr.callIndirectTypeIdx
    let typ = self.types[typIndex.int]
    return typ.output.types.len - typ.input.types.len + 1

  of RefNull, RefFunc: return 1

  of Select:
    if instr.selectValType.isSome:
      return -2
    else:
      # todo?
      return -2

  of LocalGet: return 1
  of LocalSet: return -1
  of LocalTee: return 0

  of GlobalGet: return 1
  of GlobalSet: return -1

  of TableGet: return 1
  of TableSet: return -1
  of TableInit: return -3
  of ElemDrop: return 0
  of TableCopy: return -3

  of TableGrow: return 0
  of TableSize: return 1
  of TableFill: return -2

  of I32Load, I64Load, F32Load, F64Load, I32Load8U, I32Load8S, I64Load8U, I64Load8S, I32Load16U, I32Load16S, I64Load16U, I64Load16S, I64Load32U, I64Load32S:
    return 0
  of I32Store, I64Store, F32Store, F64Store, I32Store8, I64Store8, I32Store16, I64Store16, I64Store32:
    return -2

  of MemorySize: return 1
  of MemoryGrow: return 0
  of MemoryInit: return -3
  of DataDrop: return 0
  of MemoryCopy: return -3
  of MemoryFill: return -3

  of I32Const, I64Const, F32Const, F64Const: return 1

  # unop := iunop | funop | extentN_s
  of I32Clz, I32Ctz, I32Popcnt: return 0 # iunop
  of I64Clz, I64Ctz, I64Popcnt: return 0 # iunop
  of F32Abs, F32Neg, F32Ceil, F32Floor, F32Trunc, F32Nearest, F32Sqrt: return 0 # funop
  of F64Abs, F64Neg, F64Ceil, F64Floor, F64Trunc, F64Nearest, F64Sqrt: return 0 # funop
  of I32Extend8S, I32Extend16S, I64Extend8S, I64Extend16S, I64Extend32S: return 0 # extentN_s

  # binop := ibinop | fbinop
  of I32Add, I32Sub, I32Mul, I32DivS, I32DivU, I32RemS, I32RemU, I32And, I32Or, I32Xor, I32Shl, I32ShrS, I32ShrU, I32Rotl, I32Rotr: return -1 # ibinop
  of I64Add, I64Sub, I64Mul, I64DivS, I64DivU, I64RemS, I64RemU, I64And, I64Or, I64Xor, I64Shl, I64ShrS, I64ShrU, I64Rotl, I64Rotr: return -1 # ibinop
  of F32Add, F32Sub, F32Mul, F32Div, F32Min, F32Max, F32Copysign: return -1 # fbinop
  of F64Add, F64Sub, F64Mul, F64Div, F64Min, F64Max, F64Copysign: return -1 # fbinop

  # testop := itestop
  of I32Eqz, I64Eqz: return 0

  # relop := irelop | frelop
  of I32Eq, I32Ne, I32LtS, I32LtU, I32GtS, I32GtU, I32LeS, I32LeU, I32GeS, I32GeU: return -1 # irelop
  of I64Eq, I64Ne, I64LtS, I64LtU, I64GtS, I64GtU, I64LeS, I64LeU, I64GeS, I64GeU: return -1 # irelop
  of F32Eq, F32Ne, F32Lt, F32Gt, F32Le, F32Ge: return -1 # frelop
  of F64Eq, F64Ne, F64Lt, F64Gt, F64Le, F64Ge: return -1 # frelop

  # cvtop := wrap | extend | trunc | trunc_sat | convert | demote | promote | reinterpret
  of I32WrapI64: return 0
  of I32TruncF32S, I32TruncF32U, I32TruncF64S, I32TruncF64U: return 0
  of I64ExtendI32S, I64ExtendI32U: return 0
  of I64TruncF32S, I64TruncF32U, I64TruncF64S, I64TruncF64U: return 0
  of F32ConvertI32S, F32ConvertI32U, F32ConvertI64S, F32ConvertI64U, F32DemoteF64: return 0
  of F64ConvertI32S, F64ConvertI32U, F64ConvertI64S, F64ConvertI64U, F64PromoteF32: return 0
  of I32ReinterpretF32, I64ReinterpretF64, F32ReinterpretI32, F64ReinterpretI64: return 0
  of I32TruncSatF32S, I32TruncSatF32U, I32TruncSatF64S, I32TruncSatF64U, I64TruncSatF32S, I64TruncSatF32U, I64TruncSatF64S, I64TruncSatF64U: return 0

  else:
    # todo
    log lvlError, fmt"getStackChange: unhandled instr {instr.kind}"
    return 0

proc getInstrType*(self: WasmBuilder, instr: WasmInstr): WasmFunctionType =
  return case instr.kind
  of Block:
    case instr.blockType.kind
    of TypeIdx:
      self.types[instr.blockType.idx.int]
    of ValType:
      if instr.blockType.typ.getSome(valueType):
        WasmFunctionType(
          input: WasmResultType(types: @[]),
          output: WasmResultType(types: @[valueType]),
        )
      else:
        WasmFunctionType()

  of Loop:
    case instr.loopType.kind
    of TypeIdx:
      self.types[instr.loopType.idx.int]
    of ValType:
      if instr.loopType.typ.getSome(valueType):
        WasmFunctionType(
          input: WasmResultType(types: @[]),
          output: WasmResultType(types: @[valueType]),
        )
      else:
        WasmFunctionType()

  of If:
    case instr.ifType.kind
    of TypeIdx:
      self.types[instr.ifType.idx.int]
    of ValType:
      if instr.ifType.typ.getSome(valueType):
        WasmFunctionType(
          input: WasmResultType(types: @[]),
          output: WasmResultType(types: @[valueType]),
        )
      else:
        WasmFunctionType()

  else:
    WasmFunctionType()

proc validate*(self: WasmBuilder, instr: WasmInstr, expectedSize: Option[int], path: seq[int], doLog: bool): bool =
  result = true

  if expectedSize.getSome(expectedSize) and self.getStackChange(instr) != expectedSize:
    if doLog: log lvlError, fmt"{path} validate: stack size mismatch, expected {expectedSize}, got {self.getStackChange(instr)} at {instr}"
    result = false

  let blockType = self.getInstrType(instr)

  case instr.kind:
  of Block:
    if doLog: debugf"{path} validate (expect {expectedSize}): {instr}"
    var stackSize = 0
    for i, sub in instr.blockInstr:
      let change = self.getStackChange(sub)
      if doLog: echo fmt"    block stackSize {stackSize} + {change} = {stackSize + change} ({sub})"
      stackSize += change
      if stackSize < 0:
        if doLog: log lvlError, fmt"{path}:{i} validate block: not enough values on stack at {instr}"

      if not self.validate(sub, int.none, path & @[i], doLog):
        result = false

    if stackSize != blockType.output.types.len:
      if doLog: log lvlError, fmt"{path} validate block: stack size mismatch at {instr}, expected {blockType.output.types.len}, got {stackSize}"
      result = false

  of Loop:
    var stackSize = 0
    for i, sub in instr.loopInstr:
      let change = self.getStackChange(sub)
      if doLog: echo fmt"    loop stackSize {stackSize} + {change} = {stackSize + change} ({sub})"
      stackSize += change
      if stackSize < 0:
        if doLog: log lvlError, fmt"{path}:{i} validate loop: not enough values on stack at {instr}"

      if not self.validate(sub, int.none, path & @[i], doLog):
        result = false

    if stackSize != blockType.output.types.len:
      if doLog: log lvlError, fmt"{path} validate loop: stack size mismatch at {instr}, expected {blockType.output.types.len}, got {stackSize}"
      result = false

  of If:
    var stackSize = 0
    for i, sub in instr.ifThenInstr:
      let change = self.getStackChange(sub)
      if doLog: echo fmt"    if then stackSize {stackSize} + {change} = {stackSize + change} ({sub})"
      stackSize += change
      if stackSize < 0:
        if doLog: log lvlError, fmt"{path}:{i} validate if then: not enough values on stack at {instr}"

      if not self.validate(sub, int.none, path & @[i], doLog):
        result = false

    if stackSize != blockType.output.types.len:
      if doLog: log lvlError, fmt"{path} validate if then: stack size mismatch at {instr}, expected {blockType.output.types.len}, got {stackSize}"
      result = false

    stackSize = 0
    for i, sub in instr.ifElseInstr:
      let change = self.getStackChange(sub)
      if doLog: echo fmt"    if else stackSize {stackSize} + {change} = {stackSize + change} ({sub})"
      stackSize += change
      if stackSize < 0:
        if doLog: log lvlError, fmt"{path}:{i} validate if else: not enough values on stack at {instr}"

      if not self.validate(sub, int.none, path & @[i], doLog):
        result = false

    if stackSize != blockType.output.types.len:
      if doLog: log lvlError, fmt"{path} validate if else: stack size mismatch at {instr}, expected {blockType.output.types.len}, got {stackSize}"
      result = false

  else:
    discard

proc validate*(self: WasmBuilder, doLog: bool): bool =
  result = true
  for i, f in self.funcs:
    let typ = self.types[f.typeIdx.int]
    let expectedStackSize = typ.output.types.len
    # if not self.validate(WasmInstr(kind: Block, blockInstr: f.body.instr), expectedStackSize.some, @[i]):
    #   log lvlError, fmt"validate function {f.typeIdx} failed"
    #   result = false

    if doLog: debugf"validate function {f.id} {typ}, expected stack size {expectedStackSize}"

    var stackSize = 0
    for k, sub in f.body.instr:
      let change = self.getStackChange(sub)
      if doLog: echo fmt"    function body stackSize {stackSize} + {change} = {stackSize + change} ({sub})"
      stackSize += change
      if stackSize < 0:
        if doLog: log lvlError, fmt"{i}:{k} validate function: not enough values on stack at {sub}"

      if not self.validate(sub, int.none, @[i, k], doLog):
        result = false

    if stackSize != expectedStackSize:
      if doLog: log lvlError, fmt"{i} validate function: stack size mismatch, expected {expectedStackSize}, got {stackSize}"
      result = false

when isMainModule:
  var builder = newWasmBuilder()

  # alloc
  builder.types.add(WasmFunctionType(
    input: WasmResultType(types: @[I32]),
    output: WasmResultType(types: @[I32]),
  ))

  # dealloc
  builder.types.add(WasmFunctionType(
    input: WasmResultType(types: @[I32]),
    output: WasmResultType(types: @[]),
  ))

  builder.types.add(WasmFunctionType(
    input: WasmResultType(types: @[]),
    output: WasmResultType(types: @[]),
  ))

  builder.types.add(WasmFunctionType(
    input: WasmResultType(types: @[I32, I64, F32, F64]),
    output: WasmResultType(types: @[]),
  ))

  builder.mems.add(WasmMem(typ: WasmMemoryType(limits: WasmLimits(min: 255))))

  builder.datas.add(WasmData(
    init: @[1, 2, 5],
    mode: WasmDataMode(kind: Active, memIdx: 0.WasmMemIdx, offset: WasmExpr(instr: @[
      WasmInstr(kind: I32Const, i32Const: 456),
    ]))
  ))

  builder.datas.add(WasmData(
    init: @[],
    mode: WasmDataMode(kind: Active, memIdx: 0.WasmMemIdx, offset: WasmExpr(instr: @[
      WasmInstr(kind: I32Const, i32Const: 456),
    ]))
  ))

  discard builder.addImport("test module", "test name", 2.WasmTypeIdx)
  discard builder.addImport("test module", "test name 2", 3.WasmTypeIdx)

  builder.exports.add(WasmExport(
    name: "my_alloc",
    desc: WasmExportDesc(kind: Func, funcIdx: 2.WasmFuncIdx)
  ))

  builder.exports.add(WasmExport(
    name: "my_dealloc",
    desc: WasmExportDesc(kind: Func, funcIdx: 3.WasmFuncIdx)
  ))

  builder.exports.add(WasmExport(
    name: "test export name",
    desc: WasmExportDesc(kind: Func, funcIdx: 5.WasmFuncIdx)
  ))

  # my_alloc
  builder.funcs.add(WasmFunc(
    typeIdx: 0.WasmTypeIdx,
    locals: @[],
    body: WasmExpr(instr: @[
      WasmInstr(kind: I32Const, i32Const: 0),
    ]),
  ))

  # my_dealloc
  builder.funcs.add(WasmFunc(
    typeIdx: 1.WasmTypeIdx,
    locals: @[],
    body: WasmExpr(instr: @[
      WasmInstr(kind: Nop),
    ]),
  ))

  builder.funcs.add(WasmFunc(
    typeIdx: 2.WasmTypeIdx,
    locals: @[],
    body: WasmExpr(instr: @[
      WasmInstr(kind: Loop, loopType: WasmBlockType(kind: ValType, typ: I32.some), loopInstr: @[
        WasmInstr(kind: F32Const, f32Const: -1.23),
        WasmInstr(kind: F32Const, f32Const: 456.789),
        WasmInstr(kind: F32Add),
        WasmInstr(kind: I32TruncSatF32U),
        WasmInstr(kind: BrIf, brLabelIdx: 0.WasmLabelIdx),
        WasmInstr(kind: I32Const, i32Const: 456),

      ]),
      WasmInstr(kind: Drop),
    ]),
  ))

  builder.funcs.add(WasmFunc(
    typeIdx: 3.WasmTypeIdx,
    locals: @[I32, I64, F32, F64],
    body: WasmExpr(instr: @[
      WasmInstr(kind: Call, callFuncIdx: 0.WasmFuncIdx),
      WasmInstr(kind: LocalGet, localIdx: 0.WasmLocalIdx),
      WasmInstr(kind: LocalGet, localIdx: 1.WasmLocalIdx),
      WasmInstr(kind: LocalGet, localIdx: 2.WasmLocalIdx),
      WasmInstr(kind: LocalGet, localIdx: 3.WasmLocalIdx),
      WasmInstr(kind: Call, callFuncIdx: 1.WasmFuncIdx),
    ]),
  ))

  builder.globals.add(WasmGlobal(
    typ: WasmGlobalType(mut: true, typ: F64),
    init: WasmExpr(instr: @[
      WasmInstr(kind: F64Const, f64Const: 456789.123456),
    ]),
  ))

  builder.tables.add(WasmTable(
    typ: WasmTableType(limits: WasmLimits(min: 0, max: 10.uint32.some), refType: FuncRef)
  ))

  let binary = builder.generateBinary()
  writeFile("./config/test.wasm", binary)

  echo builder

  import wasm, custom_async, array_buffer

  proc foo() =
    echo "foo"

  proc bar(a: int32, b: int64, c: float32, d: float64) =
    echo "bar"
    echo a
    echo b
    echo c
    echo d

  var imp = WasmImports(namespace: "test module")
  imp.addFunction("test name", foo)
  imp.addFunction("test name 2", bar)

  let module = waitFor newWasmModule(binary.toArrayBuffer, @[imp])
  if module.isNone:
    echo "Failed to load module"
    quit(0)

  if module.get.findFunction("test export name", void, proc(a: int32, b: int64, c: float32, d: float64): void).getSome(f):
    echo "call exported func"
    f(1, 2, 3.4, 5.6)


