
import std/[macrocache, strutils, json, options, tables, genasts, sequtils]
import binary_encoder, custom_async
import util

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

  WasmValueType* {.pure.} = enum I32, I64, F32, F64, V128, FuncRef, ExternRef
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
    RefNull = 0xD0, RefIsNul, RefFunc,

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
    of Select: selectValType*: Option[WasmValueType]

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
    locals*: seq[WasmValueType]
    body*: WasmExpr

  WasmTable* = object
    typ*: WasmTableType

  WasmMem* = object
    typ*: WasmMemoryType

  WasmGlobal* = object
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
    imports*: seq[WasmImport]
    exports*: seq[WasmExport]

proc newWasmBuilder*(): WasmBuilder =
  new result

proc getNumFunctionImports(self: WasmBuilder): int =
  for i in self.imports:
    if i.desc.kind == WasmImportDescKind.Func:
      inc result

proc getEffectiveFunctionIdx(self: WasmBuilder, funcIdx: WasmFuncIdx): int =
  return funcIdx.int + self.getNumFunctionImports()

proc addFunction*(self: WasmBuilder,
  inputs: openArray[WasmValueType], outputs: openArray[WasmValueType], exportName: Option[string] = string.none): WasmFuncIdx =
  let typeIdx = self.types.len.WasmTypeIdx
  self.types.add WasmFunctionType(input: WasmResultType(types: @inputs), output: WasmResultType(types: @outputs))

  let funcIdx = self.funcs.len.WasmFuncIdx

  self.funcs.add WasmFunc(
    typeIdx: typeIdx,
  )

  if exportName.getSome(exportName):
    self.exports.add WasmExport(
      name: exportName,
      desc: WasmExportDesc(kind: Func, funcIdx: funcIdx)
    )

  return funcIdx

proc addFunction*(self: WasmBuilder,
  inputs: openArray[WasmValueType], outputs: openArray[WasmValueType], locals: openArray[WasmValueType], body: WasmExpr, exportName: Option[string] = string.none): WasmFuncIdx =
  let typeIdx = self.types.len.WasmTypeIdx
  self.types.add WasmFunctionType(input: WasmResultType(types: @inputs), output: WasmResultType(types: @outputs))

  let funcIdx = self.funcs.len.WasmFuncIdx

  self.funcs.add WasmFunc(
    typeIdx: typeIdx,
    locals: @locals,
    body: body
  )

  if exportName.getSome(exportName):
    self.exports.add WasmExport(
      name: exportName,
      desc: WasmExportDesc(kind: Func, funcIdx: funcIdx)
    )

  return funcIdx

proc setBody*(self: WasmBuilder, funcIdx: WasmFuncIdx, locals: openArray[WasmValueType], body: WasmExpr) =
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
  echo "writeInstr ", instr
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
    encoder.writeLength(instr.callIndirectTableIdx.int)

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
    encoder.writeLength(instr.globalIdx.int)

  of TableGet, TableSet:
    encoder.write(byte, instr.kind.byte)
    encoder.writeLength(instr.tableOpIdx.int)

  of TableInit:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)
    encoder.writeLength(instr.tableInitElementIdx.int)
    encoder.writeLength(instr.tableInitIdx.int)

  of ElemDrop:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)
    encoder.writeLength(instr.elemDropIdx.int)

  of TableCopy:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)
    encoder.writeLength(instr.tableCopyTargetIdx.int)
    encoder.writeLength(instr.tableCopySourceIdx.int)

  of TableGrow, TableSize, TableFill:
    encoder.write(byte, 0xFC)
    encoder.writeLength(instr.kind.int and 0xFF)
    encoder.writeLength(instr.tableOpIdx.int)

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
  if self.imports.len > 0:
    generateSection(self, encoder, 2):
      e.writeLength(self.imports.len)
      for v in self.imports:
        e.writeString(v.module)
        e.writeString(v.name)

        case v.desc.kind
        of Func:
          e.write(byte, 0x00)
          e.writeLEB128(uint32, v.desc.funcTypeIdx.uint32)
        of Table:
          e.write(byte, 0x01)
          e.writeType(v.desc.table)
        of Mem:
          e.write(byte, 0x02)
          e.writeType(v.desc.mem)
        of Global:
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
          e.writeLength(v.desc.tableIdx.int)
        of Mem:
          e.write(byte, 0x02)
          e.writeLength(v.desc.memIdx.int)
        of Global:
          e.write(byte, 0x03)
          e.writeLength(v.desc.globalIdx.int)

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
          if v.typ != FuncRef and v.mode.tableIdx.int == 0:
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
          e.writeLength(v.mode.tableIdx.int)
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
          e.writeLength(v.mode.tableIdx.int)
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
          funcEncoder.writeType(l)

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

  builder.imports.add(WasmImport(
    module: "test module",
    name: "test name",
    desc: WasmImportDesc(kind: Func, funcTypeIdx: 2.WasmTypeIdx)
  ))

  builder.imports.add(WasmImport(
    module: "test module",
    name: "test name 2",
    desc: WasmImportDesc(kind: Func, funcTypeIdx: 3.WasmTypeIdx)
  ))

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

  # builder.tables.add(WasmTable(
  #   typ: WasmTableType(limits: WasmLimits(min: 0, max: 10.uint32.some), refType: FuncRef)
  # ))


  let binary = builder.generateBinary()
  writeFile("./config/test.wasm", binary)

  import wasm

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

  let module = waitFor newWasmModule(binary, @[imp])
  if module.isNone:
    echo "Failed to load module"
    quit(0)

  if module.get.findFunction("test export name", void, proc(a: int32, b: int64, c: float32, d: float64): void).getSome(f):
    echo "call exported func"
    f(1, 2, 3.4, 5.6)


