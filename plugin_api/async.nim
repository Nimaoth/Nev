import std/[macros, sequtils]

type
  CancelledError* = object of CatchableError

  # CallbackFunc = proc () {.closure, gcsafe.}

  CallbackFunc* = proc (arg: pointer) {.gcsafe, raises: [].}

  # Internal type, not part of API
  InternalAsyncCallback* = object
    function*: CallbackFunc
    udata*: pointer

  AsyncCallback* = InternalAsyncCallback

  FutureBase* = ref object of RootObj
    name*: string
    internalCancelcb*: CallbackFunc
    internalChild*: FutureBase
    internalState*: FutureState
    internalFlags*: FutureFlags
    internalError*: ref CatchableError ## Stored exception
    internalClosure*: iterator(f: FutureBase): FutureBase {.raises: [], gcsafe.}
    internalCallbacks*: seq[InternalAsyncCallback]

  Future*[T] = ref object of FutureBase
    onCompleted*: seq[proc(fut: Future[T]) {.closure, raises: [].}]
    when T isnot void:
      internalValue*: T ## Stored value

  FutureState* {.pure.} = enum
    Pending, Completed, Cancelled, Failed

  FutureFlag* {.pure.} = enum
    OwnCancelSchedule
      ## When OwnCancelSchedule is set, the owner of the future is responsible
      ## for implementing cancellation in one of 3 ways:
      ##
      ## * ensure that cancellation requests never reach the future by means of
      ##   not exposing it to user code, `await` and `tryCancel`
      ## * set `cancelCallback` to `nil` to stop cancellation propagation - this
      ##   is appropriate when it is expected that the future will be completed
      ##   in a regular way "soon"
      ## * set `cancelCallback` to a handler that implements cancellation in an
      ##   operation-specific way
      ##
      ## If `cancelCallback` is not set and the future gets cancelled, a
      ## `Defect` will be raised.

  FutureFlags* = set[FutureFlag]

{.push raises: [].}

proc callSoon*(cbproc: CallbackFunc, data: pointer) {.gcsafe, raises: [].}

# proc newFuture*[T](): Future[T] =
#   let fut = Future[T]()
#   # internalInitFutureBase(fut, loc, FutureState.Pending, {})
#   fut

proc newFuture*[T](name: string): Future[T] =
  let fut = Future[T]()
  fut.name = name
  # internalInitFutureBase(fut, loc, FutureState.Pending, {})
  fut

# proc complete*[T](future: Future[T], val: sink T) =
#   future.internalValue = val.ensureMove
#   for cb in future.onCompleted:
#     cb(future)

# proc complete*(future: Future[void]) =
#   for cb in future.onCompleted:
#     cb(future)
#   # if not(future.cancelled()):
#   #   checkFinished(future, loc)
#   #   doAssert(isNil(future.internalError))
#   #   future.finish(FutureState.Completed)

func state*(future: FutureBase): FutureState =
  future.internalState

func flags*(future: FutureBase): FutureFlags =
  future.internalFlags

func finished*(future: FutureBase): bool {.inline.} =
  ## Determines whether ``future`` has finished, i.e. ``future`` state changed
  ## from state ``Pending`` to one of the states (``Finished``, ``Cancelled``,
  ## ``Failed``).
  future.state != FutureState.Pending

func cancelled*(future: FutureBase): bool {.inline.} =
  ## Determines whether ``future`` has cancelled.
  future.state == FutureState.Cancelled

func failed*(future: FutureBase): bool {.inline.} =
  ## Determines whether ``future`` finished with an error.
  future.state == FutureState.Failed

func completed*(future: FutureBase): bool {.inline.} =
  ## Determines whether ``future`` finished with a value.
  future.state == FutureState.Completed

func value*[T: not void](future: Future[T]): lent T =
  ## Return the value in a completed future - raises Defect when
  ## `fut.completed()` is `false`.
  ##
  ## See `read` for a version that raises a catchable error when future
  ## has not completed.
  # when chronosStrictFutureAccess:
  #   if not future.completed():
  #     raiseFutureDefect("Future not completed while accessing value", future)

  future.internalValue

proc clearCallbacks(future: FutureBase) =
  future.internalCallbacks = default(seq[AsyncCallback])

proc addCallback*(future: FutureBase, cb: CallbackFunc, udata: pointer) {.raises: [].} =
  ## Adds the callbacks proc to be called when the future completes.
  ##
  ## If future has already completed then ``cb`` will be called immediately.
  doAssert(not isNil(cb))
  if future.finished():
    callSoon(cb, udata)
  else:
    future.internalCallbacks.add AsyncCallback(function: cb, udata: udata)

proc addCallback*(future: FutureBase, cb: CallbackFunc) {.raises: [].} =
  ## Adds the callbacks proc to be called when the future completes.
  ##
  ## If future has already completed then ``cb`` will be called immediately.
  future.addCallback(cb, cast[pointer](future))

proc removeCallback*(future: FutureBase, cb: CallbackFunc,
                     udata: pointer) =
  ## Remove future from list of callbacks - this operation may be slow if there
  ## are many registered callbacks!
  doAssert(not isNil(cb))
  # Make sure to release memory associated with callback, or reference chains
  # may be created!
  future.internalCallbacks.keepItIf:
    it.function != cb or it.udata != udata

proc removeCallback*(future: FutureBase, cb: CallbackFunc) =
  future.removeCallback(cb, cast[pointer](future))

proc `callback=`*(future: FutureBase, cb: CallbackFunc, udata: pointer) {.
    deprecated: "use addCallback/removeCallback/clearCallbacks to manage the callback list".} =
  ## Clears the list of callbacks and sets the callback proc to be called when
  ## the future completes.
  ##
  ## If future has already completed then ``cb`` will be called immediately.
  ##
  ## It's recommended to use ``addCallback`` or ``then`` instead.
  # ZAH: how about `setLen(1); callbacks[0] = cb`
  future.clearCallbacks
  future.addCallback(cb, udata)

proc `callback=`*(future: FutureBase, cb: CallbackFunc) {.
    deprecated: "use addCallback/removeCallback/clearCallbacks instead to manage the callback list".} =
  ## Sets the callback proc to be called when the future completes.
  ##
  ## If future has already completed then ``cb`` will be called immediately.
  {.push warning[Deprecated]: off.}
  `callback=`(future, cb, cast[pointer](future))
  {.pop.}

proc `cancelCallback=`*(future: FutureBase, cb: CallbackFunc) =
  ## Sets the callback procedure to be called when the future is cancelled.
  ##
  ## This callback will be called immediately as ``future.cancel()`` invoked and
  ## must be set before future is finished.

  # when chronosStrictFutureAccess:
  #   doAssert not future.finished(),
  #     "cancellation callback must be set before finishing the future"
  future.internalCancelcb = cb

proc callSoon*(acb: AsyncCallback) =
  ## Schedule `cbproc` to be called as soon as possible.
  ## The callback is called when control returns to the event loop.
  # getThreadDispatcher().callbacks.addLast(acb)
  discard
  # echo "todo: callSoon"
  acb.function(acb.udata)

proc callSoon*(cbproc: CallbackFunc, data: pointer) {.gcsafe.} =
  ## Schedule `cbproc` to be called as soon as possible.
  ## The callback is called when control returns to the event loop.
  # doAssert(not isNil(cbproc))
  callSoon(AsyncCallback(function: cbproc, udata: data))

proc callSoon*(cbproc: CallbackFunc) =
  callSoon(cbproc, nil)

proc finish(fut: FutureBase, state: FutureState) =
  # We do not perform any checks here, because:
  # 1. `finish()` is a private procedure and `state` is under our control.
  # 2. `fut.state` is checked by `checkFinished()`.
  # echo "finish ", fut.name
  fut.internalState = state
  fut.internalCancelcb = nil # release cancellation callback memory
  for item in fut.internalCallbacks.mitems():
    if not(isNil(item.function)):
      callSoon(item)
    item = default(AsyncCallback) # release memory as early as possible
  fut.internalCallbacks = default(seq[AsyncCallback]) # release seq as well

  # when chronosFutureTracking:
  #   scheduleDestructor(fut)

proc complete*[T](future: Future[T], val: T) =
  # echo "complete ", future.name
  if not(future.cancelled()):
    # checkFinished(future, loc)
    doAssert(isNil(future.internalError))
    future.internalValue = val
    future.finish(FutureState.Completed)

proc complete*(future: Future[void]) =
  # echo "complete ", future.name
  if not(future.cancelled()):
    # checkFinished(future, loc)
    doAssert(isNil(future.internalError))
    future.finish(FutureState.Completed)

template newCancelledError(): ref CancelledError =
  (ref CancelledError)(msg: "Future operation cancelled!")

proc cancelAndSchedule*(future: FutureBase) =
  if not(future.finished()):
    future.internalError = newCancelledError()
    # when chronosStackTrace:
    #   future.internalErrorStackTrace = getStackTrace()
    future.finish(FutureState.Cancelled)


{.push stackTrace: off.}
proc futureContinue*(fut: FutureBase) {.raises: [], gcsafe.}

proc internalContinue(fut: pointer) {.raises: [], gcsafe.} =
  let asFut = cast[FutureBase](fut)
  GC_unref(asFut)
  futureContinue(asFut)

proc futureContinue*(fut: FutureBase) {.raises: [], gcsafe.} =
  # This function is responsible for calling the closure iterator generated by
  # the `{.async.}` transformation either until it has completed its iteration
  #
  # Every call to an `{.async.}` proc is redirected to call this function
  # instead with its original body captured in `fut.closure`.
  while true:
    # Call closure to make progress on `fut` until it reaches `yield` (inside
    # `await` typically) or completes / fails / is cancelled
    # echo "futureContinue ", fut.name
    let next: FutureBase = fut.internalClosure(fut)
    if fut.internalClosure.finished(): # Reached the end of the transformed proc
      break

    if next == nil:
      raiseAssert "Async procedure yielded `nil`, are you await'ing a `nil` Future?"

    if not next.finished():
      # We cannot make progress on `fut` until `next` has finished - schedule
      # `fut` to continue running when that happens
      GC_ref(fut)
      # echo "futureContinue ", fut.name, ", child not finished, add callback and return"
      next.addCallback(CallbackFunc(internalContinue), cast[pointer](fut))

      # return here so that we don't remove the closure below
      return

    # Continue while the yielded future is already finished.

  # echo "futureContinue ", fut.name, ", finished"
  # `futureContinue` will not be called any more for this future so we can
  # clean it up
  fut.internalClosure = nil
  fut.internalChild = nil

{.pop.}

type
  InternalRaisesFuture*[T, E] = ref object of Future[T]
    ## Future with a tuple of possible exception types
    ## eg InternalRaisesFuture[void, (ValueError, OSError)]
    ##
    ## This type gets injected by `async: (raises: ...)` and similar utilities
    ## and should not be used manually as the internal exception representation
    ## is subject to change in future chronos versions.
    # TODO https://github.com/nim-lang/Nim/issues/23418
    # TODO https://github.com/nim-lang/Nim/issues/23419
    when E is void:
      dummy: E
    else:
      dummy: array[0, E]

proc makeNoRaises*(): NimNode {.compileTime.} =
  # An empty tuple would have been easier but...
  # https://github.com/nim-lang/Nim/issues/22863
  # https://github.com/nim-lang/Nim/issues/22865

  ident"void"

proc dig(n: NimNode): NimNode {.compileTime.} =
  # Dig through the layers of type to find the raises list
  if n.eqIdent("void"):
    n
  elif n.kind == nnkBracketExpr:
    if n[0].eqIdent("tuple"):
      n
    elif n[0].eqIdent("typeDesc"):
      dig(getType(n[1]))
    else:
      echo astGenRepr(n)
      raiseAssert "Unkown bracket"
  elif n.kind == nnkTupleConstr:
    n
  else:
    dig(getType(getTypeInst(n)))

proc isNoRaises*(n: NimNode): bool {.compileTime.} =
  dig(n).eqIdent("void")

iterator members(tup: NimNode): NimNode =
  # Given a typedesc[tuple] = (A, B, C), yields the tuple members (A, B C)
  if not isNoRaises(tup):
    for n in getType(getTypeInst(tup)[1])[1..^1]:
      yield n

proc members(tup: NimNode): seq[NimNode] {.compileTime.} =
  for t in tup.members():
    result.add(t)

macro hasException(raises: typedesc, ident: static string): bool =
  newLit(raises.members.anyIt(it.eqIdent(ident)))

macro Raising*[T](F: typedesc[Future[T]], E: typed): untyped =
  ## Given a Future type instance, return a type storing `{.raises.}`
  ## information
  ##
  ## Note; this type may change in the future

  # An earlier version used `E: varargs[typedesc]` here but this is buggyt/no
  # longer supported in 2.0 in certain cases:
  # https://github.com/nim-lang/Nim/issues/23432
  let
    e =
      case E.getTypeInst().typeKind()
      of ntyTypeDesc: @[E]
      of ntyArray:
        for x in E:
          if x.getTypeInst().typeKind != ntyTypeDesc:
            error("Expected typedesc, got " & repr(x), x)
        E.mapIt(it)
      else:
        error("Expected typedesc, got " & repr(E), E)
        @[]

  let raises = if e.len == 0:
    makeNoRaises()
  else:
    nnkTupleConstr.newTree(e)
  nnkBracketExpr.newTree(
    ident "InternalRaisesFuture",
    nnkDotExpr.newTree(F, ident"T"),
    raises
  )

template init*[T, E](
    F: type InternalRaisesFuture[T, E], fromProc: static[string] = ""): F =
  ## Creates a new pending future.
  ##
  ## Specifying ``fromProc``, which is a string specifying the name of the proc
  ## that this future belongs to, is a good habit as it helps with debugging.
  when not hasException(type(E), "CancelledError"):
    static:
      raiseAssert "Manually created futures must either own cancellation schedule or raise CancelledError"


  let res = F()
  internalInitFutureBase(res, getSrcLocation(fromProc), FutureState.Pending, {})
  res

template init*[T, E](
    F: type InternalRaisesFuture[T, E], fromProc: static[string] = "",
    flags: static[FutureFlags]): F =
  ## Creates a new pending future.
  ##
  ## Specifying ``fromProc``, which is a string specifying the name of the proc
  ## that this future belongs to, is a good habit as it helps with debugging.
  let res = F()
  when not hasException(type(E), "CancelledError"):
    static:
      doAssert FutureFlag.OwnCancelSchedule in flags,
        "Manually created futures must either own cancellation schedule or raise CancelledError"

  internalInitFutureBase(
    res, getSrcLocation(fromProc), FutureState.Pending, flags)
  res

proc containsSignature(members: openArray[NimNode], typ: NimNode): bool {.compileTime.} =
  let typHash = signatureHash(typ)

  for err in members:
    if signatureHash(err) == typHash:
      return true
  false

# Utilities for working with the E part of InternalRaisesFuture - unstable
macro prepend*(tup: typedesc, typs: varargs[typed]): typedesc =
  result = nnkTupleConstr.newTree()
  for err in typs:
    if not tup.members().containsSignature(err):
      result.add err

  for err in tup.members():
    result.add err

  if result.len == 0:
    result = makeNoRaises()

macro remove*(tup: typedesc, typs: varargs[typed]): typedesc =
  result = nnkTupleConstr.newTree()
  for err in tup.members():
    if not typs[0..^1].containsSignature(err):
      result.add err

  if result.len == 0:
    result = makeNoRaises()

macro union*(tup0: typedesc, tup1: typedesc): typedesc =
  ## Join the types of the two tuples deduplicating the entries
  result = nnkTupleConstr.newTree()

  for err in tup0.members():
    var found = false
    for err2 in tup1.members():
      if signatureHash(err) == signatureHash(err2):
        found = true
    if not found:
      result.add err

  for err2 in tup1.members():
    result.add err2
  if result.len == 0:
    result = makeNoRaises()

proc getRaisesTypes*(raises: NimNode): NimNode =
  let typ = getType(raises)
  case typ.typeKind
  of ntyTypeDesc: typ[1]
  else: typ

macro checkRaises*[T: CatchableError](
    future: InternalRaisesFuture, raises: typed, error: ref T,
    warn: static bool = true): untyped =
  ## Generate code that checks that the given error is compatible with the
  ## raises restrictions of `future`.
  ##
  ## This check is done either at compile time or runtime depending on the
  ## information available at compile time - in particular, if the raises
  ## inherit from `error`, we end up with the equivalent of a downcast which
  ## raises a Defect if it fails.
  let
    raises = getRaisesTypes(raises)

  expectKind(getTypeInst(error), nnkRefTy)
  let toMatch = getTypeInst(error)[0]


  if isNoRaises(raises):
    error(
      "`fail`: `" & repr(toMatch) & "` incompatible with `raises: []`", future)
    return

  var
    typeChecker = ident"false"
    maybeChecker = ident"false"
    runtimeChecker = ident"false"

  for errorType in raises[1..^1]:
    typeChecker = infix(typeChecker, "or", infix(toMatch, "is", errorType))
    maybeChecker = infix(maybeChecker, "or", infix(errorType, "is", toMatch))
    runtimeChecker = infix(
      runtimeChecker, "or",
      infix(error, "of", nnkBracketExpr.newTree(ident"typedesc", errorType)))

  let
    errorMsg = "`fail`: `" & repr(toMatch) & "` incompatible with `raises: " & repr(raises[1..^1]) & "`"
    warningMsg = "Can't verify `fail` exception type at compile time - expected one of " & repr(raises[1..^1]) & ", got `" & repr(toMatch) & "`"
    # A warning from this line means exception type will be verified at runtime
    warning = if warn:
      quote do: {.warning: `warningMsg`.}
    else: newEmptyNode()

  # Cannot check inhertance in macro so we let `static` do the heavy lifting
  quote do:
    when not(`typeChecker`):
      when not(`maybeChecker`):
        static:
          {.error: `errorMsg`.}
      else:
        `warning`
        assert(`runtimeChecker`, `errorMsg`)

func failed*[T](future: InternalRaisesFuture[T, void]): bool {.inline.} =
  ## Determines whether ``future`` finished with an error.
  static:
    warning("No exceptions possible with this operation, `failed` always returns false")

  false

func error*[T](future: InternalRaisesFuture[T, void]): ref CatchableError {.
    raises: [].} =
  static:
    warning("No exceptions possible with this operation, `error` always returns nil")
  nil

func readError*[T](future: InternalRaisesFuture[T, void]): ref CatchableError {.
    raises: [ValueError].} =
  static:
    warning("No exceptions possible with this operation, `readError` always raises")
  raise newException(ValueError, "No error in future.")




proc deepLineInfo(n: NimNode, p: LineInfo) =
  n.setLineInfo(p)
  for i in 0..<n.len:
    deepLineInfo(n[i], p)

proc failImpl(
    future: FutureBase, error: ref CatchableError) =
  if not(future.cancelled()):
    # checkFinished(future, loc)
    future.internalError = error
    # when chronosStackTrace:
    #   future.internalErrorStackTrace = if getStackTrace(error) == "":
    #                              getStackTrace()
    #                            else:
    #                              getStackTrace(error)
    future.finish(FutureState.Failed)

template fail*[T](
    future: Future[T], error: ref CatchableError, warn: static bool = false) =
  ## Completes ``future`` with ``error``.
  failImpl(future, error)

template fail*[T, E](
    future: InternalRaisesFuture[T, E], error: ref CatchableError,
    warn: static bool = true) =
  checkRaises(future, E, error, warn)
  failImpl(future, error)

macro internalRaiseIfError*(fut: FutureBase, info: typed) =
  # Check the error field of the given future and raise if it's set to non-nil.
  # This is a macro so we can capture the line info from the original call and
  # report the correct line number on exception effect violation
  let
    info = info.lineInfoObj()
    res = quote do:
      if not(isNil(`fut`.internalError)):
        # when chronosStackTrace:
        #   injectStacktrace(`fut`.internalError)
        raise `fut`.internalError
  res.deepLineInfo(info)
  res

macro internalRaiseIfError*(fut: InternalRaisesFuture, raises, info: typed) =
  # For InternalRaisesFuture[void, (ValueError, OSError), will do:
  # {.cast(raises: [ValueError, OSError]).}:
  #   if isNil(f.error): discard
  #   else: raise f.error
  # TODO https://github.com/nim-lang/Nim/issues/22937
  #      we cannot `getTypeInst` on the `fut` - when aliases are involved, the
  #      generics are lost - so instead, we pass the raises list explicitly

  let
    info = info.lineInfoObj()
    types = getRaisesTypes(raises)

  if isNoRaises(types):
    return quote do:
      if not(isNil(`fut`.internalError)):
        # This would indicate a bug in which `error` was set via the non-raising
        # base type
        raiseAssert("Error set on a non-raising future: " & `fut`.internalError.msg)

  expectKind(types, nnkBracketExpr)
  expectKind(types[0], nnkSym)

  assert types[0].strVal == "tuple"

  let
    internalError = nnkDotExpr.newTree(fut, ident "internalError")

    ifRaise = nnkIfExpr.newTree(
      nnkElifExpr.newTree(
        nnkCall.newTree(ident"isNil", internalError),
        nnkDiscardStmt.newTree(newEmptyNode())
      ),
      nnkElseExpr.newTree(
        nnkRaiseStmt.newTree(internalError)
      )
    )

    res = nnkPragmaBlock.newTree(
      nnkPragma.newTree(
        nnkCast.newTree(
          newEmptyNode(),
          nnkExprColonExpr.newTree(
            ident"raises",
            block:
              var res = nnkBracket.newTree()
              for r in types[1..^1]:
                res.add(r)
              res
          )
        ),
      ),
      ifRaise
    )
  res.deepLineInfo(info)
  res


proc processBody(node, setResultSym: NimNode): NimNode {.compileTime.} =
  case node.kind
  of nnkReturnStmt:
    # `return ...` -> `setResult(...); return`
    let
      res = newNimNode(nnkStmtList, node)
    if node[0].kind != nnkEmpty:
      res.add newCall(setResultSym, processBody(node[0], setResultSym))
    res.add newNimNode(nnkReturnStmt, node).add(newEmptyNode())

    res
  of RoutineNodes-{nnkTemplateDef}:
    # Skip nested routines since they have their own return value distinct from
    # the Future we inject
    node
  else:
    if node.kind == nnkYieldStmt:
      # asyncdispatch allows `yield` but this breaks cancellation
      warning(
        "`yield` in async procedures not supported - use `awaitne` instead",
        node)

    for i in 0 ..< node.len:
      node[i] = processBody(node[i], setResultSym)
    node

proc wrapInTryFinally(
  fut, baseType, body, raises: NimNode,
  handleException: bool): NimNode {.compileTime.} =
  # creates:
  # try: `body`
  # [for raise in raises]:
  #   except `raise`: closureSucceeded = false; `castFutureSym`.fail(exc)
  # finally:
  #   if closureSucceeded:
  #     `castFutureSym`.complete(result)
  #
  # Calling `complete` inside `finally` ensures that all success paths
  # (including early returns and code inside nested finally statements and
  # defer) are completed with the final contents of `result`
  let
    closureSucceeded = genSym(nskVar, "closureSucceeded")
    nTry = nnkTryStmt.newTree(body)
    excName = ident"exc"

  # Depending on the exception type, we must have at most one of each of these
  # "special" exception handlers that are needed to implement cancellation and
  # Defect propagation
  var
    hasDefect = false
    hasCancelledError = false
    hasCatchableError = false

  template addDefect =
    if not hasDefect:
      hasDefect = true
      # When a Defect is raised, the program is in an undefined state and
      # continuing running other tasks while the Future completion sits on the
      # callback queue may lead to further damage so we re-raise them eagerly.
      nTry.add nnkExceptBranch.newTree(
            nnkInfix.newTree(ident"as", ident"Defect", excName),
            nnkStmtList.newTree(
              nnkAsgn.newTree(closureSucceeded, ident"false"),
              nnkRaiseStmt.newTree(excName)
            )
          )
  template addCancelledError =
    if not hasCancelledError:
      hasCancelledError = true
      nTry.add nnkExceptBranch.newTree(
                ident"CancelledError",
                nnkStmtList.newTree(
                  nnkAsgn.newTree(closureSucceeded, ident"false"),
                  newCall(ident "cancelAndSchedule", fut)
                )
              )

  template addCatchableError =
    if not hasCatchableError:
      hasCatchableError = true
      nTry.add nnkExceptBranch.newTree(
                nnkInfix.newTree(ident"as", ident"CatchableError", excName),
                nnkStmtList.newTree(
                  nnkAsgn.newTree(closureSucceeded, ident"false"),
                  newCall(ident "fail", fut, excName)
                ))

  var raises = if raises == nil:
    nnkTupleConstr.newTree(ident"CatchableError")
  # elif isNoRaises(raises):
  #   nnkTupleConstr.newTree()
  else:
    raises.copyNimTree()

  if handleException:
    raises.add(ident"Exception")

  for exc in raises:
    if exc.eqIdent("Exception"):
      addCancelledError
      addCatchableError
      addDefect

      # Because we store `CatchableError` in the Future, we cannot re-raise the
      # original exception
      nTry.add nnkExceptBranch.newTree(
                nnkInfix.newTree(ident"as", ident"Exception", excName),
                newCall(ident "fail", fut,
                  nnkStmtList.newTree(
                    nnkAsgn.newTree(closureSucceeded, ident"false"),
                  quote do:
                    (ref AsyncExceptionError)(
                      msg: `excName`.msg, parent: `excName`)))
              )
    elif exc.eqIdent("CancelledError"):
      addCancelledError
    elif exc.eqIdent("CatchableError"):
      # Ensure cancellations are re-routed to the cancellation handler even if
      # not explicitly specified in the raises list
      addCancelledError
      addCatchableError
    else:
      nTry.add nnkExceptBranch.newTree(
                nnkInfix.newTree(ident"as", exc, excName),
                nnkStmtList.newTree(
                  nnkAsgn.newTree(closureSucceeded, ident"false"),
                  newCall(ident "fail", fut, excName)
                ))

  addDefect # Must not complete future on defect

  nTry.add nnkFinally.newTree(
    nnkIfStmt.newTree(
      nnkElifBranch.newTree(
        closureSucceeded,
        if baseType.eqIdent("void"): # shortcut for non-generic void
          newCall(ident "complete", fut)
        else:
          nnkWhenStmt.newTree(
            nnkElifExpr.newTree(
              nnkInfix.newTree(ident "is", baseType, ident "void"),
              newCall(ident "complete", fut)
            ),
            nnkElseExpr.newTree(
              newCall(ident "complete", fut, newCall(ident "move", ident "result"))
            )
          )
        )
      )
    )

  nnkStmtList.newTree(
      newVarStmt(closureSucceeded, ident"true"),
      nTry
  )

proc getName(node: NimNode): string {.compileTime.} =
  case node.kind
  of nnkSym:
    return node.strVal
  of nnkPostfix:
    return node[1].strVal
  of nnkIdent:
    return node.strVal
  of nnkEmpty:
    return "anonymous"
  else:
    error("Unknown name.")

macro unsupported(s: static[string]): untyped =
  error s

proc params2(someProc: NimNode): NimNode {.compileTime.} =
  # until https://github.com/nim-lang/Nim/pull/19563 is available
  if someProc.kind == nnkProcTy:
    someProc[0]
  else:
    params(someProc)

proc cleanupOpenSymChoice(node: NimNode): NimNode {.compileTime.} =
  # Replace every Call -> OpenSymChoice by a Bracket expr
  # ref https://github.com/nim-lang/Nim/issues/11091
  if node.kind in nnkCallKinds and
    node[0].kind == nnkOpenSymChoice and node[0].eqIdent("[]"):
    result = newNimNode(nnkBracketExpr)
    for child in node[1..^1]:
      result.add(cleanupOpenSymChoice(child))
  else:
    result = node.copyNimNode()
    for child in node:
      result.add(cleanupOpenSymChoice(child))

type
  AsyncParams = tuple
    raw: bool
    raises: NimNode
    handleException: bool

proc decodeParams(params: NimNode): AsyncParams =
  # decodes the parameter tuple given in `async: (name: value, ...)` to its
  # recognised parts
  params.expectKind(nnkTupleConstr)

  var
    raw = false
    raises: NimNode = nil
    handleException = false
    hasLocalAnnotations = false

  for param in params:
    param.expectKind(nnkExprColonExpr)

    if param[0].eqIdent("raises"):
      hasLocalAnnotations = true
      param[1].expectKind(nnkBracket)
      if param[1].len == 0:
        raises = makeNoRaises()
      else:
        raises = nnkTupleConstr.newTree()
        for possibleRaise in param[1]:
          raises.add(possibleRaise)
    elif param[0].eqIdent("raw"):
      # boolVal doesn't work in untyped macros it seems..
      raw = param[1].eqIdent("true")
    elif param[0].eqIdent("handleException"):
      hasLocalAnnotations = true
      handleException = param[1].eqIdent("true")
    else:
      warning("Unrecognised async parameter: " & repr(param[0]), param)

  # if not hasLocalAnnotations:
  #   handleException = chronosHandleException

  (raw, raises, handleException)

proc isEmpty(n: NimNode): bool {.compileTime.} =
  # true iff node recursively contains only comments or empties
  case n.kind
  of nnkEmpty, nnkCommentStmt: true
  of nnkStmtList:
    for child in n:
      if not isEmpty(child): return false
    true
  else:
    false

proc asyncSingleProc(prc, params: NimNode): NimNode {.compileTime.} =
  ## This macro transforms a single procedure into a closure iterator.
  ## The ``async`` macro supports a stmtList holding multiple async procedures.
  if prc.kind notin {nnkProcTy, nnkProcDef, nnkLambda, nnkMethodDef, nnkDo}:
      error("Cannot transform " & $prc.kind & " into an async proc." &
            " proc/method definition or lambda node expected.", prc)

  for pragma in prc.pragma():
    if pragma.kind == nnkExprColonExpr and pragma[0].eqIdent("raises"):
      warning("The raises pragma doesn't work on async procedures - use " &
      "`async: (raises: [...]) instead.", prc)

  let returnType = cleanupOpenSymChoice(prc.params2[0])

  # Verify that the return type is a Future[T]
  let baseType =
    if returnType.kind == nnkEmpty:
      ident "void"
    elif not (
        returnType.kind == nnkBracketExpr and
        (eqIdent(returnType[0], "Future") or eqIdent(returnType[0], "InternalRaisesFuture"))):
      error(
        "Expected return type of 'Future' got '" & repr(returnType) & "'", prc)
      return
    else:
      returnType[1]

  let
    # When the base type is known to be void (and not generic), we can simplify
    # code generation - however, in the case of generic async procedures it
    # could still end up being void, meaning void detection needs to happen
    # post-macro-expansion.
    baseTypeIsVoid = baseType.eqIdent("void")
    (raw, raises, handleException) = decodeParams(params)
    internalFutureType =
      if baseTypeIsVoid:
        newNimNode(nnkBracketExpr, prc).
          add(newIdentNode("Future")).
          add(baseType)
      else:
        returnType
    internalReturnType = if raises == nil:
      internalFutureType
    else:
      nnkBracketExpr.newTree(
        newIdentNode("InternalRaisesFuture"),
        baseType,
        raises
      )

  prc.params2[0] = internalReturnType

  if prc.kind notin {nnkProcTy, nnkLambda}:
    prc.addPragma(newColonExpr(ident "stackTrace", ident "off"))

  # The proc itself doesn't raise
  prc.addPragma(
    nnkExprColonExpr.newTree(newIdentNode("raises"), nnkBracket.newTree()))

  # `gcsafe` isn't deduced even though we require async code to be gcsafe
  # https://github.com/nim-lang/RFCs/issues/435
  prc.addPragma(newIdentNode("gcsafe"))

  if raw: # raw async = body is left as-is
    if raises != nil and prc.kind notin {nnkProcTy, nnkLambda} and not isEmpty(prc.body):
      # Inject `raises` type marker that causes `newFuture` to return a raise-
      # tracking future instead of an ordinary future:
      #
      # type InternalRaisesFutureRaises = `raisesTuple`
      # `body`
      prc.body = nnkStmtList.newTree(
        nnkTypeSection.newTree(
          nnkTypeDef.newTree(
            nnkPragmaExpr.newTree(
              ident"InternalRaisesFutureRaises",
              nnkPragma.newTree(ident "used")),
            newEmptyNode(),
            raises,
          )
        ),
        prc.body
      )

  elif prc.kind in {nnkProcDef, nnkLambda, nnkMethodDef, nnkDo} and
      not isEmpty(prc.body):
    let
      setResultSym = ident "setResult"
      procBody = prc.body.processBody(setResultSym)
      resultIdent = ident "result"
      fakeResult = quote do:
        template result: auto {.used.} =
          {.fatal: "You should not reference the `result` variable inside" &
                  " a void async proc".}
      resultDecl =
        if baseTypeIsVoid: fakeResult
        else: nnkWhenStmt.newTree(
          # when `baseType` is void:
          nnkElifExpr.newTree(
            nnkInfix.newTree(ident "is", baseType, ident "void"),
            fakeResult
          ),
          # else:
          nnkElseExpr.newTree(
            newStmtList(
              quote do: {.push warning[resultshadowed]: off.},
              # var result {.used.}: `baseType`
              # In the proc body, result may or may not end up being used
              # depending on how the body is written - with implicit returns /
              # expressions in particular, it is likely but not guaranteed that
              # it is not used. Ideally, we would avoid emitting it in this
              # case to avoid the default initializaiton. {.used.} typically
              # works better than {.push.} which has a tendency to leak out of
              # scope.
              # TODO figure out if there's a way to detect `result` usage in
              #      the proc body _after_ template exapnsion, and therefore
              #      avoid creating this variable - one option is to create an
              #      addtional when branch witha fake `result` and check
              #      `compiles(procBody)` - this is not without cost though
              nnkVarSection.newTree(nnkIdentDefs.newTree(
                nnkPragmaExpr.newTree(
                  resultIdent,
                  nnkPragma.newTree(ident "used")),
                baseType, newEmptyNode())
                ),
              quote do: {.pop.},
            )
          )
        )

      # ```nim
      # template `setResultSym`(code: untyped) {.used.} =
      #   when typeof(code) is void: code
      #   else: `resultIdent` = code.ensureMove
      # ```
      #
      # this is useful to handle implicit returns, but also
      # to bind the `result` to the one we declare here
      setResultDecl =
        if baseTypeIsVoid: # shortcut for non-generic void
          newEmptyNode()
        else:
          nnkTemplateDef.newTree(
            setResultSym,
            newEmptyNode(), newEmptyNode(),
            nnkFormalParams.newTree(
              newEmptyNode(),
              nnkIdentDefs.newTree(
                ident"code",
                ident"untyped",
                newEmptyNode(),
              )
            ),
            nnkPragma.newTree(ident"used"),
            newEmptyNode(),
            nnkWhenStmt.newTree(
              nnkElifBranch.newTree(
                nnkInfix.newTree(
                  ident"is", nnkTypeOfExpr.newTree(ident"code"), ident"void"),
                ident"code"
              ),
              nnkElse.newTree(
                newAssignment(resultIdent, ident"code")
              )
            )
          )

      internalFutureSym = ident "chronosInternalRetFuture"
      castFutureSym = nnkCast.newTree(internalFutureType, internalFutureSym)
      # Wrapping in try/finally ensures that early returns are handled properly
      # and that `defer` is processed in the right scope
      completeDecl = wrapInTryFinally(
        castFutureSym, baseType,
        if baseTypeIsVoid: procBody # shortcut for non-generic `void`
        else: newCall(setResultSym, procBody),
        raises,
        handleException
      )

      closureBody = newStmtList(resultDecl, setResultDecl, completeDecl)

      internalFutureParameter = nnkIdentDefs.newTree(
        internalFutureSym, newIdentNode("FutureBase"), newEmptyNode())
      prcName = prc.name.getName
      iteratorNameSym = genSym(nskIterator, $prcName)
      closureIterator = newProc(
        iteratorNameSym,
        [newIdentNode("FutureBase"), internalFutureParameter],
        closureBody, nnkIteratorDef)

    iteratorNameSym.copyLineInfo(prc)

    closureIterator.pragma = newNimNode(nnkPragma, lineInfoFrom=prc.body)
    closureIterator.addPragma(newIdentNode("closure"))

    # `async` code must be gcsafe
    closureIterator.addPragma(newIdentNode("gcsafe"))

    # Exceptions are caught inside the iterator and stored in the future
    closureIterator.addPragma(nnkExprColonExpr.newTree(
      newIdentNode("raises"),
      nnkBracket.newTree()
    ))

    # The body of the original procedure (now moved to the iterator) is replaced
    # with:
    #
    # ```nim
    # let resultFuture = newFuture[T]()
    # resultFuture.internalClosure = `iteratorNameSym`
    # futureContinue(resultFuture)
    # return resultFuture
    # ```
    #
    # Declared at the end to be sure that the closure doesn't reference it,
    # avoid cyclic ref (#203)
    #
    # Do not change this code to `quote do` version because `instantiationInfo`
    # will be broken for `newFuture()` call.

    let
      outerProcBody = newNimNode(nnkStmtList, prc.body)

    # Copy comment for nimdoc
    if prc.body.len > 0 and prc.body[0].kind == nnkCommentStmt:
      outerProcBody.add(prc.body[0])

    outerProcBody.add(closureIterator)

    let
      retFutureSym = ident "resultFuture"
      newFutProc = if raises == nil:
        nnkBracketExpr.newTree(ident "newFuture", baseType)
      else:
        nnkBracketExpr.newTree(ident "newInternalRaisesFuture", baseType, raises)

    retFutureSym.copyLineInfo(prc)
    outerProcBody.add(
      newLetStmt(
        retFutureSym,
        newCall(newFutProc, newLit("async." & prcName))
      )
    )

    outerProcBody.add(
      newAssignment(
        newDotExpr(retFutureSym, newIdentNode("internalClosure")),
        iteratorNameSym)
    )

    outerProcBody.add(
        newCall(newIdentNode("futureContinue"), retFutureSym)
    )

    outerProcBody.add newNimNode(nnkReturnStmt, prc.body[^1]).add(retFutureSym)

    prc.body = outerProcBody

  when defined(debugDumpAsync) or true:
    echo repr prc

  prc

template await*[T](f: Future[T]): T =
  ## Ensure that the given `Future` is finished, then return its value.
  ##
  ## If the `Future` failed or was cancelled, the corresponding exception will
  ## be raised instead.
  ##
  ## If the `Future` is pending, execution of the current `async` procedure
  ## will be suspended until the `Future` is finished.
  when declared(chronosInternalRetFuture):
    chronosInternalRetFuture.internalChild = f
    # `futureContinue` calls the iterator generated by the `async`
    # transformation - `yield` gives control back to `futureContinue` which is
    # responsible for resuming execution once the yielded future is finished
    yield chronosInternalRetFuture.internalChild
    # `child` released by `futureContinue`
    cast[type(f)](chronosInternalRetFuture.internalChild).internalRaiseIfError(f)

    when T isnot void:
      cast[type(f)](chronosInternalRetFuture.internalChild).value()
  else:
    unsupported "await is only available within {.async.}"

template await*[T, E](fut: InternalRaisesFuture[T, E]): T =
  ## Ensure that the given `Future` is finished, then return its value.
  ##
  ## If the `Future` failed or was cancelled, the corresponding exception will
  ## be raised instead.
  ##
  ## If the `Future` is pending, execution of the current `async` procedure
  ## will be suspended until the `Future` is finished.
  when declared(chronosInternalRetFuture):
    chronosInternalRetFuture.internalChild = fut
    # `futureContinue` calls the iterator generated by the `async`
    # transformation - `yield` gives control back to `futureContinue` which is
    # responsible for resuming execution once the yielded future is finished
    yield chronosInternalRetFuture.internalChild
    # `child` released by `futureContinue`
    cast[type(fut)](
      chronosInternalRetFuture.internalChild).internalRaiseIfError(E, fut)

    when T isnot void:
      cast[type(fut)](chronosInternalRetFuture.internalChild).value()
  else:
    unsupported "await is only available within {.async.}"

template awaitne*[T](f: Future[T]): Future[T] =
  when declared(chronosInternalRetFuture):
    chronosInternalRetFuture.internalChild = f
    yield chronosInternalRetFuture.internalChild
    cast[type(f)](chronosInternalRetFuture.internalChild)
  else:
    unsupported "awaitne is only available within {.async.}"

macro async*(params, prc: untyped): untyped =
  ## Macro which processes async procedures into the appropriate
  ## iterators and yield statements.
  if prc.kind == nnkStmtList:
    result = newStmtList()
    for oneProc in prc:
      result.add asyncSingleProc(oneProc, params)
  else:
    result = asyncSingleProc(prc, params)

macro async*(prc: untyped): untyped =
  ## Macro which processes async procedures into the appropriate
  ## iterators and yield statements.

  if prc.kind == nnkStmtList:
    result = newStmtList()
    for oneProc in prc:
      result.add asyncSingleProc(oneProc, nnkTupleConstr.newTree())
  else:
    result = asyncSingleProc(prc, nnkTupleConstr.newTree())
