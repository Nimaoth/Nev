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
    namespace*: string
    functions*: Table[string, ExposedFunction]
    global*: bool

var globalDispatchTables*: seq[DispatchTable] = @[]
var activeDispatchTables*: seq[DispatchTable] = @[]

proc addGlobalDispatchTable*(namespace: string, functions: openArray[ExposedFunction]) =
  var table = DispatchTable(namespace: namespace)
  table.functions = initTable[string, ExposedFunction]()
  for function in functions:
    table.functions[function.name] = function
  globalDispatchTables.add table

proc extendGlobalDispatchTable*(namespace: string, function: ExposedFunction) =
  for table in globalDispatchTables.mitems:
    if table.namespace == namespace:
      table.functions[function.name] = function
      return
  addGlobalDispatchTable(namespace, [function])

proc addActiveDispatchTable*(namespace: string, functions: openArray[ExposedFunction], global: bool = false) =
  var table = DispatchTable(namespace: namespace, global: global)
  table.functions = initTable[string, ExposedFunction]()
  for function in functions:
    table.functions[function.name] = function
  activeDispatchTables.add table

proc extendActiveDispatchTable*(namespace: string, function: ExposedFunction) =
  for table in activeDispatchTables.mitems:
    if table.namespace == namespace:
      table.functions[function.name] = function
      return
  addActiveDispatchTable(namespace, [function])