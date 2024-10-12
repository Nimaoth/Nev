import std/[macros, genasts]
import std/[tables]
import misc/[custom_logger, util]
import scripting/[wasm_builder]
import model, ast_ids, base_language, editor_language, generator_wasm

logCategory "editor-language-wasm"

type EditorLanguageExtension = ref object of LanguageWasmCompilerExtension

proc genLoadAppFile(self: EditorLanguageExtension, node: AstNode, dest: Destination) =
  for i, c in node.children(IdLoadAppFileArgument):
    self.compiler.genNode(c, Destination(kind: Stack))

    let typ = self.compiler.ctx.computeType(c)
    if typ.class == IdString:
      self.compiler.instr(I32WrapI64)
    else:
      log lvlError, fmt"genNodePrintExpression: Type not implemented: {`$`(typ, true)}"
      return

  let funcIdx = self.compiler.getWasmFunc(IdLoadAppFile.Id)
  self.compiler.instr(Call, callFuncIdx: funcIdx)
  self.compiler.instr(Call, callFuncIdx: self.compiler.cstrToInternal)

  self.compiler.genStoreDestination(node, dest)

proc addEditorLanguage*(self: BaseLanguageWasmCompiler) =
  let ext = EditorLanguageExtension()
  self.addExtension(ext)

  ext.addGenerator(IdLoadAppFile, genLoadAppFile)

  self.addImport(IdLoadAppFile.Id, "env", "loadAppFile", [WasmValueType.I32], [WasmValueType.I32])

  # todo
  # ext.addFunctionInputOutput(IdFunctionDefinition, getFunctionInputOutput)
  # self.wasmValueTypes[IdInt32] = (WasmValueType.I32, I32Load, I32Store) # int32
  # self.typeAttributes[IdInt32] = (4'i32, 4'i32, false)
  # self.typeAttributeComputers[IdStructDefinition] = proc(typ: AstNode): TypeAttributes = self.computeStructTypeAttributes(typ)
