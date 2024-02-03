import std/[strformat, tables, macros, json, strutils, sugar, sequtils, genasts]
import misc/[util, wrap, myjsonutils]
import absytree_api

export absytree_api, util, strformat, tables, json, strutils, sugar, sequtils, scripting_api

var scriptActions* = initTable[string, proc(args: JsonNode): JsonNode]()

macro expose*(name: string, fun: typed): untyped =
  # defer:
  #   echo result.repr

  let def = if fun.kind == nnkProcDef: fun else: fun.getImpl
  if def.kind != nnkProcDef:
    error("expose can only be used on proc definitions", fun)

  let signature = def.copy
  signature[6] = newEmptyNode()

  let signatureUntyped = parseExpr(signature.repr)
  let jsonWrapperName = (def.name.repr & "Json").ident
  let jsonWrapper = createJsonWrapper(signatureUntyped, jsonWrapperName)

  let documentation = def.getDocumentation()
  let documentationStr = documentation.map((it) => it.strVal).get("").newLit

  let returnType = if def[3][0].kind == nnkEmpty: "" else: def[3][0].repr
  var params: seq[(string, string)] = @[]
  for param in def[3][1..^1]:
    params.add (param[0].repr, param[1].repr)

  if def == fun:
    return genAst(name, def, jsonWrapper, jsonWrapperName, documentationStr, params, returnType):
      def
      jsonWrapper
      scriptActions[name] = jsonWrapperName
      addScriptAction(name, documentationStr, params, returnType)

  else:
    return genAst(name, jsonWrapper, jsonWrapperName, documentationStr, params, returnType):
      jsonWrapper
      scriptActions[name] = jsonWrapperName
      addScriptAction(name, documentationStr, params, returnType)

macro callJson*(fun: typed, args: JsonNode): JsonNode =
  ## Calls a function with a json object as argument, converting the json object to nim types
  let jsonWrapperName = genSym(nskProc, "jsonWrapper")
  let jsonWrapper = createJsonWrapper(fun, fun.getType, jsonWrapperName)
  jsonWrapper.addPragma("closure".ident)
  return genAst(jsonWrapper, jsonWrapperName, args):
    block:
      jsonWrapper
      jsonWrapperName(args)

proc exportImpl(name: string, implementNims: bool, def: NimNode): NimNode =
  # defer:
  #   echo result.repr

  when defined(wasm):
    let jsonWrapperName = (def.name.repr & "Json").ident
    let jsonWrapper = createJsonWrapper(def, jsonWrapperName)

    let documentation = def.getDocumentation()
    let documentationStr = documentation.map((it) => it.strVal).get("").newLit

    let returnType = if def[3][0].kind == nnkEmpty: "" else: def[3][0].repr
    var params: seq[(string, string)] = @[]
    for param in def[3][1..^1]:
      params.add (param[0].repr, param[1].repr)

    return genAst(name, def, jsonWrapper, jsonWrapperName, documentationStr, params, returnType):
      def
      jsonWrapper

      static:
        echo "Expose script action ", name, " (", params, ", ", returnType, ")"
      scriptActions[name] = jsonWrapperName
      addScriptAction(name, documentationStr, params, returnType)

  else:
    let argsName2 = genSym(nskVar)
    let (addArgs, argsName) = def.serializeArgumentsToJson(argsName2)
    var call = genAst(name, argsName, addArgs):
      # var argsName = newJArray()
      addArgs
      let temp = callScriptAction(name, argsName)
      if not temp.isNil:
        return

    if implementNims:
      def.body.insert(0, call)
    else:
      def.body = call

    return def

macro scriptActionWasm*(name: static string, def: untyped): untyped =
  ## Register as a script action
  ## If called in wasm then it directly runs the function
  ## If called in nimscript the script action is executed instead
  return exportImpl(name, false, def)

macro scriptActionWasmNims*(name: static string, def: untyped): untyped =
  ## Register as a script action
  ## If called in wasm then it directly runs the function
  ## If called in nimscript the script action. If no script action is found, runs directly in nimscript
  return exportImpl(name, true, def)