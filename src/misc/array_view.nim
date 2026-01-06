
import std/[macros, options]

type
  ArrayView*[T] = object
    data: ptr UncheckedArray[T]
    capacity: int
    len: int

func initArrayView*[T](elems: ptr UncheckedArray[T], len: int): ArrayView[T] =
  return ArrayView[T](data: elems, len: len, capacity: len)

func initArrayView*[T](elems: ptr UncheckedArray[T], len: int, capacity: int): ArrayView[T] =
  assert len <= capacity
  return ArrayView[T](data: elems, len: len, capacity: capacity)

func initArrayView*[T](elems: openArray[T]): ArrayView[T] =
  return ArrayView[T](data: elems.data, len: elems.len, capacity: elems.len)

func initArrayView*[T](elems: openArray[T], len: int): ArrayView[T] =
  assert len <= elems.len
  return ArrayView[T](data: elems.data, len: len, capacity: elems.len)

func low*[T](arr: ArrayView[T]): int =
  0

func high*(arr: ArrayView): int =
  int(arr.len.int - 1)

func `[]`*[T](arr: var ArrayView[T], index: int): var T =
  assert index >= 0
  assert index < arr.len
  return arr.data[index]

func `[]`*[T](arr {.byref.}: ArrayView[T], index: int): lent T =
  assert index >= 0
  assert index < arr.len
  return arr.data[index]

func `[]`*[T](arr: var ArrayView[T], index: BackwardsIndex): var T =
  assert index.int >= 1
  assert index.int <= arr.len
  return arr.data[arr.len - index.int]

func `[]`*[T](arr {.byref.}: ArrayView[T], index: BackwardsIndex): lent T =
  assert index.int >= 1
  assert index.int <= arr.len
  return arr.data[arr.len - index.int]

func `[]=`*[T](arr: var ArrayView[T], index: int, value: sink T) =
  assert index >= 0
  assert index < arr.len
  arr.data[index] = value

func first*[T](arr {.byref.}: ArrayView[T]): Option[ptr T] =
  if arr.len > 0:
    result = arr.data[0].addr.some

func last*[T](arr {.byref.}: ArrayView[T]): Option[ptr T] =
  if arr.len > 0:
    result = arr.data[arr.high].addr.some

func add*[T](arr: var ArrayView[T], val: sink T) {.nodestroy.} =
  assert arr.len < arr.capacity
  arr.data[arr.len.int] = val.ensureMove
  inc arr.len

func add*[T](arr: var ArrayView[T], vals: sink ArrayView[T]) {.nodestroy.} =
  assert arr.len + vals.len <= arr.capacity
  for i in 0..vals.high:
    arr.data[arr.len.int + i] = vals.data[i].ensureMove
  arr.len += vals.len

func add*[T](arr: var ArrayView[T], vals: openArray[T]) {.nodestroy.} =
  assert arr.len.int + vals.len <= arr.capacity
  for i in 0..vals.high:
    arr.data[arr.len.int + i] = vals[i]
  arr.len += typeof(arr.len)(vals.len)

func shift*[T](arr: var ArrayView[T], start: int, offset: int) {.nodestroy.} =
  if offset > 0:
    arr.len = (arr.len.int + offset).uint16
    for i in countdown(arr.high, start):
      arr.data[i + offset] = arr.data[i]
  elif offset < 0:
    for i in start..arr.high:
      arr.data[i + offset] = arr.data[i]
    arr.len = (arr.len.int + offset).uint16

macro evalOnceAs(expAlias, exp: untyped,
                 letAssigneable: static[bool]): untyped =
  ## Injects `expAlias` in caller scope, to avoid bugs involving multiple
  ## substitution in macro arguments such as
  ## https://github.com/nim-lang/Nim/issues/7187.
  ## `evalOnceAs(myAlias, myExp)` will behave as `let myAlias = myExp`
  ## except when `letAssigneable` is false (e.g. to handle openArray) where
  ## it just forwards `exp` unchanged.
  expectKind(expAlias, nnkIdent)
  var val = exp

  result = newStmtList()
  # If `exp` is not a symbol we evaluate it once here and then use the temporary
  # symbol as alias
  if exp.kind != nnkSym and letAssigneable:
    val = genSym()
    result.add(newLetStmt(val, exp))

  result.add(
    newProc(name = genSym(nskTemplate, $expAlias), params = [getType(untyped)],
      body = val, procType = nnkTemplateDef))

template mapIt*[T](arr: ArrayView[T], op: untyped): untyped =
  block:
    type OutType = typeof((
      block:
        var it {.inject.}: typeof(arr.data[0], typeOfProc);
        op), typeOfProc)

    evalOnceAs(arr2, arr, compiles((let _ = s)))

    var res: Array[OutType, C]
    res.len = arr2.len

    for i in 0..<arr2.len.int:
      var it {.inject, cursor.} = arr2.data[i]
      res.data[i] = op

    res

proc `$`*[T](arr {.byref.}: ArrayView[T]): string =
  # result = "Array[" & $T & ", " & $C & "]("
  result = "("
  for i in 0..<arr.len.int:
    if i > 0:
      result.add ", "
    result.add $arr[i]
  result.add ")"

template toOpenArray*[T](arr: ArrayView[T]): openArray[T] =
  arr.data.toOpenArray(0, arr.high)

template toOpenArray*[T](arr: ArrayView[T], first, last: int): openArray[T] =
  arr.data.toOpenArray(first, last)

func len*[T](arr: ArrayView[T]): int =
  arr.len.int

func cap*[T](arr: ArrayView[T]): int =
  arr.capacity.int

func `len=`*[T](arr: var ArrayView[T], newLen: int) =
  assert newLen >= 0
  assert newLen <= arr.capacity
  arr.len = newLen

iterator items*[T](arr: ArrayView[T]): T =
  for i in 0..<arr.len:
    yield arr.data[i]

iterator mitems*[T](arr: var ArrayView[T]): var T =
  for i in 0..<arr.len:
    yield arr.data[i]
