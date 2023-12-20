import std/[options]

type
  ArrayTableKey* = concept x
    x == x is bool

  ArrayTable*[K: ArrayTableKey, V] = object
    items*: seq[tuple[key: K, value: V]]

proc initArrayTable*(K: typedesc[ArrayTableKey], V: typedesc): ArrayTable[K, V] =
  discard

proc `[]`*[K, V](self: var ArrayTable[K, V], key: K): V =
  for kv in self.items.mitems:
    if kv.key == key:
      return kv.value
  raise newException(Defect, "Key not found")

proc `[]=`*[K, V](self: var ArrayTable[K, V], key: K, value: V) =
  for kv in self.items.mitems:
    if kv.key == key:
      kv.value = value
      return
  self.items.add (key, value)

proc tryGet*[K, V](self: var ArrayTable[K, V], key: K): Option[V] =
  for kv in self.items.mitems:
    if kv.key == key:
      return kv.value.some
  return V.none

proc contains*[K, V](self: var ArrayTable[K, V], key: K): bool =
  for kv in self.items.mitems:
    if kv.key == key:
      return true
  return false

template len*[K, V](self: ArrayTable[K, V]): int = self.items.len