when defined(js):
  import std/asyncjs
  export asyncjs

  template asyncCheck*(body: untyped): untyped = discard body
else:
  import std/asyncdispatch, std/asyncfile
  export asyncdispatch, asyncfile