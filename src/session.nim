import std/[options, json]
import misc/[event, id, custom_async]
import service
import compilation_config

include dynlib_export

type
  SessionService* = ref object of Service
    sessionData*: JsonNode
    onSessionRestored*: Event[SessionService]
    hasSession*: bool
    sessionSaveHandlers: seq[tuple[
      id: Id,
      key: string,
      save: proc(): JsonNode {.gcsafe, raises: [].},
      load: proc(data: JsonNode) {.gcsafe, raises: [].},
    ]]

func serviceName*(_: typedesc[SessionService]): string = "SessionService"

# DLL API
proc sessionServiceAddSaveHandler(self: SessionService, key: string, save: proc(): JsonNode {.gcsafe, raises: [].}, load: proc(data: JsonNode) {.gcsafe, raises: [].}) {.apprtl, gcsafe, raises: [].}
proc sessionServiceGetRecentSessions(self: SessionService): Future[seq[string]] {.apprtl, gcsafe, async: (raises: []).}

# Nice wrappers
proc addSaveHandler*(self: SessionService, key: string, save: proc(): JsonNode {.gcsafe, raises: [].}, load: proc(data: JsonNode) {.gcsafe, raises: [].}) {.inline.} = sessionServiceAddSaveHandler(self, key, save, load)
proc getRecentSessions*(self: SessionService): Future[seq[string]] {.inline, async: (raises: []).} = await sessionServiceGetRecentSessions(self)

# Implementation
when implModule:
  import std/[strutils, tables, os]
  import misc/[custom_logger, util, myjsonutils]
  import scripting/[expose]
  import dispatch_tables, event_service, vfs_service

  {.push gcsafe.}
  {.push raises: [].}

  logCategory "session"

  addBuiltinService(SessionService)

  method init*(self: SessionService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    log lvlInfo, &"SessionService.init"
    self.sessionData = newJObject()
    return ok()

  proc sessionServiceGetRecentSessions(self: SessionService): Future[seq[string]] {.async: (raises: []).} =
    let vfsService = self.services.getService(VFSService).getOr: return @[]
    let vfs = vfsService.vfs
    try:
      let lastSessionsJson = await vfs.read(homeConfigDir // "sessions.json")
      let lastSessions = lastSessionsJson.parseJson()
      if lastSessions.kind != JArray:
        log lvlError, &"sessions.json must contain an array of strings"
        return @[]

      for session in lastSessions.elems:
        if session.kind == JString:
          result.add session.getStr()
    except:
      log lvlError, &"Failed to read sessions.json: {getCurrentExceptionMsg()}"
      return @[]

  proc restoreSession*(self: SessionService, sessionData: JsonNode) =
    log lvlInfo, &"SessionService.restoreSession"
    self.sessionData = sessionData
    if self.sessionData.hasKey("dynamic"):
      let dynamic = self.sessionData["dynamic"]
      if dynamic.kind == JObject:
        for handler in self.sessionSaveHandlers:
          if dynamic.hasKey(handler.key):
            handler.load(dynamic[handler.key])
      else:
        log lvlError, &"Invalid data in session data: '{dynamic}' should be an object"

    self.hasSession = true
    self.onSessionRestored.invoke(self)
    let events = self.services.getService(EventService).get
    events.emit("session/restored", "")

  proc sessionServiceAddSaveHandler(self: SessionService, key: string,
      save: proc(): JsonNode {.gcsafe, raises: [].},
      load: proc(data: JsonNode) {.gcsafe, raises: [].}) =
    self.sessionSaveHandlers.add (newId(), key, save, load)

  proc saveSession*(self: SessionService): JsonNode =
    log lvlInfo, &"SessionService.saveSession"
    let events = self.services.getService(EventService).get
    events.emit("session/save", "")
    result = self.sessionData.shallowCopy()
    if result == nil:
      result = newJObject()
    var dynamic = newJObject()
    for saveHandler in self.sessionSaveHandlers:
      let data = saveHandler.save()
      if data != nil:
        dynamic[saveHandler.key] = data
    result["dynamic"] = dynamic

  ###########################################################################

  proc getSessionService(): Option[SessionService] =
    {.gcsafe.}:
      if getServices().isNil: return SessionService.none
      return getServices().getService(SessionService)

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
