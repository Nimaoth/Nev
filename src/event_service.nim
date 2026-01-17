import std/[tables]
import misc/[id]
import service

include dynlib_export

type
  EventListener* = proc(event: string, data: string) {.gcsafe, raises: [].}
  EventService* = ref object of Service
    cachedListeners: Table[string, seq[EventListener]]
    registeredListeners: seq[tuple[id: Id, pattern: string, cb: EventListener]]
    pendingListeners: seq[tuple[id: Id, pattern: string, cb: EventListener]]
    pendingCachedListeners: seq[tuple[event: string, cbs: seq[EventListener]]]
    emittingEvent: bool = false

func serviceName*(_: typedesc[EventService]): string = "EventService"

proc eventServiceListen*(self: EventService, id: Id, pattern: string, cb: EventListener) {.apprtl, gcsafe, raises: [].}
proc eventServiceStopListen*(self: EventService, id: Id, pattern: string = "") {.apprtl, gcsafe, raises: [].}
proc eventServiceEmit*(self: EventService, event: string, data: string) {.apprtl, gcsafe, raises: [].}

proc listen*(self: EventService, id: Id, pattern: string, cb: EventListener) {.inline.} = eventServiceListen(self, id, pattern, cb)
proc stopListen*(self: EventService, id: Id, pattern: string = "") {.inline.} = eventServiceStopListen(self, id, pattern)
proc emit*(self: EventService, event: string, data: string) {.inline.} = eventServiceEmit(self, event, data)

when implModule:
  import std/[strutils, sugar, sequtils]
  import misc/[custom_logger, custom_async, util, regex, myjsonutils, id]

  logCategory "ebus"
  addBuiltinService(EventService)

  method init*(self: EventService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    return ok()

  proc clearCache(self: EventService) =
    self.cachedListeners.clear()
    self.pendingCachedListeners.setLen(0)

  proc flushPendingCachedListeners(self: EventService) =
    if not self.emittingEvent and self.pendingCachedListeners.len > 0:
      for l in self.pendingCachedListeners:
        self.cachedListeners[l.event] = l.cbs
      self.pendingCachedListeners.setLen(0)

  proc eventServiceListen*(self: EventService, id: Id, pattern: string, cb: EventListener) =
    if id == idNone():
      log lvlError, &"[listen] Invalid id '{id}' for listener to '{pattern}'"
      return

    self.registeredListeners.add (id, pattern, cb)
    self.clearCache()

  proc eventServiceStopListen*(self: EventService, id: Id, pattern: string = "") =
    if id == idNone():
      log lvlError, &"[stop-listen] Invalid id '{id}' for listener to '{pattern}'"
      return

    var removed = false
    for i in countdown(self.registeredListeners.high, 0):
      if self.registeredListeners[i].id != id:
        continue
      if pattern.len > 0 and self.registeredListeners[i].pattern != pattern:
        continue
      # Don't change the order of registeredListeners because that can lead to hard
      # to debug bugs when a bug depends on the order of listeners and that changes.
      self.registeredListeners.removeShift(i)
      removed = true
    if removed:
      self.clearCache()

  proc eventServiceEmit*(self: EventService, event: string, data: string) =
    let prevEmittingEvent = self.emittingEvent
    self.emittingEvent = true
    defer:
      self.emittingEvent = prevEmittingEvent
      self.flushPendingCachedListeners()

    self.cachedListeners.withValue(event, listeners):
      # if listeners[].len > 0:
      #   debugf"emit '{event}' ({listeners[].len}) '{data}'"
      for cb in listeners[]:
        cb(event, data)
      return

    # Find matching listeners
    var cbs = newSeq[EventListener]()
    for (_, pattern, cb) in self.registeredListeners:
      try:
        if globMatch(event, pattern):
          cbs.add cb
      except CatchableError:
        log lvlError, &"Invalid event pattern '{pattern}'"

    # Only cache event listeners when we're not already emitting an event, otherwise we could be
    # modifying the cache while still holding a pointer to a value from the 'withValue' above.
    if not prevEmittingEvent:
      self.cachedListeners[event] = cbs
    else:
      self.pendingCachedListeners.add (event, cbs)

    # if cbs.len > 0:
    #   debugf"emit '{event}' ({cbs.len}) '{data}'"
    for cb in cbs:
      cb(event, data)
