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

type Oid* = object ## An OID.
  padding: int32
  time*: int32
  fuzz*: int32
  count*: int32

type Id* = distinct Oid

import std/[json, hashes, random, tables, strutils, genasts]
import myjsonutils

when not defined(nimscript) and defined(nimPreviewSlimSystem):
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

proc hashInt32(x: int32): uint32 {.inline.} =
  # convert int32 to uint32 without cast[] because it's using BigInt in js
  let b = (x and 1).uint32 # last bit
  let y = ((x shr 1) and 0x7FFFFFFF).uint32 shl 1 # every bit except last

  result = hashInt32(y or b)

static:
  assert hashInt32(0.uint32) == hashInt32(0.int32)
  assert hashInt32(1.uint32) == hashInt32(1.int32)
  assert hashInt32(0xffffffff'u32) == hashInt32(-1'i32)
  assert hashInt32(0xfffffffe'u32) == hashInt32(-2'i32)

proc hash*(oid: Oid): Hash =
  ## Generates the hash of an OID for use in hashtables.
  var h: Hash = 0
  h = h !& hashInt32(oid.time).Hash
  h = h !& hashInt32(oid.fuzz).Hash
  h = h !& hashInt32(oid.count).Hash
  result = !$h

proc hexbyte*(hex: char): int {.inline.} =
  result = handleHexChar(hex)

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

proc constructOid*(time: int32, fuzz: int32, count: int32): Oid =
  result.time = time
  result.fuzz = fuzz
  result.count = count

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

let
  t = myGetTime()

var
  seed = initRand(t)
  incr: int = seed.rand(int.high)

var timeCT {.compileTime.}: int32 = 1000
var randCT {.compileTime.}: Rand = initRand(timeCT)
var incrCT {.compileTime.}: int32 = randCT.rand(int32)

let fuzz = cast[int32](seed.rand(high(int)))

func swapBytes(a: int32): int32 =
  var x = cast[uint32](a)
  x = ((x and 0xFF) shl 24) or ((x and 0xFF00) shl 8) or ((x and 0xFF0000) shr 8) or (x shr 24)
  cast[int32](x)

import std/endians

proc bigEndian32*(b: int32): int32 =
  var temp = b
  endians.bigEndian32(result.addr, temp.addr)

template genOid(result: var Oid, incr: var int, fuzz: int32) =
  let time = cast[int32](myGetTime())
  let i: int32 = cast[int32](atomicInc(incr))

  result.time = time.bigEndian32
  result.fuzz = fuzz
  result.count = i.bigEndian32

proc genOid*(): Oid =
  ## Generates a new OID.
  runnableExamples:
    doAssert ($genOid()).len == 24
  runnableExamples("-r:off"):
    echo $genOid() # for example, "5fc7f546ddbbc84800006aaf"
  genOid(result, incr, fuzz)

proc genOidCT*(): Oid =
  ## Generates a new OID.
  result = Oid(time: timeCT.swapBytes, fuzz: 0x6AF1C4F1.int32, count: incrCT)
  inc incrCT

proc generatedTime*(oid: Oid): Time =
  ## Returns the generated timestamp of the OID.
  var tmp: int32
  var dummy = oid.time
  tmp = dummy.bigEndian32
  result = fromUnix(tmp)

proc newId*(): Id =
  return genOid().Id

proc newIdCT*(): Id =
  genOidCT().Id

func `$`*(id: Id): string =
  return $id.Oid

func idToString*(id: Id): cstring {.exportc.} =
  return ($id.Oid).cstring

proc `==`*(idA: Id, idB: Id): bool =
  return idA.Oid == idB.Oid

proc hash*(id: Id): Hash =
  return id.Oid.hash

proc idNone*(): Id =
  return default(Id)

proc isNone*(id: Id): bool = id == default(Id)
proc isSome*(id: Id): bool = id != default(Id)

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

proc construct*(time, fuzz, count: int32): Id =
  return constructOid(time, fuzz, count).Id

proc deconstruct*(id: Id): tuple[time: int32, fuzz: int32, count: int32] {.borrow.}

static:
  const idStr = "654fbb281446e19b3822523c"
  const id = idStr.parseId
  assert $id == idStr

template defineUniqueId*(name: untyped): untyped =
  type name* = distinct Id

  proc `==`*(a, b: name): bool {.borrow.}
  proc `$`*(a: name): string {.borrow.}
  proc isNone*(id: name): bool {.borrow.}
  proc isSome*(id: name): bool {.borrow.}
  proc hash*(id: name): Hash {.borrow.}
  proc fromJsonHook*(id: var name, json: JsonNode) {.borrow.}
  proc toJson*(id: name, opt: ToJsonOptions): JsonNode = newJString $id

const taggedIdsFile {.strdefine.} = ""
const existingIds = when taggedIdsFile != "":
  staticRead(taggedIdsFile)
else:
  ""

var taggedIds {.compileTime.} = initOrderedTable[string, Id]()
var numTaggedIdsOriginal {.compileTime.} = 0
static:
  var maxTime: int32 = int32.low
  for line in existingIds.splitLines:
    if line.len == 0 or line.startsWith("#"):
      continue

    let parts = line.split("=")
    let key = parts[0]
    let id = parseId(parts[1])
    taggedIds[key] = id
    maxTime = max(maxTime, id.Oid.time.swapBytes)
    # echo "  Read existing id " & key, " = ", id

  numTaggedIdsOriginal = taggedIds.len
  timeCT = maxTime + 1

proc taggedId*(tag: string): Id =
  if taggedIds.contains(tag):
    return taggedIds[tag]
  else:
    let newId = newIdCT()
    taggedIds[tag] = newId
    return newId

macro get*(T: typedesc, tag: untyped): untyped =
  result = genAst(t = tag.repr, T, taggedId(t).T)

proc writeTaggedIds*() =
  var str = ""
  var i = 0
  for (key, id) in taggedIds.pairs:
    if i >= numTaggedIdsOriginal:
      echo "  Write new id " & key, " = ", id
    # else:
    #   echo "  Write existing id " & key, " = ", id

    if str.len > 0:
      str.add "\n"
    str.add key & "=" & $id

    inc i

  when taggedIdsFile != "":
    writeFile(taggedIdsFile, str)
