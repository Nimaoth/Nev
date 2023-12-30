import std/[tables, strformat, options, os, sugar]
import misc/[id, util, custom_logger, custom_async, array_buffer, array_table]
import ui/node
import ast/[model, cells, cell_builder_database, base_language, generator_wasm, base_language_wasm]
import scripting/wasm

logCategory "lang-api"

proc langApiNodeParent(module: WasmModule, retNodeHandlePtr: WasmPtr, nodeHandlePtr: WasmPtr) =
  # debugf"langApiNodeParent {retNodeHandlePtr}, {nodeHandlePtr}"
  let nodeIndex = module.getInt32(nodeHandlePtr)
  let node = gNodeRegistry.getNode(nodeIndex).getOr:
    log lvlError, fmt"Invalid node handle: {nodeIndex}"
    module.setInt32(retNodeHandlePtr, 0)
    return

  # debugf"baseNodeParent: {retNodeHandlePtr}, {nodeHandlePtr}, {nodeIndex}, {node}"
  if node.parent.isNil:
    module.setInt32(retNodeHandlePtr, 0)
    return

  let parentIndex = gNodeRegistry.getNodeIndex(node.parent)
  module.setInt32(retNodeHandlePtr, parentIndex)

proc langApiNodeId(module: WasmModule, retPtr: WasmPtr, nodeIndexPtr: WasmPtr) =
  # debugf"langApiNodeId {retPtr}, {nodeIndexPtr}"
  let nodeIndex = module.getInt32(nodeIndexPtr)
  let node = gNodeRegistry.getNode(nodeIndex).getOr:
    log lvlError, fmt"Invalid node handle: {nodeIndex}"
    module.setInt32(retPtr, 0)
    module.setInt32(retPtr + 4, 0)
    module.setInt32(retPtr + 8, 0)
    return

  let (a, b, c) = node.id.Id.deconstruct
  module.setInt32(retPtr, a)
  module.setInt32(retPtr + 4, b)
  module.setInt32(retPtr + 8, c)

proc langApiIdToString(module: WasmModule, idPtr: WasmPtr): string =
  # debugf"langApiIdToString {idPtr}"
  let a = module.getInt32(idPtr)
  let b = module.getInt32(idPtr + 4)
  let c = module.getInt32(idPtr + 8)
  let id = construct(a, b, c)
  return $id

proc getLangApiImports*(): WasmImports =
  result = WasmImports(namespace: "base")
  result.addFunction("node-parent", langApiNodeParent)
  result.addFunction("node-id", langApiNodeId)
  result.addFunction("id-to-string", langApiIdToString)
