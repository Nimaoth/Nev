import std/[macros, genasts]
import std/[tables]
import misc/[custom_logger, util]
import scripting/[wasm_builder]
import model, ast_ids, base_language, editor_language, generator_wasm

logCategory "editor-language-wasm"

proc genLoadAppFile(self: BaseLanguageWasmCompiler, node: AstNode, dest: Destination) =
  for i, c in node.children(IdLoadAppFileArgument):
    self.genNode(c, Destination(kind: Stack))

    let typ = self.ctx.computeType(c)
    if typ.class == IdString:
      self.instr(I32WrapI64)
    else:
      log lvlError, fmt"genNodePrintExpression: Type not implemented: {`$`(typ, true)}"
      return

  let funcIdx = self.getWasmFunc(IdLoadAppFile.Id)
  self.instr(Call, callFuncIdx: funcIdx)
  self.instr(Call, callFuncIdx: self.cstrToInternal)

  self.genStoreDestination(node, dest)

proc addEditorLanguage*(self: BaseLanguageWasmCompiler) =
  self.generators[IdLoadAppFile] = genLoadAppFile

  self.addImport(IdLoadAppFile.Id, "env", "loadAppFile", [WasmValueType.I32], [WasmValueType.I32])

  # self.functionInputOutputComputer[IdFunctionDefinition] = getFunctionInputOutput
  # self.wasmValueTypes[IdInt32] = (WasmValueType.I32, I32Load, I32Store) # int32
  # self.typeAttributes[IdInt32] = (4'i32, 4'i32, false)
  # self.typeAttributeComputers[IdStructDefinition] = proc(typ: AstNode): TypeAttributes = self.computeStructTypeAttributes(typ)
