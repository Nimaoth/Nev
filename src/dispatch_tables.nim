import std/[json, tables, strutils, sequtils]

type
  ExposedFunction* = object
    name*: string
    docs*: string
    dispatch*: proc(arg: JsonNode): JsonNode
    params*: seq[tuple[name: string, typ: string]]
    returnType*: string
    signature*: string

  DispatchTable* = object
    scope*: string
    functions*: Table[string, ExposedFunction]

var globalDispatchTables*: seq[DispatchTable] = @[]

proc addGlobalDispatchTable*(scope: string, functions: seq[ExposedFunction]) =
  var table = DispatchTable(scope: scope)
  table.functions = initTable[string, ExposedFunction]()
  for function in functions:
    table.functions[function.name] = function
  echo table
  globalDispatchTables.add table