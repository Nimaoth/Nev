import std/oids
import hashes, times

type Id* = distinct Oid

proc newId*(): Id =
  return genOid().Id

proc `$`*(id: Id): string =
  return $id.Oid

proc `==`*(idA: Id, idB: Id): bool =
  return idA.Oid == idB.Oid

proc hash*(id: Id): Hash =
  return id.Oid.hash

proc parseId*(s: string): Id =
  if s.len < 23:
    assert false
  return s.parseOid.Id

proc timestamp*(id: Id): Time =
  return id.Oid.generatedTime