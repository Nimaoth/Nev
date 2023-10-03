# Originally from std/oids, but adjusted to work with javascript backend
# see LICENSES/LICENSE-nim

#
#
#            Nim's Runtime Library
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Nim OID support. An OID is a global ID that consists of a timestamp,
## a unique counter and a random value. This combination should suffice to
## produce a globally distributed unique ID.
##
## This implementation calls `initRand()` for the first call of
## `genOid`.
##

when defined(js):
  type Oid* = object ## An OID.
    padding: int
    time: int32
    fuzz: int32
    count: int32
else:
  type Oid* = object ## An OID.
    padding: int32
    time: int32
    fuzz: int32
    count: int32

type Id* = distinct Oid

import std/[json, hashes, random]
import myjsonutils

when not defined(js) and not defined(nimscript) and defined(nimPreviewSlimSystem):
  import std/[sysatomics]

when not defined(nimscript):
  import std/[times]

import timer

proc handleHexChar*(c: char): int {.inline.} =
  case c
  of '0'..'9': result = (ord(c) - ord('0'))
  of 'a'..'f': result = (ord(c) - ord('a') + 10)
  of 'A'..'F': result = (ord(c) - ord('A') + 10)
  else: discard

proc `==`*(oid1: Oid, oid2: Oid): bool {.inline.} =
  ## Compares two OIDs for equality.
  result = (oid1.time == oid2.time) and (oid1.fuzz == oid2.fuzz) and
          (oid1.count == oid2.count)

proc hashInt32(x: uint32): uint32 {.inline.} =
  result = x
  result = ((result shr 16) xor result) * 0x45d9f3b
  result = ((result shr 16) xor result) * 0x45d9f3b
  result = (result shr 16) xor result
  result = result and 0x7FFFFFFF.uint32

proc hash*(oid: Oid): Hash =
  ## Generates the hash of an OID for use in hashtables.
  var h: Hash = 0
  h = h !& hashInt32(oid.time.uint32).Hash
  h = h !& hashInt32(oid.fuzz.uint32).Hash
  h = h !& hashInt32(oid.count.uint32).Hash
  result = !$h

proc hexbyte*(hex: char): int {.inline.} =
  result = handleHexChar(hex)

proc constructOid*(time: int32, fuzz: int32, count: int32): Oid =
  result.time = time
  result.fuzz = fuzz
  result.count = count
  when defined(js):
    result.padding = result.hash

proc deconstruct*(oid: Oid): tuple[time: int32, fuzz: int32, count: int32] =
  result = (oid.time, oid.fuzz, oid.count)

proc parseOid*(str: string): Oid =
  ## Parses an OID.
  runnableExamples:
    let oid = parseOid("62e5339a564d29f77293451e").deconstruct
    doAssert oid.time == -1707874974 and oid.fuzz == -148288170 and oid.count == 507876210

  if str.len != 24:
    return

  result.time = 0
  for i in 0..<4:
    let hexValue = (hexbyte(str[2 * i]) shl 4) or hexbyte(str[2 * i + 1])
    result.time = result.time or cast[int32](hexValue shl (i * 8))

  result.fuzz = 0
  for i in 0..<4:
    let hexValue = (hexbyte(str[2 * (i + 4)]) shl 4) or hexbyte(str[2 * (i + 4) + 1])
    result.fuzz = result.fuzz or cast[int32](hexValue shl (i * 8))

  result.count = 0
  for i in 0..<4:
    let hexValue = (hexbyte(str[2 * (i + 8)]) shl 4) or hexbyte(str[2 * (i + 8) + 1])
    result.count = result.count or cast[int32](hexValue shl (i * 8))

  when defined(js):
    result.padding = result.hash

proc `$`*(oid: Oid): string =
  ## Converts an OID to a string.
  runnableExamples:
    let oid = constructOid(time = -1707874974, fuzz = -148288170, count = 507876210)
    doAssert ($oid) == "62e5339a564d29f77293451e"

  const hex = "0123456789abcdef"

  result.setLen 24

  for i in 0..<12:
    let value = if i < 4: oid.time
      elif i < 8: oid.fuzz
      else: oid.count

    let byteOffset = i mod 4

    let b = value shr (byteOffset * 8)

    result[2 * i] = hex[(b and 0xF0) shr 4]
    result[2 * i + 1] = hex[b and 0xF]

when defined(js):
  const hexChars: cstring = "0123456789abcdef"

proc toCString*(oid: Oid): cstring {.exportc.} =
  ## Converts an OID to a string.
  runnableExamples:
    let oid = constructOid(time = -1707874974, fuzz = -148288170, count = 507876210)
    doAssert oid.toCString == "62e5339a564d29f77293451e"

  when defined(js):
    proc append(str: cstring, other: cstring, i: int) {.importjs: "# += #[#];".}

    for i in 0..<12:
      let value = if i < 4: oid.time
        elif i < 8: oid.fuzz
        else: oid.count

      let byteOffset = i mod 4

      let b = value shr (byteOffset * 8)

      result.append(hexChars, (b and 0xF0) shr 4)
      result.append(hexChars, b and 0xF)
  else:
    return ($oid).cstring

let
  t = myGetTime()

var
  seed = initRand(t)
  incr: int = seed.rand(int.high)

let fuzz = cast[int32](seed.rand(high(int)))

when not defined(js) and not defined(nimscript):
  import std/endians

proc bigEndian32*(b: int32): int32 =
  when defined(js) or defined(nimscript):
    when system.cpuEndian == bigEndian:
      result = b
    else:
      result = ((b and 0xff) shl 24) or ((b and 0xff00) shl 8) or ((b and 0xff0000) shr 8) or (b shr 24)
  else:
    var temp = b
    endians.bigEndian32(result.addr, temp.addr)

template genOid(result: var Oid, incr: var int, fuzz: int32) =
  var time = cast[int32](myGetTime())
  var i: int32
  when defined(js) or defined(nimscript):
    inc incr
    i = (incr and 0x7FFFFFFF).int32
  else:
    i = cast[int32](atomicInc(incr))

  result.time = time.bigEndian32
  result.fuzz = fuzz
  result.count = i.bigEndian32

  when defined(js):
    result.padding = result.hash

proc genOid*(): Oid =
  ## Generates a new OID.
  runnableExamples:
    doAssert ($genOid()).len == 24
  runnableExamples("-r:off"):
    echo $genOid() # for example, "5fc7f546ddbbc84800006aaf"
  genOid(result, incr, fuzz)

proc generatedTime*(oid: Oid): Time =
  ## Returns the generated timestamp of the OID.
  var tmp: int32
  var dummy = oid.time
  tmp = dummy.bigEndian32
  result = fromUnix(tmp)

proc newId*(): Id =
  return genOid().Id

func `$`*(id: Id): string =
  return $id.Oid

func idToString*(id: Id): cstring {.exportc.} =
  return ($id.Oid).cstring

proc `==`*(idA: Id, idB: Id): bool =
  return idA.Oid == idB.Oid

proc hash*(id: Id): Hash =
  when defined(js):
    return id.Oid.padding
  else:
    return id.Oid.hash

proc idNone*(): Id =
  return default(Id)

proc parseId*(s: string): Id =
  if s.len != 24:
    return idNone()
  return s.parseOid.Id

proc timestamp*(id: Id): Time =
  return id.Oid.generatedTime

let null* = idNone()

proc fromJsonHook*(id: var Id, json: JsonNode) =
  if json.kind == JString:
    id = json.str.parseId
  else:
    id = null

proc toJson*(id: Id, opt = initToJsonOptions()): JsonNode =
  return newJString $id
