import std/[macros]
import fusion/matching
import util

{.experimental: "caseStmtMacros".}

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

proc argName*(def: NimNode, arg: int): NimNode =
  result = def[3][arg + 1][0]
  if result.kind == nnkPragmaExpr:
    result = result[0]

proc typeName*(def: NimNode): NimNode =
  assert def.kind == nnkTypeDef
  case def
  of TypeDef[@ident is Ident(), .._]:
    return ident
  of TypeDef[Postfix[_, @ident is Ident()], .._]:
    return ident
  else:
    assert false

proc hasCustomPragma*(def: NimNode, pragma: string): bool =
  case def.kind
  of nnkProcDef:
    if def[4].kind == nnkPragma:
      for c in def[4]:
        if c.kind == nnkIdent and c.strVal == pragma:
          return true
  else:
    return false

proc argHasPragma*(def: NimNode, arg: int, pragma: string): bool =
  let node = def[3][arg + 1][0]
  if node.kind == nnkPragmaExpr and node.len >= 2 and node[1].kind == nnkPragma and node[1][0].strVal == pragma:
    return true
  return false
proc isVarargs*(def: NimNode, arg: int): bool = def.argHasPragma(arg, "varargs")
proc argType*(def: NimNode, arg: int): NimNode = def[3][arg + 1][1]
proc argDefaultValue*(def: NimNode, arg: int): Option[NimNode] =
  if def[3][arg + 1][2].kind != nnkEMpty:
    return def[3][arg + 1][2].some
  return NimNode.none

proc returnType*(def: NimNode): Option[NimNode] =
  return if def[3][0].kind != nnkEmpty: def[3][0].some else: NimNode.none

proc getDocumentation*(def: NimNode): Option[NimNode] =
  if def[6].len > 0 and def[6][0].kind == nnkCommentStmt:
    return def[6][0].some
  else:
    NimNode.none