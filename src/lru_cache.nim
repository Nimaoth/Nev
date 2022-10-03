include lrucache

iterator values*[K, V](lru: LruCache[K, V]): V =
  for node in lru.list.items:
    yield node.val

iterator pairs*[K, V](lru: LruCache[K, V]): (K, V) =
  for node in lru.list.items:
    yield (node.key, node.val)