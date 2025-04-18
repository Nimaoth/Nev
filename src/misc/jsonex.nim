import std/[hashes, tables, strutils, lexbase, streams, macros, parsejson, json, sets, strtabs, uri, typetraits, enumutils]

import std/options # xxx remove this dependency using same approach as https://github.com/nim-lang/Nim/pull/14563
import std/private/since

import myjsonutils

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions, formatfloat]

export
  tables.`$`

export
  parsejson.JsonEventKind, parsejson.JsonError, JsonParser, JsonKindError,
  open, close, str, getInt, getFloat, kind, getColumn, getLine, getFilename,
  errorMsg, errorMsgExpected, next, JsonParsingError, raiseParseErr, nimIdentNormalize

type
  JsonNodeEx* = ref JsonNodeExObj ## JSON node
  JsonNodeExObj* {.acyclic.} = object
    isUnquoted: bool # the JString was a number-like token and
                     # so shouldn't be quoted
    extend*: bool
    userData*: int
    case kind*: JsonNodeKind
    of JString:
      str*: string
    of JInt:
      num*: BiggestInt
    of JFloat:
      fnum*: float
    of JBool:
      bval*: bool
    of JNull:
      nil
    of JObject:
      fields*: OrderedTable[string, JsonNodeEx]
    of JArray:
      elems*: seq[JsonNodeEx]

const DepthLimit = 1000

proc newJexString*(s: string): JsonNodeEx =
  ## Creates a new `JString JsonNodeEx`.
  result = JsonNodeEx(kind: JString, str: s)

proc newJexRawNumber(s: string): JsonNodeEx =
  ## Creates a "raw JS number", that is a number that does not
  ## fit into Nim's `BiggestInt` field. This is really a `JString`
  ## with the additional information that it should be converted back
  ## to the string representation without the quotes.
  result = JsonNodeEx(kind: JString, str: s, isUnquoted: true)

proc newJexInt*(n: BiggestInt): JsonNodeEx =
  ## Creates a new `JInt JsonNodeEx`.
  result = JsonNodeEx(kind: JInt, num: n)

proc newJexFloat*(n: float): JsonNodeEx =
  ## Creates a new `JFloat JsonNodeEx`.
  result = JsonNodeEx(kind: JFloat, fnum: n)

proc newJexBool*(b: bool): JsonNodeEx =
  ## Creates a new `JBool JsonNodeEx`.
  result = JsonNodeEx(kind: JBool, bval: b)

proc newJexNull*(): JsonNodeEx =
  ## Creates a new `JNull JsonNodeEx`.
  result = JsonNodeEx(kind: JNull)

proc newJexObject*(): JsonNodeEx =
  ## Creates a new `JObject JsonNodeEx`
  result = JsonNodeEx(kind: JObject, fields: initOrderedTable[string, JsonNodeEx](2))

proc newJexArray*(): JsonNodeEx =
  ## Creates a new `JArray JsonNodeEx`
  result = JsonNodeEx(kind: JArray, elems: @[])

proc getStr*(n: JsonNodeEx, default: string = ""): string =
  ## Retrieves the string value of a `JString JsonNodeEx`.
  ##
  ## Returns `default` if `n` is not a `JString`, or if `n` is nil.
  if n.isNil or n.kind != JString: return default
  else: return n.str

proc getInt*(n: JsonNodeEx, default: int = 0): int =
  ## Retrieves the int value of a `JInt JsonNodeEx`.
  ##
  ## Returns `default` if `n` is not a `JInt`, or if `n` is nil.
  if n.isNil or n.kind != JInt: return default
  else: return int(n.num)

proc getBiggestInt*(n: JsonNodeEx, default: BiggestInt = 0): BiggestInt =
  ## Retrieves the BiggestInt value of a `JInt JsonNodeEx`.
  ##
  ## Returns `default` if `n` is not a `JInt`, or if `n` is nil.
  if n.isNil or n.kind != JInt: return default
  else: return n.num

proc getFloat*(n: JsonNodeEx, default: float = 0.0): float =
  ## Retrieves the float value of a `JFloat JsonNodeEx`.
  ##
  ## Returns `default` if `n` is not a `JFloat` or `JInt`, or if `n` is nil.
  if n.isNil: return default
  case n.kind
  of JFloat: return n.fnum
  of JInt: return float(n.num)
  else: return default

proc getBool*(n: JsonNodeEx, default: bool = false): bool =
  ## Retrieves the bool value of a `JBool JsonNodeEx`.
  ##
  ## Returns `default` if `n` is not a `JBool`, or if `n` is nil.
  if n.isNil or n.kind != JBool: return default
  else: return n.bval

proc getFields*(n: JsonNodeEx,
    default = initOrderedTable[string, JsonNodeEx](2)):
        OrderedTable[string, JsonNodeEx] =
  ## Retrieves the key, value pairs of a `JObject JsonNodeEx`.
  ##
  ## Returns `default` if `n` is not a `JObject`, or if `n` is nil.
  if n.isNil or n.kind != JObject: return default
  else: return n.fields

proc getElems*(n: JsonNodeEx, default: seq[JsonNodeEx] = @[]): seq[JsonNodeEx] =
  ## Retrieves the array of a `JArray JsonNodeEx`.
  ##
  ## Returns `default` if `n` is not a `JArray`, or if `n` is nil.
  if n.isNil or n.kind != JArray: return default
  else: return n.elems

proc add*(father, child: JsonNodeEx) =
  ## Adds `child` to a JArray node `father`.
  assert father.kind == JArray
  father.elems.add(child)

proc add*(obj: JsonNodeEx, key: string, val: JsonNodeEx) =
  ## Sets a field from a `JObject`.
  assert obj.kind == JObject
  obj.fields[key] = val

proc `%%`*(s: string): JsonNodeEx =
  ## Generic constructor for JSON data. Creates a new `JString JsonNodeEx`.
  result = JsonNodeEx(kind: JString, str: s)

proc `%%`*(n: uint): JsonNodeEx =
  ## Generic constructor for JSON data. Creates a new `JInt JsonNodeEx`.
  if n > cast[uint](int.high):
    result = newJexRawNumber($n)
  else:
    result = JsonNodeEx(kind: JInt, num: BiggestInt(n))

proc `%%`*(n: int): JsonNodeEx =
  ## Generic constructor for JSON data. Creates a new `JInt JsonNodeEx`.
  result = JsonNodeEx(kind: JInt, num: n)

proc `%%`*(n: BiggestUInt): JsonNodeEx =
  ## Generic constructor for JSON data. Creates a new `JInt JsonNodeEx`.
  if n > cast[BiggestUInt](BiggestInt.high):
    result = newJexRawNumber($n)
  else:
    result = JsonNodeEx(kind: JInt, num: BiggestInt(n))

proc `%%`*(n: BiggestInt): JsonNodeEx =
  ## Generic constructor for JSON data. Creates a new `JInt JsonNodeEx`.
  result = JsonNodeEx(kind: JInt, num: n)

proc `%%`*(n: float): JsonNodeEx =
  ## Generic constructor for JSON data. Creates a new `JFloat JsonNodeEx`.
  runnableExamples:
    assert $(%%[NaN, Inf, -Inf, 0.0, -0.0, 1.0, 1e-2]) == """["nan","inf","-inf",0.0,-0.0,1.0,0.01]"""
    assert (%%NaN).kind == JString
    assert (%%0.0).kind == JFloat
  # for those special cases, we could also have used `newJexRawNumber` but then
  # it would've been inconsisten with the case of `parseJsonex` vs `%%` for representing them.
  if n != n: newJexString("nan")
  elif n == Inf: newJexString("inf")
  elif n == -Inf: newJexString("-inf")
  else: JsonNodeEx(kind: JFloat, fnum: n)

proc `%%`*(b: bool): JsonNodeEx =
  ## Generic constructor for JSON data. Creates a new `JBool JsonNodeEx`.
  result = JsonNodeEx(kind: JBool, bval: b)

proc `%%`*(keyVals: openArray[tuple[key: string, val: JsonNodeEx]]): JsonNodeEx =
  ## Generic constructor for JSON data. Creates a new `JObject JsonNodeEx`
  if keyVals.len == 0: return newJexArray()
  result = newJexObject()
  for key, val in items(keyVals): result.fields[key] = val

template `%%`*(j: JsonNodeEx): JsonNodeEx = j

proc `%%`*[T](elements: openArray[T]): JsonNodeEx =
  ## Generic constructor for JSON data. Creates a new `JArray JsonNodeEx`
  result = newJexArray()
  for elem in elements: result.add(%%elem)

proc `%%`*[T](table: Table[string, T]|OrderedTable[string, T]): JsonNodeEx =
  ## Generic constructor for JSON data. Creates a new `JObject JsonNodeEx`.
  result = newJexObject()
  for k, v in table: result[k] = %%v

proc `%%`*[T](opt: Option[T]): JsonNodeEx =
  ## Generic constructor for JSON data. Creates a new `JNull JsonNodeEx`
  ## if `opt` is empty, otherwise it delegates to the underlying value.
  if opt.isSome: %%opt.get else: newJexNull()

when false:
  # For 'consistency' we could do this, but that only pushes people further
  # into that evil comfort zone where they can use Nim without understanding it
  # causing problems later on.
  proc `%%`*(elements: set[bool]): JsonNodeEx =
    ## Generic constructor for JSON data. Creates a new `JObject JsonNodeEx`.
    ## This can only be used with the empty set `{}` and is supported
    ## to prevent the gotcha `%%*{}` which used to produce an empty
    ## JSON array.
    result = newJexObject()
    assert false notin elements, "usage error: only empty sets allowed"
    assert true notin elements, "usage error: only empty sets allowed"

proc `[]=`*(obj: JsonNodeEx, key: string, val: JsonNodeEx) {.inline.} =
  ## Sets a field from a `JObject`.
  assert(obj.kind == JObject)
  obj.fields[key] = val

proc `%%`*[T: object](o: T): JsonNodeEx =
  ## Construct JsonNodeEx from tuples and objects.
  result = newJexObject()
  for k, v in o.fieldPairs: result[k] = %%v

proc `%%`*(o: ref object): JsonNodeEx =
  ## Generic constructor for JSON data. Creates a new `JObject JsonNodeEx`
  if o.isNil:
    result = newJexNull()
  else:
    result = %%(o[])

proc `%%`*(o: enum): JsonNodeEx =
  ## Construct a JsonNodeEx that represents the specified enum value as a
  ## string. Creates a new `JString JsonNodeEx`.
  result = %%($o)

proc toJsonExImpl(x: NimNode): NimNode =
  case x.kind
  of nnkBracket: # array
    if x.len == 0: return newCall(bindSym"newJexArray")
    result = newNimNode(nnkBracket)
    for i in 0 ..< x.len:
      result.add(toJsonExImpl(x[i]))
    result = newCall(bindSym("%%", brOpen), result)
  of nnkTableConstr: # object
    if x.len == 0: return newCall(bindSym"newJexObject")
    result = newNimNode(nnkTableConstr)
    for i in 0 ..< x.len:
      x[i].expectKind nnkExprColonExpr
      result.add newTree(nnkExprColonExpr, x[i][0], toJsonExImpl(x[i][1]))
    result = newCall(bindSym("%%", brOpen), result)
  of nnkCurly: # empty object
    x.expectLen(0)
    result = newCall(bindSym"newJexObject")
  of nnkNilLit:
    result = newCall(bindSym"newJexNull")
  of nnkPar:
    if x.len == 1: result = toJsonExImpl(x[0])
    else: result = newCall(bindSym("%%", brOpen), x)
  else:
    result = newCall(bindSym("%%", brOpen), x)

macro `%%*`*(x: untyped): untyped =
  ## Convert an expression to a JsonNodeEx directly, without having to specify
  ## `%%` for every element.
  result = toJsonExImpl(x)

proc `==`*(a, b: JsonNodeEx): bool {.noSideEffect, raises: [].} =
  ## Check two nodes for equality
  if a.isNil:
    if b.isNil: return true
    return false
  elif b.isNil or a.kind != b.kind:
    return false
  else:
    case a.kind
    of JString:
      result = a.str == b.str
    of JInt:
      result = a.num == b.num
    of JFloat:
      result = a.fnum == b.fnum
    of JBool:
      result = a.bval == b.bval
    of JNull:
      result = true
    of JArray:
      {.cast(raises: []).}: # bug #19303
        result = a.elems == b.elems
    of JObject:
      # we cannot use OrderedTable's equality here as
      # the order does not matter for equality here.
      if a.fields.len != b.fields.len: return false
      for key, val in a.fields:
        if not b.fields.hasKey(key): return false
        {.cast(raises: []).}:
          when defined(nimHasEffectsOf):
            {.noSideEffect.}:
              if b.fields[key] != val: return false
          else:
            if b.fields[key] != val: return false
      result = true

proc hash*(n: OrderedTable[string, JsonNodeEx]): Hash {.noSideEffect.}

proc hash*(n: JsonNodeEx): Hash {.noSideEffect.} =
  ## Compute the hash for a JSON node
  case n.kind
  of JArray:
    result = hash(n.elems)
  of JObject:
    result = hash(n.fields)
  of JInt:
    result = hash(n.num)
  of JFloat:
    result = hash(n.fnum)
  of JBool:
    result = hash(n.bval.int)
  of JString:
    result = hash(n.str)
  of JNull:
    result = Hash(0)

proc hash*(n: OrderedTable[string, JsonNodeEx]): Hash =
  for key, val in n:
    result = result xor (hash(key) !& hash(val))
  result = !$result

proc len*(n: JsonNodeEx): int =
  ## If `n` is a `JArray`, it returns the number of elements.
  ## If `n` is a `JObject`, it returns the number of pairs.
  ## Else it returns 0.
  case n.kind
  of JArray: result = n.elems.len
  of JObject: result = n.fields.len
  else: discard

proc `[]`*(node: JsonNodeEx, name: string): JsonNodeEx {.inline.} =
  ## Gets a field from a `JObject`, which must not be nil.
  ## If the value at `name` does not exist, raises KeyError.
  assert(not isNil(node))
  assert(node.kind == JObject)
  when defined(nimJsonGet):
    if not node.fields.hasKey(name): return nil
  result = node.fields[name]

proc `[]`*(node: JsonNodeEx, index: int): JsonNodeEx {.inline.} =
  ## Gets the node at `index` in an Array. Result is undefined if `index`
  ## is out of bounds, but as long as array bound checks are enabled it will
  ## result in an exception.
  assert(not isNil(node))
  assert(node.kind == JArray)
  return node.elems[index]

proc `[]`*(node: JsonNodeEx, index: BackwardsIndex): JsonNodeEx {.inline, since: (1, 5, 1).} =
  ## Gets the node at `array.len-i` in an array through the `^` operator.
  ##
  ## i.e. `j[^i]` is a shortcut for `j[j.len-i]`.
  runnableExamples:
    let
      j = parseJsonex("[1,2,3,4,5]")

    doAssert j[^1].getInt == 5
    doAssert j[^2].getInt == 4

  `[]`(node, node.len - int(index))

proc `[]`*[U, V](a: JsonNodeEx, x: HSlice[U, V]): JsonNodeEx =
  ## Slice operation for JArray.
  ##
  ## Returns the inclusive range `[a[x.a], a[x.b]]`:
  runnableExamples:
    import std/json
    let arr = %%[0,1,2,3,4,5]
    doAssert arr[2..4] == %%[2,3,4]
    doAssert arr[2..^2] == %%[2,3,4]
    doAssert arr[^4..^2] == %%[2,3,4]

  assert(a.kind == JArray)
  result = newJexArray()
  let xa = (when x.a is BackwardsIndex: a.len - int(x.a) else: int(x.a))
  let L = (when x.b is BackwardsIndex: a.len - int(x.b) else: int(x.b)) - xa + 1
  for i in 0..<L:
    result.add(a[i + xa])

proc hasKey*(node: JsonNodeEx, key: string): bool =
  ## Checks if `key` exists in `node`.
  assert(node.kind == JObject)
  result = node.fields.hasKey(key)

proc contains*(node: JsonNodeEx, key: string): bool =
  ## Checks if `key` exists in `node`.
  assert(node.kind == JObject)
  node.fields.hasKey(key)

proc contains*(node: JsonNodeEx, val: JsonNodeEx): bool =
  ## Checks if `val` exists in array `node`.
  assert(node.kind == JArray)
  find(node.elems, val) >= 0

proc `{}`*(node: JsonNodeEx, keys: varargs[string]): JsonNodeEx =
  ## Traverses the node and gets the given value. If any of the
  ## keys do not exist, returns `nil`. Also returns `nil` if one of the
  ## intermediate data structures is not an object.
  ##
  ## This proc can be used to create tree structures on the
  ## fly (sometimes called `autovivification`:idx:):
  ##
  runnableExamples:
    var myjson = %%* {"parent": {"child": {"grandchild": 1}}}
    doAssert myjson{"parent", "child", "grandchild"} == newJexInt(1)

  result = node
  for key in keys:
    if isNil(result) or result.kind != JObject:
      return nil
    result = result.fields.getOrDefault(key)

proc `{}`*(node: JsonNodeEx, index: varargs[int]): JsonNodeEx =
  ## Traverses the node and gets the given value. If any of the
  ## indexes do not exist, returns `nil`. Also returns `nil` if one of the
  ## intermediate data structures is not an array.
  result = node
  for i in index:
    if isNil(result) or result.kind != JArray or i >= node.len:
      return nil
    result = result.elems[i]

proc getOrDefault*(node: JsonNodeEx, key: string): JsonNodeEx =
  ## Gets a field from a `node`. If `node` is nil or not an object or
  ## value at `key` does not exist, returns nil
  if not isNil(node) and node.kind == JObject:
    result = node.fields.getOrDefault(key)

proc getOrDefault*(node: JsonNodeEx, key: openArray[char]): JsonNodeEx =
  ## Gets a field from a `node`. If `node` is nil or not an object or
  ## value at `key` does not exist, returns nil
  if not isNil(node) and node.kind == JObject:
    result = node.fields.getOrDefault(key)

proc `{}`*(node: JsonNodeEx, key: string): JsonNodeEx =
  ## Gets a field from a `node`. If `node` is nil or not an object or
  ## value at `key` does not exist, returns nil
  node.getOrDefault(key)

proc `{}=`*(node: JsonNodeEx, keys: varargs[string], value: JsonNodeEx) =
  ## Traverses the node and tries to set the value at the given location
  ## to `value`. If any of the keys are missing, they are added.
  var node = node
  for i in 0..(keys.len-2):
    if not node.hasKey(keys[i]):
      node[keys[i]] = newJexObject()
    node = node[keys[i]]
  node[keys[keys.len-1]] = value

proc delete*(obj: JsonNodeEx, key: string) =
  ## Deletes `obj[key]`.
  assert(obj.kind == JObject)
  if not obj.fields.hasKey(key):
    raise newException(KeyError, "key not in object")
  obj.fields.del(key)

proc copy*(p: JsonNodeEx): JsonNodeEx =
  ## Performs a deep copy of `p`.
  case p.kind
  of JString:
    result = newJexString(p.str)
    result.isUnquoted = p.isUnquoted
  of JInt:
    result = newJexInt(p.num)
  of JFloat:
    result = newJexFloat(p.fnum)
  of JBool:
    result = newJexBool(p.bval)
  of JNull:
    result = newJexNull()
  of JObject:
    result = newJexObject()
    for key, val in pairs(p.fields):
      result.fields[key] = copy(val)
  of JArray:
    result = newJexArray()
    for i in items(p.elems):
      result.elems.add(copy(i))

  result.extend = p.extend
  result.userData = p.userData

# ------------- pretty printing ----------------------------------------------

proc indent(s: var string, i: int) =
  s.add(spaces(i))

proc newIndent(curr, indent: int, ml: bool): int =
  if ml: return curr + indent
  else: return indent

proc nl(s: var string, ml: bool) =
  s.add(if ml: "\n" else: " ")

proc escapeJsonexUnquoted*(s: string; result: var string, escapePeriod: bool) =
  ## Converts a string `s` to its JSON representation without quotes.
  ## Appends to `result`.
  for i, c in s:
    case c
    of '\L': result.add("\\n")
    of '\b': result.add("\\b")
    of '\f': result.add("\\f")
    of '\t': result.add("\\t")
    of '\v': result.add("\\u000b")
    of '\r': result.add("\\r")
    of '"': result.add("\\\"")
    of '\0'..'\7': result.add("\\u000" & $ord(c))
    of '\14'..'\31': result.add("\\u00" & toHex(ord(c), 2))
    of '\\': result.add("\\\\")
    of '.':
      if escapePeriod:
        result.add("..")
      else:
        result.add('.')
    else: result.add(c)

proc escapeJsonexUnquoted*(s: string, escapePeriod: bool): string =
  ## Converts a string `s` to its JSON representation without quotes.
  result = newStringOfCap(s.len + s.len shr 3)
  escapeJsonexUnquoted(s, result, escapePeriod)

proc escapeJsonex*(s: string; result: var string, extend: bool = false, escapePeriod: bool = false) =
  ## Converts a string `s` to its JSON representation with quotes.
  ## Appends to `result`.
  result.add("\"")
  if extend:
    result.add("+")
  escapeJsonexUnquoted(s, result, escapePeriod)
  result.add("\"")

proc escapeJsonex*(s: string, extend: bool = false, escapePeriod: bool = false): string =
  ## Converts a string `s` to its JSON representation with quotes.
  result = newStringOfCap(s.len + s.len shr 3)
  escapeJsonex(s, result, extend)

proc toUgly*(result: var string, node: JsonNodeEx) =
  ## Converts `node` to its JSON Representation, without
  ## regard for human readability. Meant to improve `$` string
  ## conversion performance.
  ##
  ## JSON representation is stored in the passed `result`
  ##
  ## This provides higher efficiency than the `pretty` procedure as it
  ## does **not** attempt to format the resulting JSON to make it human readable.
  if node.isNil:
    result.add "nil"
    return
  var comma = false
  case node.kind:
  of JArray:
    result.add "["
    for child in node.elems:
      if comma: result.add ","
      else: comma = true
      result.toUgly child
    result.add "]"
  of JObject:
    result.add "{"
    for key, value in pairs(node.fields):
      if comma: result.add ","
      else: comma = true
      key.escapeJsonex(result, value.extend, escapePeriod = true)
      result.add ":"
      result.toUgly value
    result.add "}"
  of JString:
    if node.isUnquoted:
      result.add node.str
    else:
      escapeJsonex(node.str, result)
  of JInt:
    result.addInt(node.num)
  of JFloat:
    result.addFloat(node.fnum)
  of JBool:
    result.add(if node.bval: "true" else: "false")
  of JNull:
    result.add "null"

proc toPretty(result: var string, node: JsonNodeEx, indent = 2, ml = true,
              lstArr = false, currIndent = 0, parentUserData = 0, printUserData: proc(node: JsonNodeEx): string {.gcsafe, raises: [].} = nil) =
  if node.isNil:
    result.add "nil"
    return
  case node.kind
  of JObject:
    if lstArr: result.indent(currIndent) # Indentation
    if node.fields.len > 0:
      result.add("{")
      if printUserData != nil:
        result.add(" // ")
        result.add(printUserData(node))
      result.nl(ml) # New line
      var i = 0
      for key, val in pairs(node.fields):
        # Need to indent more than {
        result.indent(newIndent(currIndent, indent, ml))
        escapeJsonex(key, result, val.extend, escapePeriod = true)
        result.add(": ")
        toPretty(result, val, indent, ml, false,
                 newIndent(currIndent, indent, ml), node.userData, printUserData)

        if i < node.fields.len - 1:
          result.add(",")
        if printUserData != nil and node.userData != parentUserData:
          result.add(" // ")
          result.add(printUserData(val))
        if i < node.fields.len - 1:
          result.nl(ml) # New Line
        inc i

      result.nl(ml)
      result.indent(currIndent) # indent the same as {
      result.add("}")
    else:
      result.add("{}")

  of JString:
    if lstArr: result.indent(currIndent)
    toUgly(result, node)
  of JInt:
    if lstArr: result.indent(currIndent)
    result.addInt(node.num)
  of JFloat:
    if lstArr: result.indent(currIndent)
    result.addFloat(node.fnum)
  of JBool:
    if lstArr: result.indent(currIndent)
    result.add(if node.bval: "true" else: "false")

  of JArray:
    if lstArr: result.indent(currIndent)
    if len(node.elems) != 0:
      result.add("[")
      if printUserData != nil:
        result.add(" // ")
        result.add(printUserData(node))
      result.nl(ml)
      for i in 0..len(node.elems)-1:
        if i > 0:
          result.add(",")
          result.nl(ml) # New Line
        toPretty(result, node.elems[i], indent, ml,
            true, newIndent(currIndent, indent, ml), node.userData, printUserData)
      result.nl(ml)
      result.indent(currIndent)
      result.add("]")
    else: result.add("[]")

  of JNull:
    if lstArr: result.indent(currIndent)
    result.add("null")

proc pretty*(node: JsonNodeEx, indent = 2, printUserData: proc(node: JsonNodeEx): string {.gcsafe, raises: [].} = nil): string =
  ## Returns a JSON Representation of `node`, with indentation and
  ## on multiple lines.
  ##
  ## Similar to prettyprint in Python.
  runnableExamples:
    let j = %%* {"name": "Isaac", "books": ["Robot Dreams"],
                "details": {"age": 35, "pi": 3.1415}}
    doAssert pretty(j) == """
{
  "name": "Isaac",
  "books": [
    "Robot Dreams"
  ],
  "details": {
    "age": 35,
    "pi": 3.1415
  }
}"""
  result = ""
  toPretty(result, node, indent, printUserData = printUserData)

proc `$`*(node: JsonNodeEx): string =
  ## Converts `node` to its JSON Representation on one line.
  if node == nil:
    return "nil"
  result = newStringOfCap(node.len shl 1)
  toUgly(result, node)

iterator items*(node: JsonNodeEx): JsonNodeEx =
  ## Iterator for the items of `node`. `node` has to be a JArray.
  assert node.kind == JArray, ": items() can not iterate a JsonNodeEx of kind " & $node.kind
  for i in items(node.elems):
    yield i

iterator mitems*(node: var JsonNodeEx): var JsonNodeEx =
  ## Iterator for the items of `node`. `node` has to be a JArray. Items can be
  ## modified.
  assert node.kind == JArray, ": mitems() can not iterate a JsonNodeEx of kind " & $node.kind
  for i in mitems(node.elems):
    yield i

iterator pairs*(node: JsonNodeEx): tuple[key: string, val: JsonNodeEx] =
  ## Iterator for the child elements of `node`. `node` has to be a JObject.
  assert node.kind == JObject, ": pairs() can not iterate a JsonNodeEx of kind " & $node.kind
  for key, val in pairs(node.fields):
    yield (key, val)

iterator keys*(node: JsonNodeEx): string =
  ## Iterator for the keys in `node`. `node` has to be a JObject.
  assert node.kind == JObject, ": keys() can not iterate a JsonNodeEx of kind " & $node.kind
  for key in node.fields.keys:
    yield key

iterator mpairs*(node: var JsonNodeEx): tuple[key: string, val: var JsonNodeEx] =
  ## Iterator for the child elements of `node`. `node` has to be a JObject.
  ## Values can be modified
  assert node.kind == JObject, ": mpairs() can not iterate a JsonNodeEx of kind " & $node.kind
  for key, val in mpairs(node.fields):
    yield (key, val)

proc parseJsonex(p: var JsonParser; rawIntegers, rawFloats: bool, depth = 0): JsonNodeEx =
  ## Parses JSON from a JSON Parser `p`.
  case p.tok
  of tkString:
    # we capture 'p.a' here, so we need to give it a fresh buffer afterwards:
    when defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc):
      result = JsonNodeEx(kind: JString, str: move p.a)
    else:
      result = JsonNodeEx(kind: JString)
      shallowCopy(result.str, p.a)
      p.a = ""
    discard getTok(p)
  of tkInt:
    if rawIntegers:
      result = newJexRawNumber(p.a)
    else:
      try:
        result = newJexInt(parseBiggestInt(p.a))
      except ValueError:
        result = newJexRawNumber(p.a)
    discard getTok(p)
  of tkFloat:
    if rawFloats:
      result = newJexRawNumber(p.a)
    else:
      try:
        result = newJexFloat(parseFloat(p.a))
      except ValueError:
        result = newJexRawNumber(p.a)
    discard getTok(p)
  of tkTrue:
    result = newJexBool(true)
    discard getTok(p)
  of tkFalse:
    result = newJexBool(false)
    discard getTok(p)
  of tkNull:
    result = newJexNull()
    discard getTok(p)
  of tkCurlyLe:
    if depth > DepthLimit:
      raiseParseErr(p, "}")
    result = newJexObject()
    discard getTok(p)
    while p.tok != tkCurlyRi:
      if p.tok != tkString:
        raiseParseErr(p, "string literal as key")
      var key = p.a
      discard getTok(p)
      eat(p, tkColon)
      var val = parseJsonex(p, rawIntegers, rawFloats, depth+1)
      result[key] = val
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkCurlyRi)
  of tkBracketLe:
    if depth > DepthLimit:
      raiseParseErr(p, "]")
    result = newJexArray()
    discard getTok(p)
    while p.tok != tkBracketRi:
      result.add(parseJsonex(p, rawIntegers, rawFloats, depth+1))
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkBracketRi)
  of tkError, tkCurlyRi, tkBracketRi, tkColon, tkComma, tkEof:
    raiseParseErr(p, "{")

iterator parseJsonexFragments*(s: Stream, filename: string = ""; rawIntegers = false, rawFloats = false): JsonNodeEx =
  ## Parses from a stream `s` into `JsonNodeExs`. `filename` is only needed
  ## for nice error messages.
  ## The JSON fragments are separated by whitespace. This can be substantially
  ## faster than the comparable loop
  ## `for x in splitWhitespace(s): yield parseJsonex(x)`.
  ## This closes the stream `s` after it's done.
  ## If `rawIntegers` is true, integer literals will not be converted to a `JInt`
  ## field but kept as raw numbers via `JString`.
  ## If `rawFloats` is true, floating point literals will not be converted to a `JFloat`
  ## field but kept as raw numbers via `JString`.
  var p: JsonParser
  p.open(s, filename)
  try:
    discard getTok(p) # read first token
    while p.tok != tkEof:
      yield p.parseJsonex(rawIntegers, rawFloats)
  finally:
    p.close()

proc parseJsonex*(s: Stream, filename: string = ""; rawIntegers = false, rawFloats = false): JsonNodeEx =
  ## Parses from a stream `s` into a `JsonNodeEx`. `filename` is only needed
  ## for nice error messages.
  ## If `s` contains extra data, it will raise `JsonParsingError`.
  ## This closes the stream `s` after it's done.
  ## If `rawIntegers` is true, integer literals will not be converted to a `JInt`
  ## field but kept as raw numbers via `JString`.
  ## If `rawFloats` is true, floating point literals will not be converted to a `JFloat`
  ## field but kept as raw numbers via `JString`.
  var p: JsonParser
  p.open(s, filename)
  try:
    discard getTok(p) # read first token
    result = p.parseJsonex(rawIntegers, rawFloats)
    eat(p, tkEof) # check if there is no extra data
  finally:
    p.close()

proc parseJsonex*(buffer: string; rawIntegers = false, rawFloats = false): JsonNodeEx =
  ## Parses JSON from `buffer`.
  ## If `buffer` contains extra data, it will raise `JsonParsingError`.
  ## If `rawIntegers` is true, integer literals will not be converted to a `JInt`
  ## field but kept as raw numbers via `JString`.
  ## If `rawFloats` is true, floating point literals will not be converted to a `JFloat`
  ## field but kept as raw numbers via `JString`.
  result = parseJsonex(newStringStream(buffer), "input", rawIntegers, rawFloats)

proc parseFile*(filename: string): JsonNodeEx =
  ## Parses `file` into a `JsonNodeEx`.
  ## If `file` contains extra data, it will raise `JsonParsingError`.
  var stream = newFileStream(filename, fmRead)
  if stream == nil:
    raise newException(IOError, "cannot read from file: " & filename)
  result = parseJsonex(stream, filename, rawIntegers=false, rawFloats=false)

# -- Json deserialiser. --

template verifyJsonKind(node: JsonNodeEx, kinds: set[JsonNodeKind],
                        ast: string) =
  if node == nil:
    raise newException(KeyError, "key not found: " & ast)
  elif  node.kind notin kinds:
    let msg = "Incorrect JSON kind. Wanted '$1' in '$2' but got '$3'." % [
      $kinds,
      ast,
      $node.kind
    ]
    raise newException(JsonKindError, msg)

macro isRefSkipDistinct*(arg: typed): untyped =
  ## internal only, do not use
  var impl = getTypeImpl(arg)
  if impl.kind == nnkBracketExpr and impl[0].eqIdent("typeDesc"):
    impl = getTypeImpl(impl[1])
  while impl.kind == nnkDistinctTy:
    impl = getTypeImpl(impl[0])
  result = newLit(impl.kind == nnkRefTy)

# The following forward declarations don't work in older versions of Nim

# forward declare all initFromJson

proc initFromJson(dst: var string; jsonNode: JsonNodeEx; jsonPath: var string)
proc initFromJson(dst: var bool; jsonNode: JsonNodeEx; jsonPath: var string)
proc initFromJson(dst: var JsonNodeEx; jsonNode: JsonNodeEx; jsonPath: var string)
proc initFromJson[T: SomeInteger](dst: var T; jsonNode: JsonNodeEx, jsonPath: var string)
proc initFromJson[T: SomeFloat](dst: var T; jsonNode: JsonNodeEx; jsonPath: var string)
proc initFromJson[T: enum](dst: var T; jsonNode: JsonNodeEx; jsonPath: var string)
proc initFromJson[T](dst: var seq[T]; jsonNode: JsonNodeEx; jsonPath: var string)
proc initFromJson[S, T](dst: var array[S, T]; jsonNode: JsonNodeEx; jsonPath: var string)
proc initFromJson[T](dst: var Table[string, T]; jsonNode: JsonNodeEx; jsonPath: var string)
proc initFromJson[T](dst: var OrderedTable[string, T]; jsonNode: JsonNodeEx; jsonPath: var string)
proc initFromJson[T](dst: var ref T; jsonNode: JsonNodeEx; jsonPath: var string)
proc initFromJson[T](dst: var Option[T]; jsonNode: JsonNodeEx; jsonPath: var string)
proc initFromJson[T: distinct](dst: var T; jsonNode: JsonNodeEx; jsonPath: var string)
proc initFromJson[T: object|tuple](dst: var T; jsonNode: JsonNodeEx; jsonPath: var string)

# initFromJson definitions

proc initFromJson(dst: var string; jsonNode: JsonNodeEx; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JString, JNull}, jsonPath)
  # since strings don't have a nil state anymore, this mapping of
  # JNull to the default string is questionable. `none(string)` and
  # `some("")` have the same potentional json value `JNull`.
  if jsonNode.kind == JNull:
    dst = ""
  else:
    dst = jsonNode.str

proc initFromJson(dst: var bool; jsonNode: JsonNodeEx; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JBool}, jsonPath)
  dst = jsonNode.bval

proc initFromJson(dst: var JsonNodeEx; jsonNode: JsonNodeEx; jsonPath: var string) =
  if jsonNode == nil:
    raise newException(KeyError, "key not found: " & jsonPath)
  dst = jsonNode.copy

proc initFromJson[T: SomeInteger](dst: var T; jsonNode: JsonNodeEx, jsonPath: var string) =
  when T is uint|uint64 or int.sizeof == 4:
    verifyJsonKind(jsonNode, {JInt, JString}, jsonPath)
    case jsonNode.kind
    of JString:
      let x = parseBiggestUInt(jsonNode.str)
      dst = cast[T](x)
    else:
      dst = T(jsonNode.num)
  else:
    verifyJsonKind(jsonNode, {JInt}, jsonPath)
    dst = cast[T](jsonNode.num)

proc initFromJson[T: SomeFloat](dst: var T; jsonNode: JsonNodeEx; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JInt, JFloat, JString}, jsonPath)
  if jsonNode.kind == JString:
    case jsonNode.str
    of "nan":
      let b = NaN
      dst = T(b)
      # dst = NaN # would fail some tests because range conversions would cause CT error
      # in some cases; but this is not a hot-spot inside this branch and backend can optimize this.
    of "inf":
      let b = Inf
      dst = T(b)
    of "-inf":
      let b = -Inf
      dst = T(b)
    else: raise newException(JsonKindError, "expected 'nan|inf|-inf', got " & jsonNode.str)
  else:
    if jsonNode.kind == JFloat:
      dst = T(jsonNode.fnum)
    else:
      dst = T(jsonNode.num)

proc initFromJson[T: enum](dst: var T; jsonNode: JsonNodeEx; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JString}, jsonPath)
  dst = parseEnum[T](jsonNode.getStr)

proc initFromJson[T](dst: var seq[T]; jsonNode: JsonNodeEx; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JArray}, jsonPath)
  dst.setLen jsonNode.len
  let orignalJsonPathLen = jsonPath.len
  for i in 0 ..< jsonNode.len:
    jsonPath.add '['
    jsonPath.addInt i
    jsonPath.add ']'
    initFromJson(dst[i], jsonNode[i], jsonPath)
    jsonPath.setLen orignalJsonPathLen

proc initFromJson[S,T](dst: var array[S,T]; jsonNode: JsonNodeEx; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JArray}, jsonPath)
  let originalJsonPathLen = jsonPath.len
  for i in 0 ..< jsonNode.len:
    jsonPath.add '['
    jsonPath.addInt i
    jsonPath.add ']'
    initFromJson(dst[i.S], jsonNode[i], jsonPath) # `.S` for enum indexed arrays
    jsonPath.setLen originalJsonPathLen

proc initFromJson[T](dst: var Table[string,T]; jsonNode: JsonNodeEx; jsonPath: var string) =
  dst = initTable[string, T]()
  verifyJsonKind(jsonNode, {JObject}, jsonPath)
  let originalJsonPathLen = jsonPath.len
  for key in keys(jsonNode.fields):
    jsonPath.add '.'
    jsonPath.add key
    initFromJson(mgetOrPut(dst, key, default(T)), jsonNode[key], jsonPath)
    jsonPath.setLen originalJsonPathLen

proc initFromJson[T](dst: var OrderedTable[string,T]; jsonNode: JsonNodeEx; jsonPath: var string) =
  dst = initOrderedTable[string,T]()
  verifyJsonKind(jsonNode, {JObject}, jsonPath)
  let originalJsonPathLen = jsonPath.len
  for key in keys(jsonNode.fields):
    jsonPath.add '.'
    jsonPath.add key
    initFromJson(mgetOrPut(dst, key, default(T)), jsonNode[key], jsonPath)
    jsonPath.setLen originalJsonPathLen

proc initFromJson[T](dst: var ref T; jsonNode: JsonNodeEx; jsonPath: var string) =
  verifyJsonKind(jsonNode, {JObject, JNull}, jsonPath)
  if jsonNode.kind == JNull:
    dst = nil
  else:
    dst = new(T)
    initFromJson(dst[], jsonNode, jsonPath)

proc initFromJson[T](dst: var Option[T]; jsonNode: JsonNodeEx; jsonPath: var string) =
  if jsonNode != nil and jsonNode.kind != JNull:
    when T is ref:
      dst = some(new(T))
    else:
      dst = some(default(T))
    initFromJson(dst.get, jsonNode, jsonPath)

macro assignDistinctImpl[T: distinct](dst: var T;jsonNode: JsonNodeEx; jsonPath: var string) =
  let typInst = getTypeInst(dst)
  let typImpl = getTypeImpl(dst)
  let baseTyp = typImpl[0]

  result = quote do:
    initFromJson(`baseTyp`(`dst`), `jsonNode`, `jsonPath`)

proc initFromJson[T: distinct](dst: var T; jsonNode: JsonNodeEx; jsonPath: var string) =
  assignDistinctImpl(dst, jsonNode, jsonPath)

proc detectIncompatibleType(typeExpr, lineinfoNode: NimNode) =
  if typeExpr.kind == nnkTupleConstr:
    error("Use a named tuple instead of: " & typeExpr.repr, lineinfoNode)

proc foldObjectBody(dst, typeNode, tmpSym, jsonNode, jsonPath, originalJsonPathLen: NimNode) =
  case typeNode.kind
  of nnkEmpty:
    discard
  of nnkRecList, nnkTupleTy:
    for it in typeNode:
      foldObjectBody(dst, it, tmpSym, jsonNode, jsonPath, originalJsonPathLen)

  of nnkIdentDefs:
    typeNode.expectLen 3
    let fieldSym = typeNode[0]
    let fieldNameLit = newLit(fieldSym.strVal)
    let fieldPathLit = newLit("." & fieldSym.strVal)
    let fieldType = typeNode[1]

    # Detecting incompatiple tuple types in `assignObjectImpl` only
    # would be much cleaner, but the ast for tuple types does not
    # contain usable type information.
    detectIncompatibleType(fieldType, fieldSym)

    dst.add quote do:
      jsonPath.add `fieldPathLit`
      when nimvm:
        when isRefSkipDistinct(`tmpSym`.`fieldSym`):
          # workaround #12489
          var tmp: `fieldType`
          initFromJson(tmp, getOrDefault(`jsonNode`,`fieldNameLit`), `jsonPath`)
          `tmpSym`.`fieldSym` = tmp
        else:
          initFromJson(`tmpSym`.`fieldSym`, getOrDefault(`jsonNode`,`fieldNameLit`), `jsonPath`)
      else:
        initFromJson(`tmpSym`.`fieldSym`, getOrDefault(`jsonNode`,`fieldNameLit`), `jsonPath`)
      jsonPath.setLen `originalJsonPathLen`

  of nnkRecCase:
    let kindSym = typeNode[0][0]
    let kindNameLit = newLit(kindSym.strVal)
    let kindPathLit = newLit("." & kindSym.strVal)
    let kindType = typeNode[0][1]
    let kindOffsetLit = newLit(uint(getOffset(kindSym)))
    dst.add quote do:
      var kindTmp: `kindType`
      jsonPath.add `kindPathLit`
      initFromJson(kindTmp, `jsonNode`[`kindNameLit`], `jsonPath`)
      jsonPath.setLen `originalJsonPathLen`
      when nimvm:
        `tmpSym`.`kindSym` = kindTmp
      else:
        # fuck it, assign kind field anyway
        ((cast[ptr `kindType`](cast[uint](`tmpSym`.addr) + `kindOffsetLit`))[]) = kindTmp
    dst.add nnkCaseStmt.newTree(nnkDotExpr.newTree(tmpSym, kindSym))
    for i in 1 ..< typeNode.len:
      foldObjectBody(dst, typeNode[i], tmpSym, jsonNode, jsonPath, originalJsonPathLen)

  of nnkOfBranch, nnkElse:
    let ofBranch = newNimNode(typeNode.kind)
    for i in 0 ..< typeNode.len-1:
      ofBranch.add copyNimTree(typeNode[i])
    let dstInner = newNimNode(nnkStmtListExpr)
    foldObjectBody(dstInner, typeNode[^1], tmpSym, jsonNode, jsonPath, originalJsonPathLen)
    # resOuter now contains the inner stmtList
    ofBranch.add dstInner
    dst[^1].expectKind nnkCaseStmt
    dst[^1].add ofBranch

  of nnkObjectTy:
    typeNode[0].expectKind nnkEmpty
    typeNode[1].expectKind {nnkEmpty, nnkOfInherit}
    if typeNode[1].kind == nnkOfInherit:
      let base = typeNode[1][0]
      var impl = getTypeImpl(base)
      while impl.kind in {nnkRefTy, nnkPtrTy}:
        impl = getTypeImpl(impl[0])
      foldObjectBody(dst, impl, tmpSym, jsonNode, jsonPath, originalJsonPathLen)
    let body = typeNode[2]
    foldObjectBody(dst, body, tmpSym, jsonNode, jsonPath, originalJsonPathLen)

  else:
    error("unhandled kind: " & $typeNode.kind, typeNode)

macro assignObjectImpl[T](dst: var T; jsonNode: JsonNodeEx; jsonPath: var string) =
  let typeSym = getTypeInst(dst)
  let originalJsonPathLen = genSym(nskLet, "originalJsonPathLen")
  result = newStmtList()
  result.add quote do:
    let `originalJsonPathLen` = len(`jsonPath`)
  if typeSym.kind in {nnkTupleTy, nnkTupleConstr}:
    # both, `dst` and `typeSym` don't have good lineinfo. But nothing
    # else is available here.
    detectIncompatibleType(typeSym, dst)
    foldObjectBody(result, typeSym, dst, jsonNode, jsonPath, originalJsonPathLen)
  else:
    foldObjectBody(result, typeSym.getTypeImpl, dst, jsonNode, jsonPath, originalJsonPathLen)

proc initFromJson[T: object|tuple](dst: var T; jsonNode: JsonNodeEx; jsonPath: var string) =
  assignObjectImpl(dst, jsonNode, jsonPath)

proc to*[T](node: JsonNodeEx, t: typedesc[T]): T =
  ## `Unmarshals`:idx: the specified node into the object type specified.
  ##
  ## Known limitations:
  ##
  ##   * Heterogeneous arrays are not supported.
  ##   * Sets in object variants are not supported.
  ##   * Not nil annotations are not supported.
  ##
  runnableExamples:
    let jsonNode = parseJsonex("""
      {
        "person": {
          "name": "Nimmer",
          "age": 21
        },
        "list": [1, 2, 3, 4]
      }
    """)

    type
      Person = object
        name: string
        age: int

      Data = object
        person: Person
        list: seq[int]

    var data = to(jsonNode, Data)
    doAssert data.person.name == "Nimmer"
    doAssert data.person.age == 21
    doAssert data.list == @[1, 2, 3, 4]

  var jsonPath = ""
  result = default(T)
  initFromJson(result, node, jsonPath)



##########################

macro getDiscriminants(a: typedesc): seq[string] =
  ## return the discriminant keys
  # candidate for std/typetraits
  var a = a.getTypeImpl
  doAssert a.kind == nnkBracketExpr
  let sym = a[1]
  let t = sym.getTypeImpl
  let t2 = t[2]
  doAssert t2.kind == nnkRecList
  result = newTree(nnkBracket)
  for ti in t2:
    if ti.kind == nnkRecCase:
      let key = ti[0][0]
      result.add newLit key.strVal
  if result.len > 0:
    result = quote do:
      @`result`
  else:
    result = quote do:
      seq[string].default

macro initCaseObject(T: typedesc, fun: untyped): untyped =
  ## does the minimum to construct a valid case object, only initializing
  ## the discriminant fields; see also `getDiscriminants`
  # maybe candidate for std/typetraits
  var a = T.getTypeImpl
  doAssert a.kind == nnkBracketExpr
  let sym = a[1]
  let t = sym.getTypeImpl
  var t2: NimNode
  case t.kind
  of nnkObjectTy: t2 = t[2]
  of nnkRefTy: t2 = t[0].getTypeImpl[2]
  else: doAssert false, $t.kind # xxx `nnkPtrTy` could be handled too
  doAssert t2.kind == nnkRecList
  result = newTree(nnkObjConstr)
  result.add sym
  for ti in t2:
    if ti.kind == nnkRecCase:
      let key = ti[0][0]
      let typ = ti[0][1]
      let key2 = key.strVal
      let val = quote do:
        `fun`(`key2`, typedesc[`typ`])
      result.add newTree(nnkExprColonExpr, key, val)

proc raiseJsonException(condStr: string, msg: string) {.noinline.} =
  # just pick 1 exception type for simplicity; other choices would be:
  # JsonError, JsonParser, JsonKindError
  raise newException(ValueError, condStr & " failed: " & msg)

template checkJson(cond: untyped, msg = "") =
  if not cond:
    raiseJsonException(astToStr(cond), msg)

proc hasField[T](obj: T, field: string): bool =
  for k, _ in fieldPairs(obj):
    if k == field:
      return true
  return false

macro accessField(obj: typed, name: static string): untyped =
  newDotExpr(obj, ident(name))

template fromJsonExFields(newObj, oldObj, json, discKeys, opt) =
  type T = typeof(newObj)
  # we could customize whether to allow JNull
  checkJson json.kind == JObject, $json.kind
  var num, numMatched = 0
  for key, val in fieldPairs(newObj):
    num.inc
    when key notin discKeys:
      if json.hasKey key:
        numMatched.inc
        fromJsonEx(val, json[key], opt)
      elif opt.allowMissingKeys:
        # if there are no discriminant keys the `oldObj` must always have the
        # same keys as the new one. Otherwise we must check, because they could
        # be set to different branches.
        when typeof(oldObj) isnot typeof(nil):
          if discKeys.len == 0 or hasField(oldObj, key):
            val = accessField(oldObj, key)
      else:
        checkJson false, $($T, key, json)
    else:
      if json.hasKey key:
        numMatched.inc

  let ok =
    if opt.allowExtraKeys and opt.allowMissingKeys:
      true
    elif opt.allowExtraKeys:
      # This check is redundant because if here missing keys are not allowed,
      # and if `num != numMatched` it will fail in the loop above but it is left
      # for clarity.
      assert num == numMatched
      num == numMatched
    elif opt.allowMissingKeys:
      json.len == numMatched
    else:
      json.len == num and num == numMatched

  checkJson ok, $(json.len, num, numMatched, $T, json)

proc fromJsonEx*[T](a: var T, b: JsonNodeEx, opt = Joptions()) {.raises: [ValueError].}

proc discKeyMatch[T](obj: T, json: JsonNodeEx, key: static string): bool =
  if not json.hasKey key:
    return true
  let field = accessField(obj, key)
  var jsonVal: typeof(field)
  fromJsonEx(jsonVal, json[key])
  if jsonVal != field:
    return false
  return true

macro discKeysMatchBodyGen(obj: typed, json: JsonNodeEx,
                           keys: static seq[string]): untyped =
  result = newStmtList()
  let r = ident("result")
  for key in keys:
    let keyLit = newLit key
    result.add quote do:
      `r` = `r` and discKeyMatch(`obj`, `json`, `keyLit`)

proc discKeysMatch[T](obj: T, json: JsonNodeEx, keys: static seq[string]): bool =
  result = true
  discKeysMatchBodyGen(obj, json, keys)

proc fromJsonEx*[T](a: var T, b: JsonNodeEx, opt = Joptions()) {.raises: [ValueError].} =
  ## inplace version of `jsonTo`
  #[
  adding "json path" leading to `b` can be added in future work.
  ]#
  checkJson b != nil, $($T, b)
  when compiles(fromJsonExHook(a, b, opt)): fromJsonExHook(a, b, opt)
  elif compiles(fromJsonExHook(a, b)): fromJsonExHook(a, b)
  elif T is bool: a = to(b,T)
  elif T is enum:
    case b.kind
    of JInt: a = T(b.getBiggestInt())
    of JString: a = parseEnum[T](b.getStr())
    else: checkJson false, $($T, " ", b)
  elif T is uint|uint64: a = T(to(b, uint64))
  elif T is Ordinal: a = cast[T](to(b, int))
  elif T is pointer: a = cast[pointer](to(b, int))
  elif T is distinct:
    when nimvm:
      # bug, potentially related to https://github.com/nim-lang/Nim/issues/12282
      when distinctBase(T) is JsonNodeEx:
        a = T(b)
      else:
        a = T(jsonTo(b, distinctBase(T)))
    else:
      a.distinctBase.fromJsonEx(b)
  elif T is string|SomeNumber: a = to(b,T)
  elif T is cstring:
    case b.kind
    of JNull: a = nil
    of JString: a = b.str
    else: checkJson false, $($T, " ", b)
  elif T is JsonNodeEx: a = b
  elif T is ref | ptr:
    if b.kind == JNull: a = nil
    else:
      a = T()
      fromJsonEx(a[], b, opt)
  elif T is array:
    checkJson a.len == b.len, $(a.len, b.len, $T)
    var i = 0
    for ai in mitems(a):
      fromJsonEx(ai, b[i], opt)
      i.inc
  elif T is set:
    type E = typeof(for ai in a: ai)
    for val in b.getElems:
      incl a, jsonTo(val, E)
  elif T is seq:
    a.setLen b.len
    for i, val in b.getElems:
      fromJsonEx(a[i], val, opt)
  elif T is object:
    template fun(key, typ): untyped {.used.} =
      if b.hasKey key:
        jsonTo(b[key], typ)
      elif hasField(a, key):
        accessField(a, key)
      else:
        default(typ)
    const keys = getDiscriminants(T)
    when keys.len == 0:
      fromJsonExFields(a, nil, b, keys, opt)
    else:
      if discKeysMatch(a, b, keys):
        fromJsonExFields(a, nil, b, keys, opt)
      else:
        var newObj = initCaseObject(T, fun)
        fromJsonExFields(newObj, a, b, keys, opt)
        a = newObj
  elif T is tuple:
    when isNamedTuple(T):
      fromJsonExFields(a, nil, b, seq[string].default, opt)
    else:
      checkJson b.kind == JArray, $(b.kind) # we could customize whether to allow JNull
      var i = 0
      for val in fields(a):
        fromJsonEx(val, b[i], opt)
        i.inc
      checkJson b.len == i, $(b.len, i, $T, b) # could customize
  else:
    # checkJson not appropriate here
    static: doAssert false, "not yet implemented: " & $T

proc jsonTo*(b: JsonNodeEx, T: typedesc, opt = Joptions()): T {.raises: [ValueError].} =
  ## reverse of `toJsonEx`
  fromJsonEx(result, b, opt)

proc toJsonEx*[T](a: T, opt = initToJsonOptions()): JsonNodeEx {.raises: [].} =
  ## serializes `a` to json; uses `toJsonExHook(a: T)` if it's in scope to
  ## customize serialization, see strtabs.toJsonExHook for an example.
  ##
  ## .. note:: With `-d:nimPreviewJsonutilsHoleyEnum`, `toJsonEx` now can
  ##    serialize/deserialize holey enums as regular enums (via `ord`) instead of as strings.
  ##    It is expected that this behavior becomes the new default in upcoming versions.
  when compiles(toJsonExHook(a)): result = toJsonExHook(a)
  elif T is object | tuple:
    when T is object or isNamedTuple(T):
      result = newJexObject()
      for k, v in a.fieldPairs: result[k] = toJsonEx(v, opt)
    else:
      result = newJexArray()
      for v in a.fields: result.add toJsonEx(v, opt)
  elif T is ref | ptr:
    template impl =
      if system.`==`(a, nil): result = newJexNull()
      else: result = toJsonEx(a[], opt)
    when T is JsonNodeEx:
      case opt.jsonNodeMode
      of joptJsonNodeAsRef: result = a
      of joptJsonNodeAsCopy: result = copy(a)
      of joptJsonNodeAsObject: impl()
    else: impl()
  elif T is array | seq | set:
    result = newJexArray()
    for ai in a: result.add toJsonEx(ai, opt)
  elif T is pointer: result = toJsonEx(cast[int](a), opt)
    # edge case: `a == nil` could've also led to `newJexNull()`, but this results
    # in simpler code for `toJsonEx` and `fromJsonEx`.
  elif T is distinct: result = toJsonEx(a.distinctBase, opt)
  elif T is bool: result = %%(a)
  elif T is SomeInteger: result = %%a
  elif T is enum:
    case opt.enumMode
    of joptEnumOrd:
      when T is Ordinal or defined(nimPreviewJsonutilsHoleyEnum): %%(a.ord)
      else: toJsonEx($a, opt)
    of joptEnumSymbol:
      when T is OrdinalEnum:
        toJsonEx(symbolName(a), opt)
      else:
        toJsonEx($a, opt)
    of joptEnumString: toJsonEx($a, opt)
  elif T is Ordinal: result = %%(a.ord)
  elif T is cstring: (if a == nil: result = newJexNull() else: result = %% $a)
  else: result = %%a

proc fromJsonExHook*[K: string|cstring, V](t: var (Table[K, V] | OrderedTable[K, V]), jsonNode: JsonNodeEx, opt = Joptions()) =
  ## Enables `fromJsonEx` for `Table` and `OrderedTable` types.
  ##
  ## See also:
  ## * `toJsonExHook proc<#toJsonExHook>`_
  runnableExamples:
    import std/[tables, json]
    var foo: tuple[t: Table[string, int], ot: OrderedTable[string, int]]
    fromJsonEx(foo, parseJsonex("""
      {"t":{"two":2,"one":1},"ot":{"one":1,"three":3}}"""))
    assert foo.t == [("one", 1), ("two", 2)].toTable
    assert foo.ot == [("one", 1), ("three", 3)].toOrderedTable

  assert jsonNode.kind == JObject,
          "The kind of the `jsonNode` must be `JObject`, but its actual " &
          "type is `" & $jsonNode.kind & "`."
  clear(t)
  for k, v in jsonNode:
    t[k] = jsonTo(v, V, opt)

proc toJsonExHook*[K: string|cstring, V](t: (Table[K, V] | OrderedTable[K, V])): JsonNodeEx =
  ## Enables `toJsonEx` for `Table` and `OrderedTable` types.
  ##
  ## See also:
  ## * `fromJsonExHook proc<#fromJsonExHook,,JsonNodeEx>`_
  # pending PR #9217 use: toSeq(a) instead of `collect` in `runnableExamples`.
  runnableExamples:
    import std/[tables, json, sugar]
    let foo = (
      t: [("two", 2)].toTable,
      ot: [("one", 1), ("three", 3)].toOrderedTable)
    assert $toJsonEx(foo) == """{"t":{"two":2},"ot":{"one":1,"three":3}}"""
    # if keys are not string|cstring, you can use this:
    let a = {10: "foo", 11: "bar"}.newOrderedTable
    let a2 = collect: (for k,v in a: (k,v))
    assert $toJsonEx(a2) == """[[10,"foo"],[11,"bar"]]"""

  result = newJexObject()
  for k, v in pairs(t):
    # not sure if $k has overhead for string
    result[(when K is string: k else: $k)] = toJsonEx(v)

proc fromJsonExHook*[A](s: var SomeSet[A], jsonNode: JsonNodeEx, opt = Joptions()) =
  ## Enables `fromJsonEx` for `HashSet` and `OrderedSet` types.
  ##
  ## See also:
  ## * `toJsonExHook proc<#toJsonExHook,SomeSet[A]>`_
  runnableExamples:
    import std/[sets, json]
    var foo: tuple[hs: HashSet[string], os: OrderedSet[string]]
    fromJsonEx(foo, parseJsonex("""
      {"hs": ["hash", "set"], "os": ["ordered", "set"]}"""))
    assert foo.hs == ["hash", "set"].toHashSet
    assert foo.os == ["ordered", "set"].toOrderedSet

  assert jsonNode.kind == JArray,
          "The kind of the `jsonNode` must be `JArray`, but its actual " &
          "type is `" & $jsonNode.kind & "`."
  clear(s)
  for v in jsonNode:
    incl(s, jsonTo(v, A, opt))

proc toJsonExHook*[A](s: SomeSet[A]): JsonNodeEx =
  ## Enables `toJsonEx` for `HashSet` and `OrderedSet` types.
  ##
  ## See also:
  ## * `fromJsonExHook proc<#fromJsonExHook,SomeSet[A],JsonNodeEx>`_
  runnableExamples:
    import std/[sets, json]
    let foo = (hs: ["hash"].toHashSet, os: ["ordered", "set"].toOrderedSet)
    assert $toJsonEx(foo) == """{"hs":["hash"],"os":["ordered","set"]}"""

  result = newJexArray()
  for k in s:
    add(result, toJsonEx(k))

proc fromJsonExHook*[T](self: var Option[T], jsonNode: JsonNodeEx, opt = Joptions()) =
  ## Enables `fromJsonEx` for `Option` types.
  ##
  ## See also:
  ## * `toJsonExHook proc<#toJsonExHook,Option[T]>`_
  runnableExamples:
    import std/[options, json]
    var opt: Option[string]
    fromJsonExHook(opt, parseJsonex("\"test\""))
    assert get(opt) == "test"
    fromJsonEx(opt, parseJsonex("null"))
    assert isNone(opt)

  if jsonNode.kind != JNull:
    self = some(jsonTo(jsonNode, T, opt))
  else:
    self = none[T]()

proc toJsonExHook*[T](self: Option[T]): JsonNodeEx =
  ## Enables `toJsonEx` for `Option` types.
  ##
  ## See also:
  ## * `fromJsonExHook proc<#fromJsonExHook,Option[T],JsonNodeEx>`_
  runnableExamples:
    import std/[options, json]
    let optSome = some("test")
    assert $toJsonEx(optSome) == "\"test\""
    let optNone = none[string]()
    assert $toJsonEx(optNone) == "null"

  if isSome(self):
    toJsonEx(get(self))
  else:
    newJexNull()

proc fromJsonExHook*(a: var StringTableRef, b: JsonNodeEx, opt = Joptions()) =
  ## Enables `fromJsonEx` for `StringTableRef` type.
  ##
  ## See also:
  ## * `toJsonExHook proc<#toJsonExHook,StringTableRef>`_
  runnableExamples:
    import std/[strtabs, json]
    var t = newStringTable(modeCaseSensitive)
    let jsonStr = """{"mode": 0, "table": {"name": "John", "surname": "Doe"}}"""
    fromJsonExHook(t, parseJsonex(jsonStr))
    assert t[] == newStringTable("name", "John", "surname", "Doe",
                                 modeCaseSensitive)[]

  var mode = jsonTo(b["mode"], StringTableMode, opt = Joptions())
  a = newStringTable(mode)
  let b2 = b["table"]
  for k,v in b2: a[k] = jsonTo(v, string, opt = Joptions())

proc toJsonExHook*(a: StringTableRef): JsonNodeEx =
  ## Enables `toJsonEx` for `StringTableRef` type.
  ##
  ## See also:
  ## * `fromJsonExHook proc<#fromJsonExHook,StringTableRef,JsonNodeEx>`_
  runnableExamples:
    import std/[strtabs, json]
    let t = newStringTable("name", "John", "surname", "Doe", modeCaseSensitive)
    let jsonStr = """{"mode": "modeCaseSensitive",
                      "table": {"name": "John", "surname": "Doe"}}"""
    assert toJsonEx(t) == parseJsonex(jsonStr)

  result = newJexObject()
  result["mode"] = toJsonEx($a.mode)
  let t = newJexObject()
  for k,v in a: t[k] = toJsonEx(v)
  result["table"] = t

proc fromJsonExHook*(a: var Uri, b: JsonNodeEx, opt = Joptions()) =
  ## Enables `fromJsonEx` for `Uri` type.
  ##
  ## See also:
  ## * `toJsonExHook proc<#toJsonExHook,Uri>`_

  a = jsonTo(b, string, opt = Joptions()).parseUri

proc toJsonExHook*(a: Uri): JsonNodeEx =
  ## Enables `toJsonEx` for `Uri` type.
  ##
  ## See also:
  ## * `fromJsonExHook proc<#fromJsonExHook,Uri,JsonNodeEx>`_

  return ($a).toJsonEx

proc toJexArray*(arr: openArray[JsonNodeEx]): JsonNodeEx =
  result = newJexArray()
  for v in arr:
    result.add v

proc toJson*(node: JsonNodeEx): JsonNode =
  if node == nil:
    return nil
  case node.kind
  of JObject:
    result = newJObject()
    for (key, value) in node.fields.pairs:
      result[key] = value.toJson
  of JArray:
    result = newJArray()
    for value in node.elems:
      result.elems.add value.toJson
  of JString:
    result = newJString(node.str)
  of JInt:
    result = newJInt(node.num)
  of JFloat:
    result = newJFloat(node.fnum)
  of JBool:
    result = newJBool(node.bval)
  of JNull:
    result = newJNull()

proc toJsonEx*(node: JsonNode): JsonNodeEx =
  if node == nil:
    return nil
  case node.kind
  of JObject:
    result = newJexObject()
    for (key, value) in node.fields.pairs:
      result[key] = value.toJsonEx
  of JArray:
    result = newJexArray()
    for value in node.elems:
      result.elems.add value.toJsonEx
  of JString:
    result = newJexString(node.str)
  of JInt:
    result = newJexInt(node.num)
  of JFloat:
    result = newJexFloat(node.fnum)
  of JBool:
    result = newJexBool(node.bval)
  of JNull:
    result = newJexNull()
