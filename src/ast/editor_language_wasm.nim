import std/[macros, genasts, sugar]
import std/[tables]
import misc/[custom_logger, util]
import scripting/[wasm_builder]
import model, ast_ids, base_language, editor_language, generator_wasm
import scripting/scripting_wasm

logCategory "editor-language-wasm"

type EditorLanguageExtension = ref object of LanguageWasmCompilerExtension

proc genCallBuiltin(self: EditorLanguageExtension, node: AstNode, dest: Destination, id: ClassId, argId: RoleId) =
  for i, c in node.children(argId):
    self.compiler.genNode(c, Destination(kind: Stack))

    let typ = self.compiler.ctx.computeType(c)
    if typ.class == IdString:
      self.compiler.instr(I32WrapI64)
    else:
      log lvlError, fmt"genNodePrintExpression: Type not implemented: {`$`(typ, true)}"
      return

  let funcIdx = self.compiler.getWasmFunc(id.Id)
  self.compiler.instr(Call, callFuncIdx: funcIdx)
  self.compiler.instr(Call, callFuncIdx: self.compiler.cstrToInternal)

  self.compiler.genStoreDestination(node, dest)

proc addEditorLanguage*(self: BaseLanguageWasmCompiler) =
  let ext = EditorLanguageExtension()
  self.addExtension(ext)

  var editorImports = ({.gcsafe.}: createEditorWasmImports())

  proc genLoadAppFile(self: EditorLanguageExtension, node: AstNode, dest: Destination) =
    genCallBuiltin(self, node, dest, IdLoadAppFile, IdLoadAppFileArgument)
  ext.addGenerator(IdLoadAppFile, genLoadAppFile)
  self.addImport(IdLoadAppFile.Id, "env", "loadAppFile", [WasmValueType.I32], [WasmValueType.I32])

  for i, name in editorImports.functionNames:
    let id = editorImports.ids[i].ClassId
    let argId = editorImports.argIds[i].RoleId

    capture id, argId:
      proc gen(self: EditorLanguageExtension, node: AstNode, dest: Destination) =
        genCallBuiltin(self, node, dest, id, argId)
      ext.addGenerator(id, gen)
      self.addImport(id.Id, "env", name, [WasmValueType.I32], [WasmValueType.I32])

  # todo
  # ext.addFunctionInputOutput(IdFunctionDefinition, getFunctionInputOutput)
  # self.wasmValueTypes[IdInt32] = (WasmValueType.I32, I32Load, I32Store) # int32
  # self.typeAttributes[IdInt32] = (4'i32, 4'i32, false)
  # self.typeAttributeComputers[IdStructDefinition] = proc(typ: AstNode): TypeAttributes = self.computeStructTypeAttributes(typ)
