import std/[sequtils]

func `in`*[T](x: T, xs: openArray[T]): bool = xs.find(x) != -1

func incl*[T](xs: var seq[T], x: T) =
  if xs.find(x) == -1: xs.add(x)

func excl*[T](xs: var seq[T], x: T) =
  let i = xs.find(x)
  if i != -1:
    xs.del(i)