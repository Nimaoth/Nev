import std/[strutils, options, json, tables]
import misc/[custom_async, custom_logger, util, myjsonutils, event]
import scripting/expose
import dispatch_tables, service

{.push gcsafe.}
{.push raises: [].}

logCategory "session"

type
  SessionService* = ref object of Service
    sessionData*: JsonNode
    onSessionRestored*: Event[SessionService]
    hasSession*: bool

func serviceName*(_: typedesc[SessionService]): string = "SessionService"
addBuiltinService(SessionService)

method init*(self: SessionService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"SessionService.init"
  self.sessionData = newJObject()
  return ok()

proc restoreSession*(self: SessionService, sessionData: JsonNode) =
  self.sessionData = sessionData
  self.onSessionRestored.invoke(self)
  self.hasSession = true

###########################################################################

proc getSessionService(): Option[SessionService] =
  {.gcsafe.}:
    if gServices.isNil: return SessionService.none
    return gServices.getService(SessionService)

static:
  addInjector(SessionService, getSessionService)

proc setSessionDataJson*(self: SessionService, path: string, value: JsonNode, override: bool = true) {.expose("session").} =
  if self.isNil or path.len == 0:
    return

  try:
    let pathItems = path.split(".")
    var node = self.sessionData
    for key in pathItems[0..^2]:
      if node.kind != JObject:
        return
      if not node.contains(key):
        node[key] = newJObject()
      node = node[key]
    if node.isNil or node.kind != JObject:
      return

    let key = pathItems[^1]
    if not override and node.hasKey(key):
      node.fields[key].extendJson(value, true)
    else:
      node[key] = value
  except:
    discard

proc getSessionDataJson*(self: SessionService, path: string, default: JsonNode): JsonNode {.expose("session").} =
  if self.isNil:
    return default
  let node = self.sessionData{path.split(".")}
  if node.isNil:
    return default
  return node

addGlobalDispatchTable "session", genDispatchTable("session")
