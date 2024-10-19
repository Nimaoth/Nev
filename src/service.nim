import std/[json, tables, options, macros, genasts, macrocache, typetraits, sets]
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

var gServices*: Services

method init*(self: Service): Future[Result[void, ref CatchableError]] {.base, async: (raises: []).} = discard

proc waitForServices*(self: Services) =
  while true:
    var servicesToWaitFor = initHashSet[string]()
    for s in self.registered.keys:
      if s notin self.running:
        servicesToWaitFor.incl(s)

    if servicesToWaitFor.len == 0:
      break

    log lvlInfo, &"Waiting for services {servicesToWaitFor}"
    poll()

  log lvlInfo, &"Finished initializing services"

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
  log lvlInfo, &"initService {name} done"
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

  else:
    log lvlError, &"Failed to initialize service '{name}'"
    service.state = Failed

proc addService*(self: Services, name: string, service: Service, dependencies: seq[string] = @[]) =
  log lvlInfo, &"addService {name}, dependencies: {dependencies}"
  service.services = self
  self.registered[name] = service
  service.state = Registered

  var dependencies = dependencies
  for name in self.running.keys:
    let idx = dependencies.find(name)
    if idx != -1:
      dependencies.removeSwap(idx)

  if dependencies.len == 0:
    asyncSpawn self.initService(name)
  else:
    log lvlInfo, &"addService {name}, remaining dependencies: {dependencies}"
    self.dependencies[name] = dependencies

proc getService*(self: Services, T: typedesc, state: Option[ServiceState] = ServiceState.none): Option[T] {.gcsafe, raises: [].} =
  let service = self.getService(T.serviceName, state)
  if service.isSome and service.get of T:
    return service.get.T.some
  return T.none

proc getServiceAsync*(self: Services, T: typedesc): Future[Option[T]] {.gcsafe, async: (raises: []).} =
  var service = self.getService(T.serviceName, ServiceState.Running.some)
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

macro addBuiltinServiceImpl(T: typed, name: static string, dependencies: static seq[string]) =
  var dependencyNames = nnkBracket.newTree()
  for n in dependencies:
    dependencyNames.add n.newLit

  builtinServices.add nnkBracket.newTree(T, newLit(name), nnkPrefix.newTree(ident"@", dependencyNames))

macro addBuiltinService*(T: typed, dependencies: varargs[typed]) =
  var dependencyNames = nnkPrefix.newTree(ident"@", nnkBracket.newTree())
  for d in dependencies:
    dependencyNames[1].add genAst(d, d.serviceName)
  result = genAst(T, dependencyNames):
    addBuiltinServiceImpl(T, T.serviceName, dependencyNames)

macro addBuiltinServices*(services: Services) =
  result = nnkStmtList.newTree()

  for serviceInfo in builtinServices:
    let T = serviceInfo[0]
    let name = serviceInfo[1]
    let dependencies = serviceInfo[2]
    result.add genAst(services, T, name, dependencies, services.addService(name, T(), dependencies))

  echo result.repr
