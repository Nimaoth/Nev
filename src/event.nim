import std/[sugar]
import id

type Event*[T] = object
  handlers: seq[tuple[id: Id, callback: (T) -> void]]

proc subscribe*[T](event: var Event[T], callback: (T) -> void): Id =
  result = newId()
  event.handlers.add (result, callback)

proc unsubscribe*[T](event: var Event[T], id: Id) =
  for i, h in event.handlers:
    if h.id == id:
      event.handlers.del(i)
      break

proc invoke*[T](event: var Event[T], arg: T) =
  for h in event.handlers:
    h.callback(arg)