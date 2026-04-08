## This file is intended to track progress of compiling Nev with nimony.
## Each file gets included here one by one as they are made to work with nimony, along with maybe some tests.

import std/syncio
echo "nimony main"

import misc/[array_view]
block:
  var a = [1, 2, 3, 4, 5]
  var av = initArrayView(a)
  for i in 0..av.high:
    echo av[i]

import misc/array_buffer

import misc/arena
block:
  var a = initArena()
  echo cast[int](a.alloc(4, 4))
  echo cast[int](a.alloc(4, 4))
  a.restoreCheckpoint(0)
  echo cast[int](a.alloc(4, 4))

import misc/array_set
echo "array_set: ", (3 in [1, 2, 3])

import misc/array_table
block:
  var t = initArrayTable[int, int]()
  echo "array_table: ", $t.tryGet(0)
