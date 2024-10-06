import std/[strformat, tables, macros, json, strutils, sugar, sequtils, genasts]
import misc/[util, wrap, myjsonutils]
import plugin_api

export plugin_api, util, strformat, tables, json, strutils, sugar, sequtils, scripting_api

var scriptActions* = initTable[string, proc(args: JsonNode): JsonNode]()

proc exposeImpl*(context: NimNode, name: NimNode, fun: NimNode, active: bool): NimNode =
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
    return genAst(name, def, jsonWrapper, jsonWrapperName, documentationStr, params, returnType, active, context):
      def
      jsonWrapper
      scriptActions[name] = jsonWrapperName
      addScriptAction(name, documentationStr, params, returnType, active, context)

  else:
    return genAst(name, jsonWrapper, jsonWrapperName, documentationStr, params, returnType, active, context):
      jsonWrapper
      scriptActions[name] = jsonWrapperName
      addScriptAction(name, documentationStr, params, returnType, active, context)

macro expose*(name: string, fun: typed): untyped =
  return exposeImpl(newLit"script", name, fun, active=false)

macro expose*(context, string, name: string, fun: typed): untyped =
  return exposeImpl(context, name, fun, active=false)

macro exposeActive*(context: string, name: string, fun: typed): untyped =
  return exposeImpl(context, name, fun, active=true)

macro callJson*(fun: typed, args: JsonNode): JsonNode =
  ## Calls a function with a json object as argument, converting the json object to nim types
  let jsonWrapperName = genSym(nskProc, "jsonWrapper")
  let jsonWrapper = createJsonWrapper(fun, fun.getType, jsonWrapperName)
  jsonWrapper.addPragma("closure".ident)
  return genAst(jsonWrapper, jsonWrapperName, args):
    block:
      jsonWrapper
      jsonWrapperName(args)
