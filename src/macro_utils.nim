import std/[macros, genasts]
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
      template `memberName`*(self: `selfType`): `returnType` = self.`member`

  # echo result.treeRepr
  # echo result.repr

proc argName*(def: NimNode, arg: int): NimNode =
  result = def[3][arg + 1][0]
  if result.kind == nnkPragmaExpr:
    result = result[0]

proc typeName*(def: NimNode): NimNode =
  assert def.kind == nnkTypeDef
  case def.kind
  of nnkTypeDef:
    if def[0].kind == nnkIdent:
      return def[0]
    if def[0].kind == nnkPostfix and def[0][1].kind == nnkIdent:
      return def[0][1]
    assert false
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

macro defineBitFlag*(body: untyped): untyped =
  let flagName = body[0][0].typeName
  let flagsName = (flagName.repr & "s").ident

  result = genAst(body, flagName, flagsName):
    body
    type flagsName* = distinct uint32

    func contains*(flags: flagsName, flag: flagName): bool {.inline.} = (flags.uint32 and (1.uint32 shl flag.uint32)) != 0
    func all*(flags: flagsName, expected: flagsName): bool {.inline.} = (flags.uint32 and expected.uint32) == expected.uint32
    func any*(flags: flagsName, expected: flagsName): bool {.inline.} = (flags.uint32 and expected.uint32) != 0
    func incl*(flags: var flagsName, flag: flagName) {.inline.} =
      flags = (flags.uint32 or (1.uint32 shl flag.uint32)).flagsName
    func excl*(flags: var flagsName, flag: flagName) {.inline.} =
      flags = (flags.uint32 and not (1.uint32 shl flag.uint32)).flagsName
    func `-`*(a: flagsName, b: flagsName): flagsName {.inline.} = (a.uint32 and not b.uint32).flagsName
    func `-`*(a: flagsName, b: flagName): flagsName {.inline.} = (a.uint32 and not (1.uint32 shl b.uint32)).flagsName
    func `+`*(a: flagsName, b: flagsName): flagsName {.inline.} = (a.uint32 or b.uint32).flagsName
    func `+`*(a: flagsName, b: flagName): flagsName {.inline.} = (a.uint32 or (1.uint32 shl b.uint32)).flagsName

    func `==`*(a, b: flagsName): bool {.borrow.}

    macro `&`*(flags: static set[flagName]): flagsName =
      var res = 0.flagsName
      for flag in flags:
        res.incl flag
      return genAst(res2 = res.uint32):
        res2.flagsName

    iterator flags*(self: flagsName): flagName =
      for v in flagName.low..flagName.high:
        if (self.uint32 and (1.uint32 shl v.uint32)) != 0:
          yield v

    proc `$`*(self: flagsName): string =
      var res2: string = "{"
      for flag in self.flags:
        if res2.len > 1:
          res2.add ", "
        res2.add $flag
      res2.add "}"
      return res2