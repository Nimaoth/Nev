import std/[oids, json, jsonutils]
import hashes, times

type Id* = distinct Oid

proc newId*(): Id =
  return genOid().Id

func `$`*(id: Id): string =
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

proc idNone*(): Id =
  zeroMem(addr result, sizeof(Id))

let null* = idNone()

proc fromJsonHook*(id: var Id, json: JsonNode) =
  if json.kind == JString:
    id = json.str.parseId
  else:
    id = null

proc toJson*(id: Id, opt = initToJsonOptions()): JsonNode =
  return newJString $id
