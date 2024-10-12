import std/[json, strutils, sequtils, tables, options, macros, genasts, macrocache, typetraits, sugar]
import misc/[util, custom_logger, custom_async]

const builtinServices = CacheSeq"builtinServices"

{.push gcsafe.}
{.push raises: [].}

logCategory "services"

type
  ServiceState* = enum
    Pending
    Failed
    Registered
    Running

  Service* = ref object of RootObj
    state*: ServiceState
    services*: Services

  Services* = ref object
    running: Table[string, Service]
    registered: Table[string, Service]
    dependencies: Table[string, seq[string]]
    pending: Table[string, Future[Option[Service]]]

method init*(self: Service): Future[Result[void, ref CatchableError]] {.base, async: (raises: []).} = discard

proc getService*(self: Services, name: string, state: Option[ServiceState] = ServiceState.none): Option[Service] =
  if state.get(Running) == Running:
    self.running.withValue(name, service):
      return service[].some
  if state.get(Registered) == Registered:
    self.registered.withValue(name, service):
      return service[].some
  Service.none

proc initService(self: Services, name: string) {.async.} =
  log lvlInfo, &"initService {name}"
  let service = self.registered[name]
  let res = await service.init()
  if res.isOk:
    self.running[name] = service
    service.state = Running
    self.pending.withValue(name, fut):
      fut[].complete(service.some)
      self.pending.del(name)

    for (s, deps) in self.dependencies.mpairs:
      let idx = deps.find(name)
      if idx == -1:
        continue

      deps.removeSwap(idx)
      if deps.len == 0:
        await self.initService(s)
        break

  else:
    log lvlError, &"Failed to initialize service '{name}'"
    service.state = Failed

proc addService*(self: Services, name: string, service: Service, dependencies: seq[string] = @[]) =
  log lvlInfo, &"addService {name}"
  service.services = self
  self.registered[name] = service
  service.state = Registered

  if dependencies.len == 0:
    asyncSpawn self.initService(name)
  else:
    self.dependencies[name] = dependencies

proc getService*(self: Services, T: typedesc): Option[T] {.gcsafe, raises: [].} =
  let service = self.getService(T.serviceName)
  if service.isSome and service.get of T:
    return service.get.T.some
  return T.none

proc getServiceAsync*(self: Services, T: typedesc): Future[Option[T]] {.gcsafe, async: (raises: []).} =
  var service = self.getService(T.serviceName)
  if service.isSome and service.get of T:
    return service.get.T.some
  self.pending.withValue(T.serviceName, fut):
    try:
      service = fut[].await
    except CatchableError as e:
      log lvlError, &"Failed to await service {T.serviceName}: {e.msg}\n{e.getStackTrace()}"
      return T.none

    if service.isSome and service.get of T:
      return service.get.T.some
  return T.none

proc addService*[T: Service](self: Services, service: T) {.gcsafe, raises: [].} =
  self.addService(T.serviceName, service)

# func addBuiltinServiceImpl(T: NimNode, name: static string, names: static seq[string], dependencies: varargs[typed]) =
#   echo "addBuiltinService ", T.treeRepr, ", ", dependencies.treeRepr
#   builtinServices.add nnkTupleExpr.newTree(T, genAst(T, T.serviceName))

macro addBuiltinServiceImpl(T: typed, name: static string, names: static seq[string], dependencies: varargs[typed]) =
  echo "addBuiltinService ", T.treeRepr, ", ", dependencies.treeRepr
  var dependencyNames = nnkBracket.newTree()
  for n in names:
    dependencyNames.add n.newLit

  builtinServices.add nnkBracket.newTree(T, newLit(name), nnkPrefix.newTree(ident"@", dependencyNames))

macro addBuiltinService*(T: typed, dependencies: varargs[typed]) =
  echo "addBuiltinService ", T.treeRepr, ", ", dependencies.treeRepr
  var dependencyNames = nnkPrefix.newTree(ident"@", nnkBracket.newTree())
  for d in dependencies:
    dependencyNames.add genAst(d, d.serviceName)
  echo dependencyNames.treeRepr
  result = genAst(T, dependencies):
    addBuiltinServiceImpl(T, T.serviceName, @[], dependencies)

macro addBuiltinServices*(services: Services) =
  result = nnkStmtList.newTree()

  for serviceInfo in builtinServices:
    let T = serviceInfo[0]
    let name = serviceInfo[1]
    let dependencies = serviceInfo[2]
    echo serviceInfo.treeRepr
    result.add genAst(services, T, name, dependencies, services.addService(name, T(), dependencies))

  echo result.repr
