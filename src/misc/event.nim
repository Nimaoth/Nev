import id, util, arena

export id

{.push gcsafe.}
{.push raises: [].}

type Event*[T] = object
  when T is void:
    handlers: seq[tuple[id: Id, callback: proc(): void {.gcsafe, raises: [].}]]
    newHandlers: seq[tuple[id: Id, callback: proc(): void {.gcsafe, raises: [].}]]
  else:
    handlers: seq[tuple[id: Id, callback: proc(arg: T): void {.gcsafe, raises: [].}]]
    newHandlers: seq[tuple[id: Id, callback: proc(arg: T): void {.gcsafe, raises: [].}]]
  active: int
  toRemove: seq[Id]

proc initEvent*[T](): Event[T] =
  result = Event[T](handlers: @[])

proc flushSubscriptionChanges*[T](event: var Event[T]) =
  assert event.active == 0
  for id in event.toRemove:
    for i in countdown(event.handlers.high, 0):
      if event.handlers[i].id == id:
        event.handlers.removeShift(i)
        break

  if event.toRemove.len > 10:
    event.toRemove = @[]
  else:
    event.toRemove.setLen(0)

  if event.newHandlers.len > 0:
    event.handlers.add event.newHandlers
    if event.newHandlers.len > 10:
      event.newHandlers = @[]
    else:
      event.newHandlers.setLen(0)

proc subscribe*[T: void](event: var Event[T], callback: proc(): void {.gcsafe, raises: [].}): Id =
  assert callback != nil
  result = newId()
  if event.active > 0:
    event.newHandlers.add (result, callback)
    return
  event.flushSubscriptionChanges()
  event.handlers.add (result, callback)

proc subscribe*[T](event: var Event[T], callback: proc(arg: T): void {.gcsafe, raises: [].}): Id =
  assert callback != nil
  result = newId()
  if event.active > 0:
    event.newHandlers.add (result, callback)
    return
  event.flushSubscriptionChanges()
  event.handlers.add (result, callback)

proc subscribe*[T: void](event: var Event[T], id: Id, callback: proc(): void {.gcsafe, raises: [].}) =
  assert callback != nil
  if event.active > 0:
    event.newHandlers.add (id, callback)
    return
  event.flushSubscriptionChanges()
  event.handlers.add (id, callback)

proc subscribe*[T: void](event: var Event[T], id: var Id, callback: proc(): void {.gcsafe, raises: [].}) =
  assert callback != nil
  if id == idNone():
    id = newId()
  if event.active > 0:
    event.newHandlers.add (id, callback)
    return
  event.flushSubscriptionChanges()
  event.handlers.add (id, callback)

proc subscribe*[T](event: var Event[T], id: Id, callback: proc(arg: T): void {.gcsafe, raises: [].}) =
  assert callback != nil
  if event.active > 0:
    event.newHandlers.add (id, callback)
    return
  event.flushSubscriptionChanges()
  event.handlers.add (id, callback)

proc subscribe*[T](event: var Event[T], id: var Id, callback: proc(arg: T): void {.gcsafe, raises: [].}) =
  assert callback != nil
  if id == idNone():
    id = newId()
  if event.active > 0:
    event.newHandlers.add (id, callback)
    return
  event.flushSubscriptionChanges()
  event.handlers.add (id, callback)

proc unsubscribe*[T](event: var Event[T], id: var Id) =
  if event.active > 0:
    event.toRemove.add(id)
    id = idNone()
    return
  event.flushSubscriptionChanges()
  for i in countdown(event.handlers.high, 0):
    if event.handlers[i].id == id:
      event.handlers.removeShift(i)
      id = idNone()

proc unsubscribe*[T](event: var Event[T], id: Id) =
  if event.active > 0:
    event.toRemove.add(id)
    return
  event.flushSubscriptionChanges()
  for i in countdown(event.handlers.high, 0):
    if event.handlers[i].id == id:
      event.handlers.removeShift(i)

proc invoke*[T: void](event: var Event[T]) =
  try:
    if event.active == 0:
      event.flushSubscriptionChanges()
    inc event.active
    for h in event.handlers:
      assert h.callback != nil
      h.callback()
  finally:
    assert event.active > 0
    dec event.active
    if event.active == 0:
      event.flushSubscriptionChanges()

proc invoke*[T](event: var Event[T], arg: T) =
  try:
    if event.active == 0:
      event.flushSubscriptionChanges()
    inc event.active
    for h in event.handlers:
      assert h.callback != nil
      h.callback(arg)
  finally:
    assert event.active > 0
    dec event.active
    if event.active == 0:
      event.flushSubscriptionChanges()

proc invoke*[T: void](event: Event[T]) =
  try:
    inc event.active
    for h in event.handlers:
      assert h.callback != nil
      h.callback()
  finally:
    assert event.active > 0
    dec event.active

proc invoke*[T](event: Event[T], arg: T) =
  try:
    inc event.active
    for h in event.handlers:
      assert h.callback != nil
      h.callback(arg)
  finally:
    assert event.active > 0
    dec event.active
