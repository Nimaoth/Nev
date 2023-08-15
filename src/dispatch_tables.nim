import std/[json, tables]

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

proc addGlobalDispatchTable*(scope: string, functions: openArray[ExposedFunction]) =
  var table = DispatchTable(scope: scope)
  table.functions = initTable[string, ExposedFunction]()
  for function in functions:
    table.functions[function.name] = function
  globalDispatchTables.add table

proc extendGlobalDispatchTable*(scope: string, function: ExposedFunction) =
  for table in globalDispatchTables.mitems:
    if table.scope == scope:
      table.functions[function.name] = function
      return
  addGlobalDispatchTable(scope, [function])