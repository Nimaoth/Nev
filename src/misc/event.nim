import std/[sugar]
import id, util

type Event*[T] = object
  handlers: seq[tuple[id: Id, callback: (T) -> void]]

proc initEvent*[T](): Event[T] =
  result = Event[T](handlers: @[])

proc subscribe*[T: void](event: var Event[T], callback: () -> void): Id =
  assert callback != nil
  result = newId()
  event.handlers.add (result, callback)

proc subscribe*[T](event: var Event[T], callback: (T) -> void): Id =
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
  let handlers = event.handlers.`=dup`
  for h in handlers:
    assert h.callback != nil
    h.callback()

proc invoke*[T](event: Event[T], arg: T) =
  # Copy handlers so that the callback can unregister itself (which would modify event.handlers
  # while iterating)
  # To guarantee a copy we use =dup, because otherwise nim thinks it can avoid the actual copy
  # because neither of them is modified from within this function.
  let handlers = event.handlers.`=dup`
  for h in handlers:
    assert h.callback != nil
    h.callback(arg)