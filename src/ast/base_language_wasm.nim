
import std/[options, tables]
import id, types, base_language, ast_ids
import scripting/[wasm, wasm_builder]

type
  BaseLanguageWasmCompiler* = ref object
    builder: WasmBuilder

    wasmFuncs: Table[Id, WasmFuncIdx]

    functionsToCompile: seq[AstNode]

proc newBaseLanguageWasmCompiler*(): BaseLanguageWasmCompiler =
  new result
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

proc genNode*(self: BaseLanguageWasmCompiler, model: AstNode) =
  discard

proc getOrCreateWasmFunc(self: BaseLanguageWasmCompiler, node: AstNode, exportName: Option[string] = string.none): WasmFuncIdx =
  if not self.wasmFuncs.contains(node.id):
    let funcIdx = self.builder.addFunction([], [], exportName=exportName)
    self.wasmFuncs[node.id] = funcIdx
    self.functionsToCompile.add node

  return self.wasmFuncs[node.id]

proc compileFunction(self: BaseLanguageWasmCompiler, node: AstNode) =
  let body = node.children(IdFunctionDefinitionBody)
  if body.len != 1:
    return

  self.genNode(body[0])

proc compileRemainingFunctions(self: BaseLanguageWasmCompiler) =
  while self.functionsToCompile.len > 0:
    let function = self.functionsToCompile.pop
    self.compileFunction(function)

proc compileToBinary*(self: BaseLanguageWasmCompiler, node: AstNode): seq[uint8] =
  let funcIdx = self.getOrCreateWasmFunc(node, exportName="test".some)
  self.compileRemainingFunctions()

  let binary = self.builder.generateBinary()
  return binary
