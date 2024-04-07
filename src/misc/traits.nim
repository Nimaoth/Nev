import std/[macros, genasts, options, macrocache]
import util

const traitFunctionCache = CacheTable"TraitCache"

macro bindFunction*(call: typed): untyped =
  return call[0]

func toRef*[T](v: T): ref T =
  result[] = v

proc getTraitFunctions*(trait: NimNode): seq[NimNode] =
  let key = trait.repr
  if traitFunctionCache.contains(key):
    for existingTrait in traitFunctionCache[key]:
      if existingTrait[1][0] == trait:
        for i in 1..<existingTrait[1].len:
          result.add existingTrait[1][i]
        return

proc getTraitFunction*(trait: NimNode, name: NimNode): Option[NimNode] =
  let key = trait.repr
  if traitFunctionCache.contains(key):
    for existingTrait in traitFunctionCache[key]:
      if existingTrait[1][0] == trait:
        for i in 1..<existingTrait[1].len:
          if eqIdent(existingTrait[1][i], name):
            return existingTrait[1][i].some

macro addTraitFunction(trait: typed, function: typed) =
  # defer:
  #   echo "addTraitFunction ", trait.repr, ", ", function.repr
  #   for (key, node) in traitFunctionCache.pairs:
  #     echo node.treeRepr
  #   echo "-----"

  let key = trait.repr

  var function = function
  if function.kind in {nnkClosedSymChoice, nnkOpenSymChoice}:
    for c in function:
      let impl = c.getImpl
      if impl[3].len < 1:
        continue

      let firstParam = impl[3][1][1]
      if firstParam == trait:
        function = c
        break

  var list = if traitFunctionCache.contains(key):
    traitFunctionCache[key]
  else:
    nnkStmtList.newTree()

  for i, existingTrait in list:
    if existingTrait[1][0] == trait:
      existingTrait[1].add function
      return

  list.add nnkCall.newTree(ident"dumpTree", nnkStmtList.newTree(trait, function))
  traitFunctionCache[key] = list

proc genTypeSection(name: NimNode, body: NimNode, isRef: bool): NimNode =
  # defer:
  #   echo result.repr

  if isRef:
    result = genAst(name, conceptName = ident("I" & name.repr), asTrait = ident("as" & name.repr)):
      type
        name* = ref object of RootObj
        conceptName* {.explain.} = concept x, T
          asTrait(x) is name
  else:
    result = genAst(name, conceptName = ident("I" & name.repr), asTrait = ident("as" & name.repr)):
      type
        name* = object of RootObj
        conceptName* {.explain.} = concept x, T
          asTrait(x) is name

  # todo: make this work
  # for item in body:
  #   if item.kind != nnkMethodDef:
  #     continue

  #   let returnType = if item[3][0].kind == nnkEmpty:
  #     ident"void"
  #   else:
  #     item[3][0]

  #   echo returnType.treeRepr

  #   var call = genAst(methodName = item.name.repr.ident, x = result[1][2][0][0]):
  #     methodName(x)

  #   for i in 2..<item[3].len:
  #     call.add item[3][i][1]

  #   let methodRequirement = genAst(call, returnType):
  #     call is returnType

  #   result[1][2][3].add methodRequirement

proc traitImpl*(name: NimNode, body: NimNode, isRef: bool): NimNode =
  # defer:
  #   echo result.repr
    # echo result.treeRepr

  let typeSection = genTypeSection(name, body, isRef)

  var methods: seq[NimNode] = @[]
  for item in body:
    case item.kind
    of nnkMethodDef:
      item[4] = genAst():
        {.base.}
      item[6] = genAst():
        discard

      methods.add item

      let temp = genAst(name, function = item.name):
        addTraitFunction(name, function)
      methods.add temp

    else:
      error("This kind of node is not allowed here: " & $item.kind & ". Only methods are allowed", item)

  result = nnkStmtList.newTree(typeSection)
  for m in methods:
    result.add m

macro trait*(name: untyped, body: untyped): untyped =
  return traitImpl(name, body, false)

macro traitRef*(name: untyped, body: untyped): untyped =
  return traitImpl(name, body, true)

proc wrapFunction(procName: NimNode, newName: NimNode, signature: NimNode, mapParam: proc(index: int, node: NimNode): Option[NimNode], mapArg: proc(index: int, node: NimNode): Option[NimNode]): NimNode =
  # defer:
  #   echo result.repr

  # echo "wrapFunction ", procName.repr, ", ", newName.repr, ", ", signature.repr

  var signature = signature.copy

  for i in 0..<signature.len:
    if mapParam(i, signature[i]).getSome(param):
      signature[i] = param

  let returnType = if signature[0].kind == nnkEmpty: ident"void" else: signature[0]

  var call = genAst(procName, newName, returnType):
    newName()

  for i in 1..<signature.len:
    if mapArg(i - 1, signature[i][0]).getSome(arg):
      call.add arg

  result = genAst(procName, newName, returnType, call):
    method newName*(): returnType =
      when returnType is void:
        call
      else:
        return call
  result[3] = signature

macro implTrait*(trait: typed, target: typed, body: untyped): untyped =
  # defer:
  #   echo result.repr
    # echo result.treeRepr

  let implName = ident(target.repr & "Impl" & trait.repr)
  let asName = ident("as" & trait.repr)

  let isRef = trait.getImpl[2].kind == nnkRefTy

  let traitImplType = if isRef:
    genAst(trait, target, implName):
      type
        implName* = ref object of trait
          data: target
  else:
    genAst(trait, target, implName):
      type
        implName* = object of trait
          data: target

  result = nnkStmtList.newTree(traitImplType)

  let asFunction = genAst(trait, target, implName, asName):
    proc asName*(self: target): implName =
      return implName(data: self)

  result.add asFunction

  for item in body:
    let (procName, signature) = case item.kind:
    of nnkProcDef:
      let procName = item.name
      result.add(item)
      let signature = item[3]
      (procName, signature)

    of nnkCall:
      var signature = nnkFormalParams.newTree(item[1])
      for i in 2..<item.len:
        signature.add nnkIdentDefs.newTree(ident("a" & $i), item[i], newEmptyNode())
      (item[0], signature)

    of nnkIdent:
      if getTraitFunction(trait, item).getSome(function):
        let impl = function.getImpl
        let name = ident item.repr

        # We need to copy the signature and replace the param names with identifiers (they are symbols right now),
        # otherwise Nim will think that the function we generate is an overload for an existing function, even though
        # it isn't. Changing the parameters is not enough.
        var signature = nnkFormalParams.newTree()
        for i in 0..<impl[3].len:
          if i > 0:
            signature.add nnkIdentDefs.newTree(ident impl[3][i][0].repr, impl[3][i][1], newEmptyNode())
          else:
            signature.add impl[3][i]

        (name, signature)

      else:
        error("No matching trait function found: " & $item.kind & ". Only procs/proc names are allowed", item)

    else:
      error("This kind of node is not allowed here: " & $item.kind & ". Only procs/proc names are allowed", item)

    proc mapParam(index: int, param: NimNode): Option[NimNode] =
      if index == 1:
        var newParam = param
        newParam[1] = implName
        return newParam.some
      else:
        return param.some

    proc mapArg(index: int, arg: NimNode): Option[NimNode] =
      if index == 0:
        let arg = genAst(arg):
          arg.data
        return arg.some
      else:
        return arg.some

    var function = wrapFunction(procName, procName, signature, mapParam, mapArg)

    result.add function
