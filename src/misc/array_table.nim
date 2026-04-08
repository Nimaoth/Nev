when not defined(nimony):
  import std/[options]
else:
  import nimonycompat

type
  ArrayTableKey* = concept
    proc `==`(a, b: Self): bool

type
  ArrayTable*[K: ArrayTableKey, V] = object
    items*: seq[tuple[key: K, value: V]]

proc initArrayTable*[K: ArrayTableKey, V](): ArrayTable[K, V] =
  result = ArrayTable[K, V](items: @[])

proc `[]`*[K: ArrayTableKey, V](self: var ArrayTable[K, V], key: K): V =
  for i in 0..self.items.high:
    if self.items[i].key == key:
      return self.items[i].value
  assert false

proc `[]=`*[K: ArrayTableKey, V](self: var ArrayTable[K, V], key: K, value: V) =
  for i in 0..self.items.high:
    if self.items[i].key == key:
      self.items[i].value = value
      return
  self.items.add (key, value)

proc tryGet*[K: ArrayTableKey, V](self: var ArrayTable[K, V], key: K): Option[V] =
  for i in 0..self.items.high:
    if self.items[i].key == key:
      return self.items[i].value.some
  return V.none

proc contains*[K: ArrayTableKey, V](self: var ArrayTable[K, V], key: K): bool =
  for i in 0..self.items.high:
    if self.items[i].key == key:
      return true
  return false

template len*[K, V](self: ArrayTable[K, V]): int = self.items.len
