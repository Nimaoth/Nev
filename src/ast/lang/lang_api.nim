import std/[strformat, options]
import misc/[id, util, custom_logger]
import ui/node
import ast/[model, base_language]
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

proc langApiNodeChildren(module: WasmModule, retPtr: WasmPtr, nodeIndexPtr: WasmPtr) =
  let nodeIndex = module.getInt32(nodeIndexPtr)
  let node = gNodeRegistry.getNode(nodeIndex).getOr:
    log lvlError, fmt"Invalid node handle: {nodeIndex}"
    module.setInt32(retPtr, 0)
    module.setInt32(retPtr + 4, 0)
    module.setInt32(retPtr + 8, 0)
    return

  var childrenCount = 0
  for i in 0..node.childLists.high:
    childrenCount += node.childLists[i].nodes.len

  let mem = module.alloc(childrenCount.uint32 * 4)

  var index = 0
  for children in node.childLists.mitems:
    for c in children.nodes:
      let nodeIndex = gNodeRegistry.getNodeIndex(c)
      module.setInt32(mem + index * 4, nodeIndex)
      index += 1

  module.setInt32(retPtr, childrenCount.int32)
  module.setInt32(retPtr + 4, childrenCount.int32)
  module.setInt32(retPtr + 8, mem.int32)

proc langApiNodeModel(module: WasmModule, retPtr: WasmPtr, nodeIndexPtr: WasmPtr) =
  let nodeIndex = module.getInt32(nodeIndexPtr)
  let node = gNodeRegistry.getNode(nodeIndex).getOr:
    log lvlError, fmt"Invalid node handle: {nodeIndex}"
    module.setInt32(retPtr, 0)
    return

  let model = node.model
  if model.isNil:
    module.setInt32(retPtr, 0)
    return

  let modelIndex = gNodeRegistry.getModelIndex(model)
  module.setInt32(retPtr, modelIndex)

proc langApiModelRootNodes(module: WasmModule, retPtr: WasmPtr, modelIndexPtr: WasmPtr) =
  let modelIndex = module.getInt32(modelIndexPtr)
  let model = gNodeRegistry.getModel(modelIndex).getOr:
    log lvlError, fmt"Invalid model handle: {modelIndex}"
    module.setInt32(retPtr, 0)
    module.setInt32(retPtr + 4, 0)
    module.setInt32(retPtr + 8, 0)
    return

  let mem = module.alloc(model.rootNodes.len.uint32 * 4)
  for i in 0..model.rootNodes.high:
    let nodeIndex = gNodeRegistry.getNodeIndex(model.rootNodes[i])
    module.setInt32(mem + i * 4, nodeIndex)

  module.setInt32(retPtr, model.rootNodes.len.int32)
  module.setInt32(retPtr + 4, model.rootNodes.len.int32)
  module.setInt32(retPtr + 8, mem.int32)

proc getLangApiImports*(): WasmImports =
  result = WasmImports(namespace: "base")
  result.addFunction("node-id", langApiNodeId)
  result.addFunction("id-to-string", langApiIdToString)
  result.addFunction("node-parent", langApiNodeParent)
  result.addFunction("node-children", langApiNodeChildren)
  result.addFunction("node-model", langApiNodeModel)
  result.addFunction("model-root-nodes", langApiModelRootNodes)
