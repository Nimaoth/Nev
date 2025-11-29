import std/[macros, options]

type
  Array*[T; C: static int] = object
    data: array[C, T]
    len: uint16

func initArray*(T: typedesc, capacity: static int): Array[T, capacity] =
  assert capacity <= typeof(Array[T, capacity].default.len).high
  result = Array[T, capacity].default

func low*[T; C: static int](arr: Array[T, C]): int =
  0

func high*(arr: Array): int =
  int(arr.len.int - 1)

func `[]`*[T; C: static int](arr: var Array[T, C], index: int): var T =
  assert index >= 0
  assert index < C
  return arr.data[index]

func `[]`*[T; C: static int](arr {.byref.}: Array[T, C], index: int): lent T =
  assert index >= 0
  assert index < C
  return arr.data[index]

func `[]=`*[T; C: static int](arr: var Array[T, C], index: int, value: sink T) =
  assert index >= 0
  assert index < C
  arr.data[index] = value

func first*[T; C: static int](arr {.byref.}: Array[T, C]): Option[ptr T] =
  if arr.len > 0:
    result = arr.data[0].addr.some

func last*[T; C: static int](arr {.byref.}: Array[T, C]): Option[ptr T] =
  if arr.len > 0:
    result = arr.data[arr.high].addr.some

func add*[T; C: static int](arr: var Array[T, C], val: sink T) {.nodestroy.} =
  assert C <= typeof(Array[T, C].default.len).high
  assert arr.len < C
  arr.data[arr.len.int] = val.ensureMove
  inc arr.len

func add*[T; C: static int](arr: var Array[T, C], vals: sink Array[T, C]) {.nodestroy.} =
  assert C <= typeof(Array[T, C].default.len).high
  assert arr.len + vals.len <= C
  for i in 0..vals.high:
    arr.data[arr.len.int + i] = vals.data[i].ensureMove
  arr.len += vals.len

func add*[T; C: static int](arr: var Array[T, C], vals: openArray[T]) {.nodestroy.} =
  assert C <= typeof(Array[T, C].default.len).high
  assert arr.len.int + vals.len <= C
  for i in 0..vals.high:
    arr.data[arr.len.int + i] = vals[i]
  arr.len += typeof(arr.len)(vals.len)

func shift*[T; C: static int](arr: var Array[T, C], start: int, offset: int) {.nodestroy.} =
  assert C <= typeof(Array[T, C].default.len).high
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

template mapIt*[T; C: static int](arr: Array[T, C], op: untyped): untyped =
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

proc `$`*[T; C: static int](arr {.byref.}: Array[T, C]): string =
  # result = "Array[" & $T & ", " & $C & "]("
  result = "("
  for i in 0..<arr.len.int:
    if i > 0:
      result.add ", "
    result.add $arr[i]
  result.add ")"

template toOpenArray*[T; C: static int](arr: Array[T, C]): openArray[T] =
  arr.data.toOpenArray(0, arr.high)

template toOpenArray*[T; C: static int](arr: Array[T, C], first, last: int): openArray[T] =
  arr.data.toOpenArray(first, last)

proc clone*[T; C: static int](arr: Array[T, C]): Array[T, C] {.noinit, nodestroy.} =
  result.len = arr.len
  for i in 0..<arr.len.int:
    result.data[i] = arr.data[i].clone()

func len*[T; C: static int](arr: Array[T, C]): int =
  assert C <= typeof(Array[T, C].default.len).high
  arr.len.int

func `len=`*[T; C: static int](arr: var Array[T, C], newLen: int) =
  assert C <= typeof(Array[T, C].default.len).high
  assert newLen <= C
  arr.len = typeof(arr.len)(newLen)

func toArray*[T](arr: openArray[T], C: static int): Array[T, C] =
  assert arr.len <= C
  result.len = typeof(result.len)(arr.len)
  for i in 0..<arr.len:
    when compiles(arr[i].clone()):
      result[i] = arr[i].clone()
    else:
      result[i] = arr[i]
