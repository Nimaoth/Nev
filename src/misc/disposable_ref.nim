import std/[options, strutils, macros, genasts]
import misc/[util, custom_logger]

logCategory "disposable-ref"

type
  Disposable* = concept a
    a.deinit()

  DisposableRef*[T: Disposable] = object
    count: ref int
    obj: T

proc `=copy`*[T: Disposable](a: var DisposableRef[T], b: DisposableRef[T]) {.error.}
proc `=dup`*[T: Disposable](a: DisposableRef[T]): DisposableRef[T] {.error.}
proc `=destroy`*[T: Disposable](a: DisposableRef[T]) =
  if not a.count.isNil:
    a.count[].dec
    # debugf"=destroy DisposableRef {$a.count[]} {a.obj.isNil}"
    if a.count[] == 0 and not a.obj.isNil:
      # debugf"count == 0, deinit"
      a.obj.deinit()

proc get*[T: Disposable](a: DisposableRef[T]): T =
  a.obj

proc toDisposableRef*[T: Disposable](obj: T): DisposableRef[T] =
  # debugf"=new DisposableRef"
  var count = new int
  count[] = 1
  DisposableRef[T](
    count: count,
    obj: obj
  )

proc toDisposableRef*[T: Disposable](obj: Option[T]): Option[DisposableRef[T]] =
  if obj.isSome:
    result = obj.get.toDisposableRef.some

proc clone*[T: Disposable](a: DisposableRef[T]): DisposableRef[T] =
  a.count[].inc
  # debugf"=inc DisposableRef {$a.count[]}"
  DisposableRef[T](
    count: a.count,
    obj: a.obj
  )

proc clone*[T: Disposable](a: Option[DisposableRef[T]]): Option[DisposableRef[T]] =
  if a.isSome:
    result = a.get.clone.some