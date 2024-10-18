import id, util

{.push gcsafe.}
{.push raises: [].}

type Event*[T] = object
  when T is void:
    handlers: seq[tuple[id: Id, callback: proc(): void {.gcsafe, raises: [].}]]
  else:
    handlers: seq[tuple[id: Id, callback: proc(arg: T): void {.gcsafe, raises: [].}]]

proc initEvent*[T](): Event[T] =
  result = Event[T](handlers: @[])

proc subscribe*[T: void](event: var Event[T], callback: proc(): void {.gcsafe, raises: [].}): Id =
  assert callback != nil
  result = newId()
  event.handlers.add (result, callback)

proc subscribe*[T](event: var Event[T], callback: proc(arg: T): void {.gcsafe, raises: [].}): Id =
  assert callback != nil
  result = newId()
  event.handlers.add (result, callback)

proc unsubscribe*[T](event: var Event[T], id: var Id) =
  for i in countdown(event.handlers.high, 0):
    if event.handlers[i].id == id:
      event.handlers.removeShift(i)
      id = idNone()

proc unsubscribe*[T](event: var Event[T], id: Id) =
  for i in countdown(event.handlers.high, 0):
    if event.handlers[i].id == id:
      event.handlers.removeShift(i)

proc invoke*[T: void](event: Event[T]) =
  # Copy handlers so that the callback can unregister itself (which would modify event.handlers
  # while iterating)
  # To guarantee a copy we use =dup, because otherwise nim thinks it can avoid the actual copy
  # because neither of them is modified from within this function.
  var handlers: typeof(event.handlers)
  handlers.setLen event.handlers.len
  for i in 0..event.handlers.high:
    handlers[i] = event.handlers[i]

  for h in handlers:
    assert h.callback != nil
    h.callback()

proc invoke*[T](event: Event[T], arg: T) =
  # Copy handlers so that the callback can unregister itself (which would modify event.handlers
  # while iterating)
  # To guarantee a copy we use =dup, because otherwise nim thinks it can avoid the actual copy
  # because neither of them is modified from within this function.
  var handlers: typeof(event.handlers)
  handlers.setLen event.handlers.len
  for i in 0..event.handlers.high:
    handlers[i] = event.handlers[i]

  for h in handlers:
    assert h.callback != nil
    h.callback(arg)
