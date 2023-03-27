import std/[macros]
import util

template getter*() {.pragma.}

proc getPragmaNode*(node: NimNode): Option[NimNode] =
  result = NimNode.none
  if node.kind == nnkIdentDefs and node[0].kind == nnkPragmaExpr:
    return node[0][1].some

proc myHasCustomPragma*(n: NimNode, cp: NimNode): bool =
  const nnkPragmaCallKinds = {nnkExprColonExpr, nnkCall, nnkCallStrLit}
  if n.getPragmaNode.getSome(pragmaNode):
    for p in pragmaNode:
      if (p.kind == nnkSym and p == cp) or
          (p.kind in nnkPragmaCallKinds and p.len > 0 and p[0].kind == nnkSym and p[0] == cp):
        return true
  return false

macro generateGetters*(T: typedesc): untyped =
  let refOrObjType = T.getImpl[2]
  let objType = if refOrObjType.kind == nnkRefTy: refOrObjType[0] else: refOrObjType

  result = nnkStmtList.newTree

  let members = objType[2]
  for m in members:
    # echo m.treeRepr
    if not m.myHasCustomPragma(bindSym("getter")):
      continue

    let selfType = T
    let returnType = m[1]
    let member = m[0][0]
    let memberName = member.strVal.ident

    result.add quote do:
      proc `memberName`*(self: `selfType`): `returnType` =
        return self.`member`

  # echo result.treeRepr
  # echo result.repr